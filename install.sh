#!/usr/bin/env bash
# ============================================================================
# equisdots niri - installer
# ============================================================================
# Distro-agnostic installer for the niri compositor config and session.
#
#   ./install.sh                 full install (packages + config + session files)
#   ./install.sh --config-only   deploy ~/.config/niri and the user units only
#   ./install.sh -y              assume "yes" for prompts
#   ./install.sh --no-apps       skip kitty/starship/nvim/xtop/xfetch/font app configs
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
    xdg-desktop-portal-gtk swayidle jq grim slurp satty zbar wl-clipboard cliphist libnotify
    gpu-screen-recorder
    pipewire pipewire-alsa pipewire-pulse wireplumber
    networkmanager bluez bluez-utils
    kitty rofi rofi-emoji playerctl brightnessctl pamixer ddcutil nautilus pavucontrol
    network-manager-applet blueman gnome-keyring libsecret polkit-gnome
    qt5-wayland qt6-wayland qt5ct qt6ct qt6-multimedia
    gvfs gvfs-mtp
    noto-fonts noto-fonts-emoji noto-fonts-cjk adw-gtk-theme papirus-icon-theme
    fd ripgrep python imagemagick librsvg ffmpeg cava power-profiles-daemon rust
    inotify-tools socat lm_sensors iw
    xdg-utils xdg-user-dirs
    zsh starship
    git rsync curl wget tar unzip base-devel)
OPT_ARCH=(mpvpaper bibata-cursor-theme)

CORE_FEDORA=(niri xwayland-satellite xdg-desktop-portal xdg-desktop-portal-gnome
    xdg-desktop-portal-gtk swayidle jq grim slurp zbar wl-clipboard cliphist libnotify
    pipewire pipewire-alsa pipewire-pulseaudio wireplumber
    NetworkManager bluez
    kitty rofi playerctl brightnessctl pamixer ddcutil nautilus pavucontrol
    network-manager-applet blueman gnome-keyring libsecret polkit-gnome
    qt5ct qt6ct qt5-qtwayland qt6-qtwayland qt6-qtmultimedia
    gvfs gvfs-mtp
    google-noto-sans-fonts google-noto-emoji-fonts google-noto-sans-cjk-fonts
    adw-gtk3-theme papirus-icon-theme
    fd-find ripgrep python3 ImageMagick librsvg2 ffmpeg-free cava power-profiles-daemon cargo
    inotify-tools socat lm_sensors iw
    xdg-utils xdg-user-dirs
    starship zsh
    git rsync curl wget tar unzip)
OPT_FEDORA=(satty gpu-screen-recorder mpvpaper rofi-emoji bibata-cursor-theme)

CORE_DEBIAN=(niri xwayland-satellite xdg-desktop-portal xdg-desktop-portal-gnome
    xdg-desktop-portal-gtk swayidle jq grim slurp zbar-tools wl-clipboard cliphist libnotify-bin
    pipewire pipewire-alsa pipewire-pulse wireplumber
    network-manager bluez
    kitty rofi playerctl brightnessctl pamixer ddcutil nautilus pavucontrol
    network-manager-gnome blueman gnome-keyring libsecret-1-0 policykit-1-gnome
    qt5ct qt6ct qt5-wayland qt6-wayland qml6-module-qtmultimedia
    gvfs gvfs-backends
    fonts-noto-core fonts-noto-color-emoji fonts-noto-cjk papirus-icon-theme
    fd-find ripgrep python3 imagemagick librsvg2-common ffmpeg cava power-profiles-daemon cargo
    inotify-tools socat lm-sensors iw
    xdg-utils xdg-user-dirs
    zsh
    git rsync curl wget tar unzip)
OPT_DEBIAN=(satty gpu-screen-recorder-cli mpvpaper rofi-emoji starship bibata-cursor-theme adw-gtk3)
# NOTE: `quickshell` is the equisdots shell/overlay. `grim`, `slurp` and
# `wl-clipboard` provide the screenshot overlay and direct capture; `satty`
# annotates, `zbar` (zbarimg on Arch/Fedora, zbar-tools on Debian) scans QR
# codes, and `gpu-screen-recorder` is the SAME screen recorder Hyprland uses
# (driven by niri/scripts/niri_record.sh; compositor-agnostic, wlr-screencopy).
#
# `qt6-multimedia` is not optional: DavincixPicker.qml and DavincixCard.qml
# import QtMultimedia, so without the QML module the whole wallpaper picker
# fails to load (StackView replace: module "QtMultimedia" is not installed).
# `inotify-tools` drives the live settings/widget watchers and `socat` feeds
# the nyx mascot overlay.
#
# The rest of CORE is the user-facing tool set the keybinds and bar expect:
# kitty (terminal), rofi (emoji picker), playerctl (media keys), brightnessctl,
# pamixer, ddcutil, nautilus, pavucontrol, nm-applet, blueman, gnome-keyring,
# the polkit agent, qt5ct/qt6ct, Qt5/Qt6 Wayland, Noto fonts, adw-gtk3 and
# Papirus icons, fd/ripgrep, python, ImageMagick, ffmpeg, cava and
# power-profiles-daemon. Distro names differ: adw-gtk3 ships as
# `adw-gtk-theme` on Arch and `adw-gtk3-theme` on Fedora; fd is `fd-find` on
# Fedora/Debian; the polkit agent is `policykit-1-gnome` on Debian;
# gpu-screen-recorder is provided by `gpu-screen-recorder-cli` on Debian.
#
# On Arch, `install.sh` ensures an AUR helper (paru, yay, or a fresh yay build
# with git + base-devel) exactly like the Hyprland installer, so AUR-only
# optional packages can be installed instead of silently skipped. `mpvpaper`
# (video wallpapers) is AUR-only and lives in OPT_ARCH, never in the core
# transaction: a missing AUR package must not abort the core install. If the
# core transaction still fails, every core package is retried individually so
# essentials such as `qt6-multimedia` land even when another name is missing.
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

# AUR helper parity with equisdots/hyprland: prefer paru, then yay, and build
# yay from the AUR when neither exists. yay must run as the desktop user, so a
# root invocation only warns and falls back to the official repositories.
AUR_HELPER=""
ensure_aur_helper() {
    if [[ "$(id -u)" == "0" ]]; then
        warn "running as root: AUR helpers cannot run as root; AUR packages will be skipped"
        return 1
    fi
    if have paru; then
        AUR_HELPER="paru"; info "AUR helper: paru"
        return 0
    fi
    if have yay; then
        AUR_HELPER="yay"; info "AUR helper: yay"
        return 0
    fi

    if ! have git || ! have makepkg; then
        info "installing yay build tools (git, base-devel)"
        sudo_cmd pacman -S --needed --noconfirm git base-devel || return 1
    fi

    local tmp
    tmp="$(mktemp -d)" || return 1
    info "no AUR helper found; building yay from the AUR"
    if ! git clone --depth 1 https://aur.archlinux.org/yay.git "$tmp/yay" >/dev/null 2>&1; then
        warn "could not clone yay; AUR-only packages will be skipped"
        rm -rf "$tmp"
        return 1
    fi
    if ( cd "$tmp/yay" && makepkg -si --noconfirm ); then
        if have yay; then
            AUR_HELPER="yay"
            info "AUR helper installed: yay"
        else
            warn "yay build finished but the binary is not on PATH"
            AUR_HELPER=""
        fi
    else
        warn "yay build failed; AUR-only packages will be skipped"
        AUR_HELPER=""
    fi
    rm -rf "$tmp"
    [[ -n "$AUR_HELPER" ]]
}

install_packages() {
    [[ "$PKG" == "unknown" ]] && { warn "unknown distro; install packages manually"; return 0; }

    info "installing packages with $PKG (niri, portals, shell runtime, capture tools)"
    case "$PKG" in
        pacman)
            info "preflight: resolving ${#CORE_ARCH[@]} core packages"
            if ! sudo_cmd pacman -Sp --needed "${CORE_ARCH[@]}" >/dev/null; then
                warn "package resolution failed; nothing was installed"
                return 1
            fi
            if ! sudo_cmd pacman -S --needed --noconfirm "${CORE_ARCH[@]}"; then
                warn "core package transaction failed; nothing was installed"
                return 1
            fi
            if ! ensure_aur_helper; then
                warn "no AUR helper for required AUR packages: ${OPT_ARCH[*]}"
                return 1
            fi
            if ! "$AUR_HELPER" -S --needed --noconfirm "${OPT_ARCH[@]}"; then
                warn "AUR transaction failed; retrying once"
                if ! "$AUR_HELPER" -S --needed --noconfirm "${OPT_ARCH[@]}"; then
                    warn "AUR package transaction failed: ${OPT_ARCH[*]}"
                    return 1
                fi
            fi
            ;;
        dnf)
            if ! sudo_cmd dnf install -y "${CORE_FEDORA[@]}"; then
                warn "core package transaction failed; niri may need a COPR (see https://yalter.github.io/niri)"
                return 1
            fi
            if ! sudo_cmd dnf install -y "${OPT_FEDORA[@]}"; then
                warn "optional package transaction failed: ${OPT_FEDORA[*]}"
                return 1
            fi
            ;;
        apt)
            sudo_cmd apt-get update
            if ! sudo_cmd apt-get install -y "${CORE_DEBIAN[@]}"; then
                warn "core package transaction failed"
                return 1
            fi
            if ! sudo_cmd apt-get install -y "${OPT_DEBIAN[@]}"; then
                warn "optional package transaction failed: ${OPT_DEBIAN[*]}"
                return 1
            fi
            ;;
    esac
    return 0
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

    local wallpaper_dir=""
    if have jq && [[ -f "$HOME/.config/hypr/settings.json" ]]; then
        wallpaper_dir="$(jq -r '.wallpaperDir // empty' "$HOME/.config/hypr/settings.json" 2>/dev/null || true)"
    fi
    wallpaper_dir="${wallpaper_dir:-$HOME/.config/hypr/wallpapers}"
    wallpaper_dir="${wallpaper_dir/#\~/$HOME}"
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
        warn "scripts/install-app-configs.sh not found; skipping kitty/starship/nvim/xtop/xfetch/font"
        return 0
    fi
    local args=()
    [[ "$ASSUME_YES" == "1" ]] && args+=("-y")
    info "installing user app configs (kitty, starship, nvim, xtop, xfetch, Hack Nerd Font)"
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

# SDDM uses the same Hack Nerd Font as the shell. Install it system-wide (the
# app-config installer also installs it per-user); without this the greeter
# shows boxes for the shutdown/reboot glyphs.
install_font_system() {
    local src="$HOME/.local/share/fonts/HackNerdFont-Regular.ttf"
    local dst="/usr/share/fonts/HackNerdFont-Regular.ttf"
    local url="https://raw.githubusercontent.com/xscriptor-colors/terminal/main/assets/fonts/HackNerdFont/HackNerdFont-Regular.ttf"
    [[ -f "$dst" ]] && cmp -s "$src" "$dst" 2>/dev/null && { info "Hack Nerd Font already installed system-wide"; return 0; }
    if [[ ! -f "$src" ]]; then
        mkdir -p "$(dirname "$src")"
        if have curl; then
            curl -fsSL "$url" -o "$src" 2>/dev/null || true
        elif have wget; then
            wget -q -O "$src" "$url" 2>/dev/null || true
        fi
    fi
    [[ -f "$src" ]] || { warn "Hack Nerd Font not available; SDDM may show boxes"; return 0; }
    if sudo_cmd install -Dm644 "$src" "$dst"; then
        sudo_cmd fc-cache -f >/dev/null 2>&1 || true
        log "installed Hack Nerd Font system-wide (SDDM/login)"
    else
        warn "could not install Hack Nerd Font system-wide (SDDM may show boxes)"
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
        install_font_system
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

# The wallpaper picker (DavincixPicker.qml) and the video previews
# (DavincixCard.qml) import QtMultimedia. When the QML module is missing the
# whole picker fails to instantiate and Super+W appears to do nothing.
qt_multimedia_present() {
    local root
    for root in \
        "$(qmake6 -query QT_INSTALL_QML 2>/dev/null || true)" \
        /usr/lib/qt6/qml \
        /usr/lib64/qt6/qml \
        /usr/lib/x86_64-linux-gnu/qt6/qml \
        /usr/lib/aarch64-linux-gnu/qt6/qml; do
        [[ -n "$root" && -d "$root/QtMultimedia" ]] && return 0
    done
    return 1
}

check_runtime_deps() {
    if qt_multimedia_present; then
        info "QtMultimedia QML module found (wallpaper picker and video previews)"
        return 0
    fi
    warn "QtMultimedia QML module is missing: the wallpaper picker will not load"
    case "$PKG" in
        pacman) warn "  install it with: sudo pacman -S qt6-multimedia" ;;
        dnf)    warn "  install it with: sudo dnf install qt6-qtmultimedia" ;;
        apt)    warn "  install it with: sudo apt install qml6-module-qtmultimedia" ;;
    esac
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
    check_runtime_deps

    echo
    log "done."
    info "Validate the config:  niri validate -c ~/.config/niri/config.kdl"
    info "Start the session:    niri-session   (or pick 'Niri' in the display manager)"
    info "Idle/lock starts from modules/autostart.kdl (niri_idle_mode.sh boot); do not attach swayidle.service separately."
}

main "$@"
