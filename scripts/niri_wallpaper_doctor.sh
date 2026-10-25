#!/usr/bin/env bash
# ============================================================================
# niri_wallpaper_doctor.sh - read-only wallpaper/picker diagnostics
# ============================================================================
# Run this on the affected machine and share the output if the picker is empty.
# ============================================================================
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
. "$SCRIPT_DIR/lib/common.sh"
# shellcheck source=caching.sh
. "$SCRIPT_DIR/caching.sh"
qs_ensure_cache "wallpaper_picker"

settings="$HOME/.config/hypr/settings.json"
dir=""
if have jq && [[ -f "$settings" ]]; then
    dir="$(jq -r '.wallpaperDir // empty' "$settings" 2>/dev/null || true)"
fi
dir="${dir:-$HOME/.config/hypr/wallpapers}"
dir="${dir/#\~/$HOME}"

echo "settings:        $settings"
echo "wallpaperDir:    $dir"
if [[ -d "$dir" ]]; then
    echo "dir exists:      yes"
    echo "top entries:     $(find "$dir" -mindepth 1 -maxdepth 1 | wc -l)"
    echo "scene dirs:      $(find "$dir" -type f -name scene.js 2>/dev/null | wc -l)"
    echo "media files:     $(find "$dir" -type f \( -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.png' -o -iname '*.webp' -o -iname '*.gif' -o -iname '*.mp4' -o -iname '*.mkv' -o -iname '*.mov' -o -iname '*.webm' \) 2>/dev/null | wc -l)"
else
    echo "dir exists:      NO"
fi
echo "WALLPAPER_DIR:   ${WALLPAPER_DIR:-<unset>}"
echo "davincix:        $(command -v davincix 2>/dev/null || echo '<missing>')"
echo "kernel:          ${DAVINCIX_KERNEL_DIR:-$HOME/.local/share/equisdots/davincix}/davincix.sh"
[[ -x "${DAVINCIX_KERNEL_DIR:-$HOME/.local/share/equisdots/davincix}/davincix.sh" ]] && echo "kernel:          executable" || echo "kernel:          missing/not executable"
echo "thumbs:          $(find "$QS_CACHE_WALLPAPER_PICKER/thumbs" -type f 2>/dev/null | wc -l)"
echo "magick:          $(command -v magick 2>/dev/null || echo '<missing>')"
echo "ffmpeg:          $(command -v ffmpeg 2>/dev/null || echo '<missing>')"
echo "xwww-daemon:     $(command -v xwww-daemon 2>/dev/null || echo '<missing>')"
echo "quickshell:      $(command -v quickshell 2>/dev/null || command -v qs 2>/dev/null || echo '<missing>')"
