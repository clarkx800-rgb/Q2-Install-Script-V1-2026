#!/usr/bin/env bash
# ==============================================================================
# simulate.sh: Interactive Sandbox Simulator & Dry-Run Test Environment
# Run this on ANY Linux PC to safely test and interact with the installer!
# ZERO RISK: No root required, zero changes to host system or hardware.
# ==============================================================================
set -euo pipefail

SUITE_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SIM_DIR="/tmp/q2_simulator"

# ANSI Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

echo -e "${CYAN}${BOLD}========================================================================${NC}"
echo -e "${YELLOW}${BOLD}   🎮 PREPARING QIDI Q2 INTERACTIVE INSTALLER SIMULATION SANDBOX 🎮${NC}"
echo -e "${CYAN}========================================================================${NC}"
echo -e "Sandbox Location: ${BOLD}${SIM_DIR}${NC}"
echo -e "Setting up mock AP board environment (UART /dev/ttyS4, USB serial, configs)..."

RERUN_MODE=0
if [[ "${1:-}" =~ ^(--keep|--rerun|-k|-r)$ ]]; then
    RERUN_MODE=1
fi

# 1. Clean and initialize sandbox structure
if [[ $RERUN_MODE -eq 0 ]]; then
    rm -rf "$SIM_DIR"
    mkdir -p "$SIM_DIR"/{bin,dev/serial/by-id,etc/sysctl.d,etc/modprobe.d,etc/udev/rules.d,etc/default,etc/systemd/system,printer_data/config,q2_ap_backups}

    # 2. Populate mock hardware serial devices
    touch "$SIM_DIR/dev/serial/by-id/usb-Klipper_stm32f407xx_643732373534350E35353635-if00"
    touch "$SIM_DIR/dev/serial/by-id/usb-Klipper_stm32f401xc_7845123698520147-if00"
    touch "$SIM_DIR/dev/ttyS4"

    # 3. Create mock Linux OS files
    cat << 'EOF' > "$SIM_DIR/etc/fstab"
UUID=4a89c0de-1122-3344 / ext4 defaults,sync 0 1
EOF

    cat << 'EOF' > "$SIM_DIR/etc/default/cpufrequtils"
ENABLE="true"
GOVERNOR="ondemand"
EOF

    # Create a 4MB zero-filled mock boot partition image
    dd if=/dev/zero of="$SIM_DIR/mock_boot_partition.img" bs=1M count=4 status=none 2>/dev/null || true

    # 4. Copy initial baseline configurations into simulated printer_data/config (simulating factory Q2 state)
    for item in printer.cfg moonraker.conf crowsnest.conf saved_variables.cfg timelapse.cfg plr.cfg MCU_ID.cfg gcode_macro_basic.cfg; do
        if [[ -e "$SUITE_ROOT/configs/$item" ]]; then
            cp -rp "$SUITE_ROOT/configs/$item" "$SIM_DIR/printer_data/config/" 2>/dev/null || true
        fi
    done
    cat << 'EOF' > "$SIM_DIR/printer_data/config/user_custom_macros.cfg"
# Factory / Custom User Macros (Pre-existing before installer)
[gcode_macro MY_CUSTOM_START]
gcode:
    RESPOND MSG="Custom user macro active"
EOF
    SIM_CONFIG_DIR="$SIM_DIR/printer_data/config" bash "$SUITE_ROOT/scripts/manage_macros.sh" --keep-silent 2>/dev/null || true
else
    echo -e "${GREEN}[*] Re-run mode active! Preserving previous sandbox state and Katapult markers...${NC}"
    mkdir -p "$SIM_DIR"/{bin,dev/serial/by-id,etc/sysctl.d,etc/modprobe.d,etc/udev/rules.d,etc/default,etc/systemd/system,printer_data/config,q2_ap_backups}
fi

# 5. Generate mock system binaries in $SIM_DIR/bin
cat << 'EOF' > "$SIM_DIR/bin/systemctl"
#!/usr/bin/env bash
echo -e "\033[1;34m[MOCK systemctl]\033[0m $*"
exit 0
EOF

cat << 'EOF' > "$SIM_DIR/bin/iw"
#!/usr/bin/env bash
echo -e "\033[1;34m[MOCK iw]\033[0m $*"
exit 0
EOF

cat << 'EOF' > "$SIM_DIR/bin/sysctl"
#!/usr/bin/env bash
echo -e "\033[1;34m[MOCK sysctl]\033[0m $*"
exit 0
EOF

cat << 'EOF' > "$SIM_DIR/bin/udevadm"
#!/usr/bin/env bash
echo -e "\033[1;34m[MOCK udevadm]\033[0m $*"
exit 0
EOF

cat << 'EOF' > "$SIM_DIR/bin/cpufreq-set"
#!/usr/bin/env bash
echo -e "\033[1;34m[MOCK cpufreq-set]\033[0m $*"
exit 0
EOF

cat << 'EOF' > "$SIM_DIR/bin/sudo"
#!/usr/bin/env bash
"$@"
EOF

chmod +x "$SIM_DIR/bin"/*

echo -e "${GREEN}[✓] Simulation sandbox initialized! Launching installer in dry-run mode...${NC}"
echo ""
sleep 1

# 6. Export simulation environment variables
export SIM_MODE=1
export PATH="$SIM_DIR/bin:$PATH"
export SIM_CONFIG_DIR="$SIM_DIR/printer_data/config"
export SIM_BACKUP_ROOT="$SIM_DIR/q2_ap_backups"
export SIM_DEV_SERIAL="$SIM_DIR/dev/serial/by-id"
export SIM_TTYS4="$SIM_DIR/dev/ttyS4"
export SIM_ETC="$SIM_DIR/etc"
export SIM_BOOT_PART="$SIM_DIR/mock_boot_partition.img"

# 7. Launch the installer
bash "$SUITE_ROOT/install.sh"

echo ""
echo -e "${CYAN}${BOLD}========================================================================${NC}"
echo -e "${GREEN}${BOLD}   🎉 SIMULATION COMPLETED!${NC}"
echo -e "${CYAN}========================================================================${NC}"
echo -e "Your real PC was untouched. You can inspect the simulated sandbox changes:"
echo -e "  • Simulated Configs: ${BOLD}ls -la ${SIM_DIR}/printer_data/config/${NC}"
echo -e "  • Simulated Backups: ${BOLD}ls -la ${SIM_DIR}/q2_ap_backups/${NC}"
echo -e "  • Simulated fstab:   ${BOLD}cat ${SIM_DIR}/etc/fstab${NC}"
echo -e "  • Test Katapult Re-run Auto-Detect: ${BOLD}./simulate.sh --rerun${NC}"
echo -e "${CYAN}========================================================================${NC}"
