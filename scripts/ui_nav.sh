#!/usr/bin/env bash
# ==============================================================================
# ui_nav.sh: Universal Interactive Arrow Key Navigation & Menu Engine
# Features:
#   • Up/Down Arrow key navigation with '>' chevron indicator
#   • ENTER to select highlighted item
#   • Number keys (1-9, 0) for direct numeric jump
#   • 'b' or 'back' to return to previous menu
#   • 'm' or 'menu' to jump directly to Main Menu
#   • 'q' or 'quit' or 'exit' to cleanly exit installer
#   • Automatic fallback to standard line input if non-interactive
# ==============================================================================
set -euo pipefail

# ANSI Color Codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
DIM='\033[2m'
REV='\033[7m'
NC='\033[0m'

# ==============================================================================
# 0. AP BOARD USER & HOME DIRECTORY RESOLUTION
# ==============================================================================
# On the Qidi Q2 AP board, users often SSH directly as 'root' (where SUDO_USER is
# empty) while Klipper/Moonraker run as 'mks' (/home/mks). This helper ensures
# configs and backups always belong to 'mks' on the AP board.
resolve_ap_user() {
    REAL_USER="${SUDO_USER:-${USER:-root}}"
    if [[ "$REAL_USER" == "root" ]] && id -u mks >/dev/null 2>&1 && [[ -d "/home/mks" ]]; then
        REAL_USER="mks"
    fi
    USER_HOME=$(getent passwd "$REAL_USER" 2>/dev/null | cut -d: -f6 || true)
    if [[ -z "$USER_HOME" || ! -d "$USER_HOME" ]]; then
        USER_HOME=$(eval echo "~$REAL_USER" 2>/dev/null || echo "/home/mks")
    fi
    BACKUP_ROOT_DIR="${SIM_BACKUP_ROOT:-$USER_HOME/q2_ap_backups}"
    export REAL_USER USER_HOME BACKUP_ROOT_DIR
}
resolve_ap_user

nav_quit() {
    cleanup_on_exit
    echo -e "\n${GREEN}${BOLD}Exiting installer. Goodbye!${NC}" >&2
    if [[ "${INSTALLER_CHILD:-0}" == "1" ]]; then
        exit 20
    else
        exit 0
    fi
}

cleanup_on_exit() {
    tput cnorm >&2 2>/dev/null || true
    if [[ "${KLIPPER_STOPPED:-0}" == "1" ]]; then
        systemctl start klipper 2>/dev/null || true
        KLIPPER_STOPPED=0
    fi
}

# ==============================================================================
# 1. ARROW MENU: Select from a list of options with Up/Down arrows & '>' chevron
# ==============================================================================
# Usage:
#   options=("Option 1" "Option 2" "Back" "Exit")
#   choice=$(arrow_menu "=== HEADER TITLE ===" options)
# Returns:
#   0-indexed number selected (0, 1, ...), OR "back", "menu", "quit"
arrow_menu() {
    local header="$1"
    local -n _items_ref="$2"
    local count=${#_items_ref[@]}
    local selected="${3:-0}"

    # Non-interactive / pipe fallback
    if [[ ! -t 0 ]]; then
        echo -e "$header" >&2
        for ((i=0; i<count; i++)); do
            echo -e "  [$((i+1))] ${_items_ref[$i]}" >&2
        done
        local raw_choice=""
        if ! read -rp "👉 Enter selection (or 'b' back, 'q' quit): " raw_choice; then
            echo "quit"
            return 0
        fi
        case "${raw_choice,,}" in
            q|quit|exit) echo "quit"; return 0 ;;
            b|back) echo "back"; return 0 ;;
            m|menu) echo "menu"; return 0 ;;
            *)
                if [[ "$raw_choice" =~ ^[0-9]+$ ]] && [[ "$raw_choice" -ge 1 ]] && [[ "$raw_choice" -le "$count" ]]; then
                    echo "$((raw_choice - 1))"
                elif [[ -z "$raw_choice" ]]; then
                    echo "$selected"
                else
                    echo "$raw_choice"
                fi
                return 0
                ;;
        esac
    fi

    # Interactive TTY Mode
    tput civis >&2 2>/dev/null || true
    trap 'cleanup_on_exit' EXIT INT TERM

    while true; do
        clear >&2 2>/dev/null || true
        echo -e "$header" >&2
        echo -e "${CYAN}Use ${BOLD}↑/↓${NC}${CYAN} arrow keys, ${BOLD}ENTER${NC}${CYAN} to select | ${BOLD}[b]${NC}${CYAN} Back | ${BOLD}[m]${NC}${CYAN} Menu | ${BOLD}[q]${NC}${CYAN} Exit${NC}\n" >&2

        for ((i=0; i<count; i++)); do
            if [[ $i -eq $selected ]]; then
                echo -e "${GREEN}${BOLD}  >  ${REV} ${_items_ref[$i]} ${NC}" >&2
            else
                echo -e "     ${_items_ref[$i]}" >&2
            fi
        done
        echo "" >&2

        local key=""
        if ! IFS= read -rsn1 key; then
            tput cnorm >&2 2>/dev/null || true
            echo "quit"
            return 0
        fi
        if [[ "$key" == $'\x1b' ]]; then
            local rest=""
            read -rsn2 -t 0.1 rest || rest=""
            if [[ "$rest" == "[A" ]]; then # UP
                selected=$(( (selected - 1 + count) % count ))
            elif [[ "$rest" == "[B" ]]; then # DOWN
                selected=$(( (selected + 1) % count ))
            fi
        elif [[ -z "$key" ]]; then # ENTER
            tput cnorm >&2 2>/dev/null || true
            echo "$selected"
            return 0
        elif [[ "$key" =~ [qQ] ]]; then
            tput cnorm >&2 2>/dev/null || true
            echo "quit"
            return 0
        elif [[ "$key" =~ [bB] ]]; then
            tput cnorm >&2 2>/dev/null || true
            echo "back"
            return 0
        elif [[ "$key" =~ [mM] ]]; then
            tput cnorm >&2 2>/dev/null || true
            echo "menu"
            return 0
        elif [[ "$key" =~ ^[1-9]$ ]]; then
            if [[ "$key" -le "$count" ]]; then
                tput cnorm >&2 2>/dev/null || true
                echo "$((key - 1))"
                return 0
            fi
        elif [[ "$key" == "0" ]]; then
            # '0' maps to last item if count >= 10, or exit
            tput cnorm >&2 2>/dev/null || true
            echo "$((count - 1))"
            return 0
        fi
    done
}

# ==============================================================================
# 2. PROMPT YES / NO: Interactive Chevron Choice for Yes / No questions
# ==============================================================================
# Usage:
#   ans=$(prompt_nav_yn "Install Pucci's Macros?")
# Returns:
#   "yes", "no", "back", "menu", or "quit"
prompt_nav_yn() {
    local question="$1"
    local yn_items=(
        "YES — Apply / Install this option"
        "NO  — Skip / Keep my own setup"
        "⬅️  Back (or type 'b')"
        "🚪 Exit Installer (or type 'q')"
    )

    local header="${CYAN}${BOLD}======================================================================${NC}\n"
    header+="${BOLD} ❓ ${question}${NC}\n"
    header+="${CYAN}======================================================================${NC}"

    local res
    res=$(arrow_menu "$header" yn_items 0)

    case "$res" in
        0|y|yes) echo "yes" ;;
        1|n|no)  echo "no" ;;
        2|b|back) echo "back" ;;
        3|q|quit) echo "quit" ;;
        menu|m)  echo "menu" ;;
        *) echo "back" ;;
    esac
}

# ==============================================================================
# 3. PROMPT TEXT INPUT: For backup names, IP addresses, ports with b/m/q escape
# ==============================================================================
# Usage:
#   val=$(prompt_nav_input "Type backup name" "default_name")
# Returns:
#   user string, OR exits on quit, OR returns code 10 on back/menu
prompt_nav_input() {
    local prompt_msg="$1"
    local default_val="${2:-}"
    local user_val=""

    echo "" >&2
    echo -e "${CYAN}----------------------------------------------------------------------${NC}" >&2
    echo -e "${DIM}Navigation: Type ${BOLD}'b'${NC}${DIM} to go back | Type ${BOLD}'menu'${NC}${DIM} for main menu | Type ${BOLD}'q'${NC}${DIM} to exit${NC}" >&2
    if [[ -n "$default_val" ]]; then
        echo -e "${DIM}Default: [${BOLD}${default_val}${NC}${DIM}] (Press ENTER to use default)${NC}" >&2
    fi

    if ! read -rp "👉 ${prompt_msg}: " user_val; then
        nav_quit
    fi

    # Check navigation commands
    case "${user_val,,}" in
        q|quit|exit)
            nav_quit
            ;;
        b|back)
            echo "back"
            return 0
            ;;
        m|menu)
            echo "menu"
            return 0
            ;;
        *)
            if [[ -z "${user_val// /}" ]]; then
                echo "$default_val"
            else
                echo "$user_val"
            fi
            return 0
            ;;
    esac
}

# ==============================================================================
# 4. PAUSE / RETURN TO MENU HELPER
# ==============================================================================
nav_pause() {
    local custom_msg="${1:-Press ENTER to continue (or 'b' for back, 'm' for menu, 'q' to exit):}"
    echo ""
    local p_in=""
    read -rp "👉 ${custom_msg} " p_in || true
    case "${p_in,,}" in
        q|quit|exit)
            nav_quit
            ;;
        m|menu)
            return 10
            ;;
        *)
            return 0
            ;;
    esac
}
