#!/usr/bin/env bash
# ==============================================================================
# apply_ap_tuning.sh: Combined Network & AP Board System Refinements
# Wrapper that executes both apply_network_refinement.sh and
# apply_ap_board_refinement.sh for convenience.
# ==============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

bash "$SCRIPT_DIR/apply_network_refinement.sh"
echo ""
bash "$SCRIPT_DIR/apply_ap_board_refinement.sh"
