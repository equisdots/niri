#!/usr/bin/env bash
# ============================================================================
# equisdots niri - shared script helpers
# ============================================================================
# Sourced by every script in this repository. Provides the path contract
# (strategy A: the shared equisdots data root stays at ~/.config/hypr, the
# compositor config lives at ~/.config/niri), small logging helpers and thin
# wrappers around `niri msg`.
#
# Environment overrides (all optional):
#   EQUISDOTS_CONFIG_DIR  shared data root        (default ~/.config/hypr)
#   EQUISDOTS_SETTINGS    settings.json path       (default $EQUISDOTS_CONFIG_DIR/settings.json)
#   EQUISDOTS_SCRIPTS_DIR shared scripts dir       (default $EQUISDOTS_CONFIG_DIR/scripts)
#   EQUISDOTS_PALETTES    palette store dir        (default $EQUISDOTS_SCRIPTS_DIR/quickshell/dock/palettes)
#   NIRI_CONFIG_DIR       niri config dir          (default ~/.config/niri)
#   NIRI_CONFIG_FILE      entry config path        (default $NIRI_CONFIG_DIR/config.kdl)
#   NIRI_GENERATED_DIR    generated fragments dir  (default $NIRI_CONFIG_DIR/generated)
#   NIRI_SCRIPTS_DIR      installed niri scripts   (default $NIRI_CONFIG_DIR/scripts)
#
# This file is a library: it must be sourced, not executed.
# ============================================================================

# Guard against double-sourcing.
if [[ -n "${EQUISDOTS_COMMON_SH:-}" ]]; then
    return 0
fi
EQUISDOTS_COMMON_SH=1

# --- Path contract ----------------------------------------------------------
XDG_CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"

# Shared equisdots data root (strategy A).
EQUISDOTS_CONFIG_DIR="${EQUISDOTS_CONFIG_DIR:-$XDG_CONFIG_HOME/hypr}"
EQUISDOTS_SETTINGS="${EQUISDOTS_SETTINGS:-$EQUISDOTS_CONFIG_DIR/settings.json}"
EQUISDOTS_SCRIPTS_DIR="${EQUISDOTS_SCRIPTS_DIR:-$EQUISDOTS_CONFIG_DIR/scripts}"
EQUISDOTS_PALETTES="${EQUISDOTS_PALETTES:-$EQUISDOTS_SCRIPTS_DIR/quickshell/dock/palettes}"

# niri compositor config.
NIRI_CONFIG_DIR="${NIRI_CONFIG_DIR:-$XDG_CONFIG_HOME/niri}"
NIRI_CONFIG_FILE="${NIRI_CONFIG_FILE:-$NIRI_CONFIG_DIR/config.kdl}"
NIRI_GENERATED_DIR="${NIRI_GENERATED_DIR:-$NIRI_CONFIG_DIR/generated}"
NIRI_SCRIPTS_DIR="${NIRI_SCRIPTS_DIR:-$NIRI_CONFIG_DIR/scripts}"

# State file behind generated/theme-effects.kdl.
NIRI_EFFECTS_STATE="${NIRI_EFFECTS_STATE:-$NIRI_CONFIG_DIR/window-effects.json}"

# Quickshell runtime dirs (kept in sync with scripts/caching.sh).
QS_RUN_DIR="${QS_RUN_DIR:-${XDG_RUNTIME_DIR:-/tmp}/quickshell}"
QS_CACHE_DIR="${QS_CACHE_DIR:-$HOME/.cache/quickshell}"
QS_STATE_DIR="${QS_STATE_DIR:-$HOME/.local/state/quickshell}"

export EQUISDOTS_CONFIG_DIR EQUISDOTS_SETTINGS EQUISDOTS_SCRIPTS_DIR
export EQUISDOTS_PALETTES NIRI_CONFIG_DIR NIRI_CONFIG_FILE
export NIRI_GENERATED_DIR NIRI_SCRIPTS_DIR NIRI_EFFECTS_STATE

# --- Logging ----------------------------------------------------------------
# All messages go to stderr so stdout stays clean for command substitution.
log()  { printf '[niri] %s\n' "$*" >&2; }
warn() { printf '[niri] warning: %s\n' "$*" >&2; }
err()  { printf '[niri] error: %s\n' "$*" >&2; }
die()  { err "$*"; exit 1; }

# --- Small utilities --------------------------------------------------------

# have CMD: true when CMD is on PATH.
have() { command -v "$1" >/dev/null 2>&1; }

# require_cmd CMD...: fail if any command is missing.
require_cmd() {
    local c
    for c in "$@"; do
        have "$c" || die "required command not found: $c"
    done
}

# ensure_dir DIR...: mkdir -p each argument.
ensure_dir() {
    local d
    for d in "$@"; do
        mkdir -p "$d"
    done
}

# niri_session_active: true when running inside a niri session.
niri_session_active() {
    [[ -n "${NIRI_SOCKET:-}" ]] && have niri
}

# niri_require: abort when no niri session is reachable.
niri_require() {
    have niri || die "niri is not installed or not on PATH"
    niri_session_active || die "NIRI_SOCKET is not set; run this inside a niri session"
}

# niri_reload: force a config reload (saving already reloads; this makes it
# explicit). Accepts an optional absolute path.
niri_reload() {
    local path="${1:-$NIRI_CONFIG_FILE}"
    have niri || return 0
    niri msg action load-config-file --path "$path" >/dev/null 2>&1 || true
}

# niri_validate [PATH]: validate the config, return its status.
niri_validate() {
    local path="${1:-$NIRI_CONFIG_FILE}"
    have niri || return 0
    niri validate -c "$path" >/dev/null 2>&1
}

# notify TITLE BODY: best-effort desktop notification (never blocks).
notify() {
    have notify-send || return 0
    if have timeout; then
        timeout 5 notify-send -t 3500 "$1" "${2:-}" >/dev/null 2>&1 || true
    else
        notify-send -t 3500 "$1" "${2:-}" >/dev/null 2>&1 || true
    fi
}

# notify_icon TITLE BODY ICON: notification with an icon path.
notify_icon() {
    have notify-send || return 0
    if have timeout; then
        timeout 5 notify-send -t 3500 -i "$3" "$1" "${2:-}" >/dev/null 2>&1 || true
    else
        notify-send -t 3500 -i "$3" "$1" "${2:-}" >/dev/null 2>&1 || true
    fi
}

# c_foreground HEX: strip a leading '#'; prints the bare hex.
strip_hash() {
    printf '%s' "${1#\#}"
}
