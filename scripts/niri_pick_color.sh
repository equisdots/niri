#!/usr/bin/env bash
# ============================================================================
# niri_pick_color.sh - pick a pixel and copy its hex value
# ============================================================================
# Replaces Hyprland's `hyprpicker -a`. niri has a native interactive query:
#
#   niri msg --json pick-color   -> {"rgb":[r,g,b]} with channels in 0.0..=1.0
#
# This wraps the float->hex conversion the mapping warns about, copies the hex
# to the clipboard and shows a notification.
# ============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
. "$SCRIPT_DIR/lib/common.sh"

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
    echo "Usage: niri_pick_color.sh   # pick a pixel, copy its hex value, notify"
    exit 0
fi

require_cmd niri jq
niri_require

rgb=""
rgb="$(niri msg --json pick-color 2>/dev/null \
    | jq -r '.rgb | map((.* 255) | round) | @tsv' 2>/dev/null || true)"

# Empty means the pick was cancelled or niri returned an error.
[[ -n "$rgb" ]] || exit 0

IFS=$'\t' read -r r g b <<<"$rgb"
hex="$(printf '#%02x%02x%02x' "$r" "$g" "$b")"

have wl-copy && printf '%s' "$hex" | wl-copy || true
notify "Color" "$hex"
printf '%s\n' "$hex"
