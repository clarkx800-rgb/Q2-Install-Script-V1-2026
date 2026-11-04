#!/usr/bin/env bash
# ==============================================================================
# docs_menu.sh: Interactive Viewer for Tips, Instructions, Firmware Anatomy,
#               Slicer G-Codes, and Beginner Troubleshooting Commands
# ==============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SUITE_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

source "$SCRIPT_DIR/ui_nav.sh"

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

show_file_clean() {
    local file_path="$1"
    echo ""
    echo -e "${CYAN}${BOLD}----------------------------------------------------------------------${NC}"
    if [[ -f "$file_path" ]]; then
        cat "$file_path"
    else
        echo "File not found: $file_path"
    fi
    echo -e "${CYAN}${BOLD}----------------------------------------------------------------------${NC}"
    nav_pause "Press ENTER (or 'b') to return to the Tips & Troubleshooting menu..." || true
}

run_live_health_check() {
    local serial_dir="${SIM_DEV_SERIAL:-/dev/serial/by-id}"
    local ttys4_dev="${SIM_TTYS4:-/dev/ttyS4}"

    echo ""
    echo -e "${CYAN}${BOLD}======================================================================${NC}"
    echo -e "${BOLD} 🩺 LIVE QIDI Q2 AP BOARD HEALTH & CONNECTION DIAGNOSTIC${NC}"
    echo -e "${CYAN}======================================================================${NC}"

    echo -e "\n${BOLD}1. Linux Kernel Version:${NC}"
    uname -a || true

    echo -e "\n${BOLD}2. Detected USB Boards (${serial_dir}/):${NC}"
    if [[ -d "$serial_dir" ]] && [[ -n "$(ls -A "$serial_dir" 2>/dev/null)" ]]; then
        ls -l "$serial_dir"/
    else
        echo -e "   ${YELLOW}[!] No USB serial devices found in ${serial_dir}/${NC}"
    fi

    echo -e "\n${BOLD}3. Internal Toolhead Serial Port (${ttys4_dev}):${NC}"
    if [[ -e "$ttys4_dev" ]]; then
        ls -l "$ttys4_dev"
    else
        echo -e "   ${YELLOW}[!] ${ttys4_dev} not detected.${NC}"
    fi

    echo -e "\n${BOLD}4. Katapult Bootloader Auto-Detection Status:${NC}"
    if source "$SCRIPT_DIR/flash_firmware.sh" --source-only 2>/dev/null; then
        if is_katapult_installed_mcu; then
            echo -e "   • Motion Mainboard (MCU): ${GREEN}[✓] Installed / Ready${NC}"
        else
            echo -e "   • Motion Mainboard (MCU): ${YELLOW}[ ] Stock / Not yet marked${NC}"
        fi
        if is_katapult_installed_thr; then
            echo -e "   • Toolhead Board (THR):   ${GREEN}[✓] Installed / Ready${NC}"
        else
            echo -e "   • Toolhead Board (THR):   ${YELLOW}[ ] Stock / Not yet marked${NC}"
        fi
        if is_katapult_installed_mmu; then
            echo -e "   • Qidi Box (MMU):         ${GREEN}[✓] Installed / Ready${NC}"
        else
            echo -e "   • Qidi Box (MMU):         ${YELLOW}[ ] Stock / Not yet marked${NC}"
        fi
    fi

    echo -e "\n${BOLD}5. CPU Governor Speed Mode:${NC}"
    cat /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor 2>/dev/null | sort -u || echo "   (Not available on this host)"

    echo -e "\n${BOLD}6. Wi-Fi Power-Save Sleep Status (wlan0):${NC}"
    iw dev wlan0 get power_save 2>/dev/null || echo "   (iw / wlan0 not active)"

    echo -e "\n${BOLD}7. Klipper & Moonraker Service Status:${NC}"
    echo -n "   • klipper:   " && systemctl is-active klipper 2>/dev/null || true
    echo -n "   • moonraker: " && systemctl is-active moonraker 2>/dev/null || true

    echo ""
    nav_pause "Press ENTER (or 'b') to return to the Tips & Troubleshooting menu..." || true
}

while true; do
    doc_items=(
        "[1] 🧬 Firmware & Printer Anatomy (How the 4 boards & firmware work)"
        "[2] 🚑 Troubleshooting & Copy-Paste Terminal Commands"
        "[3] 🖨️  Slicer Start / End G-Code Copy-Paste Guide (OrcaSlicer)"
        "[4] 📋 Step-by-Step Instructions & Overview (README)"
        "[5] 🩺 Run Live Printer Health & USB Connection Check Now"
        "[b] ⬅️  Back to Main Menu"
        "[q] 🚪 Exit Installer"
    )

    doc_header="${CYAN}${BOLD}======================================================================${NC}\n"
    doc_header+="${BOLD} 📖 TIPS, INSTRUCTIONS, FIRMWARE ANATOMY & TROUBLESHOOTING MENU${NC}\n"
    doc_header+="${CYAN}======================================================================${NC}"

    doc_res=$(arrow_menu "$doc_header" doc_items 0)

    case "$doc_res" in
        0)
            show_file_clean "$SUITE_ROOT/FIRMWARE_ANATOMY.md"
            ;;
        1)
            show_file_clean "$SUITE_ROOT/TROUBLESHOOTING.md"
            ;;
        2)
            show_file_clean "$SUITE_ROOT/SLICER_GUIDE.md"
            ;;
        3)
            show_file_clean "$SUITE_ROOT/README.md"
            ;;
        4)
            run_live_health_check
            ;;
        5|b|back|menu|m)
            exit 10
            ;;
        6|q|quit|exit)
            nav_quit
            ;;
        *)
            echo "Invalid selection."
            ;;
    esac
done
