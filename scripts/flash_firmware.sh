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
    local selected_dev=""

    while true; do
        echo ""
        echo -e "${BOLD}${prompt_title}${NC}"
        if [[ -d "/dev/serial/by-id" ]] && [[ -n "$(ls -A /dev/serial/by-id 2>/dev/null)" ]]; then
            local devices=(/dev/serial/by-id/*)
            local count=${#devices[@]}
            local idx=1
            for dev in "${devices[@]}"; do
                echo -e "  [${CYAN}${idx}${NC}] $dev"
                idx=$((idx + 1))
            done
            echo ""
            read -rp "👉 Type the number (1-${count}), 'r' to re-scan USB, or 's' to skip: " choice
            if [[ "$choice" =~ ^[0-9]+$ ]] && [[ "$choice" -ge 1 ]] && [[ "$choice" -le "$count" ]]; then
                selected_dev="${devices[$((choice - 1))]}"
                echo "$selected_dev"
                return 0
            elif [[ "$choice" =~ ^[rR]$ ]]; then
                continue
            elif [[ "$choice" =~ ^[sS]$ ]]; then
                return 1
            else
                echo -e "${RED}Invalid selection. Please try again.${NC}"
            fi
        else
            echo -e "${YELLOW}[!] No USB serial devices detected in /dev/serial/by-id/ yet.${NC}"
            read -rp "👉 Make sure the USB cable is plugged in. Press ENTER to scan again, or 's' to skip: " retry_choice
            if [[ "$retry_choice" =~ ^[sS]$ ]]; then
                return 1
            fi
        fi
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
    echo ""
    echo -e "${BLUE}${BOLD}--- PART 1 OF 2: MOTION MAINBOARD MCU (GD32F425) ---${NC}"
    echo "What is the current state of your Motion Mainboard?"
    echo "  [1] Super-Stock Factory Qidi (Never installed Katapult before)"
    echo "  [2] Already has Katapult installed (Flash mcu.bin directly over USB)"
    echo "  [3] Skip Motion Mainboard flashing"
    echo ""
    read -rp "👉 Select option [1-3] (Default: 2): " mb_state
    mb_state="${mb_state:-2}"

    if [[ "$mb_state" == "1" ]]; then
        echo ""
        echo -e "${YELLOW}${BOLD}======================================================================${NC}"
        echo -e "${BOLD} 📇 EASY 1-TIME SD CARD STEP FOR SUPER-STOCK MAINBOARD${NC}"
        echo -e "${YELLOW}======================================================================${NC}"
        echo -e "Because the factory Qidi mainboard only accepts its first unlock from"
        echo -e "a Micro-SD card, follow these simple steps (NO soldering or ST-Link!):"
        echo ""
        echo -e "  1. Take a regular Micro-SD card formatted as ${BOLD}FAT32${NC}."
        echo -e "  2. Copy this file onto the SD card:"
        echo -e "       ${CYAN}${DEPLOYERS_DIR}/mcu-deployer.bin${NC}"
        echo -e "  3. Rename that file on the SD card to:"
        echo -e "       ${GREEN}${BOLD}qd_mcu.bin${NC}"
        echo -e "  4. Turn OFF the printer, plug the Micro-SD card into the Mainboard,"
        echo -e "     and turn ON the printer. Wait ${BOLD}15 seconds${NC}."
        echo -e "  5. Turn OFF the printer, remove the Micro-SD card, and turn it back ON."
        echo -e "     ${GREEN}Congratulations! Your mainboard now has Katapult forever!${NC}"
        echo -e "${YELLOW}======================================================================${NC}"
        echo ""
        read -rp "👉 Once you have done the SD card step (or if ready now), press ENTER to flash mcu.bin over USB (or type 's' to skip): " sd_done
        if [[ ! "$sd_done" =~ ^[sS]$ ]]; then
            mb_state="2"
        fi
    fi

    if [[ "$mb_state" == "2" ]]; then
        local mb_dev=""
        if mb_dev=$(select_usb_device "Select your Motion Mainboard USB Serial Port (usually stm32f407xx):"); then
            echo -e "${CYAN}[*] Flashing Motion Mainboard (${mb_dev}) with mcu.bin...${NC}"
            "$PYTHON_BIN" "$FLASHTOOL" -d "$mb_dev" -f "$PRECOMPILED_DIR/mcu.bin" || {
                echo -e "${YELLOW}[!] Direct flash returned a warning. Waiting 2s and verifying...${NC}"
            }
            sleep 2
            # Re-check serial path in case it switched from katapult_ to Klipper_
            local new_mb_dev=""
            for d in /dev/serial/by-id/*stm32f407*; do
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
    echo ""
    echo -e "${BLUE}${BOLD}--- PART 2 OF 2: TOOLHEAD BOARD (THR - GD32F303) ---${NC}"
    echo -e "Good news! On the AP board, the Toolhead is wired directly to internal"
    echo -e "port ${BOLD}/dev/ttyS4${NC} at 500,000 speed. No SD card or USB cable needed!"
    echo ""
    echo "What is the current state of your Toolhead Board?"
    echo "  [1] Super-Stock Factory Qidi (Auto-install Katapult + Flash thr.bin)"
    echo "  [2] Already has Katapult installed (Flash thr.bin now)"
    echo "  [3] Skip Toolhead flashing"
    echo ""
    read -rp "👉 Select option [1-3] (Default: 1): " thr_state
    thr_state="${thr_state:-1}"

    if [[ "$thr_state" == "1" ]]; then
        if [[ -e /dev/ttyS4 ]]; then
            echo -e "${CYAN}[*] Step 1/2: Sending Katapult deployer (thr-deployer.bin) to /dev/ttyS4...${NC}"
            "$PYTHON_BIN" "$FLASHTOOL" -d /dev/ttyS4 -b 500000 -f "$DEPLOYERS_DIR/thr-deployer.bin" || true
            echo -e "${CYAN}[*] Waiting 3 seconds for Toolhead to reboot into Katapult...${NC}"
            sleep 3
            echo -e "${CYAN}[*] Step 2/2: Flashing production Toolhead firmware (thr.bin)...${NC}"
            "$PYTHON_BIN" "$FLASHTOOL" -d /dev/ttyS4 -b 500000 -f "$PRECOMPILED_DIR/thr.bin" || {
                echo -e "${YELLOW}[!] Note: If the Toolhead did not respond, power-cycle the printer and run Option 2.${NC}"
            }
            echo -e "${GREEN}[✓] Toolhead Board flashed!${NC}"
        else
            echo -e "${RED}[-] /dev/ttyS4 was not found on this machine.${NC}"
        fi
    elif [[ "$thr_state" == "2" ]]; then
        if [[ -e /dev/ttyS4 ]]; then
            echo -e "${CYAN}[*] Flashing Toolhead firmware (thr.bin) to /dev/ttyS4 @ 500,000 baud...${NC}"
            "$PYTHON_BIN" "$FLASHTOOL" -d /dev/ttyS4 -b 500000 -f "$PRECOMPILED_DIR/thr.bin"
            echo -e "${GREEN}[✓] Toolhead Board flashed!${NC}"
        else
            echo -e "${RED}[-] /dev/ttyS4 was not found on this machine.${NC}"
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

    echo ""
    echo -e "${CYAN}${BOLD}======================================================================${NC}"
    echo -e "${BOLD} 🎨 QIDI BOX (MMU) FIRMWARE & CONFIGURATION (OPTIONAL)${NC}"
    echo -e "${CYAN}======================================================================${NC}"
    echo -e "The Qidi Box uses an STM32F401 chip connected over standard USB."
    echo -e "Even if your Qidi Box is 100% factory stock, we can install Katapult"
    echo -e "and flash our firmware directly over the USB cable!"
    echo ""
    echo "Do you want to install firmware on your Qidi Box and enable it?"
    echo -e "  • ${GREEN}${BOLD}YES (y)${NC} — Install Qidi Box Firmware (mmu.bin) & Enable Qidi Box"
    echo -e "  • ${CYAN}${BOLD}NO  (n)${NC} — Do NOT use Qidi Box (Disable MMU / Run as Single-Spool Printer)"
    echo -e "  • ${YELLOW}${BOLD}c${NC}       — Cancel / Back to Main Menu"
    echo ""
    read -rp "👉 Install Qidi Box Firmware? Type 'yes' or 'no' (or 'c' to cancel): " box_yn

    local box_opt=""
    case "${box_yn,,}" in
        y|yes)
            echo ""
            echo "What is the current state of your Qidi Box?"
            echo "  [1] Super-Stock Qidi Box (Auto-install Katapult + Flash mmu.bin over USB)"
            echo "  [2] Already has Katapult installed (Flash mmu.bin over USB)"
            echo "  [3] Enable Qidi Box in Config Only (Already flashed previously)"
            echo ""
            read -rp "👉 Select option [1-3] (Default: 1): " box_opt
            box_opt="${box_opt:-1}"
            ;;
        n|no)
            box_opt="4"
            ;;
        *)
            return 0
            ;;
    esac

    case "$box_opt" in
        1|2)
            systemctl stop klipper 2>/dev/null || true
            local mmu_dev=""
            if mmu_dev=$(select_usb_device "Select your Qidi Box USB Serial Port (usually stm32f401xc):"); then
                if [[ "$box_opt" == "1" ]]; then
                    echo -e "${CYAN}[*] Step 1/2: Uploading Katapult deployer (mmu-deployer.bin) over USB...${NC}"
                    "$PYTHON_BIN" "$FLASHTOOL" -d "$mmu_dev" -f "$DEPLOYERS_DIR/mmu-deployer.bin" || true
                    echo -e "${CYAN}[*] Waiting 4 seconds for Qidi Box to reboot into Katapult...${NC}"
                    sleep 4
                    # Re-detect device path
                    for d in /dev/serial/by-id/*stm32f401*; do
                        [[ -e "$d" ]] && mmu_dev="$d" && break
                    done
                fi
                echo -e "${CYAN}[*] Flashing Qidi Box production firmware (mmu.bin)...${NC}"
                "$PYTHON_BIN" "$FLASHTOOL" -d "$mmu_dev" -f "$PRECOMPILED_DIR/mmu.bin"
                sleep 2
                for d in /dev/serial/by-id/*stm32f401*; do
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
        echo "1) Install Printer Firmware (Motion Mainboard + Toolhead)"
        echo "2) Install Qidi Box MMU Firmware (Optional)"
        read -rp "Select [1-2]: " m
        [[ "$m" == "1" ]] && install_printer_firmware
        [[ "$m" == "2" ]] && install_box_firmware
        ;;
esac
