#!/usr/bin/env bash
# ============================================================================
# niri_idle_mode.sh - idle / auto-lock control for niri
# ============================================================================
# Port of hyprland/scripts/idle-mode.sh. The daemon changes from hypridle to
# swayidle, and the DPMS command becomes `niri msg action power-off-monitors`;
# the lock command is the shared Quickshell locker (ext-session-lock, which
# niri supports) at ~/.config/hypr/scripts/lock.sh.
#
#   niri_idle_mode.sh awake   no auto lock/suspend; manual only
#                             (Super+Alt+L lock, Super+Ctrl+S suspend)
#   niri_idle_mode.sh normal  idle timers on (lock -> DPMS off -> suspend)
#   niri_idle_mode.sh boot    called at login; honors the saved mode
#   niri_idle_mode.sh status  prints awake|normal
#
# The choice is stored in ~/.config/hypr/idle-settings.json (shared with the
# Hyprland stack) and restored on every login.
#
# If a swayidle.service user unit is installed (see systemd/swayidle.service),
# it is used; otherwise a detached swayidle process is started, matching the
# old hypridle behavior.
# ============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
. "$SCRIPT_DIR/lib/common.sh"

STATE="$EQUISDOTS_CONFIG_DIR/idle-settings.json"
LOCK_SCRIPT="$EQUISDOTS_SCRIPTS_DIR/lock.sh"

ensure_state() {
    ensure_dir "$EQUISDOTS_CONFIG_DIR"
    [[ -f "$STATE" ]] || printf '{"idleMode":"normal"}' >"$STATE"
}

current() {
    ensure_state
    jq -r '.idleMode // "normal"' "$STATE" 2>/dev/null || printf 'normal'
}

# use_systemd: true when a swayidle.service user unit exists for this user.
use_systemd() {
    have systemctl || return 1
    systemctl --user cat swayidle.service >/dev/null 2>&1
}

# The swayidle command line for the process fallback.
swayidle_args() {
    SWAYIDLE_ARGS=(
        -w
        timeout 600 "bash $LOCK_SCRIPT"
        timeout 601 "niri msg action power-off-monitors"
        timeout 1200 "systemctl suspend"
        before-sleep "bash $LOCK_SCRIPT"
    )
}

start_idle() {
    if use_systemd; then
        systemctl --user start swayidle.service
        return 0
    fi
    have swayidle || { warn "swayidle not installed"; return 0; }
    pgrep -x swayidle >/dev/null 2>&1 && return 0
    swayidle_args
    setsid nohup swayidle "${SWAYIDLE_ARGS[@]}" >/dev/null 2>&1 </dev/null &
}

stop_idle() {
    if use_systemd; then
        systemctl --user stop swayidle.service || true
        return 0
    fi
    pkill -x swayidle 2>/dev/null || true
}

case "${1:-}" in
    awake)
        ensure_state
        printf '{"idleMode":"awake"}' >"$STATE"
        stop_idle
        notify "Idle & sleep" "Keep awake: no auto lock/suspend. Manual: Super+Alt+L lock, Super+Ctrl+S suspend"
        ;;
    normal)
        ensure_state
        printf '{"idleMode":"normal"}' >"$STATE"
        start_idle
        notify "Idle & sleep" "Auto mode: lock, DPMS off and suspend via swayidle"
        ;;
    boot)
        ensure_state
        if [[ "$(current)" == "awake" ]]; then
            stop_idle
        else
            start_idle
        fi
        ;;
    status)
        current
        ;;
    -h|--help)
        echo "usage: niri_idle_mode.sh awake|normal|boot|status" >&2
        ;;
    *)
        echo "usage: niri_idle_mode.sh awake|normal|boot|status" >&2
        exit 1
        ;;
esac
