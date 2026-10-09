# Changelog

All notable changes to the equisdots niri repository. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/); versioning is per
repository, independent of the niri release it targets.

## [Unreleased]

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
