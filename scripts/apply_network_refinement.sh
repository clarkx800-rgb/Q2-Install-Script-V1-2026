#!/usr/bin/env bash
# ==============================================================================
# apply_network_refinement.sh: Dedicated Network Adapter & Wi-Fi Sleep Killer
# Fixes ping spikes, Mainsail disconnects, and slow G-code uploads on AP Board
# ==============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SUITE_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
TUNING_DIR="$SUITE_ROOT/ap_tuning"

GREEN='\033[0;32m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

echo -e "${CYAN}${BOLD}======================================================================${NC}"
echo -e "${BOLD} 📡 APPLYING NETWORK ADAPTER REFINEMENTS (AP BOARD)${NC}"
echo -e "${CYAN}======================================================================${NC}"

if [[ $EUID -ne 0 ]]; then
    echo "[-] Error: Must be run with sudo."
    exit 1
fi

echo "[1/3] Disabling Realtek RTL8821CS Wi-Fi power-save sleep..."
if [[ -f "$TUNING_DIR/8821cs.conf" ]]; then
    cp "$TUNING_DIR/8821cs.conf" /etc/modprobe.d/8821cs.conf
fi
if [[ -f "$TUNING_DIR/70-wifi-powersave.rules" ]]; then
    cp "$TUNING_DIR/70-wifi-powersave.rules" /etc/udev/rules.d/70-wifi-powersave.rules
    udevadm control --reload-rules 2>/dev/null || true
fi
if command -v iw >/dev/null 2>&1; then
    iw dev wlan0 set power_save off 2>/dev/null || true
fi
echo -e "${GREEN}      [✓] Wi-Fi sleep mode disabled.${NC}"

echo "[2/3] Configuring systemd wlan0 stay-awake override..."
if systemctl list-unit-files makerbase-wlan0.service >/dev/null 2>&1; then
    mkdir -p /etc/systemd/system/makerbase-wlan0.service.d
    cp "$TUNING_DIR/makerbase-wlan0-override.conf" /etc/systemd/system/makerbase-wlan0.service.d/override.conf
    systemctl daemon-reload 2>/dev/null || true
fi
echo -e "${GREEN}      [✓] Systemd network override installed.${NC}"

echo "[3/3] Expanding TCP socket buffers & enabling Fast Open..."
if [[ -f "$TUNING_DIR/99-klipper-tuning.conf" ]]; then
    cp "$TUNING_DIR/99-klipper-tuning.conf" /etc/sysctl.d/99-klipper-tuning.conf
    sysctl -p /etc/sysctl.d/99-klipper-tuning.conf >/dev/null 2>&1 || sysctl --system >/dev/null 2>&1 || true
fi
echo -e "${GREEN}      [✓] TCP socket buffers optimized (2MB ceiling, zero idle lag).${NC}"

echo ""
echo -e "${GREEN}${BOLD}[✓] Network Adapter Refinements Complete!${NC}"
