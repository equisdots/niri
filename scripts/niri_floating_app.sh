#!/usr/bin/env bash
# ============================================================================
# niri_floating_app.sh - launch an app as a centered floating window
# ============================================================================
# niri equivalent of the Hyprland openFloating() helper in keybinds.lua:
#
#   niri_floating_app.sh <app-id> <width> <height> [--] <command...>
#
# Example (the two static binds):
#   niri_floating_app.sh kitty 900 560 -- kitty
#   niri_floating_app.sh code-insiders 1200 800 -- code-insiders -n
#
# Flow:
#   1. snapshot the current window ids with `niri msg --json windows`;
#   2. start `niri msg --json event-stream` (initial WindowsChanged snapshot +
#      live WindowOpenedOrChanged events) with a timeout;
#   3. spawn the app and wait for a new window whose app_id matches;
#   4. focus it, float it, set the exact logical width/height, and center it.
#
# niri 26.04 action notes (verified against `niri msg action --help` and the
# v26.04 niri-config Action enum):
#   - `toggle-window-floating`, `set-window-width`, `set-window-height` and
#     `center-window` all accept `--id` over IPC. `set-window-width 900` means
#     SetFixed (logical pixels), which applies to floating windows too.
#   - `move-floating-window` exists over IPC but is #[knuffel(skip)] in v26.04:
#     it is NOT a valid KDL bind action. We do not need it; center-window is a
#     real action and works by id.
#   - niri has no "resize to WxH and center" single action, hence the sequence.
#
# Environment: NIRI_FLOATING_TIMEOUT (seconds, default 20).
# ============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
. "$SCRIPT_DIR/lib/common.sh"

usage() {
    cat <<'EOF'
Usage: niri_floating_app.sh <app-id> <width> <height> [--] <command...>

  app-id    Wayland app_id to wait for (for example kitty, code-insiders)
  width     exact floating width in logical pixels
  height    exact floating height in logical pixels
  command   command to spawn (defaults to app-id when omitted)

Environment:
  NIRI_FLOATING_TIMEOUT   wait timeout in seconds (default 20)
EOF
}

case "${1:-}" in
    ""|-h|--help|help) usage; exit 0 ;;
esac

[[ $# -ge 3 ]] || { usage >&2; exit 1; }

APP_ID="$1"
WIDTH="$2"
HEIGHT="$3"
shift 3
# Apps whose Wayland app_id differs from the launcher name: match a stable
# substring instead of the exact id (VS Code Insiders reports
# com.microsoft.VSCodeInsiders).
APP_MATCH="$APP_ID"
case "$APP_ID" in
    code-insiders) APP_MATCH="insiders" ;;
esac
[[ "${1:-}" == "--" ]] && shift
if [[ $# -eq 0 ]]; then
    set -- "$APP_ID"
fi

[[ "$WIDTH" =~ ^[0-9]+$ && "$HEIGHT" =~ ^[0-9]+$ ]] \
    || die "width and height must be positive integers (got '$WIDTH' x '$HEIGHT')"
(( WIDTH > 0 && HEIGHT > 0 )) || die "width and height must be > 0"

require_cmd niri jq timeout
niri_require

TIMEOUT="${NIRI_FLOATING_TIMEOUT:-20}"
[[ "$TIMEOUT" =~ ^[0-9]+$ ]] && (( TIMEOUT > 0 )) || TIMEOUT=20

WORK="$(mktemp -d "${TMPDIR:-/tmp}/niri-floating.XXXXXX")"
EVENTS="$WORK/events.jsonl"
BEFORE="$WORK/before.json"
STREAM_PID=""

cleanup() {
    if [[ -n "$STREAM_PID" ]]; then
        kill "$STREAM_PID" 2>/dev/null || true
        wait "$STREAM_PID" 2>/dev/null || true
    fi
    rm -rf "$WORK"
}
trap cleanup EXIT INT TERM

# Snapshot before spawning: the event stream also sends a WindowsChanged
# snapshot on connect, and this file lets us ignore pre-existing windows.
if ! niri msg --json windows >"$BEFORE" 2>/dev/null; then
    printf '[]\n' >"$BEFORE"
fi

# Start the stream BEFORE the app so a fast open cannot be missed.
timeout "$TIMEOUT" niri msg --json event-stream >"$EVENTS" 2>/dev/null &
STREAM_PID=$!

# Detach the app so this script can keep polling. niri still sees the toplevel.
if have setsid; then
    setsid "$@" >/dev/null 2>&1 &
else
    nohup "$@" >/dev/null 2>&1 &
fi

# find_id MODE: print the newest matching window id from the event log.
# MODE=app requires a matching app_id; MODE=any accepts any new window.
find_id() {
    local mode="$1"
    jq -R -r --arg app "$APP_MATCH" --arg mode "$mode" --slurpfile before "$BEFORE" '
        def old_ids: [$before[0][]? | .id];
        def matching($w):
            ($w.id // -1) as $id
            | select((old_ids | index($id)) == null)
            | select($mode == "any" or (($w.app_id // "") | ascii_downcase | contains($app | ascii_downcase)))
            | $id;
        fromjson?
        | if type != "object" then empty
          elif has("WindowOpenedOrChanged") then .WindowOpenedOrChanged.window | matching(.)
          elif has("WindowsChanged") then .WindowsChanged.windows[]? | matching(.)
          else empty
          end
    ' "$EVENTS" 2>/dev/null | tail -n 1
}

# poll_windows MODE: fallback if the stream reconnects or an event is missed.
poll_windows() {
    local mode="$1"
    niri msg --json windows 2>/dev/null | jq -r --arg app "$APP_MATCH" --arg mode "$mode" --slurpfile before "$BEFORE" '
        def old_ids: [$before[0][]? | .id];
        [ .[]?
          | select((old_ids | index(.id)) == null)
          | select($mode == "any" or ((.app_id // "") | ascii_downcase | contains($app | ascii_downcase)))
          | .id
        ] | last // empty
    ' 2>/dev/null || true
}

DEADLINE=$((SECONDS + TIMEOUT))
START=$SECONDS
WIN_ID=""
while (( SECONDS < DEADLINE )); do
    WIN_ID="$(find_id app || true)"
    [[ -n "$WIN_ID" ]] || WIN_ID="$(poll_windows app || true)"
    [[ -n "$WIN_ID" ]] && break
    # Some apps report an app_id/native class different from the requested one.
    # After a short grace period, accept any new window from this launch so a
    # mismatch does not stall the bind for the full timeout.
    if (( SECONDS - START >= 3 )); then
        WIN_ID="$(find_id any || true)"
        [[ -n "$WIN_ID" ]] || WIN_ID="$(poll_windows any || true)"
        [[ -n "$WIN_ID" ]] && break
    fi
    sleep 0.1
done

if [[ -z "$WIN_ID" ]]; then
    notify "Floating app" "Timed out waiting for '$APP_ID' (${TIMEOUT}s)"
    die "no new window for app_id '$APP_ID' within ${TIMEOUT}s"
fi

# Focus first so the rest of the sequence behaves like the Hyprland helper.
niri msg action focus-window --id "$WIN_ID" >/dev/null 2>&1 || true

# Toggle only when needed, so an already-floating window is not unfloated.
IS_FLOATING="$(niri msg --json windows 2>/dev/null \
    | jq -r --argjson id "$WIN_ID" '.[]? | select(.id == $id) | .is_floating' 2>/dev/null \
    | head -n 1 || true)"
if [[ "$IS_FLOATING" != "true" ]]; then
    if ! niri msg action toggle-window-floating --id "$WIN_ID" >/dev/null 2>&1; then
        # Idempotent fallback: move-window-to-floating is a valid 26.04 action.
        niri msg action move-window-to-floating --id "$WIN_ID" >/dev/null 2>&1 || true
    fi
fi

# SetFixed logical pixels. The client may commit its own initial size after
# WindowOpenedOrChanged, which niri applies after our request; retry until the
# requested window_size sticks (usually 1-2 attempts), then center.
window_size() {
    niri msg --json windows 2>/dev/null \
        | jq -r --argjson id "$WIN_ID" '.[]? | select(.id == $id) | "\(.layout.window_size[0]) \(.layout.window_size[1])"' 2>/dev/null \
        | head -n 1
}

SIZED=0
for _attempt in 1 2 3 4 5; do
    niri msg action set-window-width --id "$WIN_ID" "$WIDTH" >/dev/null 2>&1 || true
    niri msg action set-window-height --id "$WIN_ID" "$HEIGHT" >/dev/null 2>&1 || true
    sleep 0.2
    read -r CUR_W CUR_H <<< "$(window_size || true)"
    if [[ "$CUR_W" == "$WIDTH" && "$CUR_H" == "$HEIGHT" ]]; then
        SIZED=1
        break
    fi
done
if (( SIZED == 0 )); then
    warn "could not size window $WIN_ID to ${WIDTH}x${HEIGHT} (got ${CUR_W:-?}x${CUR_H:-?})"
fi

niri msg action center-window --id "$WIN_ID" >/dev/null 2>&1 \
    || warn "could not center window $WIN_ID"
