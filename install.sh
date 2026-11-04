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

source "$SCRIPTS_DIR/ui_nav.sh"

# ANSI Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

if [[ "${SIM_MODE:-0}" != "1" && $EUID -ne 0 ]]; then
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
read -rp "👉 Do you understand and accept 100% of the risk? Type 'yes' to continue (or 'q' to quit): " accept_risk
case "${accept_risk,,}" in
    yes|y) ;;
    *)
        echo -e "${GREEN}${BOLD}Exiting installer without making any changes. Goodbye!${NC}"
        exit 0
        ;;
esac

run_child() {
    local st=0
    INSTALLER_CHILD=1 bash "$@" || st=$?
    if [[ $st -eq 20 ]]; then
        exit 0
    fi
    return $st
}

submenu_refinement() {
    local title="$1"
    local category="$2"
    local apply_script="$3"
    local restore_flag="$4"

    local sub_items=(
        "[1] Apply / Install this refinement (Prompts to save a named backup first)"
        "[2] Restore / Undo this refinement from a named backup"
        "[b] ⬅️  Back to Main Menu (or type 'menu')"
        "[q] 🚪 Exit Installer (or type 'quit')"
    )

    local sub_header="${CYAN}${BOLD}======================================================================${NC}\n"
    sub_header+="${BOLD} ${title}${NC}\n"
    sub_header+="${CYAN}======================================================================${NC}"

    local sub_res
    sub_res=$(arrow_menu "$sub_header" sub_items 0)

    case "$sub_res" in
        0)
            local bkp_st=0
            run_child "$SCRIPTS_DIR/backup_machine.sh" "$category" || bkp_st=$?
            if [[ $bkp_st -ne 0 ]]; then
                echo -e "${YELLOW}[*] Action cancelled. Returning to menu...${NC}"
                sleep 1
                return 0
            fi

            if [[ "$category" == "kernel" ]]; then
                local latest_bkp=""
                [[ -f "$BACKUP_ROOT_DIR/.latest_backup_path" ]] && latest_bkp=$(cat "$BACKUP_ROOT_DIR/.latest_backup_path")
                if [[ -n "$latest_bkp" && -f "$latest_bkp/system/factory_boot.img" ]]; then
                    run_child "$apply_script" "$latest_bkp/system/factory_boot.img"
                else
                    run_child "$apply_script"
                fi
            else
                run_child "$apply_script"
            fi
            nav_pause || true
            ;;
        1)
            local rst_st=0
            run_child "$SUITE_ROOT/restore.sh" "$restore_flag" || rst_st=$?
            [[ $rst_st -eq 10 ]] && return 0
            nav_pause || true
            ;;
        2|b|back|m|menu)
            return 0
            ;;
        3|q|quit|exit)
            nav_quit
            ;;
    esac
}

while true; do
    menu_items=(
        "[1]  🖨️  Install Printer Firmware (Motion Mainboard MCU + Toolhead MCU)"
        "[2]  🎨 Install / Configure Qidi Box MMU Firmware (Optional / Separate)"
        "[3]  🧵 Spoolman Manager Setup (Optional: Connect to PC / Server IP)"
        "[4]  🧩 Macro Setup: Install Pucci's Macros OR Keep Your Own Macros"
        "[5]  ⏪ Restore Your Previous Macros (If you don't like Pucci's macros)"
        "[6]  📡 Network Adapter Refinement (Apply or Restore Wi-Fi Sleep Fix)"
        "[7]  ⚡ AP Board 'Timer Too Close' Refinement (Apply or Restore CPU/Disk Fix)"
        "[8]  🐧 N3oney's Modern 5.10 Linux Kernel (Install or Restore q2_boot.img)"
        "[9]  🔄 Universal Restore Center (Restore 100% from any named backup)"
        "[10] 📖 Tips, Instructions, Firmware Anatomy & Troubleshooting"
        "[0]  🚪 Exit Installer (or press 'q')"
    )

    main_header="${CYAN}${BOLD}========================================================================${NC}\n"
    main_header+="${BOLD}   🛠️  QIDI Q2 AP BOARD — COMMUNITY INSTALLER & RESCUE CONTROL CENTER${NC}\n"
    main_header+="${CYAN}========================================================================${NC}\n"
    main_header+="  Choose an option using ${BOLD}↑/↓${NC} arrow keys with ${BOLD}>${NC} indicator, or type number.\n"
    main_header+="  Before any change is made, you will be prompted to name a backup.\n"
    main_header+="  Type ${BOLD}'b'${NC} to go back, ${BOLD}'menu'${NC} for main menu, or ${BOLD}'q'${NC} to exit anytime."

    main_res=$(arrow_menu "$main_header" menu_items 0)

    case "$main_res" in
        0)
            bkp_st=0
            run_child "$SCRIPTS_DIR/backup_machine.sh" "printer_firmware" || bkp_st=$?
            [[ $bkp_st -ne 0 ]] && continue
            local_st=0
            run_child "$SCRIPTS_DIR/flash_firmware.sh" --printer || local_st=$?
            [[ $local_st -eq 10 ]] && continue
            nav_pause || true
            ;;
        1)
            bkp_st=0
            run_child "$SCRIPTS_DIR/backup_machine.sh" "qidi_box_firmware" || bkp_st=$?
            [[ $bkp_st -ne 0 ]] && continue
            local_st=0
            run_child "$SCRIPTS_DIR/flash_firmware.sh" --box || local_st=$?
            [[ $local_st -eq 10 ]] && continue
            nav_pause || true
            ;;
        2)
            local_st=0
            run_child "$SCRIPTS_DIR/configure_spoolman.sh" || local_st=$?
            [[ $local_st -eq 10 ]] && continue
            nav_pause || true
            ;;
        3)
            local_st=0
            run_child "$SCRIPTS_DIR/manage_macros.sh" --choose || local_st=$?
            [[ $local_st -eq 10 ]] && continue
            nav_pause || true
            ;;
        4)
            local_st=0
            run_child "$SCRIPTS_DIR/manage_macros.sh" --restore || local_st=$?
            [[ $local_st -eq 10 ]] && continue
            nav_pause || true
            ;;
        5)
            submenu_refinement \
                "📡 NETWORK ADAPTER REFINEMENT (Wi-Fi Sleep Killer + 2MB TCP Buffers)" \
                "network_refinement" \
                "$SCRIPTS_DIR/apply_network_refinement.sh" \
                "--network-only"
            ;;
        6)
            submenu_refinement \
                "⚡ AP BOARD 'TIMER TOO CLOSE' REFINEMENT (1.1GHz Lock + Disk Unchoke)" \
                "ap_board_refinement" \
                "$SCRIPTS_DIR/apply_ap_board_refinement.sh" \
                "--ap-only"
            ;;
        7)
            submenu_refinement \
                "🐧 N3ONEY MODERN 5.10 LINUX KERNEL (q2_boot.img)" \
                "kernel" \
                "$SCRIPTS_DIR/flash_kernel.sh" \
                "--kernel-only"
            ;;
        8)
            local_st=0
            run_child "$SUITE_ROOT/restore.sh" || local_st=$?
            [[ $local_st -eq 10 ]] && continue
            nav_pause || true
            ;;
        9)
            local_st=0
            run_child "$SCRIPTS_DIR/docs_menu.sh" || local_st=$?
            [[ $local_st -eq 10 ]] && continue
            ;;
        10|q|quit|exit)
            echo ""
            echo -e "${GREEN}${BOLD}Thank you for using the Qidi Q2 AP Board Mint System Suite! Happy Printing!${NC}"
            exit 0
            ;;
        back|b|menu|m)
            continue
            ;;
        *)
            echo -e "${RED}Invalid option.${NC}"
            sleep 1
            ;;
    esac
done
