#!/usr/bin/env bash
# ==============================================================================
# restore.sh: Universal Named-Backup Restore Center for Qidi Q2 AP Board
# Lets users pick any custom-named backup and restore 100% or individual parts
# ==============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/scripts/ui_nav.sh"

PRESET_MODE="${1:-}"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

if [[ "${SIM_MODE:-0}" != "1" && $EUID -ne 0 ]]; then
    echo -e "${RED}[-] Please run with sudo: sudo bash $0${NC}"
    exit 1
fi

if [[ ! -d "$BACKUP_ROOT_DIR" ]] || [[ -z "$(ls -A "$BACKUP_ROOT_DIR" 2>/dev/null)" ]]; then
    echo ""
    echo -e "${CYAN}${BOLD}======================================================================${NC}"
    echo -e "${BOLD} 🔄 QIDI Q2 AP BOARD — UNIVERSAL NAMED-BACKUP RESTORE CENTER${NC}"
    echo -e "${CYAN}======================================================================${NC}"
    echo -e "${YELLOW}[!] No named backups found in ${BACKUP_ROOT_DIR} yet.${NC}"
    echo "    Backups are created automatically whenever you run an option in install.sh."
    exit 0
fi

backups=()
while IFS= read -r dir; do
    [[ ! -d "$dir" || ! -f "$dir/restore.sh" ]] && continue
    backups+=("$dir")
done < <(ls -1dt "$BACKUP_ROOT_DIR"/*/ 2>/dev/null)

total=${#backups[@]}
if [[ "$total" -eq 0 ]]; then
    echo -e "${YELLOW}[!] No restorable backup snapshots found in ${BACKUP_ROOT_DIR}.${NC}"
    exit 0
fi

b_items=()
for dir in "${backups[@]}"; do
    b_name=$(grep -E '^BACKUP_NAME=' "$dir/backup_info.txt" 2>/dev/null | cut -d= -f2- | tr -d '"' || basename "$dir")
    b_date=$(grep -E '^DATE_CREATED=' "$dir/backup_info.txt" 2>/dev/null | cut -d= -f2- | tr -d '"' || echo "Unknown date")
    b_cat=$(grep -E '^CATEGORY=' "$dir/backup_info.txt" 2>/dev/null | cut -d= -f2- | tr -d '"' || echo "snapshot")
    b_items+=("${b_name} (${b_date} — ${b_cat})")
done
b_items+=("⬅️  Back to Main Menu")
b_items+=("🚪 Exit Installer")

b_header="${CYAN}${BOLD}======================================================================${NC}\n"
b_header+="${BOLD} 🔄 QIDI Q2 AP BOARD — UNIVERSAL NAMED-BACKUP RESTORE CENTER${NC}\n"
b_header+="${CYAN}======================================================================${NC}\n"
b_header+="Select which backup snapshot you want to restore from:"

while true; do
    b_res=$(arrow_menu "$b_header" b_items 0)
    selected_dir=""

    case "$b_res" in
        back|b|menu|m) exit 10 ;;
        quit|q|exit) nav_quit ;;
        *)
            if [[ "$b_res" =~ ^[0-9]+$ ]]; then
                if [[ "$b_res" -lt "$total" ]]; then
                    selected_dir="${backups[$b_res]}"
                elif [[ "$b_res" -eq "$total" ]]; then
                    exit 10 # Back
                else
                    nav_quit # Exit
                fi
            else
                exit 10
            fi
            ;;
    esac

    if [[ -n "$PRESET_MODE" ]]; then
        bash "$selected_dir/restore.sh" "$PRESET_MODE"
        exit 0
    fi

    scope_items=(
        "[1] 100% Everything (Configs, Macros, Network, AP Board, and Kernel if saved)"
        "[2] Restore Klipper Configs & Macros Only"
        "[3] Restore Network Adapter Settings Only"
        "[4] Restore AP Board CPU & Disk Settings Only"
        "[5] Restore Factory Linux Kernel (boot partition) Only"
        "[b] ⬅️  Back to Backup Selection"
        "[q] 🚪 Exit Installer"
    )

    scope_header="${CYAN}${BOLD}======================================================================${NC}\n"
    scope_header+="${BOLD} What would you like to restore from backup: $(basename "$selected_dir")?${NC}\n"
    scope_header+="${CYAN}======================================================================${NC}"
    scope_res=$(arrow_menu "$scope_header" scope_items 0)

    case "$scope_res" in
        0)
            bash "$selected_dir/restore.sh" --full
            exit 0
            ;;
        1)
            bash "$selected_dir/restore.sh" --macros-only
            exit 0
            ;;
        2)
            bash "$selected_dir/restore.sh" --network-only
            exit 0
            ;;
        3)
            bash "$selected_dir/restore.sh" --ap-only
            exit 0
            ;;
        4)
            bash "$selected_dir/restore.sh" --kernel-only
            exit 0
            ;;
        5|b|back)
            continue
            ;;
        menu|m)
            exit 10
            ;;
        6|q|quit|exit)
            nav_quit
            ;;
        *)
            continue
            ;;
    esac
done
