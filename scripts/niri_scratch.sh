#!/usr/bin/env bash
# ============================================================================
# niri_scratch.sh - scratchpad toggle for niri
# ============================================================================
# Hyprland used a floating special workspace (`special:files`) toggled with
# Super+A. niri 26.04 has no floating special-workspace overlay, so the
# equivalent is the named workspace "scratch" (declared in
# modules/workspaces.kdl) with this smarter toggle:
#
#   - scratch not focused, has windows  -> focus it
#   - scratch not focused, no windows   -> focus it and launch nautilus
#   - scratch already focused           -> focus the previous workspace
#
# This keeps Super+A a toggle on the common path (files scratchpad) while still
# making the empty workspace useful on first press. Super+Shift+A remains the
# move-window-to-scratch bind (routed through niri_ws.sh).
#
# State comes from `niri msg --json workspaces` / `niri msg --json windows`.
# ============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
. "$SCRIPT_DIR/lib/common.sh"

case "${1:-}" in
    -h|--help|help)
        cat <<'EOF'
Usage: niri_scratch.sh

Focus the "scratch" workspace, or focus the previous workspace when scratch is
already focused. Launches nautilus when scratch has no windows.
EOF
        exit 0
        ;;
    "") ;;
    *) die "unknown argument: $1 (try --help)" ;;
esac

require_cmd niri jq
niri_require

WORKSPACES="$(niri msg --json workspaces 2>/dev/null)" || die "could not read niri workspaces"
WINDOWS="$(niri msg --json windows 2>/dev/null || printf '[]')"

# scratch_id, is_focused, window_count (0 when the workspace does not exist).
IFS=$'\t' read -r SCRATCH_ID IS_FOCUSED WINDOW_COUNT < <(
    jq -r --argjson windows "$WINDOWS" '
        ([.[] | select(.name == "scratch")][0] // {}) as $ws
        | ($ws.id // "") as $id
        | [
            $id,
            ($ws.is_focused // false),
            (if $id == "" then 0
             else ([$windows[]? | select(.workspace_id == $id)] | length)
             end)
          ]
        | @tsv
    ' <<<"$WORKSPACES"
)

# Use niri_ws.sh to focus scratch: it closes open Quickshell popups first, the
# same unified behavior as the numbered workspace binds.
focus_scratch() {
    bash "$SCRIPT_DIR/niri_ws.sh" scratch
}

if [[ "$IS_FOCUSED" == "true" ]]; then
    niri msg action focus-workspace-previous >/dev/null 2>&1 || true
    exit 0
fi

LAUNCH=0
[[ -z "$SCRATCH_ID" || "$WINDOW_COUNT" == "0" ]] && LAUNCH=1

focus_scratch

if (( LAUNCH )); then
    # Spawn through niri so the app inherits the compositor environment and
    # opens on the now-focused scratch workspace.
    niri msg action spawn -- nautilus >/dev/null 2>&1 \
        || warn "could not launch nautilus"
fi
