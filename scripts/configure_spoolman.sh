#!/usr/bin/env bash
# ==============================================================================
# configure_spoolman.sh: Optional Spoolman Manager Configuration
# Allows users to:
#   1. Enable Spoolman by entering their PC / Server local IP address
#   2. Disable Spoolman so the printer runs completely standalone
# ==============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SUITE_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

source "$SCRIPT_DIR/ui_nav.sh"

REAL_USER="${SUDO_USER:-$USER}"
USER_HOME=$(eval echo "~$REAL_USER")

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
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

configure_spoolman_interactive() {
    local target_cfg
    target_cfg=$(get_target_config_dir)
    local moonraker_cfg="$target_cfg/moonraker.conf"
    local printer_cfg="$target_cfg/printer.cfg"

    local sp_items=(
        "[1] YES — Connect to Spoolman running on PC / local network"
        "[2] NO  — Do NOT use Spoolman (Run standalone without Spoolman)"
        "[b] ⬅️  Back to Main Menu"
        "[q] 🚪 Exit Installer"
    )
    local sp_header="${CYAN}${BOLD}======================================================================${NC}\n"
    sp_header+="${BOLD} 🧵 SPOOLMAN FILAMENT MANAGER SETUP (OPTIONAL)${NC}\n"
    sp_header+="${CYAN}======================================================================${NC}\n"
    sp_header+="Spoolman is an open-source filament spool tracker that can run on your\n"
    sp_header+="PC, Raspberry Pi, home server, or Docker container.\n\n"
    sp_header+="Choose an option:"

    local sp_res
    sp_res=$(arrow_menu "$sp_header" sp_items 0)

    case "$sp_res" in
        0)
            echo ""
            echo -e "${CYAN}${BOLD}--- Enter Your PC / Spoolman Host Details ---${NC}"
            echo -e "On your PC, find your local IP (e.g. 192.168.1.50) where Spoolman is running."

            local sp_ip
            sp_ip=$(prompt_nav_input "Enter PC / Server IP Address (e.g. 192.168.1.50)")
            [[ "$sp_ip" == "back" || "$sp_ip" == "menu" ]] && return 10
            while [[ -z "${sp_ip// /}" ]]; do
                echo -e "${RED}IP address cannot be empty.${NC}"
                sp_ip=$(prompt_nav_input "Enter PC / Server IP Address (e.g. 192.168.1.50)")
                [[ "$sp_ip" == "back" || "$sp_ip" == "menu" ]] && return 10
            done

            local sp_port
            sp_port=$(prompt_nav_input "Enter Spoolman Port" "7912")
            [[ "$sp_port" == "back" || "$sp_port" == "menu" ]] && return 10
            sp_port=$(echo "$sp_port" | tr -d '[:space:]')
            [[ -z "$sp_port" ]] && sp_port="7912"

            # Prompt user to name a backup restore point
            bash "$SCRIPT_DIR/backup_machine.sh" "enable_spoolman"

            echo -e "${CYAN}[*] Updating Moonraker & Klipper with Spoolman at http://${sp_ip}:${sp_port}...${NC}"

            python3 - << PYEOF
import os, re

moonraker_path = "$moonraker_cfg"
printer_path = "$printer_cfg"
spool_url = "http://${sp_ip}:${sp_port}"

# 1. Update moonraker.conf
if os.path.isfile(moonraker_path):
    with open(moonraker_path, "r") as f:
        m = f.read()

    new_section = f"""[spoolman]
server: {spool_url}
sync_rate: 5"""

    if re.search(r"#?\s*\[spoolman\].*?(?=\n\s*\[|\Z)", m, re.DOTALL):
        m = re.sub(r"#?\s*\[spoolman\].*?(?=\n\s*\[|\Z)", new_section + "\n\n", m, count=1, flags=re.DOTALL)
    else:
        m = m.rstrip() + "\n\n" + new_section + "\n"

    with open(moonraker_path, "w") as f:
        f.write(m)

# 2. Update printer.cfg
if os.path.isfile(printer_path):
    with open(printer_path, "r") as f:
        p = f.read()

    p = p.replace("#[include sync_spoolman.cfg]", "[include sync_spoolman.cfg]")
    with open(printer_path, "w") as f:
        f.write(p)
PYEOF

            chown -R "$REAL_USER:$REAL_USER" "$target_cfg" 2>/dev/null || true
            echo -e "${CYAN}[*] Restarting Moonraker & Klipper services...${NC}"
            systemctl restart moonraker klipper 2>/dev/null || true

            echo ""
            echo -e "${GREEN}${BOLD}[✓] Spoolman Enabled Successfully!${NC}"
            echo -e "    • Server URL: ${BOLD}http://${sp_ip}:${sp_port}${NC}"
            echo -e "    • Moonraker and Klipper are now connected to your Spoolman server."
            ;;
        1)
            # Prompt user to name a backup restore point
            bash "$SCRIPT_DIR/backup_machine.sh" "disable_spoolman"

            echo -e "${CYAN}[*] Disabling Spoolman in Moonraker & Klipper...${NC}"

            python3 - << PYEOF
import os, re

moonraker_path = "$moonraker_cfg"
printer_path = "$printer_cfg"

# 1. Comment out in moonraker.conf
if os.path.isfile(moonraker_path):
    with open(moonraker_path, "r") as f:
        m = f.read()

    disabled_block = """# [spoolman]
# server: http://192.168.1.xxx:7912
# sync_rate: 5"""

    if re.search(r"#?\s*\[spoolman\].*?(?=\n\s*\[|\Z)", m, re.DOTALL):
        m = re.sub(r"#?\s*\[spoolman\].*?(?=\n\s*\[|\Z)", disabled_block + "\n\n", m, count=1, flags=re.DOTALL)

    with open(moonraker_path, "w") as f:
        f.write(m)

# 2. Comment out in printer.cfg
if os.path.isfile(printer_path):
    with open(printer_path, "r") as f:
        p = f.read()

    p = re.sub(r"(?<!#)\[include sync_spoolman\.cfg\]", "#[include sync_spoolman.cfg]", p)
    with open(printer_path, "w") as f:
        f.write(p)
PYEOF

            chown -R "$REAL_USER:$REAL_USER" "$target_cfg" 2>/dev/null || true
            echo -e "${CYAN}[*] Restarting Moonraker & Klipper services...${NC}"
            systemctl restart moonraker klipper 2>/dev/null || true

            echo ""
            echo -e "${GREEN}${BOLD}[✓] Spoolman Disabled (Standalone Mode Active)!${NC}"
            echo -e "    • Your printer will not attempt to connect to any external Spoolman server."
            ;;
        2|b|back|menu|m)
            return 10
            ;;
        3|q|quit|exit)
            exit 0
            ;;
    esac
}

configure_spoolman_interactive
