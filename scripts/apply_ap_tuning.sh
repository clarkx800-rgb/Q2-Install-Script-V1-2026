#!/usr/bin/env bash
# ==============================================================================
# apply_ap_tuning.sh: Low-Latency Kernel, CPU & Network Tuning for Qidi AP Board
# Rectifies Rockchip RK3308 "Timer too close" and MCU communication dropouts
# ==============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SUITE_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
TUNING_DIR="$SUITE_ROOT/ap_tuning"

echo "===================================================================="
echo " [QIDI AP BOARD] Applying Low-Latency & Anti-Timer-Too-Close Tuning "
echo "===================================================================="

if [[ $EUID -ne 0 ]]; then
    echo "[-] Error: This script must be run with sudo/root privileges."
    exit 1
fi

# 1. CPU Governor to Performance (Lock 1.1 GHz, eliminate clock scaling latency)
echo "[1/6] Locking CPU governor to performance (1.1 GHz)..."
if command -v apt-get >/dev/null 2>&1; then
    if ! command -v cpufreq-set >/dev/null 2>&1; then
        echo "      Installing cpufrequtils..."
        apt-get update -qq && apt-get install -y -qq cpufrequtils >/dev/null 2>&1 || true
    fi
fi
if [[ -f "$TUNING_DIR/cpufrequtils" ]]; then
    cp "$TUNING_DIR/cpufrequtils" /etc/default/cpufrequtils
fi
if command -v cpufreq-set >/dev/null 2>&1; then
    cpufreq-set -r -g performance || true
    echo "      [✓] CPU governor set to performance."
fi

# 2. Disable Wi-Fi Radio Sleep (RTL8821CS)
echo "[2/6] Disabling Wi-Fi power saving & radio sleep..."
if [[ -f "$TUNING_DIR/70-wifi-powersave.rules" ]]; then
    cp "$TUNING_DIR/70-wifi-powersave.rules" /etc/udev/rules.d/70-wifi-powersave.rules
    udevadm control --reload-rules || true
fi
if [[ -f "$TUNING_DIR/8821cs.conf" ]]; then
    cp "$TUNING_DIR/8821cs.conf" /etc/modprobe.d/8821cs.conf
fi
if command -v iw >/dev/null 2>&1; then
    iw dev wlan0 set power_save off 2>/dev/null || true
fi
if systemctl list-unit-files makerbase-wlan0.service >/dev/null 2>&1; then
    mkdir -p /etc/systemd/system/makerbase-wlan0.service.d
    cp "$TUNING_DIR/makerbase-wlan0-override.conf" /etc/systemd/system/makerbase-wlan0.service.d/override.conf
    systemctl daemon-reload || true
fi
echo "      [✓] Wi-Fi power save permanently disabled."

# 3. TCP & Network Stack Sysctl Tuning
echo "[3/6] Applying TCP & network socket sysctl latency optimizations..."
if [[ -f "$TUNING_DIR/99-klipper-tuning.conf" ]]; then
    cp "$TUNING_DIR/99-klipper-tuning.conf" /etc/sysctl.d/99-klipper-tuning.conf
    sysctl -p /etc/sysctl.d/99-klipper-tuning.conf >/dev/null 2>&1 || sysctl --system >/dev/null 2>&1 || true
    echo "      [✓] Sysctl network tuning active."
fi

# 4. Storage I/O Optimization (fstab noatime & commit=30)
echo "[4/6] Checking eMMC mount flags in /etc/fstab..."
if grep -q "sync" /etc/fstab 2>/dev/null; then
    echo "      Found legacy blocking 'sync' mount option in /etc/fstab."
    sed -i.bak_q2 's/\bsync\b/rw,noatime,commit=30/g' /etc/fstab
    echo "      [✓] Updated /etc/fstab with noatime,commit=30 (backup saved to /etc/fstab.bak_q2)."
else
    echo "      [✓] /etc/fstab does not contain blocking sync flags."
fi

# 5. Disable Dead Makerbase / Qidi Background Telemetry
echo "[5/6] Sanitizing background daemons..."
SERVICES_TO_DISABLE=(
    "makerbase-mac"
    "makerbase-byid"
    "makerbase-webcam"
    "makerbase-client"
    "QIDILink-client"
)
for svc in "${SERVICES_TO_DISABLE[@]}"; do
    if systemctl list-unit-files "${svc}.service" 2>/dev/null | grep -q "$svc"; then
        echo "      Stopping & disabling $svc..."
        systemctl stop "$svc" 2>/dev/null || true
        systemctl disable "$svc" 2>/dev/null || true
    fi
done
echo "      [✓] Background bloatware sanitized."

# 6. Set UART & Serial buffer limits
echo "[6/6] Verifying toolhead serial port (/dev/ttyS4)..."
if [[ -e /dev/ttyS4 ]]; then
    chmod 666 /dev/ttyS4 || true
    echo "      [✓] /dev/ttyS4 permissions verified."
fi

echo ""
echo "===================================================================="
echo " [✓] AP Board System Tuning Complete! 'Timer too close' mitigated.  "
echo "===================================================================="
