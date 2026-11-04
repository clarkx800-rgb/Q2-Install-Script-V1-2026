#!/usr/bin/env bash
# ==============================================================================
# restore.sh: Universal Named-Backup Restore Center for Qidi Q2 AP Board
# Lets users pick any custom-named backup and restore 100% or individual parts
# ==============================================================================
set -euo pipefail

PRESET_MODE="${1:-}"
REAL_USER="${SUDO_USER:-$USER}"
USER_HOME=$(eval echo "~$REAL_USER")
BACKUP_ROOT_DIR="$USER_HOME/q2_ap_backups"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

if [[ $EUID -ne 0 ]]; then
    echo -e "${RED}[-] Please run with sudo: sudo bash $0${NC}"
    exit 1
fi

echo ""
echo -e "${CYAN}${BOLD}======================================================================${NC}"
echo -e "${BOLD} 🔄 QIDI Q2 AP BOARD — UNIVERSAL NAMED-BACKUP RESTORE CENTER${NC}"
echo -e "${CYAN}======================================================================${NC}"

if [[ ! -d "$BACKUP_ROOT_DIR" ]] || [[ -z "$(ls -A "$BACKUP_ROOT_DIR" 2>/dev/null)" ]]; then
    echo -e "${YELLOW}[!] No named backups found in ${BACKUP_ROOT_DIR} yet.${NC}"
    echo "    Backups are created automatically whenever you run an option in install.sh."
    exit 0
fi

echo "Available Named Backups on Your Printer:"
echo ""

backups=()
idx=1
while IFS= read -r dir; do
    [[ ! -d "$dir" || ! -f "$dir/restore.sh" ]] && continue
    backups+=("$dir")
    b_name=$(grep -E '^BACKUP_NAME=' "$dir/backup_info.txt" 2>/dev/null | cut -d= -f2- | tr -d '"' || basename "$dir")
    b_date=$(grep -E '^DATE_CREATED=' "$dir/backup_info.txt" 2>/dev/null | cut -d= -f2- | tr -d '"' || echo "Unknown date")
    b_cat=$(grep -E '^CATEGORY=' "$dir/backup_info.txt" 2>/dev/null | cut -d= -f2- | tr -d '"' || echo "snapshot")
    echo -e "  [${CYAN}${idx}${NC}] ${BOLD}${b_name}${NC}  — Created: ${b_date} (Action: ${b_cat})"
    idx=$((idx + 1))
done < <(ls -1dt "$BACKUP_ROOT_DIR"/*/ 2>/dev/null)

total=${#backups[@]}
if [[ "$total" -eq 0 ]]; then
    echo -e "${YELLOW}[!] No restorable backup snapshots found in ${BACKUP_ROOT_DIR}.${NC}"
    exit 0
fi

echo ""
read -rp "👉 Enter the backup number (1-${total}) you want to restore (or 'c' to cancel): " b_num
if [[ ! "$b_num" =~ ^[0-9]+$ ]] || [[ "$b_num" -lt 1 ]] || [[ "$b_num" -gt "$total" ]]; then
    echo "Restore cancelled."
    exit 0
fi

selected_dir="${backups[$((b_num - 1))]}"

if [[ -n "$PRESET_MODE" ]]; then
    bash "$selected_dir/restore.sh" "$PRESET_MODE"
    exit 0
fi

echo ""
echo "What would you like to restore from this snapshot?"
echo -e "  [${GREEN}1${NC}] ${BOLD}100% Everything${NC} (Configs, Macros, Network, AP Board, and Kernel if saved)"
echo -e "  [${CYAN}2${NC}] Restore ${BOLD}Klipper Configs & Macros${NC} Only"
echo -e "  [${CYAN}3${NC}] Restore ${BOLD}Network Adapter Settings${NC} Only"
echo -e "  [${CYAN}4${NC}] Restore ${BOLD}AP Board CPU & Disk Settings${NC} Only"
echo -e "  [${CYAN}5${NC}] Restore ${BOLD}Factory Linux Kernel (boot partition)${NC} Only"
echo -e "  [${YELLOW}0${NC}] Cancel"
echo ""
read -rp "👉 Choose restore scope [0-5] (Default: 1): " r_scope
r_scope="${r_scope:-1}"

case "$r_scope" in
    1)
        bash "$selected_dir/restore.sh" --full
        ;;
    2)
        bash "$selected_dir/restore.sh" --macros-only
        ;;
    3)
        bash "$selected_dir/restore.sh" --network-only
        ;;
    4)
        bash "$selected_dir/restore.sh" --ap-only
        ;;
    5)
        bash "$selected_dir/restore.sh" --kernel-only
        ;;
    *)
        echo "Cancelled."
        ;;
esac
