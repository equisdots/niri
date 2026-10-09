#!/usr/bin/env bash
# ============================================================================
# niri_record.sh - screen recording for niri
# ============================================================================
# Self-contained recorder (no dependency on the Hyprland repo). Uses the SAME
# engine as Hyprland, gpu-screen-recorder, and writes the same cache contract
# the Quickshell bar reads, so the recording indicator lights up and the
# stop button works:
#
#   $QS_CACHE_RECORDING/rec_pid      PID of the running gpu-screen-recorder
#   $QS_CACHE_RECORDING/final_file   path of the output mp4
#
# Output: ${XDG_VIDEOS_DIR:-$HOME/Videos}/Recordings/Recording_<stamp>.mp4
#
# Usage:
#   niri_record.sh toggle            start (screen) if idle, stop if recording
#   niri_record.sh start [screen]    start full-screen recording
#   niri_record.sh region            pick a region with slurp, then record it
#   niri_record.sh stop              stop and finalise
#   niri_record.sh status            print "recording" or "idle"
#   niri_record.sh --help
#
# Environment:
#   NIRI_RECORD_AUDIO=off            disable audio capture (default: on)
#   NIRI_RECORD_FPS=60               frame rate
# ============================================================================

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
. "$SCRIPT_DIR/lib/common.sh"
# shellcheck source=caching.sh
. "$SCRIPT_DIR/caching.sh"
qs_ensure_cache "recording"

CACHE="${QS_CACHE_RECORDING:-$QS_CACHE_DIR/recording}"
RECORD_DIR="${XDG_VIDEOS_DIR:-$HOME/Videos}/Recordings"
PID_FILE="$CACHE/rec_pid"
FINAL_FILE="$CACHE/final_file"
GSR_LOG="$CACHE/gsr.log"
FPS="${NIRI_RECORD_FPS:-60}"
mkdir -p "$CACHE" "$RECORD_DIR" 2>/dev/null || true

is_recording() {
    [[ -s "$PID_FILE" ]] || return 1
    local pid
    pid="$(cat "$PID_FILE" 2>/dev/null || true)"
    [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null
}

stop_recording() {
    if ! is_recording; then
        rm -f "$PID_FILE" "$FINAL_FILE"
        notify "Recorder" "Not recording"
        return 0
    fi
    local pid final i
    pid="$(cat "$PID_FILE")"
    final="$(cat "$FINAL_FILE" 2>/dev/null || true)"

    # SIGINT lets gpu-screen-recorder finalise the mp4 cleanly.
    kill -SIGINT "$pid" 2>/dev/null || true
    for i in $(seq 1 300); do
        kill -0 "$pid" 2>/dev/null || break
        sleep 0.1
    done
    kill -9 "$pid" 2>/dev/null || true

    rm -f "$PID_FILE" "$FINAL_FILE"
    if [[ -s "$final" ]]; then
        notify_icon "Recorder" "Saved: $(basename "$final")" "$final"
    else
        notify "Recorder" "Recording stopped (no file; see $GSR_LOG)"
    fi
}

# grim-style geometry "X,Y WxH" -> gpu-screen-recorder "WxH+X+Y".
to_gsr_region() {
    local g="$1"
    if [[ "$g" =~ ^([0-9]+),([0-9]+)[[:space:]]+([0-9]+)x([0-9]+)$ ]]; then
        printf '%sx%s+%s+%s' "${BASH_REMATCH[3]}" "${BASH_REMATCH[4]}" "${BASH_REMATCH[1]}" "${BASH_REMATCH[2]}"
    else
        printf '%s' "$g"
    fi
}

start_recording() {
    local mode="${1:-screen}" region="${2:-}"
    have gpu-screen-recorder || die "gpu-screen-recorder is not installed"

    local -a args=(-c mp4 -f "$FPS")
    if [[ "$mode" == "region" ]]; then
        if [[ -z "$region" ]]; then
            have slurp || die "slurp is required for region recording"
            region="$(slurp)" || exit 0
        fi
        [[ -n "$region" ]] || exit 0
        args+=(-w region -region "$(to_gsr_region "$region")")
    else
        args+=(-w screen)
    fi

    if [[ "${NIRI_RECORD_AUDIO:-on}" != "off" ]]; then
        # gpu-screen-recorder understands the special "default_output" device.
        args+=(-a default_output)
    fi

    local ts out pid
    ts="$(date +'%Y-%m-%d-%H%M%S')"
    out="$RECORD_DIR/Recording_$ts.mp4"
    : >"$GSR_LOG"

    gpu-screen-recorder "${args[@]}" -o "$out" >"$GSR_LOG" 2>&1 &
    pid=$!
    sleep 1
    if ! kill -0 "$pid" 2>/dev/null; then
        notify "Recorder" "Failed to start; see $GSR_LOG"
        rm -f "$PID_FILE" "$FINAL_FILE"
        return 1
    fi

    echo "$pid" >"$PID_FILE"
    echo "$out" >"$FINAL_FILE"
    notify "Recorder" "Recording started ($mode)"
}

case "${1:-toggle}" in
    start)
        shift
        start_recording "${1:-screen}"
        ;;
    region)
        start_recording region
        ;;
    region-geom)
        start_recording region "${2:-}"
        ;;
    stop)
        stop_recording
        ;;
    toggle)
        if is_recording; then stop_recording; else start_recording screen; fi
        ;;
    status)
        if is_recording; then echo recording; else echo idle; fi
        ;;
    -h|--help)
        sed -n '2,28p' "$0" | sed 's/^# \{0,1\}//'
        ;;
    *)
        echo "usage: niri_record.sh start [screen] | region | stop | toggle | status" >&2
        exit 2
        ;;
esac
