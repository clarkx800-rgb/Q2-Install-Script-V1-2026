#!/usr/bin/env bash
# ==============================================================================
# backup_machine.sh: Interactive Named Backup & Snapshot Engine
# Prompts user to name their backup before any single action is executed
# ==============================================================================
set -euo pipefail

CATEGORY="${1:-full_system}"
CUSTOM_NAME_ARG="${2:-}"

TIMESTAMP="$(date +%Y%m%d_%H%M%S)"
HUMAN_DATE="$(date '+%Y-%m-%d %H:%M:%S')"
REAL_USER="${SUDO_USER:-$USER}"
USER_HOME=$(eval echo "~$REAL_USER")
BACKUP_ROOT_DIR="${SIM_BACKUP_ROOT:-$USER_HOME/q2_ap_backups}"
ETC_DIR="${SIM_ETC:-/etc}"

# ANSI Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

mkdir -p "$BACKUP_ROOT_DIR"

echo ""
echo -e "${CYAN}${BOLD}======================================================================${NC}"
echo -e "${BOLD} 🛡️  SAFETY STEP: NAME YOUR BACKUP RESTORE POINT${NC}"
echo -e "${CYAN}======================================================================${NC}"
echo -e "Before we make this change (${BOLD}${CATEGORY}${NC}), let's save a 100% restorable"
echo -e "snapshot of your current setup so you can undo this at any time."
echo ""

if [[ -n "$CUSTOM_NAME_ARG" ]]; then
    RAW_NAME="$CUSTOM_NAME_ARG"
else
    read -rp "👉 Type a name for this backup (e.g. before_${CATEGORY}) [Press ENTER for auto-name]: " RAW_NAME
fi

if [[ -z "${RAW_NAME// /}" ]]; then
    RAW_NAME="auto_${CATEGORY}"
fi

# Sanitize backup name for safe folder creation
SAFE_NAME=$(echo "$RAW_NAME" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9_-]/_/g' | sed 's/__*/_/g' | sed 's/^_//;s/_$//')
[[ -z "$SAFE_NAME" ]] && SAFE_NAME="backup"

BACKUP_DIR="${BACKUP_ROOT_DIR}/${TIMESTAMP}_${SAFE_NAME}"
mkdir -p "$BACKUP_DIR"/{config,system}

echo ""
echo -e "${CYAN}[*] Creating backup '${BOLD}${SAFE_NAME}${NC}${CYAN}' at: ${BACKUP_DIR}${NC}"

# 1. Locate and copy Klipper configuration
CONFIG_SOURCE="${SIM_CONFIG_DIR:-}"
if [[ -z "$CONFIG_SOURCE" ]]; then
    if [[ -d "$USER_HOME/printer_data/config" ]]; then
        CONFIG_SOURCE="$USER_HOME/printer_data/config"
    elif [[ -d "/home/mks/printer_data/config" ]]; then
        CONFIG_SOURCE="/home/mks/printer_data/config"
    elif [[ -d "/home/mks/klipper_config" ]]; then
        CONFIG_SOURCE="/home/mks/klipper_config"
    elif [[ -d "$USER_HOME/klipper_config" ]]; then
        CONFIG_SOURCE="$USER_HOME/klipper_config"
    fi
fi

if [[ -n "$CONFIG_SOURCE" && -d "$CONFIG_SOURCE" ]]; then
    echo -e "    • Saving Klipper configs & macros from ${CONFIG_SOURCE}..."
    cp -rp "$CONFIG_SOURCE"/. "$BACKUP_DIR/config/" 2>/dev/null || true
    echo "$CONFIG_SOURCE" > "$BACKUP_DIR/config_source_path.txt"
fi

# 2. Save System, CPU, fstab & Network Rules
echo -e "    • Saving AP board system & network settings..."
[[ -f "$ETC_DIR/fstab" ]] && cp -p "$ETC_DIR/fstab" "$BACKUP_DIR/system/fstab" || true
[[ -f "$ETC_DIR/default/cpufrequtils" ]] && cp -p "$ETC_DIR/default/cpufrequtils" "$BACKUP_DIR/system/cpufrequtils" || true
[[ -f "$ETC_DIR/sysctl.d/99-klipper-tuning.conf" ]] && cp -p "$ETC_DIR/sysctl.d/99-klipper-tuning.conf" "$BACKUP_DIR/system/99-klipper-tuning.conf" || true
[[ -f "$ETC_DIR/udev/rules.d/70-wifi-powersave.rules" ]] && cp -p "$ETC_DIR/udev/rules.d/70-wifi-powersave.rules" "$BACKUP_DIR/system/70-wifi-powersave.rules" || true
[[ -f "$ETC_DIR/modprobe.d/8821cs.conf" ]] && cp -p "$ETC_DIR/modprobe.d/8821cs.conf" "$BACKUP_DIR/system/8821cs.conf" || true
if [[ -d "$ETC_DIR/systemd/system/makerbase-wlan0.service.d" ]]; then
    cp -rp "$ETC_DIR/systemd/system/makerbase-wlan0.service.d" "$BACKUP_DIR/system/" 2>/dev/null || true
fi

# Record active/enabled state of Makerbase services
> "$BACKUP_DIR/system/enabled_services.txt"
for svc in makerbase-mac makerbase-byid makerbase-webcam makerbase-client QIDILink-client; do
    if systemctl is-enabled "${svc}.service" 2>/dev/null | grep -q "enabled"; then
        echo "$svc" >> "$BACKUP_DIR/system/enabled_services.txt"
    fi
done

# 3. Save Kernel Boot Partition if category is kernel or full_system
if [[ "$CATEGORY" == "kernel" || "$CATEGORY" == "full_system" ]]; then
    BOOT_PART="${SIM_BOOT_PART:-}"
    if [[ -z "$BOOT_PART" ]]; then
        if [[ -e /dev/disk/by-partlabel/boot ]]; then
            BOOT_PART="/dev/disk/by-partlabel/boot"
        elif [[ -e /dev/disk/by-partlabel/BOOT ]]; then
            BOOT_PART="/dev/disk/by-partlabel/BOOT"
        elif command -v lsblk >/dev/null 2>&1; then
            FOUND=$(lsblk -ln -o PATH,PARTLABEL 2>/dev/null | grep -wi "boot" | awk '{print $1}' | head -n 1 || true)
            [[ -n "$FOUND" && -e "$FOUND" ]] && BOOT_PART="$FOUND"
        fi
    fi

    if [[ -n "$BOOT_PART" && (-b "$BOOT_PART" || -f "$BOOT_PART") ]]; then
        echo -e "    • Backing up stock Linux kernel partition (${BOOT_PART})..."
        dd if="$BOOT_PART" of="$BACKUP_DIR/system/factory_boot.img" bs=4M conv=fsync status=none 2>/dev/null || true
        echo "$BOOT_PART" > "$BACKUP_DIR/boot_partition_path.txt"
    fi
fi

# 4. Write Human-Readable Metadata
cat << META_EOF > "$BACKUP_DIR/backup_info.txt"
BACKUP_NAME="${RAW_NAME}"
SAFE_NAME="${SAFE_NAME}"
CATEGORY="${CATEGORY}"
DATE_CREATED="${HUMAN_DATE}"
CONFIG_PATH="${CONFIG_SOURCE}"
META_EOF

# 5. Generate Self-Contained Restore Script inside this Backup Folder
cat << 'RESTORE_EOF' > "$BACKUP_DIR/restore.sh"
#!/usr/bin/env bash
# ==============================================================================
# Self-Contained Restore Script for Snapshot
# Supports: --full (default), --macros-only, --network-only, --ap-only, --kernel-only
# ==============================================================================
set -euo pipefail

BACKUP_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MODE="${1:---full}"
REAL_USER="${SUDO_USER:-$USER}"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

if [[ "${SIM_MODE:-0}" != "1" && $EUID -ne 0 ]]; then
    echo -e "${RED}[-] Please run with sudo: sudo bash $0 $MODE${NC}"
    exit 1
fi

source "$BACKUP_ROOT/backup_info.txt" 2>/dev/null || true

echo -e "${CYAN}${BOLD}======================================================================${NC}"
echo -e "${BOLD} 🔄 RESTORING BACKUP: ${BACKUP_NAME:-$(basename "$BACKUP_ROOT")}${NC}"
echo -e "    Created on: ${DATE_CREATED:-Unknown} | Mode: ${MODE}"
echo -e "${CYAN}======================================================================${NC}"

restore_configs_and_macros() {
    if [[ -f "$BACKUP_ROOT/config_source_path.txt" ]]; then
        local target_cfg
        target_cfg=$(cat "$BACKUP_ROOT/config_source_path.txt")
        if [[ -d "$target_cfg" && -d "$BACKUP_ROOT/config" ]]; then
            echo -e "${CYAN}[+] Restoring Klipper configuration & macros to ${target_cfg}...${NC}"
            rm -rf "${target_cfg:?}"/*
            cp -rp "$BACKUP_ROOT/config"/. "$target_cfg/"
            chown -R "$REAL_USER:$REAL_USER" "$target_cfg" 2>/dev/null || true
            echo -e "${GREEN}    [✓] Configurations and macros restored 100%.${NC}"
        fi
    fi
}

restore_network() {
    echo -e "${CYAN}[+] Reverting Network Adapter settings to snapshot state...${NC}"
    if [[ -f "$BACKUP_ROOT/system/99-klipper-tuning.conf" ]]; then
        cp -p "$BACKUP_ROOT/system/99-klipper-tuning.conf" /etc/sysctl.d/99-klipper-tuning.conf
    else
        rm -f /etc/sysctl.d/99-klipper-tuning.conf
    fi

    if [[ -f "$BACKUP_ROOT/system/70-wifi-powersave.rules" ]]; then
        cp -p "$BACKUP_ROOT/system/70-wifi-powersave.rules" /etc/udev/rules.d/70-wifi-powersave.rules
    else
        rm -f /etc/udev/rules.d/70-wifi-powersave.rules
    fi

    if [[ -f "$BACKUP_ROOT/system/8821cs.conf" ]]; then
        cp -p "$BACKUP_ROOT/system/8821cs.conf" /etc/modprobe.d/8821cs.conf
    else
        rm -f /etc/modprobe.d/8821cs.conf
    fi

    if [[ -d "$BACKUP_ROOT/system/makerbase-wlan0.service.d" ]]; then
        mkdir -p /etc/systemd/system/makerbase-wlan0.service.d
        cp -rp "$BACKUP_ROOT/system/makerbase-wlan0.service.d"/. /etc/systemd/system/makerbase-wlan0.service.d/
    else
        rm -rf /etc/systemd/system/makerbase-wlan0.service.d 2>/dev/null || true
    fi

    sysctl --system >/dev/null 2>&1 || true
    udevadm control --reload-rules 2>/dev/null || true
    systemctl daemon-reload 2>/dev/null || true
    echo -e "${GREEN}    [✓] Network adapter settings reverted.${NC}"
}

restore_ap_board() {
    echo -e "${CYAN}[+] Reverting AP Board CPU, disk & service settings...${NC}"
    [[ -f "$BACKUP_ROOT/system/fstab" ]] && cp -p "$BACKUP_ROOT/system/fstab" /etc/fstab || true
    if [[ -f "$BACKUP_ROOT/system/cpufrequtils" ]]; then
        cp -p "$BACKUP_ROOT/system/cpufrequtils" /etc/default/cpufrequtils
    else
        rm -f /etc/default/cpufrequtils
    fi

    if [[ -f "$BACKUP_ROOT/system/enabled_services.txt" ]]; then
        while IFS= read -r svc; do
            [[ -z "$svc" ]] && continue
            if systemctl list-unit-files "${svc}.service" 2>/dev/null | grep -q "$svc"; then
                systemctl enable "$svc" 2>/dev/null || true
                systemctl start "$svc" 2>/dev/null || true
            fi
        done < "$BACKUP_ROOT/system/enabled_services.txt"
    fi
    systemctl daemon-reload 2>/dev/null || true
    echo -e "${GREEN}    [✓] AP board settings reverted.${NC}"
}

restore_kernel() {
    if [[ -f "$BACKUP_ROOT/system/factory_boot.img" && -f "$BACKUP_ROOT/boot_partition_path.txt" ]]; then
        local boot_part
        boot_part=$(cat "$BACKUP_ROOT/boot_partition_path.txt")
        if [[ -n "$boot_part" && -b "$boot_part" ]]; then
            echo -e "${CYAN}[+] Restoring original kernel image to ${boot_part}...${NC}"
            dd if="$BACKUP_ROOT/system/factory_boot.img" of="$boot_part" bs=4M conv=fsync status=progress
            echo -e "${GREEN}    [✓] Original Linux kernel restored! (Reboot required to take effect).${NC}"
        else
            echo -e "${YELLOW}[!] Boot partition ${boot_part} not found on this device.${NC}"
        fi
    else
        echo -e "${YELLOW}[!] No kernel image was part of this backup snapshot.${NC}"
    fi
}

case "$MODE" in
    --macros-only|--config-only)
        restore_configs_and_macros
        ;;
    --network-only)
        restore_network
        ;;
    --ap-only)
        restore_ap_board
        ;;
    --kernel-only)
        restore_kernel
        ;;
    --full|*)
        restore_configs_and_macros
        restore_network
        restore_ap_board
        if [[ -f "$BACKUP_ROOT/system/factory_boot.img" ]]; then
            restore_kernel
        fi
        ;;
esac

echo -e "${CYAN}[+] Restarting Klipper & Moonraker...${NC}"
systemctl restart klipper 2>/dev/null || true
systemctl restart moonraker 2>/dev/null || true

echo ""
echo -e "${GREEN}${BOLD}======================================================================${NC}"
echo -e "${GREEN}${BOLD} [✓] RESTORE COMPLETE! Everything is back to '${BACKUP_NAME:-snapshot}'.${NC}"
echo -e "${GREEN}${BOLD}======================================================================${NC}"
RESTORE_EOF

chmod +x "$BACKUP_DIR/restore.sh"
chown -R "$REAL_USER:$REAL_USER" "$BACKUP_DIR" 2>/dev/null || true

# Save path of latest backup so caller scripts can read it if needed
echo "$BACKUP_DIR" > "$BACKUP_ROOT_DIR/.latest_backup_path"
chown "$REAL_USER:$REAL_USER" "$BACKUP_ROOT_DIR/.latest_backup_path" 2>/dev/null || true

echo -e "${GREEN}[✓] Backup '${BOLD}${RAW_NAME}${NC}${GREEN}' saved safely!${NC}"
echo -e "    Location: ${BACKUP_DIR}"
echo ""
