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

## Configuration authoring (KDL strictness)

niri's KDL parser is strict. A block whose **last node is not terminated** by
`;` or a newline before `}` fails to parse:

```kdl
// INVALID: the last node (open-floating) is not terminated before }
window-rule { match app-id="^(kitty)$"; open-floating true }

// VALID: multi-line block
window-rule {
    match app-id="^(kitty)$"
    open-floating true
}

// VALID: one-line block with a trailing ;
focus-ring { off; }
```

An invalid config makes niri **silently fall back to its default config**: a
grey screen with the "Important Hotkeys" overlay, no error on screen. This is
why every rule in `modules/window-rules.kdl` and every generated fragment uses
multi-line blocks (see `docs/kdl-gotchas.md`).

Always validate before trusting a running session:

```sh
niri validate -c ~/.config/niri/config.kdl
```

Saving a watched file live-reloads it, but a bad fragment can still be loaded
if it is written between validations; the generators run `niri validate` before
forcing a reload, so a broken runtime fragment is not applied.

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
    layer-rules.kdl          layers.lua -> layer-rule {} (forced blur removed)
    autostart.kdl            autostart.lua -> spawn-sh-at-startup
    keybinds.kdl             keybinds.lua -> binds {}
  generated/
    README.md                generated fragments and their writers
    theme-colors.kdl*        border colors (niri_write_borders.sh)
    borders.kdl*             live border colors (shell backend, Compositor.setWindowBorders)
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
  enabled with width 2. The default border is a neutral grey; the shell refines
  it from the palette's muted colour (`color8`), not the loud accent, through
  `generated/borders.kdl`.
- **No forced layer blur.** Hyprland's namespace blur used `ignore_alpha`, which
  niri 26.04 does not have. Forcing blur on the large, mostly transparent
  Quickshell panels painted a full-screen blur sheet, so the layer rules no
  longer force it. Surfaces that request blur via `ext-background-effect` are
  still blurred with the global `blur {}` settings.
- **No separate notification daemon.** The Quickshell shell registers
  `org.freedesktop.Notifications` itself and renders palette-aware
  notifications; no `mako`/`dunst` is installed (a rival daemon would win the
  D-Bus name and use its own colours).
- **Key conflicts resolved.** Hyprland rebound keys; niri rejects duplicates.
  Focus wins for `Super+H/J/L`, and lock moved to `Super+Alt+L`.
- **No output mirroring.** Hardware mirroring does not exist in niri 26.04;
  use `wl-mirror` as a window if needed.
- **No live effect preview.** `niri_effects.sh` writes and reloads; call it on
  slider release, not per frame.
- **Recording uses the same recorder as Hyprland.** `gpu-screen-recorder` via
  the shared `~/.config/hypr/scripts/screenshot.sh` (compositor agnostic:
  `gpu-screen-recorder` + `grim` + `slurp` + `wl-clipboard`); that script does
  not use `hyprctl`, so it runs unchanged on niri. `install.sh` adds
  `gpu-screen-recorder` as an optional package (it may live in the AUR / a COPR),
  and `niri_screenshot.sh --record` forwards to the shared script. OBS over the
  screencast portal remains an alternative.
- **`GDK_BACKEND` is not set.** A global `wayland` value breaks the screencast
  portal; the KDL `environment {}` deliberately omits it.

## Graphical substitutions

Where a Hyprland visual feature has no niri equivalent, it is replaced by a
valid alternative rather than dropped silently.

| Hyprland feature | niri substitute |
| --- | --- |
| Per-window `immediate` (tearing) | `variable-refresh-rate on-demand=true` on the output + `variable-refresh-rate true` on game windows |
| Layer blur per namespace (`ignore_alpha`) | No forced layer blur (niri has no `ignore_alpha`); surfaces that request `ext-background-effect` are blurred with the global `blur {}` tuning |
| Accent-coloured active border | Neutral grey default; shell refines it from the palette muted colour (`color8`) via `generated/borders.kdl` |
| `mako` / `dunst` notification daemon | The Quickshell shell registers `org.freedesktop.Notifications` itself (palette-aware) |
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
