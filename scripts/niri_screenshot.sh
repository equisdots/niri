#!/usr/bin/env bash
# ============================================================================
# niri_screenshot.sh - equisdots screenshot & recording overlay for niri
# ============================================================================
# Self-contained port of the equisdots screenshot flow (hyprland/scripts/
# screenshot.sh) for niri, so the SAME Quickshell overlay opens under niri:
# it lets you pick a region and choose screenshot vs. video and microphone
# on/off. No dependency on the Hyprland repo.
#
# Modes:
#   niri_screenshot.sh                          open the equisdots overlay
#   niri_screenshot.sh --edit                    overlay, start in edit mode
#   niri_screenshot.sh --full                    focused output (native action)
#   niri_screenshot.sh --window                  focused window (native action)
#   niri_screenshot.sh --geometry "X,Y WxH"      capture that region (grim)
#   niri_screenshot.sh --geometry "X,Y WxH" --record [audio args]
#                                                record that region (GSR)
#   niri_screenshot.sh --full --record           record the whole screen
#   niri_screenshot.sh --scan-qr --geometry G    scan a QR in that region
#   niri_screenshot.sh --help
#
# The overlay calls back into this script (via EQUISDOTS_SCREENSHOT_SCRIPT)
# with --geometry/--record. Recording is delegated to scripts/niri_record.sh
# (gpu-screen-recorder, the same engine as Hyprland).
# ============================================================================

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
. "$SCRIPT_DIR/lib/common.sh"
# shellcheck source=caching.sh
. "$SCRIPT_DIR/caching.sh"
qs_ensure_cache "screenshot"
qs_ensure_cache "recording"

have notify-send || { echo "[niri] error: notify-send is required" >&2; exit 1; }

EDIT=0; FULL=0; WINDOW=0; RECORD=0; QR=0; GEOMETRY=""
DESK_VOL="1.0"; DESK_MUTE="false"; MIC_VOL="1.0"; MIC_MUTE="false"; MIC_DEVICE=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        --edit)      EDIT=1 ;;
        --full)      FULL=1 ;;
        --window)    WINDOW=1 ;;
        --record)    RECORD=1 ;;
        --scan-qr)   QR=1 ;;
        --geometry)  GEOMETRY="${2:-}"; shift ;;
        --desk-vol)  DESK_VOL="${2:-1.0}"; shift ;;
        --desk-mute) DESK_MUTE="${2:-false}"; shift ;;
        --mic-vol)   MIC_VOL="${2:-1.0}"; shift ;;
        --mic-mute)  MIC_MUTE="${2:-false}"; shift ;;
        --mic-dev)   MIC_DEVICE="${2:-}"; shift ;;
        -h|--help)   sed -n '2,24p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        *)           ;;
    esac
    shift
done

SAVE_DIR="${XDG_PICTURES_DIR:-$HOME/Pictures}/Screenshots"
ensure_dir "$SAVE_DIR"

# ---------------------------------------------------------
# QR scanning (grim + zbarimg + python)
# ---------------------------------------------------------
if [[ "$QR" == 1 ]]; then
    RES_FILE="$QS_RUN_SCREENSHOT/qr_result"
    DEBUG_LOG="$QS_LOG_DIR/qr_debug.log"
    rm -f "$RES_FILE" "$DEBUG_LOG"
    echo "=== QR SCAN INITIATED $(date) ===" > "$DEBUG_LOG"
    if ! have zbarimg; then
        echo "0,0,0,0|||ERROR: zbarimg is not installed." > "$RES_FILE"
        exit 1
    fi
    TMP_IMG="$QS_RUN_SCREENSHOT/qr_temp_$$.png"
    grim -g "$GEOMETRY" "$TMP_IMG"
    XML_OUT="$(zbarimg --xml -q "$TMP_IMG" 2>>"$DEBUG_LOG")"
    if [[ -n "$XML_OUT" ]]; then
        XML_OUT="$XML_OUT" DEBUG_LOG="$DEBUG_LOG" python3 - > "$RES_FILE" <<'PY'
import os, sys, re
import xml.etree.ElementTree as ET
raw = os.environ.get("XML_OUT", "")
if not raw.strip():
    print("0,0,0,0|||ERROR: empty zbarimg output."); sys.exit(0)
try:
    clean = re.sub(r'\sxmlns="[^"]+"', '', raw)
    clean = re.sub(r"\sxmlns='[^']+'", '', clean)
    tree = ET.fromstring(clean)
    found = False
    for el in tree.iter():
        if el.tag.endswith('symbol'):
            found = True
            data = ''
            xs, ys = [], []
            for ch in el:
                if ch.tag.endswith('data'): data = ch.text or ''
                elif ch.tag.endswith('polygon'):
                    for pair in (ch.get('points','') or '').replace('+','').split(' '):
                        if ',' in pair:
                            try:
                                x, y = pair.split(','); xs.append(int(x)); ys.append(int(y))
                            except ValueError: pass
            if not xs: xs, ys = [0], [0]
            w, h = max(xs)-min(xs), max(ys)-min(ys)
            enc = data.replace('\\','\\\\').replace('\n','\\n').replace('\r','')
            print(f"{min(xs)},{min(ys)},{w},{h}|||{enc}")
    if not found: print("0,0,0,0|||NOT_FOUND")
except Exception as e:
    print(f"0,0,0,0|||ERROR: {e}")
PY
    else
        echo "0,0,0,0|||NOT_FOUND" > "$RES_FILE"
    fi
    rm -f "$TMP_IMG"
    exit 0
fi

# ---------------------------------------------------------
# Recording smart toggle: a second invocation stops it
# ---------------------------------------------------------
if [[ -s "$QS_CACHE_RECORDING/rec_pid" ]]; then
    exec bash "$SCRIPT_DIR/niri_record.sh" stop
fi

# ---------------------------------------------------------
# Phase 1: direct capture (overlay passes --geometry / --full)
# ---------------------------------------------------------
if [[ "$WINDOW" == 1 ]]; then
    niri msg action screenshot-window
    notify "Screenshot" "Saved to $SAVE_DIR (and clipboard)"
    exit 0
fi

if [[ "$FULL" == 1 || -n "$GEOMETRY" ]]; then
    if [[ "$RECORD" == 1 ]]; then
        if [[ -n "$GEOMETRY" ]]; then
            exec bash "$SCRIPT_DIR/niri_record.sh" region-geom "$GEOMETRY"
        else
            exec bash "$SCRIPT_DIR/niri_record.sh" start screen
        fi
    fi

    if [[ "$FULL" == 1 && -z "$GEOMETRY" ]]; then
        # Whole-output still: use the niri-native action (clipboard + disk).
        niri msg action screenshot-screen
        notify "Screenshot" "Saved to $SAVE_DIR (and clipboard)"
        exit 0
    fi

    require_cmd grim
    STAMP="$(date +'%Y-%m-%d-%H%M%S')"
    FILE="$SAVE_DIR/Screenshot_${STAMP}.png"
    if [[ "$EDIT" == 1 ]]; then
        require_cmd satty
        grim -g "$GEOMETRY" - | GSK_RENDERER=gl satty \
            --filename - --output-filename "$FILE" \
            --init-tool brush --copy-command wl-copy
    else
        grim -g "$GEOMETRY" - | tee "$FILE" | wl-copy
    fi
    [[ -s "$FILE" ]] && notify_icon "Screenshot" "Saved: $(basename "$FILE")" "$FILE"
    exit 0
fi

# ---------------------------------------------------------
# Phase 2: open the equisdots overlay (region + still/video + mic)
# ---------------------------------------------------------
QML="$HOME/.config/hypr/scripts/quickshell/ScreenshotOverlay.qml"
[[ -f "$QML" ]] || die "ScreenshotOverlay.qml not found; run 'dotsniri install' first"

# Toggle: a second press closes a running overlay.
if pgrep -f "quickshell -p $QML" >/dev/null 2>&1; then
    pkill -f "quickshell -p $QML"
    exit 0
fi

QS_BIN="quickshell"; have quickshell || QS_BIN="qs"
have "$QS_BIN" || die "quickshell is required for the screenshot overlay"

# The overlay calls back into THIS script (not the Hyprland one).
export EQUISDOTS_SCREENSHOT_SCRIPT="$SCRIPT_DIR/niri_screenshot.sh"

if have pactl; then
    QS_MIC_LIST="$(pactl list sources short 2>/dev/null | awk '{print $2}' | grep -v '\.monitor$' | while IFS= read -r name; do
        desc=$(pactl list sources 2>/dev/null | awk -v n="$name" '/Name:/{f=($2==n)} f&&/Description:/{sub(/^[[:space:]]*Description:[[:space:]]*/,"");print;exit}')
        echo "$name|${desc:-$name}"
    done)"
else
    QS_MIC_LIST=""
fi
export QS_MIC_LIST

PREFS="$QS_STATE_SCREENSHOT/audio_prefs"
if [[ -f "$PREFS" ]]; then
    IFS=',' read -r QS_DESK_VOL QS_DESK_MUTE QS_MIC_VOL QS_MIC_MUTE QS_MIC_DEV < "$PREFS"
    export QS_DESK_VOL QS_DESK_MUTE QS_MIC_VOL QS_MIC_MUTE QS_MIC_DEV
fi

[[ "$EDIT" == 1 ]] && export QS_SCREENSHOT_EDIT="true" || export QS_SCREENSHOT_EDIT="false"
CACHE_FILE="$QS_CACHE_SCREENSHOT/geometry"
MODE_CACHE_FILE="$QS_CACHE_SCREENSHOT/video_mode"
[[ -f "$CACHE_FILE" ]] && export QS_CACHED_GEOM="$(cat "$CACHE_FILE")" || export QS_CACHED_GEOM=""
[[ -f "$MODE_CACHE_FILE" ]] && export QS_CACHED_MODE="$(cat "$MODE_CACHE_FILE")" || export QS_CACHED_MODE="false"

exec "$QS_BIN" -p "$QML"
