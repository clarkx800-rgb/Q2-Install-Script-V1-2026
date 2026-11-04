#!/usr/bin/env bash
# ==============================================================================
# flash_kernel.sh: Flasher for N3oney's Modern 5.10 Linux Kernel (RK3308 AP Board)
# Backs up existing boot partition before flashing q2_boot.img
# ==============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SUITE_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
KERNEL_IMG="$SUITE_ROOT/firmwares/kernel/q2_boot.img"

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
RED='\033[0;31m'
BOLD='\033[1m'
NC='\033[0m'

echo -e "${CYAN}${BOLD}======================================================================${NC}"
echo -e "${BOLD} 🐧 [QIDI AP BOARD] N3ONEY MODERN 5.10 LINUX KERNEL INSTALLER${NC}"
echo -e "${CYAN}======================================================================${NC}"

if [[ $EUID -ne 0 ]]; then
    echo -e "${RED}[-] Error: This operation requires root privileges (sudo).${NC}"
    exit 1
fi

if [[ ! -f "$KERNEL_IMG" ]]; then
    echo -e "${RED}[-] Error: Kernel image not found at: $KERNEL_IMG${NC}"
    exit 1
fi

# Detect boot partition
BOOT_PART=""
if [[ -e /dev/disk/by-partlabel/boot ]]; then
    BOOT_PART="/dev/disk/by-partlabel/boot"
elif [[ -e /dev/disk/by-partlabel/BOOT ]]; then
    BOOT_PART="/dev/disk/by-partlabel/BOOT"
elif command -v lsblk >/dev/null 2>&1; then
    FOUND=$(lsblk -ln -o PATH,PARTLABEL 2>/dev/null | grep -wi "boot" | awk '{print $1}' | head -n 1 || true)
    [[ -n "$FOUND" && -e "$FOUND" ]] && BOOT_PART="$FOUND"
fi

if [[ -z "$BOOT_PART" ]]; then
    echo -e "${RED}[-] Error: Could not automatically detect the AP board 'boot' partition.${NC}"
    echo "    Make sure you are running directly on the Qidi OEM AP board (RK3308)."
    exit 1
fi

echo -e "${CYAN}[*] Detected Boot Partition: ${BOLD}${BOOT_PART}${NC}"
BACKUP_FILE="${1:-/tmp/q2_factory_boot_backup_$(date +%Y%m%d_%H%M%S).img}"

if [[ -f "$BACKUP_FILE" ]]; then
    echo -e "${GREEN}[✓] Factory kernel backup already saved in your named snapshot:${NC}"
    echo "    $BACKUP_FILE"
else
    echo -e "${CYAN}[+] Backing up current boot partition to: $BACKUP_FILE...${NC}"
    dd if="$BOOT_PART" of="$BACKUP_FILE" bs=4M conv=fsync status=progress
    echo -e "${GREEN}    [✓] Backup saved safely.${NC}"
fi

echo -e "${CYAN}[+] Writing N3oney 5.10 Kernel (q2_boot.img) to ${BOOT_PART}...${NC}"
dd if="$KERNEL_IMG" of="$BOOT_PART" bs=4M conv=fsync status=progress
echo ""
echo -e "${GREEN}${BOLD}======================================================================${NC}"
echo -e "${GREEN}${BOLD} [✓] N3oney 5.10 Kernel Flashed Successfully!${NC}"
echo -e "     Reboot your printer when ready (${BOLD}sudo reboot${NC}) to load the new kernel."
echo -e "${GREEN}${BOLD}======================================================================${NC}"
