#!/usr/bin/env bash
# ============================================================================
# niri_wallpaper.sh - open the wallpaper picker and prepare its thumbnails
# ============================================================================
# Niri counterpart of `qs_manager.sh toggle wallpaper`, without depending on
# the shared Hyprland script. It runs davinci thumbs first and then toggles the
# picker through the shell IPC. Super+W keeps the same chord.
# ============================================================================

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
. "$SCRIPT_DIR/lib/common.sh"
# shellcheck source=caching.sh
. "$SCRIPT_DIR/caching.sh"
qs_ensure_cache "wallpaper_picker"

KERNEL_DIR="${DAVINCI_KERNEL_DIR:-${DAVINCI_KERNEL_DIR:-$HOME/.local/share/equisdots/davinci}}"
[ -d "$KERNEL_DIR" ] || KERNEL_DIR="${DAVINCI_KERNEL_DIR:-$HOME/.local/share/equisdots/davinci}"
KERNEL="$KERNEL_DIR/davinci.sh"
[[ -f "$KERNEL" ]] || KERNEL="$KERNEL_DIR/davinci.sh"
if [[ -x "$HOME/.local/bin/davinci" ]]; then
    ( "$HOME/.local/bin/davinci" thumbs >/dev/null 2>&1 & )
elif [[ -x "$HOME/.local/bin/davinci" ]]; then
    ( "$HOME/.local/bin/davinci" thumbs >/dev/null 2>&1 & )
elif [[ -x "$KERNEL" ]]; then
    ( bash "$KERNEL" thumbs >/dev/null 2>&1 & )
elif have davinci; then
    ( davinci thumbs >/dev/null 2>&1 & )
elif have davinci; then
    ( davinci thumbs >/dev/null 2>&1 & )
else
    warn "davinci not found; the picker will show an empty grid"
fi

QML="$HOME/.config/hypr/scripts/quickshell/Shell.qml"
QS_BIN="quickshell"; have quickshell || QS_BIN="qs"
if ! have "$QS_BIN"; then
    die "quickshell/qs not found"
fi

# qs_manager.sh used to start the shell when it was not running; keep that
# behavior so the first Super+W after login always works.
if ! pgrep -f -- "-p $QML" >/dev/null 2>&1; then
    setsid "$QS_BIN" -p "$QML" >/dev/null 2>&1 &
    sleep 1
fi

exec "$QS_BIN" -p "$QML" ipc call main handleCommand toggle wallpaper ""
