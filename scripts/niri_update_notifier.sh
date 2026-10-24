#!/usr/bin/env bash
# ============================================================================
# niri_update_notifier.sh - niri-stack update indicator
# ============================================================================
# Hyprland counterpart: hyprland/scripts/update_notifier.sh. The shared script
# compares the Hyprland install version, which is wrong on a niri-only machine
# (it would advertise Hyprland updates). This one compares the niri-meta
# version state with niri-meta/updates.json and writes the same Quickshell
# cache files the bar/updater already read:
#
#   $QS_CACHE_UPDATER/update_pending   -> bar update indicator
#   $QS_CACHE_UPDATER/notified_version -> notification de-duplication
#
# Usage: niri_update_notifier.sh [--once]
# ============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=caching.sh
. "$SCRIPT_DIR/caching.sh"
qs_ensure_cache "updater"

INTERVAL=600
ONCE=0
case "${1:-}" in
    --once) ONCE=1 ;;
    -h|--help)
        sed -n '2,16p' "$0" | sed 's/^# \{0,1\}//'
        exit 0
        ;;
    "") ;;
    *) echo "unknown option: $1 (try --help)" >&2; exit 2 ;;
esac

CACHE_FILE="$QS_CACHE_UPDATER/notified_version"
PENDING_FILE="$QS_CACHE_UPDATER/update_pending"
MANIFEST_URL="https://raw.githubusercontent.com/equisdots/niri-meta/main/updates.json"
LOCAL_MANIFEST="${XDG_DATA_HOME:-$HOME/.local/share}/equisdots-niri/niri-meta/updates.json"
VERSION_STATE="${XDG_STATE_HOME:-$HOME/.local/state}/equisdots-niri-version"

local_version() {
    local v=""
    if [[ -f "$VERSION_STATE" ]]; then
        # shellcheck disable=SC1090
        v="$(source "$VERSION_STATE" 2>/dev/null && printf '%s' "${LOCAL_VERSION:-}")"
    fi
    if [[ -z "$v" && -f "$(dirname "$LOCAL_MANIFEST")/VERSION" ]]; then
        v="$(tr -d '[:space:]' < "$(dirname "$LOCAL_MANIFEST")/VERSION" 2>/dev/null || true)"
    fi
    printf '%s' "${v:-0.0.0}"
}

remote_version() {
    local v=""
    if command -v curl >/dev/null 2>&1; then
        v="$(curl -m 5 -fsSL "$MANIFEST_URL" 2>/dev/null | jq -r '.version // empty' 2>/dev/null || true)"
    fi
    if [[ -z "$v" && -f "$LOCAL_MANIFEST" ]]; then
        v="$(jq -r '.version // empty' "$LOCAL_MANIFEST" 2>/dev/null || true)"
    fi
    printf '%s' "$v"
}

check_once() {
    local local_v remote_v newest
    local_v="$(local_version)"
    remote_v="$(remote_version)"

    if [[ -n "$remote_v" && "$local_v" != "Unknown" && "$local_v" != "0.0.0" && "$local_v" != "$remote_v" ]]; then
        newest="$(printf '%s\n' "$local_v" "$remote_v" | sort -V | tail -n 1)"
        if [[ "$newest" == "$remote_v" ]]; then
            touch "$PENDING_FILE"
            if [[ ! -f "$CACHE_FILE" ]] || [[ "$(cat "$CACHE_FILE")" != "$remote_v" ]]; then
                printf '%s\n' "$remote_v" > "$CACHE_FILE"
                if command -v notify-send >/dev/null 2>&1; then
                    notify-send -t 15000 -a 'equisdots-niri' -u normal \
                        'niri stack update available' \
                        "A new version ($remote_v) is ready. Open the updater in the bar to run dotsniri update." \
                        || true
                fi
            fi
        fi
    else
        # Versions match or the manifest is unreachable: clear the indicator.
        rm -f "$PENDING_FILE"
    fi
}

while true; do
    check_once
    if (( ONCE )); then
        exit 0
    fi
    sleep "$INTERVAL"
done
