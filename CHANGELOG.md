# Changelog

All notable changes to the equisdots niri repository. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/); versioning is per
repository, independent of the niri release it targets.

## [Unreleased]

Bring-up fixes for the niri 26.04 session: KDL strictness, border rendering,
layer blur, environment generation and the package/notification-daemon install
path. The keybinds and autostart are now at parity with Hyprland HEAD
(f665ee5) wherever niri 26.04 has an equivalent action.

### Added

- `scripts/niri_wallpaper.sh` + `Super+W`: the wallpaper picker no longer
  depends on the shared `qs_manager.sh`; the niri wrapper runs
  `davincix thumbs`, starts Quickshell if needed and toggles the picker over
  IPC. `scripts/niri_wallpaper_doctor.sh` prints the resolved wallpaper dir,
  scene/media counts, davincix/kernel/thumbs/font tools for field debugging.
- `install-app-configs.sh` creates `~/.config/xtop/themes` when xtop is
  already installed, so theme-sync's xtop target is available and applies the
  palette (it previously skipped because the themes directory did not exist).
- `install.sh`: the generated `WALLPAPER_DIR` now follows
  `settings.json.wallpaperDir` (expanded), matching the shell and the picker.
- `config/niri/modules/layer-rules.kdl`: `place-within-backdrop true` for the
  `xwww-daemon` layer, so the wallpaper fills the Overview backdrop and the
  space between workspaces instead of staying inside a workspace rectangle.
- `config/niri/modules/layout.kdl`: `background-color "transparent"` so the
  wallpaper placed in the Overview backdrop also stays visible on the normal
  workspace. An opaque workspace background covered it (wallpaper only showed
  in the Overview).
- `config/niri/modules/layout.kdl`: new windows open at `proportion 1.0`
  (full output width) and `1.0` is in `preset-column-widths`, matching the
  wide-window behavior of the shared niri configs. Existing windows are not
  resized.
- `config/niri/modules/window-rules.kdl`: the browser workspace rule now
  covers `brave-browser`, LibreWolf, Zen, Vivaldi, Edge, Floorp and qutebrowser
  in addition to Firefox/Chromium/Chrome.
- `install.sh`: package parity with the Hyprland installer. Core now includes
  `qt6-multimedia` (required by the davincix wallpaper picker/video previews),
  `inotify-tools` (live settings/widget watchers), `socat` (nyx IPC), PipeWire
  ALSA/pulse, NetworkManager/BlueZ, Qt5/Qt6 Wayland, GVfs/libsecret,
  `lm_sensors`, `iw`, `librsvg`, CJK fonts, `rofi-emoji`, `xdg-utils`,
  `starship`/`zsh` and the base build tools (`git`, `base-devel`, `rsync`,
  `curl`, `wget`, `tar`, `unzip`). On Arch it ensures an AUR helper
  (paru/yay, or builds yay) for AUR-only extras (`mpvpaper` and Bibata
  cursors; `envycontrol` is installed by niri-meta's NVIDIA step) and warns
  when the QtMultimedia QML module is still missing.
  If the core pacman transaction fails, every core package is retried
  individually so an unknown/missing package cannot block `qt6-multimedia` and
  the rest of the essentials.
- Standalone app config installer (`scripts/install-app-configs.sh`): kitty
  themes/shaders/aliases from `xscriptor-colors/terminal`, starship, neovim,
  Hack Nerd Font, and the palette sync. `install.sh` runs it on a full install
  (`--no-apps` skips it) and `niri-meta` calls it on `install`.
- `scripts/install-app-configs.sh`: install xtop (built from
  `xtop-cli/xtop` with cargo) so theme-sync can theme it, copy the interactive
  wallpaper scenes from the `background` clone into the davincix wallpaper
  directory, optionally download a still-wallpaper pack
  (`WALLPAPERS_PACK`/`wallpapers.sh`), and install Hack Nerd Font
  **system-wide** (`/usr/share/fonts`) for SDDM/login. `rust`/`cargo` is in the
  package lists for the xtop build. `--no-xtop`, `--no-scenes`,
  `--no-wallpapers` and `--no-system-font` opt out; `DOTSNIRI_NO_*` env vars
  provide the same for automation.
- `config/apps/rofi/` and `config/apps/cava/`: the rofi/cava configs now live
  in the niri repo and are deployed by `install.sh` and `dotsniri deploy`, so a
  fresh niri install no longer depends on the `hyprland` repo for them.
- `config/pam.d/quickshell` + `install.sh`: install the Quickshell lock-screen
  PAM service on a full direct install (backup of an existing service).
- `install.sh`: when no meta installer is present and `git` is available, it
  clones `equisdots/niri-meta` and delegates, so a standalone niri checkout
  still gets the full shell/plugin/config payload.
- `keybinds.kdl`: `Super+Shift+M` opens the Plugins panel (same chord as
  Hyprland); `maximize-column` moved to `Super+Ctrl+M` to free it.
- `keybinds.kdl`: `Super+Shift+F` (`fullscreen-window`) and `Super+Slash`
  (`show-hotkey-overlay`).
- Hyprland application parity: `Super+Shift+K` launches a centered floating
  kitty (900x560) and `Super+Shift+D` a centered floating VS Code Insiders
  (1200x800); the bar editor remains on `Super+Shift+S`. New
  `scripts/niri_floating_app.sh` snapshots `niri msg --json windows`, follows
  `niri msg --json event-stream` with a timeout (plus a windows-poll fallback),
  then focuses/floats/`set-window-width`/`set-window-height`/`center-window`s
  the new window by id. Verified against niri 26.04: `move-floating-window` is
  IPC-only (`#[knuffel(skip)]`) and is not used in KDL.
- `keybinds.kdl`: `Super+Shift+Q` exits with `skip-confirmation=true`, matching
  Hyprland; `Super+Escape` now also skips the confirmation.
- `keybinds.kdl`: `Super+Alt+Shift+M` opens the monitor manager in `info` mode
  (`niri_monitor_manager.sh info`).
- `scripts/niri_scratch.sh`: `Super+A` now focuses `scratch`, returns to the
  previous workspace when scratch is already focused, and launches nautilus
  when scratch has no windows. `Super+Shift+A` still moves the focused window
  there (through `niri_ws.sh scratch move`).
- `config/niri/defaults/environment.kdl` + installer-seeded
  `generated/env.kdl` for the single-occurrence `environment {}` section:
  literal `PATH` with `~/.local/bin` first, `WALLPAPER_DIR`, `SCRIPT_DIR`,
  `XDG_PICTURES_DIR`, `XDG_VIDEOS_DIR`, plus `GDK_SCALE`, `GDK_DPI_SCALE`,
  `ELECTRON_FORCE_DEVICE_SCALE_FACTOR` and `XCURSOR_SIZE` when
  `settings.json` has `appScale != 1.0`. `config.kdl` includes
  `optional=true "generated/env.kdl"`.
- `scripts/niri_update_notifier.sh` + autostart: the update indicator now
  compares `~/.local/state/equisdots-niri-version` with
  `niri-meta/updates.json` and writes the same Quickshell cache files the bar
  reads, instead of running the shared Hyprland notifier (which advertised
  Hyprland updates on a niri-only machine). `--once` is available for tests.
- `modules/autostart.kdl`: idle/lock now starts at session boot through
  `niri_idle_mode.sh boot` (Hyprland `idle-mode.sh boot` parity); the
  Quickshell launch sets
  `QT_LOGGING_RULES=qt.qpa.wayland.textinput.warning=false`; added the
  `pam_kwallet_init`/gnome-keyring fallback and extra polkit agent paths.
  Autostart is documented as the owner of idle (do not also attach
  `swayidle.service`).
- `install.sh`: expanded CORE/OPT package arrays (kitty, rofi, playerctl,
  brightnessctl, pamixer, ddcutil, nautilus, pavucontrol,
  network-manager-applet, blueman, gnome-keyring, polkit agent, qt6ct, Noto
  fonts, adw-gtk3, Papirus, Bibata, fd, ripgrep, python, ImageMagick, ffmpeg,
  cava, power-profiles-daemon, envycontrol, satty, gpu-screen-recorder, zbar)
  with per-distro names; `python3` is no longer used on Arch. Optional
  packages install one by one so a missing AUR/COPR/PPA name does not block
  the rest.
- `install.sh`: a shared-payload check warns that `~/.config/hypr/scripts` and
  the Quickshell shell come from the `niri-meta` deploy and are not duplicated
  here; `deploy_config` seeds `generated/env.kdl`.
- `config.kdl`: `include optional=true "generated/borders.kdl"` after
  `generated/theme-colors.kdl`, so the border colours written by the shell
  backend actually reach the running config.
- `install.sh`: `gpu-screen-recorder` as an optional package, so niri uses the
  SAME screen recorder as Hyprland (`gpu-screen-recorder`).
- `scripts/niri_record.sh`: a self-contained screen recorder
  (`gpu-screen-recorder`, no dependency on the Hyprland repo) with a start/stop
  toggle, region capture via `slurp`, and the same pid cache the bar reads.
  `niri_screenshot.sh --record` forwards to it. New binds: `Super+Alt+R`
  (toggle) and `Super+Alt+Shift+R` (region).
- `scripts/niri_screenshot.sh` now opens the shared equisdots screenshot
  overlay (region + still/video + microphone selection), matching Hyprland, and
  the `Print` binds point at it. It resolves the screenshots plugin's overlay
  first (`plugin-screenshots-ScreenshotOverlay.qml` /
  `ui/plugins/screenshots/ui/ScreenshotOverlay.qml`) and keeps the legacy root
  path as a fallback. `install.sh` adds `quickshell`/`zbar` and keeps
  `grim`/`slurp`/`wl-clipboard`/`satty`/`gpu-screen-recorder` so the overlay has
  everything it needs.
- Plugin-standard parity with the merged Hyprland stack: the same shell plugin
  catalog, MD3 tokens, plugin popups and bar modules; `niri-meta` deploys
  `plugin-api`, `plugin-sdk`, the plugin hub, the default plugins and their
  registry. Plugin actions are reached through the static compositor binds
  (clipboard, quicknotes, RSS, file search, screenshots, timex) because niri
  loads KDL and does not evaluate plugin `hypr.lua` fragments.

### Changed

- `layout.kdl`: the default border colours are a neutral grey instead of the
  loud palette accent; the shell refines them at runtime from the palette's
  muted colour (`color8`) through `generated/borders.kdl`.
- `layer-rules.kdl`: the forced `background-effect { blur }` on the Quickshell
  layer surfaces was removed. niri has no `ignore_alpha`, so forcing blur on the
  large, mostly transparent popup surfaces painted a full-screen blur sheet.
  niri still blurs any surface that asks for it through `ext-background-effect`.
- `keybinds.kdl`: `Super+G` is `center-window` (Hyprland centers the active
  window, not the column); `Super+Alt+Shift+I/U` use
  `move-window-to-monitor-right/left` so they move the active window instead of
  the whole column.
- `keybinds.kdl`: numbered focus/move and Page Up/Down binds route through
  `scripts/niri_ws.sh`, which closes Quickshell popups first. Wheel scrolling
  and `Super+Tab` stay direct niri actions because the script has no matching
  verb and a process per wheel tick would be worse than the cooldown bind.
- `install.sh`: the package prompt now defaults to yes, the meta hook delegates
  to `niri-meta/bin/dotsniri install`, and a failed package step no longer
  aborts the install (config and session files are still deployed).

### Fixed

- `scripts/niri_floating_app.sh`: retry the `set-window-width`/`set-window-height`
  pair until the client's initial commit settles (the first request could be
  overwritten by the app's own size), match VS Code Insiders' real
  `com.microsoft.VSCodeInsiders` app_id, and accept any new window after a
  short grace period instead of stalling for the full timeout. Verified live
  against nested niri 26.04 with kitty and VS Code Insiders.
- Single-occurrence sections: `input`, `animations` and `blur` are now owned by
  one generated fragment each (`generated/user-input.kdl`,
  `generated/user-animations.kdl`, `generated/blur.kdl`) seeded from
  `config/niri/defaults/`. Previously the static modules plus the generated
  fragments defined the same sections, which is a `niri validate` error once
  the settings panel wrote `user-input.kdl`/`user-animations.kdl`, and `blur`
  appeared both in `config.kdl` and `theme-effects.kdl`. The input writer now
  also emits the keyboard layout/options and `focus-follows-mouse`, so making
  the generated file the sole owner does not lose the translated defaults.
- KDL strictness: niri's parser rejects a block whose last node is not
  terminated by `;` or a newline before `}` (for example
  `window-rule { match app-id="x"; open-floating true }` or `focus-ring { off }`).
  An invalid config makes niri silently fall back to its default config (grey
  screen plus the "Important Hotkeys" overlay). The one-line rules in
  `modules/window-rules.kdl` and the shell-generated border fragment are now
  emitted as multi-line blocks.
- `window-rules.kdl`: `draw-border-with-background false`, so niri no longer
  paints a solid border-coloured rectangle behind windows (which tinted
  translucent windows with the border colour).
- `install.sh`: the meta installer hook calls
  `niri-meta/bin/dotsniri install` correctly (previously it looked for the wrong
  path and passed no subcommand).
- `niri_screenshot.sh`: `--full --edit` now captures the focused output with
  `grim` (falling back to the whole layout) and opens it in `satty`; previously
  the native `screenshot-screen` path ran and exited before the editor.
  `--full` without `--edit` still uses the native action, and `--edit` without
  `--full` still opens the overlay in edit mode.
- `environment {}` moved out of `modules/environment.kdl` into the installer
  seed. niri rejects a duplicate `environment` node and cannot expand `$HOME`,
  so the section now has exactly one owner and literal paths. `README.md`,
  `docs/kdl-gotchas.md`, `generated/README.md` and `systemd/README.md` document
  the new layout and the idle/autostart ownership.

### Removed

- `modules/environment.kdl` (moved to `defaults/environment.kdl` as the seed for
  `generated/env.kdl`; the section is single-occurrence).
- The forced layer blur in `layer-rules.kdl` (see Changed).
- The separate notification daemon (`mako`/`dunst`) from the package lists. The
  Quickshell shell owns `org.freedesktop.Notifications`; a rival daemon would
  win the D-Bus name and serve notifications with its own colours.
- The GitHub Actions validation workflow. It was added to guard KDL syntax
  regressions and then removed because CI was not authorized.

## [0.1.0]

First release: the niri compositor layer for the equisdots desktop, targeting
niri 26.04.

### Added

- Entry config `config/niri/config.kdl` with a modular `include` tree and
  optional `generated/*.kdl` fragments.
- Modules translated from the Hyprland Lua config: `environment`, `input`,
  `layout`, `animations`, `workspaces`, `window-rules`, `layer-rules`,
  `autostart`, `keybinds`.
- Session scripts: `niri_workspaces.sh` (event-stream workspace daemon),
  `niri_kb_fetch.sh`, `niri_ws.sh`, `niri_write_borders.sh`, `niri_effects.sh`,
  `niri_monitor_apply.sh`, `niri_monitor_manager.sh`, `niri_scale.sh`,
  `niri_idle_mode.sh`, `niri_screenshot.sh`, `niri_pick_color.sh`, plus
  `scripts/caching.sh` and `scripts/lib/common.sh`.
- Optional systemd user units: `swayidle.service`, `quickshell.service`,
  `xwww.service`, `focus-daemon.service`.
- Session and portal files: `session/niri.desktop`,
  `portals/niri-portals.conf`.
- Idempotent, distro-agnostic `install.sh` (Arch/Fedora/Debian detection,
  `--config-only`, `-y`, meta-installer hook) and `uninstall.sh`.

### Notes

- Uses strategy A: the shared equisdots data root stays at `~/.config/hypr`;
  only the compositor config lives at `~/.config/niri`.
- Known feature gaps (no niri equivalent): hardware output mirroring, live
  effect preview, floating scratchpad overlay, tearing, `hyprctl getoption`,
  and global pointer-position queries. They are documented per file and in the
  README.
