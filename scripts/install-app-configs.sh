#!/usr/bin/env bash
# ============================================================================
# install-app-configs.sh - user app configs for the niri stack
# ============================================================================
# Hyprland's installer sets up kitty (themes, shaders, aliases), starship,
# neovim and Hack Nerd Font from the xscriptor-colors ecosystem. This script
# provides the same user-facing configs for a standalone niri install, from the
# niri repository, without touching equisdots/hyprland.
#
#   ./install-app-configs.sh                 install all (kitty/starship/nvim/font)
#   ./install-app-configs.sh -y              non-interactive (keep existing nvim)
#   ./install-app-configs.sh --replace-nvim  replace an existing ~/.config/nvim
#   ./install-app-configs.sh --no-kitty --no-starship --no-nvim --no-font
#   ./install-app-configs.sh --dry-run       print the plan, change nothing
#
# Rofi and cava configs are deployed by `niri/install.sh` and `dotsniri deploy`
# from this repository's config/apps/ tree (no network, no sudo).
# ============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}"
ASSUME_YES=0
DRY_RUN=0
DO_KITTY=1
DO_STARSHIP=1
DO_NVIM=1
DO_FONT=1
REPLACE_NVIM=0

log()  { printf '[apps] %s\n' "$*"; }
warn() { printf '[apps] warning: %s\n' "$*" >&2; }
have() { command -v "$1" >/dev/null 2>&1; }
run()  {
    if (( DRY_RUN )); then
        printf '   [dry-run] %s\n' "$*"
        return 0
    fi
    "$@"
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        -y|--yes)       ASSUME_YES=1 ;;
        --dry-run)      DRY_RUN=1 ;;
        --no-kitty)     DO_KITTY=0 ;;
        --no-starship)  DO_STARSHIP=0 ;;
        --no-nvim)      DO_NVIM=0 ;;
        --no-font)      DO_FONT=0 ;;
        --replace-nvim) REPLACE_NVIM=1 ;;
        -h|--help)
            sed -n '2,20p' "$0" | sed 's/^# \{0,1\}//'
            exit 0
            ;;
        *) warn "unknown option: $1"; exit 2 ;;
    esac
    shift
done

if (( DRY_RUN )); then
    log "dry-run plan:"
    (( DO_FONT )) && log "  - Hack Nerd Font -> $HOME/.local/share/fonts (user)"
    (( DO_KITTY )) && log "  - clone xscriptor-colors/terminal and run emulators/kitty/install.sh"
    (( DO_STARSHIP )) && log "  - clone xscriptor-colors/terminal and run prompts/starship/install.sh"
    (( DO_NVIM )) && log "  - clone xscriptor-colors/nvim -> $CONFIG_DIR/nvim (existing: $([[ -d "$CONFIG_DIR/nvim" ]] && echo keep || echo create))"
    log "rofi/cava are deployed by niri/install.sh and dotsniri deploy"
    exit 0
fi

theme_sync_run() {
    local engine="${XDG_DATA_HOME:-$HOME/.local/share}/equisdots/theme-sync/theme-sync.sh"
    [[ -x "$engine" ]] || engine="$HOME/.local/bin/theme-sync"
    if [[ -x "$engine" ]]; then
        bash "$engine" || warn "theme sync failed (non-fatal)"
    else
        warn "theme-sync engine not installed yet; run 'dotsniri install' for palette sync"
    fi
}

install_font() {
    local font_dir="$HOME/.local/share/fonts"
    local font="$font_dir/HackNerdFont-Regular.ttf"
    local url="https://raw.githubusercontent.com/xscriptor-colors/terminal/main/assets/fonts/HackNerdFont/HackNerdFont-Regular.ttf"
    mkdir -p "$font_dir"
    if [[ -f "$font" ]]; then
        log "Hack Nerd Font already present"
    elif have curl; then
        log "downloading Hack Nerd Font"
        curl -fsSL "$url" -o "$font" || { warn "font download failed (non-fatal)"; return 0; }
    elif have wget; then
        log "downloading Hack Nerd Font"
        wget -q -O "$font" "$url" || { warn "font download failed (non-fatal)"; return 0; }
    else
        warn "curl/wget missing; cannot download Hack Nerd Font"
        return 0
    fi
    have fc-cache && fc-cache -f "$font_dir" >/dev/null 2>&1 || true
}

install_kitty_shaders() {
    local src="$1" dest="$CONFIG_DIR/kitty/shaders" f n=0
    [[ -d "$src" ]] || { warn "kitty shaders not found in the terminal checkout"; return 0; }
    mkdir -p "$dest"
    for f in "$src"/*.slang "$src"/*.pipeline; do
        [[ -f "$f" ]] || continue
        cp -f "$f" "$dest/" && n=$((n + 1))
    done
    [[ -f "$dest/x-glow.slang" ]] && rm -f "$dest/x-glow.slang"
    log "kitty shaders: $n file(s) -> $dest"
}

ensure_kitty_shader_config() {
    local conf="$CONFIG_DIR/kitty/kitty.conf" added=0
    [[ -f "$conf" ]] || return 0
    if ! grep -qE '^[[:space:]]*custom_shaders[[:space:]]' "$conf"; then
        printf '\ncustom_shaders x-trail\n' >> "$conf"; added=1
    fi
    if ! grep -qE '^[[:space:]]*cursor_trail[[:space:]]' "$conf"; then
        printf 'cursor_trail 12\n' >> "$conf"; added=1
    fi
    if ! grep -qE '^[[:space:]]*cursor_trail_start_threshold[[:space:]]' "$conf"; then
        printf 'cursor_trail_start_threshold 0\n' >> "$conf"; added=1
    fi
    (( added )) && log "kitty shaders: enabled the lightning trail in kitty.conf"
}

install_kitty() {
    log "Installing kitty config from xscriptor-colors/terminal"
    have git || { warn "git missing; cannot clone the terminal repo"; return 0; }
    local tmp; tmp="$(mktemp -d)"
    if ! git clone --depth 1 https://github.com/xscriptor-colors/terminal.git "$tmp/terminal" >/dev/null 2>&1; then
        warn "failed to clone xscriptor-colors/terminal (non-fatal)"
        rm -rf "$tmp"
        return 0
    fi
    local installer="$tmp/terminal/emulators/kitty/install.sh"
    if [[ -f "$installer" ]]; then
        bash "$installer" || warn "kitty installer finished with warnings (non-fatal)"
    else
        warn "kitty installer not found in the terminal checkout"
    fi
    install_kitty_shaders "$tmp/terminal/emulators/kitty/shaders"
    ensure_kitty_shader_config
    rm -rf "$tmp"
    theme_sync_run
}

ensure_starship_grml_prompt_fix() {
    local rc="$1"
    local fix='typeset -ga precmd_functions; precmd_functions=(${precmd_functions:#prompt_grml*_precmd})'
    grep -qF "$fix" "$rc" 2>/dev/null && return 0
    {
        printf '\n# equisdots: starship owns PROMPT (grml-zsh-config overrides it)\n'
        printf '%s\n' "$fix"
    } >> "$rc"
}

ensure_starship_init() {
    local rc="$1" shell="$2"
    [[ -f "$rc" ]] || return 0
    if ! grep -qF "starship init $shell" "$rc" 2>/dev/null; then
        {
            printf '\n# equisdots: starship prompt\n'
            printf 'eval "$(starship init %s)"\n' "$shell"
        } >> "$rc"
    fi
    if [[ "$shell" == "zsh" ]]; then
        ensure_starship_grml_prompt_fix "$rc"
    fi
    return 0
}

install_starship() {
    log "Installing starship config from xscriptor-colors/terminal"
    have git || { warn "git missing; cannot clone the terminal repo"; return 0; }
    local tmp; tmp="$(mktemp -d)"
    if ! git clone --depth 1 https://github.com/xscriptor-colors/terminal.git "$tmp/terminal" >/dev/null 2>&1; then
        warn "failed to clone xscriptor-colors/terminal (non-fatal)"
        rm -rf "$tmp"
        return 0
    fi
    local installer="$tmp/terminal/prompts/starship/install.sh"
    if [[ -f "$installer" ]]; then
        bash "$installer" || warn "starship installer finished with warnings (non-fatal)"
        local entry rc shell
        for entry in "$HOME/.zshrc zsh" "$HOME/.bashrc bash"; do
            rc="${entry%% *}"; shell="${entry##* }"
            have "$shell" || continue
            [[ -f "$rc" ]] && grep -q 'xscriptor-starship-v2' "$rc" 2>/dev/null && continue
            XSC_STARSHIP_SHELL_RC="$rc" bash "$installer" \
                || warn "starship: could not configure $rc (non-fatal)"
        done
    else
        warn "starship installer not found in the terminal checkout"
    fi
    rm -rf "$tmp"
    if have bash; then ensure_starship_init "$HOME/.bashrc" bash; fi
    if have zsh; then ensure_starship_init "$HOME/.zshrc" zsh; fi
    theme_sync_run
}

install_nvim() {
    local dest="$CONFIG_DIR/nvim"
    log "Installing Neovim config from xscriptor-colors/nvim"
    have git || { warn "git missing; cannot clone the nvim repo"; return 0; }
    if [[ -d "$dest" ]]; then
        if (( REPLACE_NVIM == 0 )); then
            warn "existing nvim config found at $dest; keeping it (use --replace-nvim to replace)"
            return 0
        fi
        rm -rf "$dest"
    fi
    if git clone --depth 1 https://github.com/xscriptor-colors/nvim.git "$dest"; then
        log "Neovim config installed; run nvim then :Lazy and :Mason"
    else
        warn "failed to clone xscriptor-colors/nvim (non-fatal)"
    fi
}

(( DO_FONT )) && install_font
(( DO_KITTY )) && install_kitty
(( DO_STARSHIP )) && install_starship
(( DO_NVIM )) && install_nvim
log "app configs finished"
