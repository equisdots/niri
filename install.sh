#!/usr/bin/env bash
# ============================================================================
# equisdots niri - installer
# ============================================================================
# Distro-agnostic installer for the niri compositor config and session.
#
#   ./install.sh                 full install (packages + config + session files)
#   ./install.sh --config-only   deploy ~/.config/niri and the user units only
#   ./install.sh -y              assume "yes" for prompts
#   ./install.sh --no-apps       skip kitty/starship/nvim/font app configs
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
USER_CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}"

CONFIG_ONLY=0
ASSUME_YES=0
WITH_META=1
APPS=1

while [[ $# -gt 0 ]]; do
    case "$1" in
        --config-only) CONFIG_ONLY=1 ;;
        -y|--yes)      ASSUME_YES=1 ;;
        --no-meta)     WITH_META=0 ;;
        --no-apps)     APPS=0 ;;
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
CORE_ARCH=(niri xwayland-satellite quickshell xdg-desktop-portal xdg-desktop-portal-gnome
    xdg-desktop-portal-gtk swayidle jq grim slurp wl-clipboard cliphist libnotify
    pipewire wireplumber
    kitty rofi playerctl brightnessctl pamixer ddcutil nautilus pavucontrol
    network-manager-applet blueman gnome-keyring polkit-gnome qt6ct
    noto-fonts noto-fonts-emoji adw-gtk-theme papirus-icon-theme
    fd ripgrep python imagemagick ffmpeg cava power-profiles-daemon)
OPT_ARCH=(satty gpu-screen-recorder zbar envycontrol bibata-cursor-theme)

CORE_FEDORA=(niri xwayland-satellite xdg-desktop-portal xdg-desktop-portal-gnome
    xdg-desktop-portal-gtk swayidle jq grim slurp wl-clipboard cliphist libnotify
    pipewire wireplumber
    kitty rofi playerctl brightnessctl pamixer ddcutil nautilus pavucontrol
    network-manager-applet blueman gnome-keyring polkit-gnome qt6ct
    google-noto-sans-fonts google-noto-emoji-fonts adw-gtk3-theme papirus-icon-theme
    fd-find ripgrep python3 ImageMagick ffmpeg-free cava power-profiles-daemon)
OPT_FEDORA=(satty gpu-screen-recorder zbar envycontrol bibata-cursor-theme)

CORE_DEBIAN=(niri xwayland-satellite xdg-desktop-portal xdg-desktop-portal-gnome
    xdg-desktop-portal-gtk swayidle jq grim slurp wl-clipboard cliphist libnotify-bin
    pipewire wireplumber
    kitty rofi playerctl brightnessctl pamixer ddcutil nautilus pavucontrol
    network-manager-gnome blueman gnome-keyring policykit-1-gnome qt6ct
    fonts-noto-core fonts-noto-color-emoji papirus-icon-theme
    fd-find ripgrep python3 imagemagick ffmpeg cava power-profiles-daemon)
OPT_DEBIAN=(satty gpu-screen-recorder-cli zbar-tools envycontrol bibata-cursor-theme adw-gtk3)
# NOTE: `quickshell` is the equisdots shell/overlay. `grim`, `slurp` and
# `wl-clipboard` provide the screenshot overlay and direct capture; `satty`
# annotates, `zbar` (zbarimg on Arch/Fedora, zbar-tools on Debian) scans QR
# codes, and `gpu-screen-recorder` is the SAME screen recorder Hyprland uses
# (driven by niri/scripts/niri_record.sh; compositor-agnostic, wlr-screencopy).
#
# The rest of CORE is the user-facing tool set the keybinds and bar expect:
# kitty (terminal), rofi (emoji picker), playerctl (media keys), brightnessctl,
# pamixer, ddcutil, nautilus, pavucontrol, nm-applet, blueman, gnome-keyring,
# the polkit agent, qt6ct, Noto fonts, adw-gtk3 and Papirus icons, fd/ripgrep,
# python, ImageMagick, ffmpeg, cava and power-profiles-daemon.
# Distro names differ: adw-gtk3 ships as `adw-gtk-theme` on Arch and
# `adw-gtk3-theme` on Fedora; fd is `fd-find` on Fedora/Debian; the polkit
# agent is `policykit-1-gnome` on Debian; gpu-screen-recorder is provided by
# `gpu-screen-recorder-cli` on Debian.
#
# OPTIONAL packages may live in the AUR / a COPR / a PPA or simply not be
# packaged for a distro. They are installed one by one, so a missing name only
# warns and never blocks the rest. No separate notification daemon
# (mako/dunst) is installed on purpose: the Quickshell shell registers
# org.freedesktop.Notifications itself.

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

    info "installing packages with $PKG (niri, portals, swayidle, capture tools)"
    case "$PKG" in
        pacman)
            sudo_cmd pacman -S --needed --noconfirm "${CORE_ARCH[@]}" \
                || warn "core packages failed; install niri manually: sudo pacman -S niri xwayland-satellite xdg-desktop-portal-gnome xdg-desktop-portal-gtk"
            local p
            for p in "${OPT_ARCH[@]}"; do
                sudo_cmd pacman -S --needed --noconfirm "$p" 2>/dev/null \
                    || warn "optional package skipped: $p"
            done
            ;;
        dnf)
            sudo_cmd dnf install -y "${CORE_FEDORA[@]}" \
                || warn "some packages failed; niri may need a COPR (see https://yalter.github.io/niri)"
            local p
            for p in "${OPT_FEDORA[@]}"; do
                sudo_cmd dnf install -y "$p" 2>/dev/null \
                    || warn "optional package skipped: $p"
            done
            ;;
        apt)
            sudo_cmd apt-get update
            sudo_cmd apt-get install -y "${CORE_DEBIAN[@]}" || warn "some packages failed to install"
            local p
            for p in "${OPT_DEBIAN[@]}"; do
                sudo_cmd apt-get install -y "$p" 2>/dev/null \
                    || warn "optional package skipped: $p"
            done
            ;;
    esac
}

# --- Config deployment ------------------------------------------------------
# seed_generated_env DEST: write generated/env.kdl with literal paths.
# `environment {}` is a single-occurrence section and niri cannot expand $HOME,
# so the whole section is generated here from defaults/environment.kdl. Existing
# files are never overwritten (edit the generated file directly afterwards).
seed_generated_env() {
    local dest="$1"
    local out="$dest/generated/env.kdl"
    local template="$SCRIPT_DIR/config/niri/defaults/environment.kdl"

    [[ -f "$out" ]] && return 0
    [[ -f "$template" ]] || { warn "missing env seed template: $template"; return 1; }

    # ~/.local/bin first, then the caller's PATH without duplicates.
    local local_bin="$HOME/.local/bin"
    local session_path="$local_bin"
    local -a path_parts=()
    local p
    IFS=: read -r -a path_parts <<< "${PATH:-/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin}"
    for p in "${path_parts[@]}"; do
        [[ -n "$p" ]] || continue
        [[ ":$session_path:" == *":$p:"* ]] && continue
        session_path="$session_path:$p"
    done

    local wallpaper_dir="$HOME/.config/hypr/wallpapers"
    local scripts_dir="$HOME/.config/hypr/scripts"
    local pictures_dir="${XDG_PICTURES_DIR:-$HOME/Pictures}"
    local videos_dir="${XDG_VIDEOS_DIR:-$HOME/Videos}"

    # appScale parity with env.lua: only emit the derived block when != 1.0.
    local app_scale="1.0"
    if have jq && [[ -f "$HOME/.config/hypr/settings.json" ]]; then
        app_scale="$(jq -r '.appScale // 1.0' "$HOME/.config/hypr/settings.json" 2>/dev/null || printf '1.0')"
    fi
    [[ "$app_scale" =~ ^[0-9]+([.][0-9]+)?$ ]] || app_scale="1.0"

    local app_scale_env=""
    if awk -v s="$app_scale" 'BEGIN { exit !(s + 0 != 1.0) }'; then
        local gdk_int gdk_dpi electron_factor xcursor_size
        read -r gdk_int gdk_dpi electron_factor xcursor_size < <(
            awk -v s="$app_scale" 'BEGIN {
                gi = int(s + 0.0001); if (gi < 1) gi = 1;
                printf "%d %.4f %s %d\n", gi, s / gi, s, int(24 * s)
            }'
        )
        app_scale_env="$(printf '    GDK_SCALE "%s"\n    GDK_DPI_SCALE "%s"\n    ELECTRON_FORCE_DEVICE_SCALE_FACTOR "%s"\n    XCURSOR_SIZE "%s"' \
            "$gdk_int" "$gdk_dpi" "$electron_factor" "$xcursor_size")"
    fi

    local line
    while IFS= read -r line || [[ -n "$line" ]]; do
        line="${line//@SESSION_PATH@/$session_path}"
        line="${line//@WALLPAPER_DIR@/$wallpaper_dir}"
        line="${line//@SCRIPT_DIR@/$scripts_dir}"
        line="${line//@XDG_PICTURES_DIR@/$pictures_dir}"
        line="${line//@XDG_VIDEOS_DIR@/$videos_dir}"
        line="${line//@APP_SCALE_ENV@/$app_scale_env}"
        printf '%s\n' "$line"
    done < "$template" > "$out"

    chmod 644 "$out" 2>/dev/null || true
    log "seeded generated/env.kdl (literal PATH/XDG paths, appScale $app_scale)"
}

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

    # Seed the single-occurrence generated sections (input/animations/blur) so
    # the session starts with the translated defaults. The writers own them
    # from then on; existing user files are never overwritten.
    mkdir -p "$dest/generated"
    local f
    for f in input:user-input animations:user-animations blur:blur; do
        src="${f%%:*}"; dst="${f##*:}"
        if [[ ! -f "$dest/generated/$dst.kdl" && -f "$SCRIPT_DIR/config/niri/defaults/$src.kdl" ]]; then
            cp "$SCRIPT_DIR/config/niri/defaults/$src.kdl" "$dest/generated/$dst.kdl"
        fi
    done

    # environment {} is the fourth single-occurrence section and contains
    # literal paths, so it is generated rather than copied verbatim.
    seed_generated_env "$dest"

    mkdir -p "$dest/scripts"
    cp -R "$SCRIPT_DIR/scripts/." "$dest/scripts/"
    chmod +x "$dest/scripts/"*.sh 2>/dev/null || true
    chmod +x "$dest/scripts/lib/common.sh" 2>/dev/null || true
    deploy_app_configs
    log "deployed niri config to $dest"
}

# Rofi/cava configs shipped by this repo, so a standalone niri install does not
# depend on the equisdots/hyprland repo. Existing user configs are backed up.
backup_user_config() {
    local dest="$1"
    [[ -d "$dest" ]] || return 0
    local bak="$dest.bak.$(date +%Y%m%d_%H%M%S)"
    cp -a "$dest" "$bak"
    info "backed up $dest -> $bak"
}

deploy_app_configs() {
    local apps="$SCRIPT_DIR/config/apps"
    deploy_one_app_config "$apps/rofi" "$USER_CONFIG_DIR/rofi"
    deploy_one_app_config "$apps/cava" "$USER_CONFIG_DIR/cava"
}

deploy_one_app_config() {
    local src="$1" dest="$2"
    [[ -d "$src" ]] || return 0
    if [[ -d "$dest" ]] && diff -qr "$src" "$dest" >/dev/null 2>&1; then
        return 0
    fi
    backup_user_config "$dest"
    mkdir -p "$dest"
    cp -R "$src/." "$dest/"
}

install_app_configs() {
    [[ "$APPS" == "1" ]] || { info "skipping app configs (--no-apps)"; return 0; }
    local script="$SCRIPT_DIR/scripts/install-app-configs.sh"
    if [[ ! -f "$script" ]]; then
        warn "scripts/install-app-configs.sh not found; skipping kitty/starship/nvim/font"
        return 0
    fi
    local args=()
    [[ "$ASSUME_YES" == "1" ]] && args+=("-y")
    info "installing user app configs (kitty, starship, nvim, Hack Nerd Font)"
    bash "$script" "${args[@]}" || warn "app config installer finished with warnings"
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
# The Quickshell lock screen authenticates through the "quickshell" PAM service.
# Without it PAM falls back to pam_deny and no password is accepted.
install_pam_lock() {
    local src="$SCRIPT_DIR/config/pam.d/quickshell"
    [[ -f "$src" ]] || return 0
    if [[ -f /etc/pam.d/quickshell ]] && grep -q 'system-auth' /etc/pam.d/quickshell 2>/dev/null; then
        info "PAM service 'quickshell' already configured"
        return 0
    fi
    if [[ -f /etc/pam.d/quickshell ]]; then
        sudo_cmd cp -f /etc/pam.d/quickshell /etc/pam.d/quickshell.backup || true
    fi
    if sudo_cmd install -Dm644 "$src" /etc/pam.d/quickshell; then
        log "installed PAM service 'quickshell'"
    else
        warn "could not install /etc/pam.d/quickshell"
    fi
}

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
        install_pam_lock
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

    if [[ -z "$meta" ]] && have git; then
        local meta_dir="$HOME/.local/share/equisdots-niri/niri-meta"
        info "meta installer not found; cloning equisdots/niri-meta for the full niri stack..."
        mkdir -p "$(dirname "$meta_dir")"
        if git clone --depth 1 https://github.com/equisdots/niri-meta "$meta_dir" --quiet 2>/dev/null; then
            meta="$meta_dir/bin/dotsniri"
        fi
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

# --- Shared payload check ---------------------------------------------------
# This repository deliberately does NOT ship the shared scripts under
# ~/.config/hypr/scripts: they belong to the equisdots Hyprland/shell payload
# and are deployed by the niri-meta installer (niri-meta/bin/dotsniri install).
# Warn clearly instead of duplicating them here.
check_shared_payload() {
    local dir="$HOME/.config/hypr/scripts"
    local -a needed=(qs_manager.sh lock.sh volume.sh brightness.sh reload.sh
        init.sh volume_listener.sh update_notifier.sh gpu-mode.sh)
    local -a missing=()
    local f
    for f in "${needed[@]}"; do
        [[ -e "$dir/$f" ]] || missing+=("$f")
    done

    if (( ${#missing[@]} > 0 )); then
        warn "shared equisdots scripts are missing under $dir:"
        warn "  ${missing[*]}"
        warn "they are provided by the niri-meta deploy, not by this repository;"
        warn "run 'dotsniri install' (niri-meta) before starting niri."
    else
        info "shared equisdots scripts found under $dir (provided by niri-meta)."
    fi
    [[ -d "$dir/quickshell" ]] \
        || warn "Quickshell payload missing at $dir/quickshell (provided by niri-meta)."
}

# --- Main -------------------------------------------------------------------
main() {
    echo "equisdots niri installer"
    detect_distro

    if [[ "$CONFIG_ONLY" == "0" ]]; then
        local go="y"
        printf 'Install system packages (niri, portals, swayidle)? [Y/n] '
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
    if [[ "$CONFIG_ONLY" == "0" ]]; then
        install_app_configs
    fi
    check_shared_payload

    echo
    log "done."
    info "Validate the config:  niri validate -c ~/.config/niri/config.kdl"
    info "Start the session:    niri-session   (or pick 'Niri' in the display manager)"
    info "Idle/lock starts from modules/autostart.kdl (niri_idle_mode.sh boot); do not attach swayidle.service separately."
}

main "$@"
