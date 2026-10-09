#!/usr/bin/env bash
# ============================================================================
# niri_workspaces.sh - workspace state daemon for the Quickshell bar
# ============================================================================
# Writes the same JSON the Hyprland workspaces.sh produced, so Bar.qml (which
# watches that file) needs no change:
#
#   $XDG_RUNTIME_DIR/quickshell/workspaces/workspaces.json
#
# Shape: [ { id, state: active|occupied|empty, tooltip, classes } ]
#
# Unlike the Hyprland version this consumes the niri event stream instead of
# polling socket2. On connect niri sends the full WorkspacesChanged and
# WindowsChanged snapshots, so the model is rebuilt from scratch and can never
# desync; after that only deltas arrive.
#
# Run it as a daemon (autostart/systemd) or once for a single snapshot:
#   niri_workspaces.sh --once
# ============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
. "$SCRIPT_DIR/lib/common.sh"
# shellcheck source=caching.sh
. "$SCRIPT_DIR/caching.sh"

ONCE=0
case "${1:-}" in
    --once) ONCE=1 ;;
    -h|--help)
        cat <<'EOF'
Usage: niri_workspaces.sh [--once]

  (no args)   run continuously, reacting to the niri event stream
  --once      render one snapshot and exit
EOF
        exit 0
        ;;
    "") ;;
    *) die "unknown argument: $1 (try --help)" ;;
esac

require_cmd python3

OUT_DIR="$QS_RUN_DIR/workspaces"
ensure_dir "$OUT_DIR"
OUT="$OUT_DIR/workspaces.json"

TMP_WS="$OUT_DIR/.ws.$$"
TMP_WIN="$OUT_DIR/.win.$$"
TMP_OUT="$OUT_DIR/.out.$$"

cleanup() { rm -f "$TMP_WS" "$TMP_WIN" "$TMP_OUT"; }
trap cleanup EXIT

# Workspace count shown in the bar; settings.json is the source of truth.
count=8
if [[ -f "$EQUISDOTS_SETTINGS" ]] && have jq; then
    count="$(jq -r '.workspaceCount // 8' "$EQUISDOTS_SETTINGS" 2>/dev/null || printf '8')"
fi
[[ "$count" =~ ^[0-9]+$ ]] || count=8

# render: query niri, derive per-workspace state, atomically replace the JSON.
render() {
    have niri || return 0
    niri msg --json workspaces >"$TMP_WS" 2>/dev/null || return 0
    niri msg --json windows >"$TMP_WIN" 2>/dev/null || : >"$TMP_WIN"

    python3 - "$TMP_WS" "$TMP_WIN" "$count" >"$TMP_OUT" <<'PY' || return 0
import json
import sys

try:
    with open(sys.argv[1]) as fh:
        workspaces = json.load(fh)
except Exception:
    workspaces = []
try:
    with open(sys.argv[2]) as fh:
        windows = json.load(fh)
except Exception:
    windows = []
try:
    count = int(sys.argv[3])
except Exception:
    count = 8

classes, titles = {}, {}
for win in windows:
    wid = win.get("workspace_id")
    if wid is None:
        continue
    app = win.get("app_id")
    if app:
        classes.setdefault(wid, [])
        if app not in classes[wid]:
            classes[wid].append(app)
    if win.get("title"):
        titles[wid] = win["title"]

out = []
for ws in sorted(workspaces, key=lambda w: w.get("idx", 0)):
    idx = ws.get("idx", 0)
    if idx <= 0:
        continue
    wid = ws.get("id")
    if ws.get("is_focused"):
        state = "active"
    elif classes.get(wid):
        state = "occupied"
    else:
        state = "empty"
    out.append({
        "id": idx,
        "state": state,
        "tooltip": titles.get(wid, ws.get("name") or "Empty"),
        "classes": ",".join(classes.get(wid, [])),
    })

# Pad/trim to the configured count so the bar keeps a stable row.
while len(out) < count:
    out.append({"id": len(out) + 1, "state": "empty", "tooltip": "Empty", "classes": ""})
del out[count:]

json.dump(out, sys.stdout)
PY

    mv -f "$TMP_OUT" "$OUT"
}

render

if [[ "$ONCE" = "1" ]]; then
    exit 0
fi

# Event-driven loop. A missing niri (or a dropped stream) reconnects and lays
# down a fresh snapshot.
while true; do
    if niri msg --json event-stream 2>/dev/null | while IFS= read -r line; do
        case "$line" in
            *WorkspacesChanged*|*WorkspaceActivated*|*WorkspaceActiveWindowChanged*|*WindowsChanged*|*WindowOpenedOrChanged*|*WindowClosed*|*WindowFocusChanged*|*WindowLayoutsChanged*|*WindowUrgencyChanged*)
                # Drain the burst so a move/resize does not spam rewrites.
                while IFS= read -t 0.05 -r _drain; do :; done
                render || true
                ;;
        esac
    done; then
        :
    fi
    sleep 1
done
