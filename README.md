# equisdots niri — niri

The niri compositor layer of the equisdots desktop: a modular KDL config, the
niri session scripts and the session/portal files needed to run the equisdots
stack on [niri](https://github.com/YaLTeR/niri) 26.04+ instead of Hyprland. It
is the niri sibling of the `hyprland` repository.

niri is a scrollable-tiling Wayland compositor. Windows live in columns on an
infinite horizontal strip per monitor, workspaces are dynamic and independent
per monitor, and the config is a single KDL document that hot-reloads on save.

## What this repository owns

| Installed path | Source | Purpose |
| --- | --- | --- |
| `~/.config/niri/config.kdl` | `config/niri/config.kdl` | Entry config; includes the modules and the generated fragments. |
| `~/.config/niri/modules/*.kdl` | `config/niri/modules/` | The translated Hyprland modules (input, layout, keys, ...). |
| `~/.config/niri/generated/` | `config/niri/generated/` | Runtime fragments (palette border colors, saved outputs, effects). |
| `~/.config/niri/scripts/*.sh` | `scripts/` | The niri session scripts and their shared `lib/common.sh`. |
| `~/.config/systemd/user/*.service` | `systemd/` | Optional user units (swayidle, quickshell, xwww, focus-daemon). |
| `/usr/share/wayland-sessions/niri.desktop` | `session/niri.desktop` | The display-manager session entry. |
| `/usr/share/xdg-desktop-portal/niri-portals.conf` | `portals/niri-portals.conf` | Portal backend selection (`gnome` + `gtk`). |

`install.sh` deploys all of the above (`--config-only` deploys just the config
and the user units). `uninstall.sh` removes them without touching packages.

## Relationship to the shared root

This repository uses **strategy A**: the shared equisdots data root stays at
`~/.config/hypr`, and only the compositor config moves to `~/.config/niri`.

- `~/.config/hypr/settings.json`, `palettes/`, `wallpapers/`, the Quickshell
  shell (`~/.config/hypr/scripts/quickshell`) and the shared scripts
  (`~/.config/hypr/scripts/*.sh`, e.g. `lock.sh`, `volume.sh`, `qs_manager.sh`)
  are reused unchanged.
- The niri scripts read the shared root through `EQUISDOTS_CONFIG_DIR`
  (default `~/.config/hypr`); see `scripts/lib/common.sh`.
- Hyprland and niri can run side by side from one `settings.json` and one
  palette store.

Only the compositor-specific pieces differ: the KDL config, the workspace
event-stream daemon, the monitor/idle/screenshot wrappers and the shell backend
(a `Niri.qml` compositor adapter in the shell repository).

## Validate, run, verify

```sh
# 1. Validate the assembled config (niri is not required to be running).
niri validate -c ~/.config/niri/config.kdl

# 2. Start a session from a display manager (choose "Niri") or a TTY:
niri-session

# 3. Follow the session log:
journalctl --user-unit=niri -b --no-pager

# 4. Check the bar data sources:
~/.config/niri/scripts/niri_kb_fetch.sh
~/.config/niri/scripts/niri_workspaces.sh --once
```

> `niri` is not installed in the authoring environment, so `niri validate` must
> be run by the user on a machine with niri 26.04+. The scripts are checked
> here with `bash -n`, and the KDL is checked for brace balance, but that is not
> a substitute for `niri validate`.

Portals (screencasting, file choosers) require a real session (`niri-session`
or a display manager); a bare `niri` on a TTY does not provide the
graphical-session plumbing.

## File map

```
config/niri/
  config.kdl                 entry: includes modules, top-level options, generated
  modules/
    environment.kdl          env.lua -> environment {} (see caveats in-file)
    input.kdl                settings.lua input -> input {}
    layout.kdl               general/decoration -> layout {}
    animations.kdl           animations.lua -> animations {}
    workspaces.kdl           workspaces.lua -> named workspaces
    window-rules.kdl         windowrules.lua -> window-rule {}
    layer-rules.kdl          layers.lua -> layer-rule {} (Quickshell blur)
    autostart.kdl            autostart.lua -> spawn-sh-at-startup
    keybinds.kdl             keybinds.lua -> binds {}
  generated/
    README.md                generated fragments and their writers
    theme-colors.kdl*        border colors (niri_write_borders.sh)
    theme-effects.kdl*       gaps/border/blur/shadow (niri_effects.sh)
    outputs.kdl*             saved monitor layout (niri_monitor_apply.sh)
    user-binds.kdl*          shell-generated binds (Config.qml, pending port)
    user-startup.kdl*        shell-generated startup (Config.qml, pending port)

scripts/
  lib/common.sh              shared paths/logging (EQUISDOTS_CONFIG_DIR, ...)
  caching.sh                 Quickshell cache/state/run exports
  niri_workspaces.sh         workspace state daemon for the bar (event stream)
  niri_kb_fetch.sh           active keyboard layout
  niri_ws.sh                 workspace/window routing
  niri_write_borders.sh      write generated/theme-colors.kdl and reload
  niri_effects.sh            read/preview/persist gaps/border/blur/shadow
  niri_monitor_apply.sh      apply saved layout -> generated/outputs.kdl
  niri_monitor_manager.sh    list/apply outputs, position presets, save
  niri_scale.sh              scale the focused output up/down/auto
  niri_idle_mode.sh          swayidle awake/normal/boot/status
  niri_screenshot.sh         native region/full/window + grim+satty --edit
  niri_pick_color.sh         native pick-color -> hex on the clipboard

systemd/                     optional user units + README
session/niri.desktop         display-manager session entry
portals/niri-portals.conf    xdg-desktop-portal selection (gnome + gtk)
install.sh / uninstall.sh    idempotent, distro-agnostic
```

`*` = generated at runtime and gitignored.

## Script verbs

| Script | Usage |
| --- | --- |
| `niri_ws.sh` | `<index\|name> [move]`, `next`, `prev` |
| `niri_effects.sh` | `read`, `preview KEY=VAL ...`, `persist`, `apply KEY=VAL ...` |
| `niri_monitor_manager.sh` | `list`, `apply NAME key=val`, `layout PRESET`, `save` |
| `niri_scale.sh` | `up`, `down`, `auto`, `<scale> [output]` |
| `niri_idle_mode.sh` | `awake`, `normal`, `boot`, `status` |
| `niri_screenshot.sh` | (default), `--full`, `--window`, `--edit`, `--geometry G` |
| `niri_workspaces.sh` | (daemon), `--once` |

Run any script with `--help` for details.

## Known differences from the Hyprland config

These are deliberate; see the comments in each module.

- **Workspaces are dynamic.** The numbered binds still work (1..0 address
  indices), but app placement uses named workspaces (`browser`, `code`, `chat`,
  `media`, `games`, `scratch`). There is no floating scratchpad overlay.
- **No `hyprctl eval`.** Live changes write a KDL fragment under `generated/`
  and reload; this is why the border/effects writers exist.
- **Border, not focus-ring.** Hyprland drew a border around every window;
  niri's `focus-ring` (active window) is disabled and `border` (all windows) is
  enabled with width 2.
- **Key conflicts resolved.** Hyprland rebound keys; niri rejects duplicates.
  Focus wins for `Super+H/J/L`, and lock moved to `Super+Alt+L`.
- **No output mirroring.** Hardware mirroring does not exist in niri 26.04;
  use `wl-mirror` as a window if needed.
- **No live effect preview.** `niri_effects.sh` writes and reloads; call it on
  slider release, not per frame.
- **Recording is external.** Use OBS (screencast portal) or `wf-recorder`; the
  old `gpu-screen-recorder` path is not ported.
- **`GDK_BACKEND` is not set.** A global `wayland` value breaks the screencast
  portal; the KDL `environment {}` deliberately omits it.

## Graphical substitutions

Where a Hyprland visual feature has no niri equivalent, it is replaced by a
valid alternative rather than dropped silently.

| Hyprland feature | niri substitute |
| --- | --- |
| Per-window `immediate` (tearing) | `variable-refresh-rate on-demand=true` on the output + `variable-refresh-rate true` on game windows |
| Layer blur per namespace (`ignore_alpha`) | `layer-rule { background-effect { blur true; xray true } }` + global `blur {}` |
| `dim_inactive` / `dim_strength` | `window-rule { match is-active=false; opacity 0.80 }` |
| `borderangle` / `fade*` animation leaves | springs (`window-movement`, `workspace-switch`, `horizontal-view-movement`) |
| Special workspace (scratchpad overlay) | named workspace `scratch` focused with `Super+A` |
| `center` floating rule | remembered floating position (`default-floating-position`) |
| `pin` window | move to a persistent named workspace, or keep it floating |
| `shadow.render_power` | not exposed; `shadow.softness` is the control |
| Output mirroring | no hardware mirror; run `wl-mirror` as a window |
| `hyprpicker` | `niri_pick_color.sh` (niri pick-color / screenshot UI) |
| Screenshot `--edit` annotation | pipe the capture to `satty` in `niri_screenshot.sh` |

## Requirements

- niri 26.04+ with `xwayland-satellite >= 0.7`.
- `jq` and `python3` for the scripts.
- For capture/annotation: `grim`, `slurp`, `satty`, `wl-clipboard`.
- The shared equisdots payload (Quickshell shell, settings.json, palettes) from
  the other repositories; `install.sh` calls a meta installer when present.

## License

See `LICENSE`.
