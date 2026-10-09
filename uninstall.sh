#!/usr/bin/env bash
# ============================================================================
# equisdots niri - uninstaller
# ============================================================================
# Removes the niri compositor config, the user units and the session/portal
# files installed by install.sh. It does NOT uninstall packages and does NOT
# touch the shared equisdots data root (~/.config/hypr).
#
#   ./uninstall.sh        interactive confirmation
#   ./uninstall.sh -y     assume yes
#   ./uninstall.sh --help
# ============================================================================

set -euo pipefail

ASSUME_YES=0
while [[ $# -gt 0 ]]; do
    case "$1" in
        -y|--yes) ASSUME_YES=1 ;;
        -h|--help) sed -n '2,12p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        *) echo "unknown option: $1" >&2; exit 1 ;;
    esac
    shift
done

GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
log()  { printf '%b[ok]%b %s\n' "$GREEN" "$NC" "$*"; }
warn() { printf '%b[!]%b %s\n' "$YELLOW" "$NC" "$*" >&2; }
have() { command -v "$1" >/dev/null 2>&1; }

echo "This will remove the equisdots niri configuration:"
echo "  - ~/.config/niri (config, generated fragments, niri scripts)"
echo "  - ~/.config/systemd/user/{swayidle,quickshell,xwww,focus-daemon}.service"
echo "  - ~/.config/systemd/user/niri.service.wants symlinks to those units"
echo "  - /usr/local/share/wayland-sessions/niri.desktop"
echo "  - /usr/local/share/xdg-desktop-portal/niri-portals.conf"
echo
echo "It will NOT uninstall packages or touch ~/.config/hypr."
echo

if [[ "$ASSUME_YES" != "1" ]]; then
    printf 'Continue? [y/N] '
    read -r response
    [[ "$response" =~ ^[Yy]$ ]] || { echo "Cancelled."; exit 0; }
fi

NIRI_DIR="$HOME/.config/niri"
UNIT_DIR="$HOME/.config/systemd/user"
WANTS_DIR="$UNIT_DIR/niri.service.wants"
UNITS=(swayidle.service quickshell.service xwww.service focus-daemon.service)

# Restore the most recent config backup if the user wants it.
LATEST_BAK="$(ls -1t "$NIRI_DIR"/config.kdl.bak.* 2>/dev/null | head -n1 || true)"
if [[ -n "$LATEST_BAK" ]]; then
    info_msg="Found backup: $LATEST_BAK"
    echo "$info_msg"
    if [[ "$ASSUME_YES" == "1" ]]; then
        restore="y"
    else
        printf 'Restore it to ~/.config/niri/config.kdl before removal? [Y/n] '
        read -r restore
    fi
    if [[ ! "$restore" =~ ^[Nn]$ ]]; then
        cp -f "$LATEST_BAK" "$NIRI_DIR/config.kdl"
        log "restored config.kdl from backup (it will be removed with the directory)"
    fi
fi

# User units and wants symlinks.
for u in "${UNITS[@]}"; do
    rm -f "$WANTS_DIR/$u"
    rm -f "$UNIT_DIR/$u"
done
if have systemctl; then
    systemctl --user daemon-reload >/dev/null 2>&1 || true
fi
log "removed user units"

# Config tree (user data first; generated state goes with it).
rm -rf "$NIRI_DIR"
log "removed $NIRI_DIR"

# System session/portal files (best effort).
if [[ "$(id -u)" == "0" ]]; then
    rm -f /usr/local/share/wayland-sessions/niri.desktop
    rm -f /usr/local/share/xdg-desktop-portal/niri-portals.conf
    log "removed session/portal files"
elif have sudo; then
    if sudo rm -f /usr/local/share/wayland-sessions/niri.desktop \
        /usr/local/share/xdg-desktop-portal/niri-portals.conf; then
        log "removed session/portal files"
    else
        warn "could not remove session/portal files (sudo failed)"
    fi
else
    warn "no root/sudo: session/portal files were not removed"
fi

echo
log "uninstall complete."
echo "To reinstall: ./install.sh"
