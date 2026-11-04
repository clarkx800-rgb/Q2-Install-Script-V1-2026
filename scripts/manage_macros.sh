#!/usr/bin/env bash
# ==============================================================================
# manage_macros.sh: Beginner-Friendly Yes/No Macro Selector & Macro Restore
# Allows users to:
#   • Answer YES to install Pucci's Advanced Print Lifecycle Macros
#   • Answer NO to keep their own existing macros with the upgraded firmware
#   • Restore their previous macros at any time if they don't like Pucci's
# ==============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SUITE_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
SUITE_CONFIGS="$SUITE_ROOT/configs"

source "$SCRIPT_DIR/ui_nav.sh"

REAL_USER="${SUDO_USER:-$USER}"
USER_HOME=$(eval echo "~$REAL_USER")
BACKUP_ROOT_DIR="${SIM_BACKUP_ROOT:-$USER_HOME/q2_ap_backups}"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

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

install_pucci_macros() {
    local target_cfg
    target_cfg=$(get_target_config_dir)

    # 1. Prompt user to name their backup before touching macros
    bash "$SCRIPT_DIR/backup_machine.sh" "install_pucci_macros"

    echo -e "${CYAN}[*] Installing Pucci's Advanced Print Lifecycle Macros into ${target_cfg}...${NC}"
    mkdir -p "$target_cfg"

    # Copy Pucci's macro folders and files
    cp -rp "$SUITE_CONFIGS/START-END-PAUSE-CANCEL" "$target_cfg/"
    cp -p "$SUITE_CONFIGS/FAN-SETTINGS.cfg" "$target_cfg/"
    cp -p "$SUITE_CONFIGS/nonlinear_pa.cfg" "$target_cfg/"
    [[ -f "$SUITE_CONFIGS/gcode_macro_basic.cfg" ]] && cp -p "$SUITE_CONFIGS/gcode_macro_basic.cfg" "$target_cfg/" || true

    # Ensure printer.cfg exists
    if [[ ! -f "$target_cfg/printer.cfg" ]]; then
        cp -p "$SUITE_CONFIGS/printer.cfg" "$target_cfg/printer.cfg"
    fi

    # Activate Pucci's Macro Suite block inside printer.cfg
    python3 - << PYEOF
import re
p = "$target_cfg/printer.cfg"
with open(p, "r") as f:
    c = f.read()

pucci_block = """# <MACRO_SUITE_START>
[include START-END-PAUSE-CANCEL/includes.cfg]
[include FAN-SETTINGS.cfg]
[include nonlinear_pa.cfg]
# <MACRO_SUITE_END>"""

if "# <MACRO_SUITE_START>" in c:
    c = re.sub(r"# <MACRO_SUITE_START>.*?# <MACRO_SUITE_END>", pucci_block, c, flags=re.DOTALL)
else:
    c = pucci_block + "\n\n" + c

with open(p, "w") as f:
    f.write(c)
PYEOF

    chown -R "$REAL_USER:$REAL_USER" "$target_cfg" 2>/dev/null || true
    systemctl restart klipper 2>/dev/null || true

    echo ""
    echo -e "${GREEN}${BOLD}[✓] YES Selected: Pucci's Macros Installed & Activated!${NC}"
    echo -e "    • Automatic Bed Tramming, Chamber Thermal Soak, Wiper Polish, and"
    echo -e "      Blade Cut macros are now active."
    echo -e "    • Check ${BOLD}SLICER_GUIDE.md${NC} (or Menu Option 9) for the matching Slicer G-Codes!"
    echo -e "    • If you ever want your old macros back, just choose ${BOLD}Menu Option 4${NC}."
}

keep_user_macros() {
    local skip_backup="${1:-false}"
    local target_cfg
    target_cfg=$(get_target_config_dir)

    if [[ "$skip_backup" != "true" ]]; then
        # Prompt user to name their backup first
        bash "$SCRIPT_DIR/backup_machine.sh" "keep_my_macros"
    fi

    local latest_backup=""
    [[ -f "$BACKUP_ROOT_DIR/.latest_backup_path" ]] && latest_backup=$(cat "$BACKUP_ROOT_DIR/.latest_backup_path")

    echo -e "${CYAN}[*] Preserving your existing macros while keeping hardware config ready...${NC}"
    mkdir -p "$target_cfg"

    if [[ ! -f "$target_cfg/printer.cfg" ]]; then
        cp -p "$SUITE_CONFIGS/printer.cfg" "$target_cfg/printer.cfg"
    fi
    [[ ! -f "$target_cfg/gcode_macro_basic.cfg" && -f "$SUITE_CONFIGS/gcode_macro_basic.cfg" ]] && \
        cp -p "$SUITE_CONFIGS/gcode_macro_basic.cfg" "$target_cfg/gcode_macro_basic.cfg" || true

    # Restore any custom macro .cfg files from the backup snapshot and detect user's macro includes
    python3 - << PYEOF
import os, re, shutil

target_cfg = "$target_cfg"
backup_cfg = os.path.join("$latest_backup", "config") if "$latest_backup" else ""
printer_cfg_path = os.path.join(target_cfg, "printer.cfg")

user_includes = []
if backup_cfg and os.path.isdir(backup_cfg):
    pucci_items = {"START-END-PAUSE-CANCEL", "FAN-SETTINGS.cfg", "nonlinear_pa.cfg"}
    for item in os.listdir(backup_cfg):
        if item in pucci_items or item == "printer.cfg":
            continue
        src = os.path.join(backup_cfg, item)
        dst = os.path.join(target_cfg, item)
        if os.path.isdir(src):
            if os.path.exists(dst):
                shutil.rmtree(dst)
            shutil.copytree(src, dst)
        else:
            shutil.copy2(src, dst)

    old_printer = os.path.join(backup_cfg, "printer.cfg")
    if os.path.isfile(old_printer):
        with open(old_printer, "r") as f:
            for line in f:
                s = line.strip()
                if s.startswith("[include ") and not any(k in s for k in ["START-END-PAUSE-CANCEL", "FAN-SETTINGS.cfg", "nonlinear_pa.cfg", "mmu", "timelapse.cfg", "plr.cfg", "MKS_THR.cfg"]):
                    user_includes.append(s)

if not user_includes:
    if os.path.isfile(os.path.join(target_cfg, "gcode_macro.cfg")):
        user_includes.append("[include gcode_macro.cfg]")
    else:
        user_includes.append("[include gcode_macro_basic.cfg]")

macro_block = "# <MACRO_SUITE_START>\n# Using User's Own Macros (Pucci Macros Disabled)\n" + "\n".join(user_includes) + "\n# <MACRO_SUITE_END>"

with open(printer_cfg_path, "r") as f:
    c = f.read()

if "# <MACRO_SUITE_START>" in c:
    c = re.sub(r"# <MACRO_SUITE_START>.*?# <MACRO_SUITE_END>", macro_block, c, flags=re.DOTALL)
else:
    c = macro_block + "\n\n" + c

with open(printer_cfg_path, "w") as f:
    f.write(c)
PYEOF

    chown -R "$REAL_USER:$REAL_USER" "$target_cfg" 2>/dev/null || true
    systemctl restart klipper 2>/dev/null || true

    echo ""
    echo -e "${GREEN}${BOLD}[✓] NO Selected: Your Own Macros Are Preserved & Active!${NC}"
    echo -e "    • Pucci's macro suite is disabled in printer.cfg."
    echo -e "    • Your own macro files remain active."
}

choose_macros_menu() {
    local macro_items=(
        "[1] YES — Install Pucci's Macros (Auto Soak, Wiper Polish, Blade Cutter, Smart Fans)"
        "[2] NO  — Keep My Own Existing Macros (Keep my own macros with upgraded firmware)"
        "[b] ⬅️  Back to Main Menu"
        "[q] 🚪 Exit Installer"
    )
    local macro_header="${CYAN}${BOLD}======================================================================${NC}\n"
    macro_header+="${BOLD} 🧩 MACRO SETUP: INSTALL PUCCI'S MACROS? (YES OR NO)${NC}\n"
    macro_header+="${CYAN}======================================================================${NC}\n"
    macro_header+="Would you like to install Pucci's automated print lifecycle macros?\n\n"
    macro_header+="Choose an option:"

    local m_res
    m_res=$(arrow_menu "$macro_header" macro_items 0)
    case "$m_res" in
        0)
            install_pucci_macros
            ;;
        1)
            keep_user_macros "false"
            ;;
        2|b|back|menu|m)
            return 10
            ;;
        3|q|quit|exit)
            exit 0
            ;;
    esac
}

restore_macros_menu() {
    local target_cfg
    target_cfg=$(get_target_config_dir)

    if [[ ! -d "$BACKUP_ROOT_DIR" ]] || [[ -z "$(ls -A "$BACKUP_ROOT_DIR" 2>/dev/null)" ]]; then
        echo ""
        echo -e "${CYAN}${BOLD}======================================================================${NC}"
        echo -e "${BOLD} ⏪ RESTORE PREVIOUS MACROS (IF YOU DON'T LIKE PUCCI'S MACROS)${NC}"
        echo -e "${CYAN}======================================================================${NC}"
        echo -e "${YELLOW}[!] No named backups found in ${BACKUP_ROOT_DIR} yet.${NC}"
        echo "    Switching printer.cfg to basic stock macro mode (gcode_macro_basic.cfg)..."
        keep_user_macros "false"
        return 0
    fi

    local backups=()
    local b_items=()
    while IFS= read -r dir; do
        [[ ! -d "$dir" ]] && continue
        backups+=("$dir")
        local b_name b_date b_cat
        b_name=$(grep -E '^BACKUP_NAME=' "$dir/backup_info.txt" 2>/dev/null | cut -d= -f2- | tr -d '"' || basename "$dir")
        b_date=$(grep -E '^DATE_CREATED=' "$dir/backup_info.txt" 2>/dev/null | cut -d= -f2- | tr -d '"' || echo "Unknown date")
        b_cat=$(grep -E '^CATEGORY=' "$dir/backup_info.txt" 2>/dev/null | cut -d= -f2- | tr -d '"' || echo "snapshot")
        b_items+=("${b_name} (${b_date} — ${b_cat})")
    done < <(ls -1dt "$BACKUP_ROOT_DIR"/*/ 2>/dev/null)

    local total=${#backups[@]}
    if [[ "$total" -eq 0 ]]; then
        echo -e "${YELLOW}[!] No valid backup folders found.${NC}"
        return 0
    fi

    b_items+=("⬅️  Back to Main Menu")
    b_items+=("🚪 Exit Installer")

    local b_header="${CYAN}${BOLD}======================================================================${NC}\n"
    b_header+="${BOLD} ⏪ RESTORE PREVIOUS MACROS (IF YOU DON'T LIKE PUCCI'S MACROS)${NC}\n"
    b_header+="${CYAN}======================================================================${NC}\n"
    b_header+="Select which backup to restore macros from:"

    local b_res
    b_res=$(arrow_menu "$b_header" b_items 0)
    local selected_backup=""

    case "$b_res" in
        back|b|menu|m) return 10 ;;
        quit|q|exit) exit 0 ;;
        *)
            if [[ "$b_res" =~ ^[0-9]+$ ]]; then
                if [[ "$b_res" -lt "$total" ]]; then
                    selected_backup="${backups[$b_res]}"
                elif [[ "$b_res" -eq "$total" ]]; then
                    return 10 # Back
                else
                    exit 0 # Exit
                fi
            else
                return 10
            fi
            ;;
    esac

    local scope_items=(
        "[1] Restore ONLY my previous macros (Keep upgraded hardware printer.cfg & serial IDs)"
        "[2] Restore the ENTIRE config folder (printer.cfg + all macros) from this backup"
        "[b] ⬅️  Back to Backup Selection"
        "[q] 🚪 Exit Installer"
    )
    local scope_header="How would you like to restore from backup: $(basename "$selected_backup")?"
    local scope_res
    scope_res=$(arrow_menu "$scope_header" scope_items 0)
    local r_type="1"

    case "$scope_res" in
        0) r_type="1" ;;
        1) r_type="2" ;;
        2|b|back|menu|m) return 0 ;;
        3|q|quit|exit) exit 0 ;;
        *) r_type="1" ;;
    esac

    # Prompt user to name a safety backup before restoring
    bash "$SCRIPT_DIR/backup_machine.sh" "before_macro_restore"

    if [[ "$r_type" == "2" ]]; then
        bash "$selected_backup/restore.sh" --macros-only
    else
        echo -e "${CYAN}[*] Restoring your original macro files and macro includes from $(basename "$selected_backup")...${NC}"
        python3 - << PYEOF
import os, re, shutil

target_cfg = "$target_cfg"
backup_cfg = os.path.join("$selected_backup", "config")
printer_cfg_path = os.path.join(target_cfg, "printer.cfg")

user_includes = []
if os.path.isdir(backup_cfg):
    pucci_items = {"START-END-PAUSE-CANCEL", "FAN-SETTINGS.cfg", "nonlinear_pa.cfg"}
    for item in os.listdir(backup_cfg):
        if item in pucci_items or item == "printer.cfg":
            continue
        src = os.path.join(backup_cfg, item)
        dst = os.path.join(target_cfg, item)
        if os.path.isdir(src):
            if os.path.exists(dst):
                shutil.rmtree(dst)
            shutil.copytree(src, dst)
        else:
            shutil.copy2(src, dst)

    old_printer = os.path.join(backup_cfg, "printer.cfg")
    if os.path.isfile(old_printer):
        with open(old_printer, "r") as f:
            for line in f:
                s = line.strip()
                if s.startswith("[include ") and not any(k in s for k in ["START-END-PAUSE-CANCEL", "FAN-SETTINGS.cfg", "nonlinear_pa.cfg", "mmu", "timelapse.cfg", "plr.cfg", "MKS_THR.cfg"]):
                    user_includes.append(s)

if not user_includes:
    if os.path.isfile(os.path.join(target_cfg, "gcode_macro.cfg")):
        user_includes.append("[include gcode_macro.cfg]")
    else:
        user_includes.append("[include gcode_macro_basic.cfg]")

macro_block = "# <MACRO_SUITE_START>\n# Restored User's Original Macros\n" + "\n".join(user_includes) + "\n# <MACRO_SUITE_END>"

with open(printer_cfg_path, "r") as f:
    c = f.read()

if "# <MACRO_SUITE_START>" in c:
    c = re.sub(r"# <MACRO_SUITE_START>.*?# <MACRO_SUITE_END>", macro_block, c, flags=re.DOTALL)
else:
    c = macro_block + "\n\n" + c

with open(printer_cfg_path, "w") as f:
    f.write(c)
PYEOF
        chown -R "$REAL_USER:$REAL_USER" "$target_cfg" 2>/dev/null || true
        systemctl restart klipper 2>/dev/null || true
        echo -e "${GREEN}${BOLD}[✓] Your previous macros have been restored and Klipper restarted!${NC}"
    fi
}

case "${1:-}" in
    --choose)
        choose_macros_menu
        ;;
    --keep-silent)
        keep_user_macros "true"
        ;;
    --restore)
        restore_macros_menu
        ;;
    *)
        choose_macros_menu
        ;;
esac
