#!/usr/bin/env bash
# ============================================================================
# niri_ws.sh - workspace and window routing
# ============================================================================
# Replaces the hyprctl fast path of qs_manager.sh. Used by the keybinds
# (Super+1..0, page keys, wheel) and by the bar's Compositor.switchWorkspace.
#
# Usage:
#   niri_ws.sh <index|name>          focus a workspace
#   niri_ws.sh <index|name> move     move the focused window to a workspace
#   niri_ws.sh next                  focus the workspace below
#   niri_ws.sh prev                  focus the workspace above
#   niri_ws.sh --help
#
# `focus-workspace <index>` acts on the focused output, which matches the
# Hyprland behavior this replaces.
# ============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
. "$SCRIPT_DIR/lib/common.sh"

usage() {
    cat <<'EOF'
Usage: niri_ws.sh <index|name> [move] | next | prev

  <index|name>        focus the workspace
  <index|name> move   move the focused window to the workspace
  next                focus the workspace down
  prev                focus the workspace up
EOF
}

# close_popups: dismiss any open Quickshell popup before switching.
close_popups() {
    local bin=""
    if have quickshell; then
        bin="quickshell"
    elif have qs; then
        bin="qs"
    fi
    [[ -n "$bin" ]] || return 0
    "$bin" -p "$EQUISDOTS_SCRIPTS_DIR/quickshell/Shell.qml" \
        ipc call main handleCommand "close" "" "" >/dev/null 2>&1 || true
}

action="${1:-}"
target="${2:-}"

case "$action" in
    ""|-h|--help|help)
        usage
        exit 0
        ;;
    next)
        niri_require
        close_popups
        niri msg action focus-workspace-down
        ;;
    prev)
        niri_require
        close_popups
        niri msg action focus-workspace-up
        ;;
    *)
        niri_require
        close_popups
        if [[ "$target" == "move" ]]; then
            niri msg action move-window-to-workspace "$action"
        else
            niri msg action focus-workspace "$action"
        fi
        ;;
esac
