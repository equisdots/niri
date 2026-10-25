#!/usr/bin/env bash
# ============================================================================
# niri_split_pair.sh - open two windows as a 50/50 column pair
# ============================================================================
# Opens the same command twice and sets each new column to half the output
# width, so the two windows sit side by side instead of the full-width default.
#
#   niri_split_pair.sh [--] <command...>
#
# Defaults to two kitty terminals. Useful when the global default column width
# is 1.0 but you want a one-shot split without resizing by hand.
#
# Environment:
#   NIRI_SPLIT_WIDTH    column width (default 50%)
#   NIRI_SPLIT_TIMEOUT  seconds to wait for each window (default 10)
# ============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
. "$SCRIPT_DIR/lib/common.sh"

usage() {
    cat <<'EOF'
Usage: niri_split_pair.sh [--] <command...>

  Opens <command> twice and sets each new column to NIRI_SPLIT_WIDTH
  (default 50%), producing a side-by-side pair.

Environment:
  NIRI_SPLIT_WIDTH    column width (default 50%)
  NIRI_SPLIT_TIMEOUT  wait timeout per window in seconds (default 10)
EOF
}

case "${1:-}" in
    -h|--help|help) usage; exit 0 ;;
esac

[[ "${1:-}" == "--" ]] && shift
if [[ $# -eq 0 ]]; then
    set -- kitty
fi

WIDTH="${NIRI_SPLIT_WIDTH:-50%}"
TIMEOUT="${NIRI_SPLIT_TIMEOUT:-10}"
[[ "$WIDTH" =~ ^[0-9]+%$ ]] || die "NIRI_SPLIT_WIDTH must be a percentage (got '$WIDTH')"
[[ "$TIMEOUT" =~ ^[0-9]+$ ]] && (( TIMEOUT > 0 )) || TIMEOUT=10

require_cmd niri jq
niri_require

window_ids() {
    niri msg --json windows 2>/dev/null | jq -r '.[].id' | sort -n
}

wait_for_new() {
    local before="$1" deadline=$((SECONDS + TIMEOUT)) new
    while (( SECONDS < deadline )); do
        new="$(comm -13 \
            <(printf '%s\n' "$before" | sort -n) \
            <(window_ids) 2>/dev/null | tail -n 1 || true)"
        if [[ -n "$new" ]]; then
            printf '%s' "$new"
            return 0
        fi
        sleep 0.1
    done
    return 1
}

focus_id() {
    local id="$1" i current
    for i in {1..40}; do
        niri msg action focus-window --id "$id" >/dev/null 2>&1 || true
        sleep 0.05
        current="$(niri msg --json focused-window 2>/dev/null | jq -r '.id // empty')"
        [[ "$current" == "$id" ]] && return 0
    done
    return 1
}

spawn_half() {
    local before id out_w cur i target_pct
    before="$(window_ids)"
    niri msg action spawn -- "$@" >/dev/null 2>&1 || true
    id="$(wait_for_new "$before")" || die "timed out waiting for the new window (${TIMEOUT}s)"
    focus_id "$id" || die "new window $id did not take focus"
    out_w="$(niri msg --json focused-output 2>/dev/null | jq -r '.logical.width // 0')"
    target_pct="${WIDTH%\%}"
    # set-column-width acts on the focused column. The client may commit its
    # initial (full-width) size after our first request, so retry and verify
    # the resulting tile width instead of trusting a single call.
    for i in {1..20}; do
        focus_id "$id" || continue
        niri msg action set-column-width "$WIDTH" >/dev/null 2>&1 || true
        sleep 0.1
        cur="$(niri msg --json windows 2>/dev/null | jq -r --argjson id "$id" \
            '.[] | select(.id == $id) | ((.layout.tile_size // .layout.window_size)[0] // 0)' 2>/dev/null | head -n1)"
        if awk -v c="$cur" -v o="$out_w" -v p="$target_pct" \
            'BEGIN { t = o * p / 100; exit !(c > 0 && o > 0 && c > t * 0.65 && c < t * 1.35) }'; then
            break
        fi
    done
    printf '%s' "$id"
}

FIRST="$(spawn_half "$@")"
SECOND="$(spawn_half "$@")"
printf 'split pair: %s %s (%s each)\n' "$FIRST" "$SECOND" "$WIDTH"
