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
for p in "/home/mks/klippy-env/bin/python" "$USER_HOME/klippy-env/bin/python" "/home/mks/klipper-env/bin/python" "$USER_HOME/klipper-env/bin/python"; do
    if [[ -x "$p" ]]; then
        PYTHON_BIN="$p"
        break
    fi
done

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
    if [[ -d "/home/mks/printer_data/config" ]]; then
        echo "/home/mks/printer_data/config"
    elif [[ -d "$USER_HOME/printer_data/config" ]]; then
        echo "$USER_HOME/printer_data/config"
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
                nav_quit
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
                        nav_quit
                    fi
                fi
                ;;
        esac
    done
}

sync_loadcell_drivers() {
    local klipper_dir=""
    for kdir in "$USER_HOME/klipper" "/home/mks/klipper" "/home/mks/qidi-q2-klipper" "$USER_HOME/qidi-q2-klipper"; do
        if [[ -d "$kdir" ]]; then
            klipper_dir="$kdir"
            break
        fi
    done

    if [[ -n "$klipper_dir" && -d "$klipper_dir" ]]; then
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
# KATAPULT BOOTLOADER AUTO-DETECTION HELPERS
# ==============================================================================
is_katapult_installed_mcu() {
    local target_cfg
    target_cfg=$(get_target_config_dir)
    local serial_dir="${SIM_DEV_SERIAL:-/dev/serial/by-id}"

    # 1. Check persistent marker files
    if [[ -f "$target_cfg/.katapult_mcu_installed" ]]; then
        return 0
    fi
    if [[ "${SIM_MODE:-0}" != "1" ]] && [[ -f "$USER_HOME/.katapult_mcu_installed" || -f "/home/mks/.katapult_mcu_installed" ]]; then
        return 0
    fi

    # 2. Check if USB serial device explicitly reports Katapult bootloader
    if [[ -d "$serial_dir" ]]; then
        for dev in "$serial_dir"/*katapult*stm32f407* "$serial_dir"/*katapult*GD32F4* "$serial_dir"/*katapult*; do
            if [[ -e "$dev" ]]; then
                return 0
            fi
        done
    fi

    # 3. Simulator test override
    if [[ "${SIM_KATAPULT_MCU:-0}" == "1" ]]; then
        return 0
    fi

    # 4. Live query via flashtool.py status probe
    if [[ -d "$serial_dir" && "${SIM_MODE:-0}" != "1" && -x "$PYTHON_BIN" && -f "$FLASHTOOL" ]]; then
        for dev in "$serial_dir"/*stm32f407*; do
            if [[ -e "$dev" ]]; then
                if timeout 2 "$PYTHON_BIN" "$FLASHTOOL" -d "$dev" -s >/dev/null 2>&1; then
                    return 0
                fi
            fi
        done
    fi

    return 1
}

is_katapult_installed_thr() {
    local target_cfg
    target_cfg=$(get_target_config_dir)
    local ttys4_dev="${SIM_TTYS4:-/dev/ttyS4}"

    # 1. Check persistent marker files
    if [[ -f "$target_cfg/.katapult_thr_installed" ]]; then
        return 0
    fi
    if [[ "${SIM_MODE:-0}" != "1" ]] && [[ -f "$USER_HOME/.katapult_thr_installed" || -f "/home/mks/.katapult_thr_installed" ]]; then
        return 0
    fi

    # 2. Simulator test override
    if [[ "${SIM_KATAPULT_THR:-0}" == "1" ]]; then
        return 0
    fi

    # 3. Live query on /dev/ttyS4 via flashtool.py status probe
    if [[ -e "$ttys4_dev" && "${SIM_MODE:-0}" != "1" && -x "$PYTHON_BIN" && -f "$FLASHTOOL" ]]; then
        if timeout 2 "$PYTHON_BIN" "$FLASHTOOL" -d "$ttys4_dev" -b 500000 -s >/dev/null 2>&1; then
            return 0
        fi
    fi

    return 1
}

is_katapult_installed_mmu() {
    local target_cfg
    target_cfg=$(get_target_config_dir)
    local serial_dir="${SIM_DEV_SERIAL:-/dev/serial/by-id}"

    # 1. Check persistent marker files
    if [[ -f "$target_cfg/.katapult_mmu_installed" ]]; then
        return 0
    fi
    if [[ "${SIM_MODE:-0}" != "1" ]] && [[ -f "$USER_HOME/.katapult_mmu_installed" || -f "/home/mks/.katapult_mmu_installed" ]]; then
        return 0
    fi

    # 2. Check if USB serial device explicitly reports Katapult bootloader
    if [[ -d "$serial_dir" ]]; then
        for dev in "$serial_dir"/*katapult*stm32f401*; do
            if [[ -e "$dev" ]]; then
                return 0
            fi
        done
    fi

    # 3. Simulator test override
    if [[ "${SIM_KATAPULT_MMU:-0}" == "1" ]]; then
        return 0
    fi

    # 4. Live query via flashtool.py status probe
    if [[ -d "$serial_dir" && "${SIM_MODE:-0}" != "1" && -x "$PYTHON_BIN" && -f "$FLASHTOOL" ]]; then
        for dev in "$serial_dir"/*stm32f401*; do
            if [[ -e "$dev" ]]; then
                if timeout 2 "$PYTHON_BIN" "$FLASHTOOL" -d "$dev" -s >/dev/null 2>&1; then
                    return 0
                fi
            fi
        done
    fi

    return 1
}

mark_katapult_installed() {
    local target="$1" # mcu, thr, or mmu
    local target_cfg
    target_cfg=$(get_target_config_dir)
    touch "$target_cfg/.katapult_${target}_installed" 2>/dev/null || true
    if [[ "${SIM_MODE:-0}" != "1" ]]; then
        touch "$USER_HOME/.katapult_${target}_installed" 2>/dev/null || true
        if [[ -d "/home/mks" ]]; then
            touch "/home/mks/.katapult_${target}_installed" 2>/dev/null || true
        fi
    fi
}

# ==============================================================================
# HELPER: DEPLOY CORE HARDWARE CONFIGS WHILE PRESERVING SERIALS & STATE
# ==============================================================================
deploy_core_configs() {
    local target_cfg="$1"
    echo -e "${CYAN}[*] Deploying core hardware configuration to ${target_cfg} (keeping your macros & serials safe)...${NC}"
    mkdir -p "$target_cfg"

    # Preserve existing serials and feature flags if printer.cfg / mmu.cfg already exist
    local old_mcu_serial=""
    local old_mmu_serial=""
    local old_mmu_enabled="0"
    local old_spoolman_enabled="0"

    if [[ -f "$target_cfg/printer.cfg" ]]; then
        old_mcu_serial=$(python3 -c '
import re, sys
with open(sys.argv[1], "r") as f:
    c = f.read()
m = re.search(r"\[mcu\]\s*\n\s*serial\s*:\s*(\S+)", c)
if m:
    print(m.group(1).strip())
' "$target_cfg/printer.cfg" 2>/dev/null || true)

        if grep -Eq "^\s*\[include\s+mmu\.cfg\]" "$target_cfg/printer.cfg" 2>/dev/null; then
            old_mmu_enabled="1"
        fi
        if grep -Eq "^\s*\[include\s+sync_spoolman\.cfg\]" "$target_cfg/printer.cfg" 2>/dev/null; then
            old_spoolman_enabled="1"
        fi
    fi

    if [[ -f "$target_cfg/moonraker.conf" ]] && grep -Eq "^\s*\[spoolman\]" "$target_cfg/moonraker.conf" 2>/dev/null; then
        old_spoolman_enabled="1"
    fi

    if [[ -f "$target_cfg/mmu/base/mmu.cfg" ]]; then
        old_mmu_serial=$(python3 -c '
import re, sys
with open(sys.argv[1], "r") as f:
    c = f.read()
m = re.search(r"\[mcu\s+mmu\]\s*\n\s*serial\s*:\s*(\S+)", c)
if m:
    print(m.group(1).strip())
' "$target_cfg/mmu/base/mmu.cfg" 2>/dev/null || true)
    fi

    for item in printer.cfg autotune_tmc.cfg timelapse.cfg plr.cfg MCU_ID.cfg gcode_macro_basic.cfg mmu mmu.cfg mmu_custom_actions.cfg mmu_ui_bridge.cfg sync_spoolman.cfg; do
        if [[ -e "$SUITE_ROOT/configs/$item" ]]; then
            cp -rp "$SUITE_ROOT/configs/$item" "$target_cfg/"
        fi
    done

    # Copy state/service configs only if missing so user data is never wiped
    for item in saved_variables.cfg moonraker.conf crowsnest.conf; do
        if [[ ! -f "$target_cfg/$item" && -f "$SUITE_ROOT/configs/$item" ]]; then
            cp -p "$SUITE_ROOT/configs/$item" "$target_cfg/"
        fi
    done

    # Ensure [save_variables] points to the active target_cfg path
    if [[ -f "$target_cfg/printer.cfg" ]]; then
        sed -i "s|filename\s*=.*saved_variables.cfg|filename = ${target_cfg}/saved_variables.cfg|g" "$target_cfg/printer.cfg"
    fi

    # Restore previously configured MCU serial if present
    if [[ -n "$old_mcu_serial" && -f "$target_cfg/printer.cfg" ]]; then
        python3 - << PYEOF
import re
p = "$target_cfg/printer.cfg"
with open(p, "r") as f:
    c = f.read()
c = re.sub(r"(\[mcu\]\s*\n\s*serial\s*:\s*).*(\n)", r"\g<1>${old_mcu_serial}\2", c)
with open(p, "w") as f:
    f.write(c)
PYEOF
        if [[ -f "$target_cfg/MCU_ID.cfg" ]]; then
            sed -i "s|serial:.*|serial: ${old_mcu_serial}|g" "$target_cfg/MCU_ID.cfg"
        fi
    fi

    # Restore previously configured MMU serial if present
    if [[ -n "$old_mmu_serial" ]]; then
        for mmu_cfg in "$target_cfg/mmu/base/mmu.cfg" "$target_cfg/mmu/base/mmu_hardware.cfg"; do
            if [[ -f "$mmu_cfg" ]]; then
                sed -i "s|serial:.*|serial: ${old_mmu_serial}|g" "$mmu_cfg"
            fi
        done
    fi

    # Restore MMU / Spoolman enabled state in printer.cfg
    if [[ "$old_mmu_enabled" == "1" ]]; then
        enable_mmu_in_config "$target_cfg/printer.cfg" >/dev/null 2>&1 || true
    elif [[ "$old_spoolman_enabled" == "1" ]]; then
        sed -i 's|^#\s*\[include sync_spoolman.cfg\]|[include sync_spoolman.cfg]|g' "$target_cfg/printer.cfg" 2>/dev/null || true
    fi

    # Keep user's macros by default until they run Option 4 (unless Pucci's macros are already installed)
    if [[ ! -d "$target_cfg/START-END-PAUSE-CANCEL" ]]; then
        bash "$SCRIPT_DIR/manage_macros.sh" --keep-silent || true
    fi
    chown -R "$REAL_USER:$REAL_USER" "$target_cfg" 2>/dev/null || true
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
    deploy_core_configs "$target_cfg"

    echo -e "${CYAN}[*] Stopping Klipper temporarily so we can talk to the boards...${NC}"
    systemctl stop klipper 2>/dev/null || true
    export KLIPPER_STOPPED=1

    # --------------------------------------------------------------------------
    # PART A: MOTION MAINBOARD MCU (GD32F425)
    # --------------------------------------------------------------------------
    local mb_state="2"
    if is_katapult_installed_mcu; then
        echo -e "${GREEN}${BOLD}[✓] Katapult bootloader detected on Motion Mainboard!${NC}"
        echo -e "${GREEN}    Auto-skipping 1-time Micro-SD card deployer step.${NC}\n"
        local mb_items=(
            "[1] Flash mcu.bin directly over USB (Katapult ready)"
            "[2] Skip Motion Mainboard flashing"
            "[3] Force re-run 1-time Micro-SD card deployer"
            "[b] ⬅️  Back to Main Menu"
            "[q] 🚪 Exit Installer"
        )
        local mb_header="${BLUE}${BOLD}--- PART 1 OF 2: MOTION MAINBOARD MCU (GD32F425) ---${NC}\n"
        mb_header+="${GREEN}[✓] Katapult is already installed.${NC} Select an action:"

        local mb_res
        mb_res=$(arrow_menu "$mb_header" mb_items 0)
        case "$mb_res" in
            0) mb_state="2" ;; # Katapult direct
            1) mb_state="3" ;; # Skip
            2) mb_state="1" ;; # Force SD deployer
            3|b|back|menu|m) return 10 ;;
            4|q|quit|exit) nav_quit ;;
            *) mb_state="2" ;;
        esac
    else
        local mb_items=(
            "[1] Super-Stock Factory Qidi (Walk through 1-time Micro-SD card deployer)"
            "[2] Already has Katapult installed (Flash mcu.bin directly over USB)"
            "[3] Skip Motion Mainboard flashing"
            "[b] ⬅️  Back to Main Menu"
            "[q] 🚪 Exit Installer"
        )
        local mb_header="${BLUE}${BOLD}--- PART 1 OF 2: MOTION MAINBOARD MCU (GD32F425) ---${NC}\n"
        mb_header+="What is the current state of your Motion Mainboard?"

        local mb_res
        mb_res=$(arrow_menu "$mb_header" mb_items 0)
        case "$mb_res" in
            0) mb_state="1" ;; # Super-Stock SD deployer
            1) mb_state="2" ;; # Katapult direct
            2) mb_state="3" ;; # Skip
            3|b|back|menu|m) return 10 ;;
            4|q|quit|exit) nav_quit ;;
            *) mb_state="1" ;;
        esac
    fi

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
            2|b|back|menu|m) return 10 ;;
            3|q|quit|exit) nav_quit ;;
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
                python3 - << PYEOF
import re
p = "$target_cfg/printer.cfg"
with open(p, "r") as f:
    c = f.read()
c = re.sub(r"(\[mcu\]\s*\n\s*serial\s*:\s*).*(\n)", r"\g<1>${new_mb_dev}\2", c)
with open(p, "w") as f:
    f.write(c)
PYEOF
            fi
            if [[ -f "$target_cfg/MCU_ID.cfg" ]]; then
                sed -i "s|serial:.*|serial: ${new_mb_dev}|g" "$target_cfg/MCU_ID.cfg"
            fi
            mark_katapult_installed "mcu"
            echo -e "${GREEN}[✓] Motion Mainboard flashed and linked in printer.cfg!${NC}"
        fi
    fi

    # --------------------------------------------------------------------------
    # PART B: TOOLHEAD MCU (GD32F303 OVER /dev/ttyS4)
    # --------------------------------------------------------------------------
    local thr_state="1"
    if is_katapult_installed_thr; then
        echo -e "${GREEN}${BOLD}[✓] Katapult bootloader detected on Toolhead Board!${NC}"
        echo -e "${GREEN}    Auto-skipping Toolhead Katapult deployer step.${NC}\n"
        local thr_items=(
            "[1] Flash Toolhead firmware (thr.bin) directly over /dev/ttyS4"
            "[2] Skip Toolhead flashing"
            "[3] Force re-deploy Katapult (thr-deployer.bin)"
            "[b] ⬅️  Back to Main Menu"
            "[q] 🚪 Exit Installer"
        )
        local thr_header="${BLUE}${BOLD}--- PART 2 OF 2: TOOLHEAD BOARD (THR - GD32F303) ---${NC}\n"
        thr_header+="${GREEN}[✓] Katapult bootloader is already installed on /dev/ttyS4.${NC}\n"
        thr_header+="Select an action:"

        local thr_res
        thr_res=$(arrow_menu "$thr_header" thr_items 0)
        case "$thr_res" in
            0) thr_state="2" ;; # Direct flash thr.bin
            1) thr_state="3" ;; # Skip
            2) thr_state="1" ;; # Force re-deploy
            3|b|back|menu|m) return 10 ;;
            4|q|quit|exit) nav_quit ;;
            *) thr_state="2" ;;
        esac
    else
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
        case "$thr_res" in
            0) thr_state="1" ;; # Stock auto-deployer
            1) thr_state="2" ;; # Direct flash
            2) thr_state="3" ;; # Skip
            3|b|back|menu|m) return 10 ;;
            4|q|quit|exit) nav_quit ;;
            *) thr_state="1" ;;
        esac
    fi

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
            mark_katapult_installed "thr"
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
            mark_katapult_installed "thr"
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

    chown -R "$REAL_USER:$REAL_USER" "$target_cfg" 2>/dev/null || true

    echo ""
    echo -e "${CYAN}[*] Starting Klipper service...${NC}"
    systemctl start klipper 2>/dev/null || true
    export KLIPPER_STOPPED=0
    echo -e "${GREEN}${BOLD}[✓] Printer Firmware (Motion MCU + Toolhead) Setup Complete!${NC}"
}

# ==============================================================================
# WORKFLOW 2: QIDI BOX (MMU) FIRMWARE & CONFIG (OPTIONAL / SEPARATE)
# ==============================================================================
install_box_firmware() {
    ensure_pyserial
    local target_cfg
    target_cfg=$(get_target_config_dir)

    local box_opt=""
    if is_katapult_installed_mmu; then
        echo -e "${GREEN}${BOLD}[✓] Katapult bootloader detected on Qidi Box!${NC}"
        echo -e "${GREEN}    Auto-skipping Qidi Box deployer step.${NC}\n"
        local box_items=(
            "[1] Flash Qidi Box firmware (mmu.bin) directly over USB"
            "[2] Enable Qidi Box in Config Only (Already flashed previously)"
            "[3] Force re-deploy Katapult (mmu-deployer.bin)"
            "[4] Do NOT use Qidi Box (Disable MMU / Run as Single-Spool Printer)"
            "[b] ⬅️  Back to Main Menu"
            "[q] 🚪 Exit Installer"
        )
        local box_header="${CYAN}${BOLD}======================================================================${NC}\n"
        box_header+="${BOLD} 🎨 QIDI BOX (MMU) FIRMWARE & CONFIGURATION (OPTIONAL)${NC}\n"
        box_header+="${CYAN}======================================================================${NC}\n"
        box_header+="${GREEN}[✓] Katapult bootloader is already installed on the Qidi Box.${NC}\n\n"
        box_header+="Select an action:"

        local box_res
        box_res=$(arrow_menu "$box_header" box_items 0)
        case "$box_res" in
            0) box_opt="2" ;; # Direct flash mmu.bin (Katapult ready)
            1) box_opt="3" ;; # Config only
            2) box_opt="1" ;; # Force re-deploy Katapult
            3) box_opt="4" ;; # Disable MMU
            4|b|back|menu|m) return 10 ;;
            5|q|quit|exit) nav_quit ;;
            *) return 10 ;;
        esac
    else
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
        case "$box_res" in
            0) box_opt="1" ;;
            1) box_opt="2" ;;
            2) box_opt="3" ;;
            3) box_opt="4" ;;
            4|b|back|menu|m) return 10 ;;
            5|q|quit|exit) nav_quit ;;
            *) return 10 ;;
        esac
    fi

    # Ensure MMU config files exist in target_cfg
    mkdir -p "$target_cfg"
    for item in mmu mmu.cfg mmu_custom_actions.cfg mmu_ui_bridge.cfg sync_spoolman.cfg; do
        if [[ ! -e "$target_cfg/$item" && -e "$SUITE_ROOT/configs/$item" ]]; then
            cp -rp "$SUITE_ROOT/configs/$item" "$target_cfg/"
        fi
    done

    case "$box_opt" in
        1|2)
            systemctl stop klipper 2>/dev/null || true
            export KLIPPER_STOPPED=1
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
                for mmu_cfg in "$target_cfg/mmu/base/mmu.cfg" "$target_cfg/mmu/base/mmu_hardware.cfg" "$target_cfg/mmu.cfg"; do
                    if [[ -f "$mmu_cfg" ]]; then
                        sed -i "s|serial:.*|serial: ${mmu_dev}|g" "$mmu_cfg"
                    fi
                done
                mark_katapult_installed "mmu"
                echo -e "${GREEN}[✓] Qidi Box firmware flashed and serial updated!${NC}"
            fi
            # Enable MMU in printer.cfg
            enable_mmu_in_config "$target_cfg/printer.cfg"
            chown -R "$REAL_USER:$REAL_USER" "$target_cfg" 2>/dev/null || true
            systemctl start klipper 2>/dev/null || true
            export KLIPPER_STOPPED=0
            ;;
        3)
            mark_katapult_installed "mmu"
            enable_mmu_in_config "$target_cfg/printer.cfg"
            chown -R "$REAL_USER:$REAL_USER" "$target_cfg" 2>/dev/null || true
            systemctl restart klipper 2>/dev/null || true
            export KLIPPER_STOPPED=0
            ;;
        4)
            disable_mmu_in_config "$target_cfg/printer.cfg"
            chown -R "$REAL_USER:$REAL_USER" "$target_cfg" 2>/dev/null || true
            systemctl restart klipper 2>/dev/null || true
            export KLIPPER_STOPPED=0
            ;;
        *)
            return 10
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
import os, re
p = "$cfg_file"
with open(p, "r") as f:
    c = f.read()

cfg_dir = os.path.dirname(p)
mr_path = os.path.join(cfg_dir, "moonraker.conf")
spoolman_line = "#[include sync_spoolman.cfg]"
if os.path.isfile(mr_path):
    with open(mr_path, "r") as mf:
        mc = mf.read()
    if re.search(r"^\s*\[spoolman\]", mc, re.MULTILINE):
        spoolman_line = "[include sync_spoolman.cfg]"

block = f"""# <MMU_SUITE_START>
# Qidi Box MMU Disabled (Standalone Single-Extruder Mode)
#[include mmu.cfg]
#[include mmu_custom_actions.cfg]
#[include mmu_ui_bridge.cfg]
{spoolman_line}
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
    --source-only)
        return 0 2>/dev/null || exit 0
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
            2|b|back|menu|m) exit 10 ;;
            3|q|quit|exit) nav_quit ;;
        esac
        ;;
esac
