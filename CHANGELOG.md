# Changelog

All notable changes to the equisdots niri repository. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/); versioning is per
repository, independent of the niri release it targets.

## [Unreleased]

Bring-up fixes for the niri 26.04 session: KDL strictness, border rendering,
layer blur and the package/notification-daemon install path.

### Added

- `keybinds.kdl`: `Super+Shift+F` (`fullscreen-window`), `Super+Shift+M`
  (`maximize-column`) and `Super+Slash` (`show-hotkey-overlay`).
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
  the `Print` binds point at it. `install.sh` adds `quickshell`/`zbar` and keeps
  `grim`/`slurp`/`wl-clipboard`/`satty`/`gpu-screen-recorder` so the overlay has
  everything it needs.

### Changed

- `layout.kdl`: the default border colours are a neutral grey instead of the
  loud palette accent; the shell refines them at runtime from the palette's
  muted colour (`color8`) through `generated/borders.kdl`.
- `layer-rules.kdl`: the forced `background-effect { blur }` on the Quickshell
  layer surfaces was removed. niri has no `ignore_alpha`, so forcing blur on the
  large, mostly transparent popup surfaces painted a full-screen blur sheet.
  niri still blurs any surface that asks for it through `ext-background-effect`.
- `install.sh`: the package prompt now defaults to yes, the meta hook delegates
  to `niri-meta/bin/dotsniri install`, and a failed package step no longer
  aborts the install (config and session files are still deployed).

### Fixed

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

### Removed

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
