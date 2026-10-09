#!/usr/bin/env bash
# ============================================================================
# niri_monitor_manager.sh - list and apply monitor configuration
# ============================================================================
# TUI/rofi-free replacement for hyprland/scripts/monitor-manager.sh. It talks
# to niri over IPC:
#
#   niri_monitor_manager.sh [list|info]            show connected outputs
#   niri_monitor_manager.sh apply NAME key=value...
#   niri_monitor_manager.sh layout <preset>        position presets
#   niri_monitor_manager.sh save                   write generated/outputs.kdl
#   niri_monitor_manager.sh --help
#
# `apply` keys: mode, scale, position, transform, vrr, and the bare flags
# `on` / `off`. Runtime changes via `niri msg output` are temporary; use `save`
# (or niri_monitor_apply.sh) to persist them to the config.
#
# `layout` presets: right, left, above, below, only-primary, only-external.
# Hardware mirroring does not exist in niri 26.04, so the old `mirror` preset is
# intentionally not provided.
# ============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
. "$SCRIPT_DIR/lib/common.sh"

usage() {
    cat <<'EOF'
Usage:
  niri_monitor_manager.sh list                 list outputs (default)
  niri_monitor_manager.sh apply NAME key=val   apply runtime output options
  niri_monitor_manager.sh layout PRESET        right|left|above|below|
                                               only-primary|only-external
  niri_monitor_manager.sh save                 write generated/outputs.kdl

apply keys:
  mode=WxH@R | mode=auto
  scale=1.5 | scale=auto
  position=X,Y | position=auto
  transform=normal|90|180|270|flipped|flipped-90|flipped-180|flipped-270
  vrr=on|off|on-demand
  on | off
EOF
}

# Help must work even without niri installed.
if [[ "${1:-}" == "-h" || "${1:-}" == "--help" || "${1:-}" == "help" ]]; then
    usage
    exit 0
fi

require_cmd niri jq

# outputs_json: raw `niri msg --json outputs`.
outputs_json() { niri msg --json outputs 2>/dev/null; }

cmd_list() {
    local json
    json="$(outputs_json)"
    [[ -n "$json" ]] || die "no outputs (is niri running?)"

    jq -r '
        def hz3:
            (. / 1000) as $r
            | ($r | floor) as $i
            | (((($r - $i) * 1000) | round)) as $f
            | "\($i).\($f | tostring | if length == 1 then "00" + . elif length == 2 then "0" + . else . end)";
        to_entries[]
        | .key as $name
        | .value as $o
        | ($o.modes[$o.current_mode] // null) as $m
        | ($o.logical // null) as $l
        | [
            $name,
            ((($o.make // "") + " " + ($o.model // "") + " " + ($o.serial // "")) | gsub(" +"; " ") | sub(" $"; "")),
            (if $m == null then "off" else "\($m.width)x\($m.height)@\($m.refresh_rate | hz3)" end),
            (if $l == null then "-" else "\($l.width)x\($l.height)" end),
            (if $l == null then "-" else "\($l.x),\($l.y)" end),
            (if $l == null then "-" else "\($l.scale)" end),
            (if $l == null then "-" else "\($l.transform)" end),
            (if ($o.vrr_enabled // false) then "vrr" else "novrr" end)
        ]
        | @tsv' <<<"$json" \
    | while IFS=$'\t' read -r name ident mode logical pos scale transform vrr; do
        printf '%s\n' "$name"
        printf '  identity: %s\n' "$ident"
        printf '  mode: %s | logical: %s @ %s | scale %s | transform %s | %s\n' \
            "$mode" "$logical" "$pos" "$scale" "$transform" "$vrr"
    done
}

# logical_dim NAME FIELD: numeric logical width/height, or empty.
logical_dim() {
    outputs_json | jq -r --arg n "$1" --arg f "$2" '.[$n].logical[$f] // empty'
}

cmd_layout() {
    local preset="$1"
    local -a outs
    mapfile -t outs < <(outputs_json | jq -r 'keys[]')
    (( ${#outs[@]} >= 1 )) || die "no outputs"

    local primary="${outs[0]}" secondary="${outs[1]:-}"

    case "$preset" in
        only-primary)
            [[ -n "$secondary" ]] || { warn "only one output"; return 0; }
            niri msg output "$secondary" off
            notify "Monitor Layout" "Only primary ($primary)"
            return 0
            ;;
        only-external)
            [[ -n "$secondary" ]] || { warn "only one output"; return 0; }
            niri msg output "$primary" off
            notify "Monitor Layout" "Only external ($secondary)"
            return 0
            ;;
    esac

    [[ -n "$secondary" ]] || die "two outputs are required for layout '$preset'"

    local pw ph sw sh
    pw="$(logical_dim "$primary" width)"; ph="$(logical_dim "$primary" height)"
    sw="$(logical_dim "$secondary" width)"; sh="$(logical_dim "$secondary" height)"
    : "${pw:=1920}" "${ph:=1080}" "${sw:=1920}" "${sh:=1080}"

    case "$preset" in
        right)
            niri msg output "$primary" position set 0 0
            niri msg output "$secondary" position set "$pw" 0
            ;;
        left)
            niri msg output "$secondary" position set 0 0
            niri msg output "$primary" position set "$sw" 0
            ;;
        above)
            niri msg output "$secondary" position set 0 0
            niri msg output "$primary" position set 0 "$sh"
            ;;
        below)
            niri msg output "$primary" position set 0 0
            niri msg output "$secondary" position set 0 "$ph"
            ;;
        *)
            die "unknown preset: $preset (right|left|above|below|only-primary|only-external)"
            ;;
    esac
    notify "Monitor Layout" "Applied: $preset"
}

cmd_apply() {
    local name="$1"; shift
    [[ -n "$name" ]] || die "apply requires an output name"
    local pair
    for pair in "$@"; do
        case "$pair" in
            on)                  niri msg output "$name" on ;;
            off)                 niri msg output "$name" off ;;
            mode=auto|mode="")   niri msg output "$name" mode auto ;;
            mode=*)              niri msg output "$name" mode "${pair#mode=}" ;;
            scale=auto)          niri msg output "$name" scale auto ;;
            scale=*)             niri msg output "$name" scale "${pair#scale=}" ;;
            position=auto)       niri msg output "$name" position auto ;;
            position=*)
                local p="${pair#position=}"
                niri msg output "$name" position set "${p%%,*}" "${p##*,}"
                ;;
            transform=*)         niri msg output "$name" transform "${pair#transform=}" ;;
            vrr=on-demand)       niri msg output "$name" vrr on --on-demand ;;
            vrr=on)              niri msg output "$name" vrr on ;;
            vrr=off)             niri msg output "$name" vrr off ;;
            *) warn "ignoring unknown option: $pair" ;;
        esac
    done
}

# cmd_save: write the live output state as generated/outputs.kdl and reload.
cmd_save() {
    ensure_dir "$NIRI_GENERATED_DIR"
    local out="$NIRI_GENERATED_DIR/outputs.kdl"
    local tmp="$NIRI_GENERATED_DIR/.outputs.$$"

    outputs_json | jq -r '
        def hz3:
            (. / 1000) as $r
            | ($r | floor) as $i
            | (((($r - $i) * 1000) | round)) as $f
            | "\($i).\($f | tostring | if length == 1 then "00" + . elif length == 2 then "0" + . else . end)";
        to_entries[]
        | .key as $name
        | .value as $o
        | ($o.modes[$o.current_mode] // null) as $m
        | ($o.logical // null) as $l
        | (($o.make // "") + " " + ($o.model // "") + " " + ($o.serial // "")) as $ident
        | ($ident | gsub(" +"; " ") | sub("^ "; "") | sub(" $"; "")) as $clean
        | (if ($clean | length) > 0 then $clean else $name end) as $id
        | "output \"\($id)\" {"
        , (if $l == null then "    off"
           else (
             (if $m == null then "" else "    mode \"\($m.width)x\($m.height)@\($m.refresh_rate | hz3)\"\n" end)
             + "    scale \($l.scale)\n"
             + "    position x=\($l.x) y=\($l.y)\n"
             + (if $l.transform != "normal" then "    transform \"\($l.transform)\"\n" else "" end)
             + (if ($o.vrr_enabled // false) then "    variable-refresh-rate\n" else "" end)
           )
           end)
        , "}"
    ' >"$tmp"

    {
        printf '// Generated by niri_monitor_manager.sh save - do not edit.\n'
        cat "$tmp"
    } >"$tmp.wrapped"
    mv -f "$tmp.wrapped" "$out"
    rm -f "$tmp"
    log "wrote $out"

    if niri_validate; then
        niri_reload
    else
        warn "niri validate failed after writing $out; not reloading"
    fi
}

case "${1:-list}" in
    list|info) cmd_list ;;
    apply) shift; cmd_apply "$@" ;;
    layout) shift; cmd_layout "${1:-}" ;;
    save) cmd_save ;;
    -h|--help|help) usage ;;
    *) usage; exit 1 ;;
esac
