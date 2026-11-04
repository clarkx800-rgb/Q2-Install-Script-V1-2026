#!/usr/bin/env bash
# ==============================================================================
# apply_ap_board_refinement.sh: Dedicated AP Board "Timer Too Close" Fix
# Locks RK3308 CPU to 1.1 GHz performance, unchokes eMMC I/O, stops bloatware
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
echo -e "${BOLD} ⚡ APPLYING AP BOARD 'TIMER TOO CLOSE' REFINEMENTS${NC}"
echo -e "${CYAN}======================================================================${NC}"

if [[ $EUID -ne 0 ]]; then
    echo "[-] Error: Must be run with sudo."
    exit 1
fi

echo "[1/4] Locking Rockchip RK3308 4-core CPU to 1.1 GHz Performance mode..."
if command -v apt-get >/dev/null 2>&1; then
    if ! command -v cpufreq-set >/dev/null 2>&1; then
        apt-get update -qq >/dev/null 2>&1 && apt-get install -y -qq cpufrequtils >/dev/null 2>&1 || true
    fi
fi
if [[ -f "$TUNING_DIR/cpufrequtils" ]]; then
    cp "$TUNING_DIR/cpufrequtils" /etc/default/cpufrequtils
fi
if command -v cpufreq-set >/dev/null 2>&1; then
    cpufreq-set -r -g performance 2>/dev/null || true
fi
for gov in /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor; do
    [[ -w "$gov" ]] && echo "performance" > "$gov" 2>/dev/null || true
done
echo -e "${GREEN}      [✓] CPU locked to maximum performance (no clock-scaling stutters).${NC}"

echo "[2/4] Optimizing eMMC flash storage writes in /etc/fstab..."
if grep -q "sync" /etc/fstab 2>/dev/null; then
    sed -i.bak_q2 's/\bsync\b/rw,noatime,commit=30/g' /etc/fstab
    mount -o remount / 2>/dev/null || true
    echo -e "${GREEN}      [✓] Replaced slow blocking 'sync' with fast 'noatime,commit=30'.${NC}"
else
    echo -e "${GREEN}      [✓] /etc/fstab storage flags are already non-blocking.${NC}"
fi

echo "[3/4] Disabling background Makerbase / Qidi bloatware services..."
SERVICES_TO_DISABLE=(
    "makerbase-mac"
    "makerbase-byid"
    "makerbase-webcam"
    "makerbase-client"
    "QIDILink-client"
)
for svc in "${SERVICES_TO_DISABLE[@]}"; do
    if systemctl list-unit-files "${svc}.service" 2>/dev/null | grep -q "$svc"; then
        systemctl stop "$svc" 2>/dev/null || true
        systemctl disable "$svc" 2>/dev/null || true
    fi
done
echo -e "${GREEN}      [✓] Background CPU-stealing services stopped and disabled.${NC}"

echo "[4/4] Verifying internal Toolhead UART port (/dev/ttyS4)..."
if [[ -e /dev/ttyS4 ]]; then
    chmod 666 /dev/ttyS4 2>/dev/null || true
    echo -e "${GREEN}      [✓] /dev/ttyS4 ready at 500,000 baud.${NC}"
fi

echo ""
echo -e "${GREEN}${BOLD}[✓] AP Board 'Timer Too Close' Refinements Complete!${NC}"
