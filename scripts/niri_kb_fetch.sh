#!/usr/bin/env bash
# ============================================================================
# niri_kb_fetch.sh - active keyboard layout for the bar
# ============================================================================
# Replaces shell/core/scripts/watchers/kb_fetch.sh (which parsed
# `hyprctl devices -j`). niri exposes one global layout set:
#
#   niri msg --json keyboard-layouts -> {"names": [...], "current_idx": N}
#
# Prints the first two letters of the active layout, uppercased (es -> ES),
# falling back to US when niri is unreachable or jq is missing.
# ============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
. "$SCRIPT_DIR/lib/common.sh"

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
    echo "Usage: niri_kb_fetch.sh   # prints the active keyboard layout (e.g. ES)"
    exit 0
fi

layout=""
if have niri && have jq; then
    layout="$(niri msg --json keyboard-layouts 2>/dev/null \
        | jq -r '(.names[.current_idx]) // empty' 2>/dev/null \
        | head -n1 || true)"
fi

[[ -z "$layout" || "$layout" == "null" ]] && layout="US"
printf '%s\n' "${layout:0:2}" | tr '[:lower:]' '[:upper:]'
