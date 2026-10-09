#!/usr/bin/env bash
# ============================================================================
# equisdots niri - Quickshell cache/state/run environment
# ============================================================================
# Same contract as hyprland/scripts/caching.sh: the shell and the session
# scripts must agree on where per-widget caches, state and runtime files live.
# Sourced by the niri scripts that need those paths (niri_workspaces.sh,
# niri_screenshot.sh, ...). It is safe to source repeatedly.
#
# Exports:
#   QS_CACHE_DIR, QS_STATE_DIR, QS_RUN_DIR, QS_LOG_DIR
#   QS_CACHE_<WIDGET>, QS_STATE_<WIDGET>, QS_RUN_<WIDGET>  (via qs_ensure_cache)
# ============================================================================

# Load the shared path contract when available; otherwise fall back to the
# same defaults so the file stays usable on its own.
CACHING_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ -f "$CACHING_DIR/lib/common.sh" ]]; then
    # shellcheck source=lib/common.sh
    . "$CACHING_DIR/lib/common.sh"
fi

export QS_CACHE_DIR="${QS_CACHE_DIR:-$HOME/.cache/quickshell}"
export QS_STATE_DIR="${QS_STATE_DIR:-$HOME/.local/state/quickshell}"
export QS_RUN_DIR="${QS_RUN_DIR:-${XDG_RUNTIME_DIR:-/tmp}/quickshell}"
export QS_LOG_DIR="${QS_LOG_DIR:-$QS_RUN_DIR/logs}"

# The Quickshell payload is shared and lives under the equisdots data root.
QS_DIR="${EQUISDOTS_SCRIPTS_DIR:-${XDG_CONFIG_HOME:-$HOME/.config}/hypr/scripts}/quickshell"

mkdir -p "$QS_CACHE_DIR" "$QS_STATE_DIR" "$QS_RUN_DIR" "$QS_LOG_DIR" 2>/dev/null || true

# qs_ensure_cache NAME: create and export QS_CACHE/STATE/RUN_<NAME> for a module.
qs_ensure_cache() {
    local name="$1"
    local upper
    upper="$(printf '%s' "$name" | tr '[:lower:]-' '[:upper:]_')"

    local cache="$QS_CACHE_DIR/$name"
    local state="$QS_STATE_DIR/$name"
    local run="$QS_RUN_DIR/$name"
    mkdir -p "$cache" "$state" "$run" 2>/dev/null || true

    export "QS_CACHE_${upper}=$cache"
    export "QS_STATE_${upper}=$state"
    export "QS_RUN_${upper}=$run"
}

# Pre-initialize the cache dirs for every QML widget folder present.
if [[ -d "$QS_DIR" ]]; then
    for dir in "$QS_DIR"/*/; do
        [[ -d "$dir" ]] || continue
        qs_ensure_cache "$(basename "$dir")"
    done
fi
