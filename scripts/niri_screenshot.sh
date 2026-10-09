#!/usr/bin/env bash
# ============================================================================
# niri_screenshot.sh - screenshot wrapper for niri
# ============================================================================
# Maps the old hyprland/scripts/screenshot.sh verbs onto niri. The default and
# --full paths use niri's native screenshot actions (clipboard + disk to
# `screenshot-path`, with the built-in annotation UI). --edit uses grim+slurp
# and hands the capture to satty for annotation.
#
# Screen recording uses the SAME recorder as Hyprland: the shared
# ~/.config/hypr/scripts/screenshot.sh, which drives gpu-screen-recorder
# (compositor agnostic: gpu-screen-recorder + grim + slurp + wl-clipboard).
# Any --record invocation is forwarded to that shared script verbatim.
#
# Usage:
#   niri_screenshot.sh                 interactive region capture (native UI)
#   niri_screenshot.sh --full          focused output (native action)
#   niri_screenshot.sh --window        focused window (native action)
#   niri_screenshot.sh --edit          region capture, open in satty
#   niri_screenshot.sh --geometry G    grim with a slurp-style geometry
#   niri_screenshot.sh --record ...    forwarded to the shared screenshot.sh
#   niri_screenshot.sh --help
# ============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
. "$SCRIPT_DIR/lib/common.sh"
# shellcheck source=caching.sh
. "$SCRIPT_DIR/caching.sh"

# Screen recording is the shared gpu-screen-recorder path (same as Hyprland);
# forward --record (and its audio args) to the shared screenshot.sh verbatim.
for _a in "$@"; do
    if [[ "$_a" == "--record" ]]; then
        SHARED="$HOME/.config/hypr/scripts/screenshot.sh"
        [[ -f "$SHARED" ]] || die "screen recording needs the shared screenshot.sh (gpu-screen-recorder); install gpu-screen-recorder and run 'dotsniri install'"
        exec bash "$SHARED" "$@"
    fi
done

EDIT=0
FULL=0
WINDOW=0
GEOMETRY=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --edit)     EDIT=1 ;;
        --full)     FULL=1 ;;
        --window)   WINDOW=1 ;;
        --geometry) GEOMETRY="${2:-}"; shift ;;
        -h|--help)
            sed -n '2,26p' "$0" | sed 's/^# \{0,1\}//'
            exit 0
            ;;
        *) warn "ignoring unknown argument: $1" ;;
    esac
    shift
done

require_cmd niri
niri_require

SAVE_DIR="${XDG_PICTURES_DIR:-$HOME/Pictures}/Screenshots"
ensure_dir "$SAVE_DIR"

native() {
    # $@ = action name plus extra args.
    niri msg action "$@"
}

# Default path (no --edit / --geometry): use the niri-native actions, which
# write to `screenshot-path` and the clipboard and provide the built-in UI.
if [[ "$EDIT" == "0" && -z "$GEOMETRY" ]]; then
    if [[ "$FULL" == "1" ]]; then
        native screenshot-screen
        notify "Screenshot" "Saved to $SAVE_DIR (and clipboard)"
    elif [[ "$WINDOW" == "1" ]]; then
        native screenshot-window
        notify "Screenshot" "Saved to $SAVE_DIR (and clipboard)"
    else
        # Interactive region capture with the built-in annotation UI.
        native screenshot
    fi
    exit 0
fi

# --edit or --geometry: grim + slurp (+ satty for --edit).
require_cmd grim
have slurp || die "--edit/--geometry require slurp"

if [[ -z "$GEOMETRY" ]]; then
    GEOMETRY="$(slurp)"
    [[ -n "$GEOMETRY" ]] || exit 0
fi

STAMP="$(date +'%Y-%m-%d-%H%M%S')"
FILE="$SAVE_DIR/Screenshot_${STAMP}.png"

if [[ "$EDIT" == "1" ]]; then
    require_cmd satty
    grim -g "$GEOMETRY" - | GSK_RENDERER=gl satty \
        --filename - \
        --output-filename "$FILE" \
        --init-tool brush \
        --copy-command wl-copy
    [[ -s "$FILE" ]] && notify_icon "Screenshot" "Annotated: $(basename "$FILE")" "$FILE"
else
    grim -g "$GEOMETRY" "$FILE"
    have wl-copy && wl-copy <"$FILE" || true
    notify_icon "Screenshot" "Saved: $(basename "$FILE")" "$FILE"
fi
