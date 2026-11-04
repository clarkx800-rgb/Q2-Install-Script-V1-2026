#!/usr/bin/env bash
# ==============================================================================
# QIDI Q2 AP BOARD — "MINT SYSTEM" COMMUNITY INSTALLER & RESCUE CONTROL CENTER
# ==============================================================================
# Beginner-Friendly Segmented Menu:
#   • Pick & choose individual upgrades one at a time
#   • Prompts you to name a 100% restorable backup before EVERY action
#   • Separate Printer Firmware (Motion MCU + Toolhead) vs Optional Qidi Box MMU
#   • Separate Macro Selector (Pucci Macros vs Keep Your Own) + Instant Macro Restore
#   • Separate Network, AP Board, and N3oney 5.10 Kernel Refinements (Apply or Restore)
#   • Built-in Tips, Instructions, Firmware Anatomy & Troubleshooting Menu
# ==============================================================================
set -euo pipefail

SUITE_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS_DIR="$SUITE_ROOT/scripts"
REAL_USER="${SUDO_USER:-$USER}"
USER_HOME=$(eval echo "~$REAL_USER")
BACKUP_ROOT_DIR="$USER_HOME/q2_ap_backups"

# ANSI Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

if [[ $EUID -ne 0 ]]; then
    echo -e "${RED}${BOLD}[-] Please run this installer with sudo:${NC}"
    echo -e "    ${CYAN}sudo bash install.sh${NC}"
    exit 1
fi

chmod +x "$SCRIPTS_DIR"/*.sh "$SUITE_ROOT/restore.sh" 2>/dev/null || true

clear 2>/dev/null || true
echo -e "${RED}${BOLD}========================================================================${NC}"
echo -e "${YELLOW}${BOLD}   ⚠️  CRITICAL WARNING & LIABILITY DISCLAIMER — READ CAREFULLY  ⚠️${NC}"
echo -e "${RED}${BOLD}========================================================================${NC}"
echo -e "  1. ${BOLD}UNTESTED INSTALL SCRIPT:${NC} This installer script wrapper was packaged"
echo -e "     from a pre-migration backup and ${RED}${BOLD}HAS NEVER BEEN TESTED${NC} on a live machine."
echo -e "  2. ${BOLD}ZERO LIABILITY:${NC} The repository author (${BOLD}clarkx800-rgb${NC}) is ${RED}${BOLD}NOT responsible${NC}"
echo -e "     for any damages, bricked boards, fires, injuries, or anything else."
echo -e "  3. ${BOLD}NO SUPPORT:${NC} Provided strictly 'AS-IS' with ${RED}${BOLD}NO support${NC} whatsoever."
echo -e "  4. ${BOLD}CREDITS:${NC} Built on upstream work by n3oney, Kalico, Klipper, Arksine"
echo -e "     (Katapult/Moonraker), moggieuk (Happy Hare), & prestonbrown (HelixScreen)."
echo -e "${RED}${BOLD}========================================================================${NC}"
echo ""
read -rp "👉 Do you understand and accept 100% of the risk? Type 'yes' to continue: " accept_risk
if [[ "${accept_risk,,}" != "yes" && "${accept_risk,,}" != "y" ]]; then
    echo "Exiting without making any changes."
    exit 0
fi

pause_return() {
    echo ""
    read -rp "👉 Press ENTER to return to the Main Control Center..." _
}

submenu_refinement() {
    local title="$1"
    local category="$2"
    local apply_script="$3"
    local restore_flag="$4"

    echo ""
    echo -e "${CYAN}${BOLD}======================================================================${NC}"
    echo -e "${BOLD} ${title}${NC}"
    echo -e "${CYAN}======================================================================${NC}"
    echo -e "  [${GREEN}1${NC}] ${BOLD}Apply / Install${NC} this refinement (Prompts to save a named backup first)"
    echo -e "  [${YELLOW}2${NC}] ${BOLD}Restore / Undo${NC} this refinement from a named backup"
    echo -e "  [${CYAN}0${NC}] Cancel / Back to Main Menu"
    echo ""
    read -rp "👉 Choose an action [0-2]: " sub_act

    case "$sub_act" in
        1)
            bash "$SCRIPTS_DIR/backup_machine.sh" "$category"
            if [[ "$category" == "kernel" ]]; then
                local latest_bkp=""
                [[ -f "$BACKUP_ROOT_DIR/.latest_backup_path" ]] && latest_bkp=$(cat "$BACKUP_ROOT_DIR/.latest_backup_path")
                if [[ -n "$latest_bkp" && -f "$latest_bkp/system/factory_boot.img" ]]; then
                    bash "$apply_script" "$latest_bkp/system/factory_boot.img"
                else
                    bash "$apply_script"
                fi
            else
                bash "$apply_script"
            fi
            pause_return
            ;;
        2)
            bash "$SUITE_ROOT/restore.sh" "$restore_flag"
            pause_return
            ;;
        *)
            ;;
    esac
}

while true; do
    clear 2>/dev/null || true
    echo -e "${CYAN}${BOLD}========================================================================${NC}"
    echo -e "${BOLD}   🛠️  QIDI Q2 AP BOARD — COMMUNITY INSTALLER & RESCUE CONTROL CENTER${NC}"
    echo -e "${CYAN}========================================================================${NC}"
    echo -e "  Welcome! Choose one item at a time. Before any change is made, you"
    echo -e "  will be asked to ${BOLD}name a backup snapshot${NC} so you can restore 100% anytime."
    echo ""
    echo -e "  ${BLUE}${BOLD}--- FIRMWARE, MACROS & TOOLS ---${NC}"
    echo -e "  [${GREEN}1${NC}] 🖨️  ${BOLD}Install Printer Firmware${NC} (Motion Mainboard MCU + Toolhead MCU)"
    echo -e "  [${GREEN}2${NC}] 🎨 ${BOLD}Install / Configure Qidi Box MMU Firmware${NC} (Optional / Separate)"
    echo -e "  [${GREEN}3${NC}] 🧵 ${BOLD}Spoolman Manager Setup${NC} (Optional: Connect to PC / Server IP)"
    echo -e "  [${GREEN}4${NC}] 🧩 ${BOLD}Macro Setup:${NC} Install Pucci's Macros OR Keep Your Own Macros"
    echo -e "  [${YELLOW}5${NC}] ⏪ ${BOLD}Restore Your Previous Macros${NC} (If you don't like Pucci's macros)"
    echo ""
    echo -e "  ${BLUE}${BOLD}--- AP BOARD REFINEMENTS (EACH SEPARATE & RESTORABLE) ---${NC}"
    echo -e "  [${GREEN}6${NC}] 📡 ${BOLD}Network Adapter Refinement${NC} (Apply or Restore Wi-Fi Sleep Fix)"
    echo -e "  [${GREEN}7${NC}] ⚡ ${BOLD}AP Board 'Timer Too Close' Refinement${NC} (Apply or Restore CPU/Disk Fix)"
    echo -e "  [${GREEN}8${NC}] 🐧 ${BOLD}N3oney's Modern 5.10 Linux Kernel${NC} (Install or Restore q2_boot.img)"
    echo ""
    echo -e "  ${BLUE}${BOLD}--- BACKUP, RESTORE & HELP ---${NC}"
    echo -e "  [${CYAN}9${NC}] 🔄 ${BOLD}Universal Restore Center${NC} (Restore 100% from any named backup)"
    echo -e "  [${CYAN}10${NC}] 📖 ${BOLD}Tips, Instructions, Firmware Anatomy & Troubleshooting${NC}"
    echo -e "  [${RED}0${NC}] 🚪 Exit Installer"
    echo -e "${CYAN}========================================================================${NC}"
    read -rp "👉 Enter your choice [0-10]: " main_opt

    case "$main_opt" in
        1)
            bash "$SCRIPTS_DIR/backup_machine.sh" "printer_firmware"
            bash "$SCRIPTS_DIR/flash_firmware.sh" --printer
            pause_return
            ;;
        2)
            bash "$SCRIPTS_DIR/backup_machine.sh" "qidi_box_firmware"
            bash "$SCRIPTS_DIR/flash_firmware.sh" --box
            pause_return
            ;;
        3)
            bash "$SCRIPTS_DIR/configure_spoolman.sh"
            pause_return
            ;;
        4)
            bash "$SCRIPTS_DIR/manage_macros.sh" --choose
            pause_return
            ;;
        5)
            bash "$SCRIPTS_DIR/manage_macros.sh" --restore
            pause_return
            ;;
        6)
            submenu_refinement \
                "📡 NETWORK ADAPTER REFINEMENT (Wi-Fi Sleep Killer + 2MB TCP Buffers)" \
                "network_refinement" \
                "$SCRIPTS_DIR/apply_network_refinement.sh" \
                "--network-only"
            ;;
        7)
            submenu_refinement \
                "⚡ AP BOARD 'TIMER TOO CLOSE' REFINEMENT (1.1GHz Lock + Disk Unchoke)" \
                "ap_board_refinement" \
                "$SCRIPTS_DIR/apply_ap_board_refinement.sh" \
                "--ap-only"
            ;;
        8)
            submenu_refinement \
                "🐧 N3ONEY MODERN 5.10 LINUX KERNEL (q2_boot.img)" \
                "kernel" \
                "$SCRIPTS_DIR/flash_kernel.sh" \
                "--kernel-only"
            ;;
        9)
            bash "$SUITE_ROOT/restore.sh"
            pause_return
            ;;
        10)
            bash "$SCRIPTS_DIR/docs_menu.sh"
            ;;
        0|q|Q)
            echo ""
            echo -e "${GREEN}${BOLD}Thank you for using the Qidi Q2 AP Board Mint System Suite! Happy Printing!${NC}"
            exit 0
            ;;
        *)
            echo -e "${RED}Invalid option. Please enter a number from 0 to 10.${NC}"
            sleep 1
            ;;
    esac
done
