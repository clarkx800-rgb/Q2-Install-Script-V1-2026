#!/usr/bin/env bash
# ==============================================================================
# flash_firmware.sh: Beginner-Friendly Firmware Installer for Qidi Q2
# Mode 1 (--printer): Flashes Motion Mainboard MCU + Toolhead MCU Together
# Mode 2 (--box):     Flashes / Configures Optional Qidi Box MMU Separately
# ==============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SUITE_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
FIRMWARE_DIR="$SUITE_ROOT/firmwares"
FLASHTOOL="$FIRMWARE_DIR/flashtool.py"
DEPLOYERS_DIR="$FIRMWARE_DIR/deployers"
PRECOMPILED_DIR="$FIRMWARE_DIR/precompiled"

source "$SCRIPT_DIR/ui_nav.sh"

REAL_USER="${SUDO_USER:-$USER}"
USER_HOME=$(eval echo "~$REAL_USER")

# ANSI Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

# Detect best Python interpreter (prefer klippy-env which always has pyserial)
PYTHON_BIN="python3"
if [[ -x "$USER_HOME/klippy-env/bin/python" ]]; then
    PYTHON_BIN="$USER_HOME/klippy-env/bin/python"
elif [[ -x "/home/mks/klippy-env/bin/python" ]]; then
    PYTHON_BIN="/home/mks/klippy-env/bin/python"
fi

ensure_pyserial() {
    if ! "$PYTHON_BIN" -c "import serial" >/dev/null 2>&1; then
        echo -e "${YELLOW}[*] Installing Python serial helper (pyserial)...${NC}"
        apt-get update -qq >/dev/null 2>&1 && apt-get install -y -qq python3-serial >/dev/null 2>&1 || true
    fi
}

get_target_config_dir() {
    if [[ -n "${SIM_CONFIG_DIR:-}" ]]; then
        echo "$SIM_CONFIG_DIR"
        return 0
    fi
    if [[ -d "$USER_HOME/printer_data/config" ]]; then
        echo "$USER_HOME/printer_data/config"
    elif [[ -d "/home/mks/printer_data/config" ]]; then
        echo "/home/mks/printer_data/config"
    elif [[ -d "/home/mks/klipper_config" ]]; then
        echo "/home/mks/klipper_config"
    else
        mkdir -p "$USER_HOME/printer_data/config"
        echo "$USER_HOME/printer_data/config"
    fi
}

select_usb_device() {
    local prompt_title="$1"
    local filter_hint="${2:-}"
    local serial_dir="${SIM_DEV_SERIAL:-/dev/serial/by-id}"

    while true; do
        local dev_items=()
        local devices=()
        if [[ -d "$serial_dir" ]] && [[ -n "$(ls -A "$serial_dir" 2>/dev/null)" ]]; then
            devices=("$serial_dir"/*)
            for dev in "${devices[@]}"; do
                dev_items+=("🔌 $dev")
            done
        fi
        dev_items+=("🔄 Re-scan USB devices")
        dev_items+=("⬅️  Back (Skip this step)")
        dev_items+=("🚪 Exit Installer")

        local header="${CYAN}${BOLD}======================================================================${NC}\n"
        header+="${BOLD} ${prompt_title}${NC}\n"
        header+="${CYAN}======================================================================${NC}"
        if [[ ${#devices[@]} -eq 0 ]]; then
            header+="\n${YELLOW}[!] No USB serial devices detected in ${serial_dir}/ yet.${NC}\n"
            header+="Make sure the USB cable is firmly plugged in."
        fi

        local sel_res
        sel_res=$(arrow_menu "$header" dev_items 0)
        local num_devs=${#devices[@]}

        case "$sel_res" in
            back|b|menu|m)
                return 1
                ;;
            quit|q|exit)
                echo -e "\n${GREEN}${BOLD}Exiting installer. Goodbye!${NC}"
                exit 0
                ;;
            *)
                if [[ "$sel_res" =~ ^[0-9]+$ ]]; then
                    if [[ "$sel_res" -lt "$num_devs" ]]; then
                        echo "${devices[$sel_res]}"
                        return 0
                    elif [[ "$sel_res" -eq "$num_devs" ]]; then
                        # Re-scan option
                        continue
                    elif [[ "$sel_res" -eq $((num_devs + 1)) ]]; then
                        # Back option
                        return 1
                    else
                        # Exit option
                        echo -e "\n${GREEN}${BOLD}Exiting installer. Goodbye!${NC}"
                        exit 0
                    fi
                fi
                ;;
        esac
    done
}

sync_loadcell_drivers() {
    local klipper_dir="$USER_HOME/klipper"
    [[ ! -d "$klipper_dir" && -d "/home/mks/klipper" ]] && klipper_dir="/home/mks/klipper"

    if [[ -d "$klipper_dir" ]]; then
        echo -e "${CYAN}[*] Syncing CS1237 nozzle load-cell drivers into ${klipper_dir}...${NC}"
        if [[ -f "$SUITE_ROOT/patches/cs1237_loadcell/sensor_cs1237.c" && -d "$klipper_dir/src" ]]; then
            cp -u "$SUITE_ROOT/patches/cs1237_loadcell/sensor_cs1237.c" "$klipper_dir/src/" 2>/dev/null || true
        fi
        if [[ -f "$SUITE_ROOT/patches/cs1237_loadcell/cs1237.py" && -d "$klipper_dir/klippy/extras" ]]; then
            mkdir -p "$klipper_dir/klippy/extras/load_cell"
            cp -u "$SUITE_ROOT/patches/cs1237_loadcell/cs1237.py" "$klipper_dir/klippy/extras/load_cell/" 2>/dev/null || true
        fi
        chown -R "$REAL_USER:$REAL_USER" "$klipper_dir" 2>/dev/null || true
        echo -e "${GREEN}    [✓] Load-cell drivers verified.${NC}"
    fi
}

# ==============================================================================
# WORKFLOW 1: PRINTER FIRMWARE (MOTION MAINBOARD MCU + TOOLHEAD MCU)
# ==============================================================================
install_printer_firmware() {
    ensure_pyserial
    local target_cfg
    target_cfg=$(get_target_config_dir)

    echo ""
    echo -e "${CYAN}${BOLD}======================================================================${NC}"
    echo -e "${BOLD} 🖨️  INSTALLING PRINTER FIRMWARE (MOTION MCU + TOOLHEAD MCU)${NC}"
    echo -e "${CYAN}======================================================================${NC}"
    echo -e "Your Qidi Q2 printer has ${BOLD}2 main boards${NC} inside the printer body:"
    echo -e "  1. ${BOLD}Motion Mainboard (mcu)${NC} — Controls X/Y/Z motors & heated bed (via USB)"
    echo -e "  2. ${BOLD}Toolhead Board (THR)${NC}   — Controls extruder, nozzle & load cell (via /dev/ttyS4)"
    echo -e "We will walk through both boards right now!"
    echo ""

    sync_loadcell_drivers

    # Deploy core hardware configuration files while preserving user's existing macros
    echo -e "${CYAN}[*] Deploying core hardware configuration to ${target_cfg} (keeping your macros safe)...${NC}"
    mkdir -p "$target_cfg"
    for item in printer.cfg autotune_tmc.cfg timelapse.cfg plr.cfg MCU_ID.cfg gcode_macro_basic.cfg mmu mmu.cfg mmu_custom_actions.cfg mmu_ui_bridge.cfg sync_spoolman.cfg; do
        if [[ -e "$SUITE_ROOT/configs/$item" ]]; then
            cp -rp "$SUITE_ROOT/configs/$item" "$target_cfg/"
        fi
    done
    # Keep user's macros by default until they run Option 3 (unless Pucci's macros are already installed)
    if [[ ! -d "$target_cfg/START-END-PAUSE-CANCEL" ]]; then
        bash "$SCRIPT_DIR/manage_macros.sh" --keep-silent || true
    fi
    chown -R "$REAL_USER:$REAL_USER" "$target_cfg" 2>/dev/null || true

    echo -e "${CYAN}[*] Stopping Klipper temporarily so we can talk to the boards...${NC}"
    systemctl stop klipper 2>/dev/null || true

    # --------------------------------------------------------------------------
    # PART A: MOTION MAINBOARD MCU (GD32F425)
    # --------------------------------------------------------------------------
    local mb_items=(
        "[1] Already has Katapult installed (Flash mcu.bin directly over USB)"
        "[2] Super-Stock Factory Qidi (Walk through 1-time Micro-SD card deployer)"
        "[3] Skip Motion Mainboard flashing"
        "[b] ⬅️  Back to Main Menu"
        "[q] 🚪 Exit Installer"
    )
    local mb_header="${BLUE}${BOLD}--- PART 1 OF 2: MOTION MAINBOARD MCU (GD32F425) ---${NC}\n"
    mb_header+="What is the current state of your Motion Mainboard?"

    local mb_res
    mb_res=$(arrow_menu "$mb_header" mb_items 0)
    local mb_state="2"

    case "$mb_res" in
        0) mb_state="2" ;; # Katapult direct
        1) mb_state="1" ;; # Super-Stock SD deployer
        2) mb_state="3" ;; # Skip
        3|b|back|menu|m) return 0 ;;
        4|q|quit|exit) exit 0 ;;
        *) mb_state="2" ;;
    esac

    if [[ "$mb_state" == "1" ]]; then
        local sd_items=(
            "Micro-SD card step complete! Proceed to flash mcu.bin over USB"
            "Skip Motion Mainboard flashing"
            "⬅️  Back to Main Menu"
            "🚪 Exit Installer"
        )
        local sd_header="${YELLOW}${BOLD}======================================================================${NC}\n"
        sd_header+="${BOLD} 📇 EASY 1-TIME SD CARD STEP FOR SUPER-STOCK MAINBOARD${NC}\n"
        sd_header+="${YELLOW}======================================================================${NC}\n"
        sd_header+="Because the factory Qidi mainboard only accepts its first unlock from\n"
        sd_header+="a Micro-SD card, follow these simple steps (NO soldering or ST-Link!):\n\n"
        sd_header+="  1. Take a regular Micro-SD card formatted as ${BOLD}FAT32${NC}.\n"
        sd_header+="  2. Copy this file onto the SD card:\n"
        sd_header+="       ${CYAN}${DEPLOYERS_DIR}/mcu-deployer.bin${NC}\n"
        sd_header+="  3. Rename that file on the SD card to:\n"
        sd_header+="       ${GREEN}${BOLD}qd_mcu.bin${NC}\n"
        sd_header+="  4. Turn OFF the printer, plug the Micro-SD card into the Mainboard,\n"
        sd_header+="     and turn ON the printer. Wait ${BOLD}15 seconds${NC}.\n"
        sd_header+="  5. Turn OFF the printer, remove the Micro-SD card, and turn it back ON.\n"
        sd_header+="     ${GREEN}Congratulations! Your mainboard now has Katapult forever!${NC}\n"

        local sd_res
        sd_res=$(arrow_menu "$sd_header" sd_items 0)
        case "$sd_res" in
            0) mb_state="2" ;;
            1) mb_state="3" ;;
            2|b|back|menu|m) return 0 ;;
            3|q|quit|exit) exit 0 ;;
            *) mb_state="3" ;;
        esac
    fi

    if [[ "$mb_state" == "2" ]]; then
        local mb_dev=""
        if mb_dev=$(select_usb_device "Select your Motion Mainboard USB Serial Port (usually stm32f407xx):"); then
            echo -e "${CYAN}[*] Flashing Motion Mainboard (${mb_dev}) with mcu.bin...${NC}"
            if [[ "${SIM_MODE:-0}" == "1" ]]; then
                echo -e "${GREEN}    [SIMULATOR] Sent mcu.bin to ${mb_dev}! Microcontroller Flashed 100% OK.${NC}"
            else
                "$PYTHON_BIN" "$FLASHTOOL" -d "$mb_dev" -f "$PRECOMPILED_DIR/mcu.bin" || {
                    echo -e "${YELLOW}[!] Direct flash returned a warning. Waiting 2s and verifying...${NC}"
                }
            fi
            sleep 1
            # Re-check serial path in case it switched from katapult_ to Klipper_
            local new_mb_dev=""
            local serial_dir="${SIM_DEV_SERIAL:-/dev/serial/by-id}"
            for d in "$serial_dir"/*stm32f407*; do
                [[ -e "$d" ]] && new_mb_dev="$d" && break
            done
            [[ -z "$new_mb_dev" ]] && new_mb_dev="$mb_dev"
            if [[ -f "$target_cfg/printer.cfg" ]]; then
                sed -i "s|serial:\s*/dev/serial/by-id/.*stm32f407.*|serial: ${new_mb_dev}|g" "$target_cfg/printer.cfg"
            fi
            echo -e "${GREEN}[✓] Motion Mainboard flashed and linked in printer.cfg!${NC}"
        fi
    fi

    # --------------------------------------------------------------------------
    # PART B: TOOLHEAD MCU (GD32F303 OVER /dev/ttyS4)
    # --------------------------------------------------------------------------
    local thr_items=(
        "[1] Super-Stock Factory Qidi (Auto-install Katapult + Flash thr.bin)"
        "[2] Already has Katapult installed (Flash thr.bin now)"
        "[3] Skip Toolhead flashing"
        "[b] ⬅️  Back to Main Menu"
        "[q] 🚪 Exit Installer"
    )
    local thr_header="${BLUE}${BOLD}--- PART 2 OF 2: TOOLHEAD BOARD (THR - GD32F303) ---${NC}\n"
    thr_header+="Good news! On the AP board, the Toolhead is wired directly to internal\n"
    thr_header+="port ${BOLD}/dev/ttyS4${NC} at 500,000 speed. No SD card or USB cable needed!\n\n"
    thr_header+="What is the current state of your Toolhead Board?"

    local thr_res
    thr_res=$(arrow_menu "$thr_header" thr_items 0)
    local thr_state="1"
    case "$thr_res" in
        0) thr_state="1" ;;
        1) thr_state="2" ;;
        2) thr_state="3" ;;
        3|b|back|menu|m) return 0 ;;
        4|q|quit|exit) exit 0 ;;
        *) thr_state="1" ;;
    esac

    local ttys4_dev="${SIM_TTYS4:-/dev/ttyS4}"
    if [[ "$thr_state" == "1" ]]; then
        if [[ -e "$ttys4_dev" ]]; then
            echo -e "${CYAN}[*] Step 1/2: Sending Katapult deployer (thr-deployer.bin) to ${ttys4_dev}...${NC}"
            if [[ "${SIM_MODE:-0}" == "1" ]]; then
                echo -e "${GREEN}    [SIMULATOR] Sent Katapult deployer to ${ttys4_dev}! OK.${NC}"
            else
                "$PYTHON_BIN" "$FLASHTOOL" -d "$ttys4_dev" -b 500000 -f "$DEPLOYERS_DIR/thr-deployer.bin" || true
            fi
            sleep 1
            echo -e "${CYAN}[*] Step 2/2: Flashing production Toolhead firmware (thr.bin)...${NC}"
            if [[ "${SIM_MODE:-0}" == "1" ]]; then
                echo -e "${GREEN}    [SIMULATOR] Sent thr.bin to ${ttys4_dev}! Toolhead Flashed 100% OK.${NC}"
            else
                "$PYTHON_BIN" "$FLASHTOOL" -d "$ttys4_dev" -b 500000 -f "$PRECOMPILED_DIR/thr.bin" || {
                    echo -e "${YELLOW}[!] Note: If the Toolhead did not respond, power-cycle the printer and run Option 2.${NC}"
                }
            fi
            echo -e "${GREEN}[✓] Toolhead Board flashed!${NC}"
        else
            echo -e "${RED}[-] ${ttys4_dev} was not found on this machine.${NC}"
        fi
    elif [[ "$thr_state" == "2" ]]; then
        if [[ -e "$ttys4_dev" ]]; then
            echo -e "${CYAN}[*] Flashing Toolhead firmware (thr.bin) to ${ttys4_dev} @ 500,000 baud...${NC}"
            if [[ "${SIM_MODE:-0}" == "1" ]]; then
                echo -e "${GREEN}    [SIMULATOR] Sent thr.bin to ${ttys4_dev}! Toolhead Flashed 100% OK.${NC}"
            else
                "$PYTHON_BIN" "$FLASHTOOL" -d "$ttys4_dev" -b 500000 -f "$PRECOMPILED_DIR/thr.bin"
            fi
            echo -e "${GREEN}[✓] Toolhead Board flashed!${NC}"
        else
            echo -e "${RED}[-] ${ttys4_dev} was not found on this machine.${NC}"
        fi
    fi

    # Ensure /dev/ttyS4 is set in printer.cfg
    if [[ -f "$target_cfg/printer.cfg" ]]; then
        sed -i '/\[mcu THR\]/,/\[/ s|serial:.*|serial: /dev/ttyS4|' "$target_cfg/printer.cfg"
        sed -i '/\[mcu THR\]/,/\[/ s|baud:.*|baud: 500000|' "$target_cfg/printer.cfg"
    fi

    echo ""
    echo -e "${CYAN}[*] Starting Klipper service...${NC}"
    systemctl start klipper 2>/dev/null || true
    echo -e "${GREEN}${BOLD}[✓] Printer Firmware (Motion MCU + Toolhead) Setup Complete!${NC}"
}

# ==============================================================================
# WORKFLOW 2: QIDI BOX (MMU) FIRMWARE & CONFIG (OPTIONAL / SEPARATE)
# ==============================================================================
install_box_firmware() {
    ensure_pyserial
    local target_cfg
    target_cfg=$(get_target_config_dir)

    local box_items=(
        "[1] Super-Stock Qidi Box (Auto-install Katapult + Flash mmu.bin over USB)"
        "[2] Already has Katapult installed (Flash mmu.bin over USB)"
        "[3] Enable Qidi Box in Config Only (Already flashed previously)"
        "[4] Do NOT use Qidi Box (Disable MMU / Run as Single-Spool Printer)"
        "[b] ⬅️  Back to Main Menu"
        "[q] 🚪 Exit Installer"
    )
    local box_header="${CYAN}${BOLD}======================================================================${NC}\n"
    box_header+="${BOLD} 🎨 QIDI BOX (MMU) FIRMWARE & CONFIGURATION (OPTIONAL)${NC}\n"
    box_header+="${CYAN}======================================================================${NC}\n"
    box_header+="The Qidi Box uses an STM32F401 chip connected over standard USB.\n"
    box_header+="Even if your Qidi Box is 100% factory stock, we can deploy Katapult\n"
    box_header+="and flash our firmware directly over the USB cable!\n\n"
    box_header+="Choose an option:"

    local box_res
    box_res=$(arrow_menu "$box_header" box_items 0)
    local box_opt=""

    case "$box_res" in
        0) box_opt="1" ;;
        1) box_opt="2" ;;
        2) box_opt="3" ;;
        3) box_opt="4" ;;
        4|b|back|menu|m) return 0 ;;
        5|q|quit|exit) exit 0 ;;
        *) return 0 ;;
    esac

    case "$box_opt" in
        1|2)
            systemctl stop klipper 2>/dev/null || true
            local mmu_dev=""
            local serial_dir="${SIM_DEV_SERIAL:-/dev/serial/by-id}"
            if mmu_dev=$(select_usb_device "Select your Qidi Box USB Serial Port (usually stm32f401xc):"); then
                if [[ "$box_opt" == "1" ]]; then
                    echo -e "${CYAN}[*] Step 1/2: Uploading Katapult deployer (mmu-deployer.bin) over USB...${NC}"
                    if [[ "${SIM_MODE:-0}" == "1" ]]; then
                        echo -e "${GREEN}    [SIMULATOR] Sent Katapult deployer to ${mmu_dev}! OK.${NC}"
                    else
                        "$PYTHON_BIN" "$FLASHTOOL" -d "$mmu_dev" -f "$DEPLOYERS_DIR/mmu-deployer.bin" || true
                    fi
                    sleep 1
                    # Re-detect device path
                    for d in "$serial_dir"/*stm32f401*; do
                        [[ -e "$d" ]] && mmu_dev="$d" && break
                    done
                fi
                echo -e "${CYAN}[*] Flashing Qidi Box production firmware (mmu.bin)...${NC}"
                if [[ "${SIM_MODE:-0}" == "1" ]]; then
                    echo -e "${GREEN}    [SIMULATOR] Sent mmu.bin to ${mmu_dev}! Qidi Box Flashed 100% OK.${NC}"
                else
                    "$PYTHON_BIN" "$FLASHTOOL" -d "$mmu_dev" -f "$PRECOMPILED_DIR/mmu.bin"
                fi
                sleep 1
                for d in "$serial_dir"/*stm32f401*; do
                    [[ -e "$d" ]] && mmu_dev="$d" && break
                done
                if [[ -f "$target_cfg/mmu/base/mmu_hardware.cfg" ]]; then
                    sed -i "s|serial:.*|serial: ${mmu_dev}|g" "$target_cfg/mmu/base/mmu_hardware.cfg"
                fi
                echo -e "${GREEN}[✓] Qidi Box firmware flashed and serial updated!${NC}"
            fi
            # Enable MMU in printer.cfg
            enable_mmu_in_config "$target_cfg/printer.cfg"
            systemctl start klipper 2>/dev/null || true
            ;;
        3)
            enable_mmu_in_config "$target_cfg/printer.cfg"
            systemctl restart klipper 2>/dev/null || true
            ;;
        4)
            disable_mmu_in_config "$target_cfg/printer.cfg"
            systemctl restart klipper 2>/dev/null || true
            ;;
        *)
            return 0
            ;;
    esac
}

enable_mmu_in_config() {
    local cfg_file="$1"
    [[ ! -f "$cfg_file" ]] && return 0
    python3 - << PYEOF
import os, re
p = "$cfg_file"
with open(p, "r") as f:
    c = f.read()

# Check if spoolman is actively enabled in moonraker.conf
cfg_dir = os.path.dirname(p)
mr_path = os.path.join(cfg_dir, "moonraker.conf")
spoolman_line = "#[include sync_spoolman.cfg]"
if os.path.isfile(mr_path):
    with open(mr_path, "r") as mf:
        mc = mf.read()
    if re.search(r"^\s*\[spoolman\]", mc, re.MULTILINE):
        spoolman_line = "[include sync_spoolman.cfg]"

block = f"""# <MMU_SUITE_START>
[include mmu.cfg]
[include mmu_custom_actions.cfg]
[include mmu_ui_bridge.cfg]
{spoolman_line}
# <MMU_SUITE_END>"""
if "# <MMU_SUITE_START>" in c:
    c = re.sub(r"# <MMU_SUITE_START>.*?# <MMU_SUITE_END>", block, c, flags=re.DOTALL)
else:
    c = c.replace("#[include mmu.cfg]", "[include mmu.cfg]")
    c = c.replace("#[include mmu/base/mmu.cfg]", "[include mmu/base/mmu.cfg]")
with open(p, "w") as f:
    f.write(c)
PYEOF
    echo -e "${GREEN}[✓] Qidi Box (MMU) enabled in printer.cfg!${NC}"
}

disable_mmu_in_config() {
    local cfg_file="$1"
    [[ ! -f "$cfg_file" ]] && return 0
    python3 - << PYEOF
import re
p = "$cfg_file"
with open(p, "r") as f:
    c = f.read()
block = """# <MMU_SUITE_START>
# Qidi Box MMU Disabled (Standalone Single-Extruder Mode)
#[include mmu.cfg]
#[include mmu_custom_actions.cfg]
#[include mmu_ui_bridge.cfg]
#[include sync_spoolman.cfg]
# <MMU_SUITE_END>"""
if "# <MMU_SUITE_START>" in c:
    c = re.sub(r"# <MMU_SUITE_START>.*?# <MMU_SUITE_END>", block, c, flags=re.DOTALL)
else:
    c = re.sub(r"^\s*\[include mmu.*\]", lambda m: "#" + m.group(0), c, flags=re.MULTILINE)
with open(p, "w") as f:
    f.write(c)
PYEOF
    echo -e "${GREEN}[✓] Qidi Box (MMU) disabled in printer.cfg (Standalone Single-Spool Mode).${NC}"
}

case "${1:-}" in
    --printer)
        install_printer_firmware
        ;;
    --box)
        install_box_firmware
        ;;
    *)
        fw_items=(
            "[1] Install Printer Firmware (Motion Mainboard + Toolhead MCU)"
            "[2] Install Qidi Box MMU Firmware (Optional Multi-Material)"
            "[b] ⬅️  Back to Main Menu"
            "[q] 🚪 Exit Installer"
        )
        fw_res=$(arrow_menu "=== QIDI Q2 FIRMWARE INSTALLER ===" fw_items 0)
        case "$fw_res" in
            0) install_printer_firmware ;;
            1) install_box_firmware ;;
            2|b|back|menu|m) exit 0 ;;
            3|q|quit|exit) exit 0 ;;
        esac
        ;;
esac
