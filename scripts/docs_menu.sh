#!/usr/bin/env bash
# ==============================================================================
# docs_menu.sh: Interactive Viewer for Tips, Instructions, Firmware Anatomy,
#               Slicer G-Codes, and Beginner Troubleshooting Commands
# ==============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SUITE_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

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
    echo ""
    read -rp "👉 Press ENTER to return to the Tips & Troubleshooting menu..." _
}

run_live_health_check() {
    echo ""
    echo -e "${CYAN}${BOLD}======================================================================${NC}"
    echo -e "${BOLD} 🩺 LIVE QIDI Q2 AP BOARD HEALTH & CONNECTION DIAGNOSTIC${NC}"
    echo -e "${CYAN}======================================================================${NC}"

    echo -e "\n${BOLD}1. Linux Kernel Version:${NC}"
    uname -a || true

    echo -e "\n${BOLD}2. Detected USB Boards (/dev/serial/by-id/):${NC}"
    if [[ -d /dev/serial/by-id ]] && [[ -n "$(ls -A /dev/serial/by-id 2>/dev/null)" ]]; then
        ls -l /dev/serial/by-id/
    else
        echo -e "   ${YELLOW}[!] No USB serial devices found in /dev/serial/by-id/${NC}"
    fi

    echo -e "\n${BOLD}3. Internal Toolhead Serial Port (/dev/ttyS4):${NC}"
    if [[ -e /dev/ttyS4 ]]; then
        ls -l /dev/ttyS4
    else
        echo -e "   ${YELLOW}[!] /dev/ttyS4 not detected.${NC}"
    fi

    echo -e "\n${BOLD}4. CPU Governor Speed Mode:${NC}"
    cat /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor 2>/dev/null | sort -u || echo "   (Not available on this host)"

    echo -e "\n${BOLD}5. Wi-Fi Power-Save Sleep Status (wlan0):${NC}"
    iw dev wlan0 get power_save 2>/dev/null || echo "   (iw / wlan0 not active)"

    echo -e "\n${BOLD}6. Klipper & Moonraker Service Status:${NC}"
    echo -n "   • klipper:   " && systemctl is-active klipper 2>/dev/null || true
    echo -n "   • moonraker: " && systemctl is-active moonraker 2>/dev/null || true

    echo ""
    read -rp "👉 Press ENTER to return to the Tips & Troubleshooting menu..." _
}

while true; do
    echo ""
    echo -e "${CYAN}${BOLD}======================================================================${NC}"
    echo -e "${BOLD} 📖 TIPS, INSTRUCTIONS, FIRMWARE ANATOMY & TROUBLESHOOTING MENU${NC}"
    echo -e "${CYAN}======================================================================${NC}"
    echo -e "  [${GREEN}1${NC}] 🧬 ${BOLD}Firmware & Printer Anatomy${NC} (How the 4 boards & firmware work)"
    echo -e "  [${GREEN}2${NC}] 🚑 ${BOLD}Troubleshooting & Copy-Paste Terminal Commands${NC}"
    echo -e "  [${GREEN}3${NC}] 🖨️  ${BOLD}Slicer Start / End G-Code Copy-Paste Guide${NC} (OrcaSlicer)"
    echo -e "  [${GREEN}4${NC}] 📋 ${BOLD}Step-by-Step Instructions & Overview${NC} (README)"
    echo -e "  [${CYAN}5${NC}] 🩺 ${BOLD}Run Live Printer Health & USB Connection Check Now${NC}"
    echo -e "  [${YELLOW}0${NC}] ⬅️  Back to Main Menu"
    echo -e "${CYAN}======================================================================${NC}"
    read -rp "👉 Select an option [0-5]: " doc_opt

    case "$doc_opt" in
        1)
            show_file_clean "$SUITE_ROOT/FIRMWARE_ANATOMY.md"
            ;;
        2)
            show_file_clean "$SUITE_ROOT/TROUBLESHOOTING.md"
            ;;
        3)
            show_file_clean "$SUITE_ROOT/SLICER_GUIDE.md"
            ;;
        4)
            show_file_clean "$SUITE_ROOT/README.md"
            ;;
        5)
            run_live_health_check
            ;;
        0|q|Q|"")
            break
            ;;
        *)
            echo "Invalid selection."
            ;;
    esac
done
