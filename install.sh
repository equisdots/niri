#!/usr/bin/env bash
# ============================================================================
# equisdots niri - installer
# ============================================================================
# Distro-agnostic installer for the niri compositor config and session.
#
#   ./install.sh                 full install (packages + config + session files)
#   ./install.sh --config-only   deploy ~/.config/niri and the user units only
#   ./install.sh -y              assume "yes" for prompts
#   ./install.sh --help
#
# It is safe and idempotent: existing config is backed up once, files are
# overwritten in place, and no destructive action runs without confirmation.
# The shared equisdots data root (~/.config/hypr) is NOT touched.
#
# The interactive `dots`/meta installer is only a soft hook: it is called when
# present, but the niri install works without it.
# ============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

CONFIG_ONLY=0
ASSUME_YES=0
WITH_META=1

while [[ $# -gt 0 ]]; do
    case "$1" in
        --config-only) CONFIG_ONLY=1 ;;
        -y|--yes)      ASSUME_YES=1 ;;
        --no-meta)     WITH_META=0 ;;
        -h|--help)
            sed -n '2,20p' "$0" | sed 's/^# \{0,1\}//'
            exit 0
            ;;
        *) echo "unknown option: $1" >&2; exit 1 ;;
    esac
    shift
done

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'
log()  { printf '%b[ok]%b %s\n' "$GREEN" "$NC" "$*"; }
warn() { printf '%b[!]%b %s\n' "$YELLOW" "$NC" "$*" >&2; }
err()  { printf '%b[x]%b %s\n' "$RED" "$NC" "$*" >&2; }
info() { printf '%b[i]%b %s\n' "$BLUE" "$NC" "$*"; }

read_answer() {
    local var="$1" def="${2:-y}"
    if [[ "$ASSUME_YES" == "1" ]]; then
        printf -v "$var" '%s' "$def"
    else
        read -r "$var"
    fi
}

have() { command -v "$1" >/dev/null 2>&1; }

# --- Distro detection -------------------------------------------------------
DISTRO="unknown"; DISTRO_LIKE=""
detect_distro() {
    if [[ -f /etc/os-release ]]; then
        # shellcheck disable=SC1091
        . /etc/os-release
        DISTRO="${ID:-unknown}"
        DISTRO_LIKE="${ID_LIKE:-}"
    fi
    case "$DISTRO" in
        arch|manjaro|endeavouros) PKG="pacman" ;;
        fedora|rhel|centos)       PKG="dnf" ;;
        debian|ubuntu|linuxmint|pop) PKG="apt" ;;
        *)
            case " $DISTRO_LIKE " in
                *" arch "*) PKG="pacman" ;;
                *" fedora "*|*" rhel "*) PKG="dnf" ;;
                *" debian "*|*" ubuntu "*) PKG="apt" ;;
                *) PKG="unknown" ;;
            esac
            ;;
    esac
    info "detected distro: $DISTRO (package manager: $PKG)"
}

# --- Package installation ---------------------------------------------------
CORE_ARCH=(niri xwayland-satellite xdg-desktop-portal xdg-desktop-portal-gnome
    xdg-desktop-portal-gtk swayidle mako jq grim slurp wl-clipboard pipewire wireplumber)
OPT_ARCH=(satty)

CORE_FEDORA=(niri xwayland-satellite xdg-desktop-portal xdg-desktop-portal-gnome
    xdg-desktop-portal-gtk swayidle mako jq grim slurp wl-clipboard pipewire wireplumber)
OPT_FEDORA=(satty)

CORE_DEBIAN=(niri xwayland-satellite xdg-desktop-portal xdg-desktop-portal-gnome
    xdg-desktop-portal-gtk swayidle mako-notifier jq grim slurp wl-clipboard pipewire wireplumber)
OPT_DEBIAN=(satty)

sudo_cmd() {
    if [[ "$(id -u)" == "0" ]]; then
        "$@"
    elif have sudo; then
        sudo "$@"
    else
        err "root or sudo is required for: $*"; return 1
    fi
}

install_packages() {
    [[ "$PKG" == "unknown" ]] && { warn "unknown distro; install packages manually"; return 0; }

    info "installing packages with $PKG (niri, portals, swayidle, notification daemon, capture tools)"
    case "$PKG" in
        pacman)
            sudo_cmd pacman -S --needed --noconfirm "${CORE_ARCH[@]}" \
                || warn "core packages failed; install niri manually: sudo pacman -S niri xwayland-satellite xdg-desktop-portal-gnome xdg-desktop-portal-gtk"
            sudo_cmd pacman -S --needed --noconfirm "${OPT_ARCH[@]}" 2>/dev/null \
                || warn "optional packages skipped: ${OPT_ARCH[*]}"
            ;;
        dnf)
            sudo_cmd dnf install -y "${CORE_FEDORA[@]}" \
                || warn "some packages failed; niri may need a COPR (see https://yalter.github.io/niri)"
            sudo_cmd dnf install -y "${OPT_FEDORA[@]}" 2>/dev/null \
                || warn "optional packages skipped: ${OPT_FEDORA[*]}"
            ;;
        apt)
            sudo_cmd apt-get update
            sudo_cmd apt-get install -y "${CORE_DEBIAN[@]}" || warn "some packages failed to install"
            sudo_cmd apt-get install -y "${OPT_DEBIAN[@]}" 2>/dev/null \
                || warn "optional packages skipped: ${OPT_DEBIAN[*]}"
            ;;
    esac
}

# --- Config deployment ------------------------------------------------------
deploy_config() {
    local dest="$HOME/.config/niri"
    mkdir -p "$dest"

    # Back up an existing entry config once (never delete user data).
    if [[ -f "$dest/config.kdl" ]]; then
        local bak="$dest/config.kdl.bak.$(date +%Y%m%d_%H%M%S)"
        cp -f "$dest/config.kdl" "$bak"
        info "backed up existing config.kdl to $bak"
    fi

    # Copy the tracked tree (modules/generated/session docs) in place.
    cp -R "$SCRIPT_DIR/config/niri/." "$dest/"
    mkdir -p "$dest/scripts"
    cp -R "$SCRIPT_DIR/scripts/." "$dest/scripts/"
    chmod +x "$dest/scripts/"*.sh 2>/dev/null || true
    chmod +x "$dest/scripts/lib/common.sh" 2>/dev/null || true
    log "deployed niri config to $dest"
}

install_units() {
    local dest="$HOME/.config/systemd/user"
    mkdir -p "$dest"
    cp -f "$SCRIPT_DIR/systemd/"*.service "$dest/"
    if have systemctl; then
        systemctl --user daemon-reload >/dev/null 2>&1 || true
    fi
    log "installed systemd user units to $dest"
}

# --- Session and portal files ----------------------------------------------
install_session_files() {
    if [[ "$CONFIG_ONLY" == "1" ]]; then
        info "config-only: skipping system session/portal files"
        return 0
    fi

    if have sudo || [[ "$(id -u)" == "0" ]]; then
        if sudo_cmd install -Dm644 "$SCRIPT_DIR/session/niri.desktop" \
                /usr/local/share/wayland-sessions/niri.desktop \
            && sudo_cmd install -Dm644 "$SCRIPT_DIR/portals/niri-portals.conf" \
                /usr/local/share/xdg-desktop-portal/niri-portals.conf; then
            log "installed niri.desktop and niri-portals.conf under /usr/local/share"
        else
            warn "could not install session/portal files (sudo failed)"
        fi
    else
        warn "no root/sudo: skipping system session/portal files"
        warn "copy manually: session/niri.desktop -> /usr/share/wayland-sessions/"
        warn "               portals/niri-portals.conf -> /usr/share/xdg-desktop-portal/"
    fi
}

# --- Meta installer hook ----------------------------------------------------
maybe_call_meta() {
    [[ "$WITH_META" == "1" ]] || return 0
    [[ "${EQUISDOTS_NIRI_INSTALL_DONE:-0}" == "1" ]] && return 0
    [[ "$CONFIG_ONLY" == "1" ]] && return 0

    local meta="${NIRI_META_INSTALLER:-}"
    if [[ -z "$meta" ]]; then
        local candidates=(
            "$SCRIPT_DIR/../niri-meta/bin/dotsniri"
            "$SCRIPT_DIR/../equisdots-niri/niri-meta/bin/dotsniri"
            "$HOME/.local/share/equisdots-niri/niri-meta/bin/dotsniri"
        )
        local c
        for c in "${candidates[@]}"; do
            [[ -x "$c" || -f "$c" ]] && { meta="$c"; break; }
        done
    fi

    if [[ -n "$meta" && -f "$meta" ]]; then
        info "meta installer found: $meta (delegating)"
        local args=(install)
        [[ "$ASSUME_YES" == "1" ]] && args+=("-y")
        EQUISDOTS_NIRI_INSTALL_DONE=1 bash "$meta" "${args[@]}" \
            || warn "meta installer reported an error; continue with the niri install"
    else
        info "no meta installer found; install the shell later (dots install)"
    fi
}

# --- Main -------------------------------------------------------------------
main() {
    echo "equisdots niri installer"
    detect_distro

    if [[ "$CONFIG_ONLY" == "0" ]]; then
        local go="y"
        printf 'Install system packages (niri, portals, swayidle, notification daemon)? [Y/n] '
        if [[ "$ASSUME_YES" != "1" ]]; then
            read -r go || go=""
            go="${go:-y}"
        fi
        if [[ ! "$go" =~ ^[Nn]$ ]]; then
            install_packages
        else
            info "skipping package installation"
        fi
    fi

    deploy_config
    install_units
    install_session_files
    maybe_call_meta

    echo
    log "done."
    info "Validate the config:  niri validate -c ~/.config/niri/config.kdl"
    info "Start the session:    niri-session   (or pick 'Niri' in the display manager)"
    info "Attach user units:    systemctl --user add-wants niri.service swayidle.service"
}

main "$@"
