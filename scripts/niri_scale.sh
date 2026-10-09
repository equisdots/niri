#!/usr/bin/env bash
# ============================================================================
# niri_scale.sh - scale the focused output up/down or set it explicitly
# ============================================================================
# Port of hyprland/scripts/scale-menu.sh. Hyprland applied a global scale to
# every monitor through the Lua API; niri exposes a runtime setter per output:
#
#   niri msg output <name> scale <value>|auto
#
# Usage:
#   niri_scale.sh up|down        step the focused output along the ladder
#   niri_scale.sh auto           let niri pick a scale for the focused output
#   niri_scale.sh 1.5            set an explicit scale
#   niri_scale.sh up NAME        operate on a named output instead of focused
#   niri_scale.sh --help
#
# Runtime changes are temporary; `niri_monitor_manager.sh save` persists the
# live state to generated/outputs.kdl.
# ============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
. "$SCRIPT_DIR/lib/common.sh"

LADDER="0.8 1.0 1.25 1.5 2.0"

usage() {
    cat <<'EOF'
Usage: niri_scale.sh up|down|auto|<scale> [output]

  up|down    step the focused (or named) output along 0.8 1.0 1.25 1.5 2.0
  auto       niri picks the scale
  1.5        explicit scale
EOF
}

# Help and empty invocation must work even without niri installed.
[[ "${1:-}" == "-h" || "${1:-}" == "--help" || -z "${1:-}" ]] && { usage; exit 0; }

require_cmd niri jq

verb="$1"
want_output="${2:-}"

# Resolve the output to operate on.
if [[ -n "$want_output" ]]; then
    out="$want_output"
else
    out="$(niri msg --json focused-output 2>/dev/null | jq -r '.name // empty' 2>/dev/null || true)"
    if [[ -z "$out" ]]; then
        out="$(niri msg --json outputs 2>/dev/null | jq -r 'keys[0] // empty' 2>/dev/null || true)"
    fi
fi
[[ -n "$out" ]] || die "could not determine an output"

# Current scale (logical.scale may be absent until the output is mapped).
current="$(niri msg --json outputs 2>/dev/null \
    | jq -r --arg o "$out" '.[$o].logical.scale // empty' 2>/dev/null || true)"
[[ -n "$current" ]] || current=1

# next_in_ladder DIR: nearest rung in the given direction, clamped at the ends.
next_in_ladder() {
    awk -v cur="$current" -v dir="$1" -v ladder="$LADDER" 'BEGIN {
        n = split(ladder, a, " ")
        idx = 1; best = 1e9
        for (i = 1; i <= n; i++) {
            d = a[i] - cur; if (d < 0) d = -d
            if (d < best) { best = d; idx = i }
        }
        if (dir == "up")   idx = (idx < n) ? idx + 1 : n
        if (dir == "down") idx = (idx > 1) ? idx - 1 : 1
        print a[idx]
    }'
}

case "$verb" in
    up|down) scale="$(next_in_ladder "$verb")" ;;
    auto)    scale="auto" ;;
    *)
        scale="$verb"
        [[ "$scale" =~ ^[0-9]+(\.[0-9]+)?$ ]] || die "invalid scale: $scale"
        ;;
esac

niri msg output "$out" scale "$scale"

# Record the value in settings.json (the shell reads it for its own UI scale).
if [[ "$scale" != "auto" && -f "$EQUISDOTS_SETTINGS" ]]; then
    tmp="$EQUISDOTS_SETTINGS.tmp.$$"
    if jq --arg n "$out" --argjson s "$scale" \
        'if (.monitors // [] | length) > 0
         then .monitors = [ .monitors[] | if .name == $n then .scale = $s else . end ]
         else . end' \
        "$EQUISDOTS_SETTINGS" >"$tmp" 2>/dev/null; then
        mv -f "$tmp" "$EQUISDOTS_SETTINGS"
    else
        rm -f "$tmp"
    fi
fi

if [[ "$scale" == "auto" ]]; then
    notify "Display Scale" "$out: auto"
else
    notify "Display Scale" "$out: $(awk -v s="$scale" 'BEGIN { printf "%d%%", s * 100 }')"
fi
