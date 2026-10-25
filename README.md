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
| `~/.config/niri/modules/*.kdl` | `config/niri/modules/` | The translated Hyprland modules (layout, workspaces, rules, autostart, keys). |
| `~/.config/niri/generated/` | `config/niri/generated/` | Runtime fragments (environment, palette border colors, saved outputs, effects). |
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

Because niri cannot expand `$HOME` inside `environment {}`, and the section may
appear only once, `install.sh` seeds `~/.config/niri/generated/env.kdl` from
`config/niri/defaults/environment.kdl` with literal paths (`PATH` with
`~/.local/bin` first, `WALLPAPER_DIR`, `SCRIPT_DIR`, `XDG_PICTURES_DIR`,
`XDG_VIDEOS_DIR` and the appScale-derived variables when `appScale != 1.0`).
Delete that file and re-run `./install.sh --config-only` to regenerate it after
changing `appScale`. The shared scripts under `~/.config/hypr/scripts` are
provided by the `niri-meta` deploy, not by this repository.

## User app configs

`install.sh` runs `scripts/install-app-configs.sh` on a full install: kitty,
starship, nvim, xtop, Hack Nerd Font (user + system-wide for SDDM), the
interactive scenes and an optional wallpaper pack. `--no-apps` (or
`DOTSNIRI_NO_*` for automation) skips individual steps. Rofi/cava configs are
deployed from `config/apps/` by the installer and `dotsniri deploy`.

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

> The config is validated against the niri 26.04 binary by seeding a temporary
> `HOME` (`./install.sh --config-only`) and running
> `niri validate -c <tmp>/.config/niri/config.kdl`. Always re-run `niri validate`
> on the target machine after editing KDL; `bash -n` only checks the scripts.

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
    layout.kdl               general/decoration -> layout {}
    workspaces.kdl           workspaces.lua -> named workspaces
    window-rules.kdl         windowrules.lua -> window-rule {}
    layer-rules.kdl          layers.lua -> layer-rule {} (forced blur removed)
    autostart.kdl            autostart.lua -> spawn-sh-at-startup
    keybinds.kdl             keybinds.lua -> binds {}
  defaults/
    environment.kdl          seed for generated/env.kdl (literal paths)
    input.kdl                seed for generated/user-input.kdl
    animations.kdl           seed for generated/user-animations.kdl
    blur.kdl                 seed for generated/blur.kdl
  generated/
    README.md                generated fragments and their writers
    env.kdl*                 environment {} owner (installer seed, literal paths)
    user-input.kdl*          input {} owner (seeded, then Settings panel)
    user-animations.kdl*     animations {} owner (seeded, then Settings panel)
    blur.kdl*                blur {} owner (seeded, then effects writer)
    theme-colors.kdl*        border colors (niri_write_borders.sh)
    borders.kdl*             live border colors (shell backend, Compositor.setWindowBorders)
    theme-effects.kdl*       gaps/border/shadow (niri_effects.sh)
    outputs.kdl*             saved monitor layout (niri_monitor_apply.sh)
    user-binds.kdl*          shell-generated binds (Config.qml -> Niri backend)
    user-startup.kdl*        shell-generated startup (Config.qml -> Niri backend)

scripts/
  lib/common.sh              shared paths/logging (EQUISDOTS_CONFIG_DIR, ...)
  caching.sh                 Quickshell cache/state/run exports
  niri_workspaces.sh         workspace state daemon for the bar (event stream)
  niri_kb_fetch.sh           active keyboard layout
  niri_ws.sh                 workspace/window routing (closes popups)
  niri_scratch.sh            scratch workspace toggle + nautilus fallback
  niri_floating_app.sh       spawn -> float -> set size -> center a new window
  niri_write_borders.sh      write generated/theme-colors.kdl and reload
  niri_effects.sh            read/preview/persist gaps/border/blur/shadow
  niri_monitor_apply.sh      apply saved layout -> generated/outputs.kdl
  niri_monitor_manager.sh    list/apply outputs, position presets, save
  niri_scale.sh              scale the focused output up/down/auto
  niri_idle_mode.sh          swayidle awake/normal/boot/status
  niri_screenshot.sh         equisdots overlay (region + still/video + mic)
  niri_record.sh             gpu-screen-recorder start/stop, region via slurp
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
| `niri_scratch.sh` | (no args) toggle/focus the `scratch` workspace, launch nautilus when empty |
| `niri_floating_app.sh` | `<app-id> <width> <height> [--] <command...>` |
| `niri_effects.sh` | `read`, `preview KEY=VAL ...`, `persist`, `apply KEY=VAL ...` |
| `niri_monitor_manager.sh` | `list`, `apply NAME key=val`, `layout PRESET`, `save` |
| `niri_scale.sh` | `up`, `down`, `auto`, `<scale> [output]` |
| `niri_idle_mode.sh` | `awake`, `normal`, `boot`, `status` |
| `niri_screenshot.sh` | (default overlay), `--full`, `--full --edit`, `--window`, `--edit`, `--geometry G`, `--record`, `--scan-qr` |
| `niri_record.sh` | `toggle`, `start [screen]`, `region`, `region-geom G`, `stop`, `status` |
| `niri_workspaces.sh` | (daemon), `--once` |

Run any script with `--help` for details.

## Known differences from the Hyprland config

These are deliberate; see the comments in each module.

- **Workspaces are dynamic.** The numbered binds still work (1..0 address
  indices), but app placement uses named workspaces (`browser`, `code`, `chat`,
  `media`, `games`, `scratch`). There is no floating scratchpad overlay. The
  `scratch` approximation is smarter than a plain focus: `Super+A` focuses it,
  returns to the previous workspace when scratch is already focused, and
  launches nautilus when scratch has no windows. `Super+Shift+A` moves the
  focused window there. Numbered/page workspace binds go through
  `scripts/niri_ws.sh`, which closes Quickshell popups first; wheel scrolling
  and `Super+Tab` stay direct niri actions because the script has no interface
  for them (and a process per wheel tick would be worse).
- **Floating terminal/editor.** `Super+Shift+K` launches a centered floating
  kitty (900x560) and `Super+Shift+D` a centered floating VS Code Insiders
  (1200x800), matching Hyprland. `scripts/niri_floating_app.sh` snapshots the
  window list, follows `niri msg --json event-stream` (with a timeout and a
  windows-poll fallback), then focuses/floats/resizes/centers the new window by
  id. The bar editor remains on `Super+Shift+S`.
- **`move-floating-window` is not a bind action.** niri 26.04 exposes it over
  IPC but marks it `#[knuffel(skip)]` in the config parser, so KDL binds using
  it fail validation. The helper uses `toggle-window-floating`,
  `set-window-width`, `set-window-height` and `center-window`, all of which
  accept `--id`. Width/height use `SetFixed` logical pixels and work for
  floating windows.
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
  Focus wins for `Super+H/J/L`, lock moved to `Super+Alt+L`, and
  `maximize-column` moved to `Super+Ctrl+M` so `Super+Shift+M` can open the
  Plugins panel (the same chord as Hyprland).
- **No output mirroring.** Hardware mirroring does not exist in niri 26.04;
  use `wl-mirror` as a window if needed.
- **No live effect preview.** `niri_effects.sh` writes and reloads; call it on
  slider release, not per frame.
- **Screenshots open the equisdots overlay** (`Print`), the same UI as Hyprland:
  pick a region and choose screenshot vs. video and microphone on/off.
  `scripts/niri_screenshot.sh` launches the screenshots plugin's Quickshell
  overlay (with the legacy root path as a fallback) and handles the capture;
  the overlay calls back into the niri script through
  `EQUISDOTS_SCREENSHOT_SCRIPT` (shipped by `niri-shell`). `Super+Print` takes a
  native full-output still; `Super+Shift+Print` captures the focused output with
  `grim` and opens it in `satty` (the `--full --edit` path), so the edit route
  is no longer swallowed by the native screenshot action.
- **Plugins are Quickshell-side and compositor-neutral.** `niri-meta` deploys
  the plugin standard (`plugin-api`, `plugin-sdk`, the `plugins` hub, the
  default plugins and their registry), so the same 63 plugins, MD3 theme
  tokens, plugin popups/positions and bar modules run on niri. `Super+Shift+M`
  opens the Plugins panel. Plugin-provided keybind actions are covered by the
  static binds below (clipboard, quicknotes, RSS, file search, screenshots,
  timex), because niri reads KDL rather than evaluating plugin `hypr.lua`
  fragments at runtime.
- **Recording uses the same engine as Hyprland: `gpu-screen-recorder`.** It is
  self-contained in `scripts/niri_record.sh` (no dependency on the Hyprland
  repo): `Super+Alt+R` toggles a full-screen recording and `Super+Alt+Shift+R`
  records a region picked with `slurp`. Recordings go to
  `${XDG_VIDEOS_DIR:-$HOME/Videos}/Recordings`, and the pid cache
  (`~/.cache/quickshell/recording/rec_pid`) drives the bar's recording
  indicator, so the widget's stop button works too. `install.sh` adds
  `gpu-screen-recorder` as an optional package (AUR / COPR on some distros).
  OBS over the screencast portal remains an alternative.
- **`GDK_BACKEND` is not set.** A global `wayland` value breaks the screencast
  portal; the KDL `environment {}` deliberately omits it.
- **Idle/lock is started by autostart.** `modules/autostart.kdl` calls
  `scripts/niri_idle_mode.sh boot` exactly once, matching Hyprland's
  `idle-mode.sh boot`. The script uses the optional systemd
  `swayidle.service` when installed, otherwise a detached `swayidle`. Do not
  also attach `swayidle.service` to `niri.service`; autostart is the owner.
- **Packages follow the binds and bar.** `install.sh` installs the user-facing
  tools (`kitty`, `rofi`, `playerctl`, `brightnessctl`, `pamixer`, `ddcutil`,
  `nautilus`, `pavucontrol`, NetworkManager applet, `blueman`, `gnome-keyring`,
  a polkit agent, `qt6ct`, Noto fonts, adw-gtk3, Papirus, `fd`, `ripgrep`,
  `python`, ImageMagick, ffmpeg, `cava`, `power-profiles-daemon`, ...) and
  keeps AUR/COPR/PPA-only tools optional. On Debian/Ubuntu `fd-find` installs
  the binary as `fdfind`; the file-search plugin expects `fd`.

## Keybind parity with Hyprland

The full translated bind set lives in `config/niri/modules/keybinds.kdl`. These
are the binds changed in the latest parity pass (niri 26.04 action names):

| Bind | Action |
| --- | --- |
| `Super+Shift+K` | Floating centered kitty 900x560 (`scripts/niri_floating_app.sh`) |
| `Super+Shift+D` | Floating centered VS Code Insiders 1200x800 (`scripts/niri_floating_app.sh`) |
| `Super+Shift+S` | Bar editor (unchanged; `Super+Shift+D` no longer opens it) |
| `Super+Shift+Q` | `quit skip-confirmation=true` (Hyprland exit chord) |
| `Super+Escape` | `quit skip-confirmation=true` (skips the confirmation) |
| `Super+G` | `center-window` (Hyprland centers the active window, not the column) |
| `Super+Alt+Shift+I/U` | `move-window-to-monitor-right/left` (active window, not column) |
| `Super+Alt+Shift+M` | `niri_monitor_manager.sh info` |
| `Super+A` | Scratch toggle (`scripts/niri_scratch.sh`) |
| `Super+Shift+A` | Move focused window to `scratch` via `niri_ws.sh scratch move` |
| `Super+Shift+Print` | Full focused-output capture -> `satty` editor |
| `Super+1..0`, `Super+Shift+1..0` | `niri_ws.sh <n> [move]` (closes Quickshell popups) |
| `Super+Page_Up/Page_Down` | `niri_ws.sh prev/next` (closes Quickshell popups) |

`Super+Shift+Up` remains `move-window-up`; `Super+WheelScrollUp/Down` and
`Super+Tab` stay direct niri actions (no `niri_ws.sh` verb; the wheel bind keeps
its `cooldown-ms`).

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
| Special workspace (scratchpad overlay) | named workspace `scratch`: `Super+A` focuses/returns/launches nautilus when empty via `niri_scratch.sh` |
| `center` floating rule | remembered floating position (`default-floating-position`) |
| `pin` window | move to a persistent named workspace, or keep it floating |
| `shadow.render_power` | not exposed; `shadow.softness` is the control |
| Output mirroring | no hardware mirror; run `wl-mirror` as a window |
| `hyprpicker` | `niri_pick_color.sh` (niri pick-color / screenshot UI) |
| Screenshot `--edit` annotation | pipe region or `--full` focused-output capture to `satty` in `niri_screenshot.sh` |

## Requirements

- niri 26.04+ with `xwayland-satellite >= 0.7`.
- `jq` and `python3` (Arch `python`) for the scripts.
- For capture/annotation: `grim`, `slurp`, `satty`, `wl-clipboard`, `zbar`
  (Debian `zbar-tools`) and `gpu-screen-recorder` (Debian
  `gpu-screen-recorder-cli`) for recording.
- User-facing tools installed by `install.sh`: `kitty`, `rofi`, `rofi-emoji`,
  `playerctl`, `brightnessctl`, `pamixer`, `ddcutil`, `nautilus`,
  `pavucontrol`, NetworkManager applet, `blueman`, `gnome-keyring`, `libsecret`,
  a polkit agent, `qt5ct`/`qt6ct`, Qt5/Qt6 Wayland, PipeWire ALSA/pulse,
  NetworkManager/BlueZ, GVfs, Noto fonts (including CJK), adw-gtk3, Papirus
  icons, `fd`, `ripgrep`, ImageMagick, `librsvg`, ffmpeg, `cava`,
  `power-profiles-daemon`, `lm_sensors`, `iw`, `xdg-utils`, `inotify-tools`,
  `socat`, `mpvpaper` (video wallpapers), `satty`, `zbar` and
  `gpu-screen-recorder`. Optional AUR extras: `envycontrol` and Bibata cursors.
- `qt6-multimedia` is **required**, not optional: `DavincixPicker.qml` and
  `DavincixCard.qml` import `QtMultimedia`, and without the QML module the
  wallpaper picker fails to load (`module "QtMultimedia" is not installed`).
- On Arch, `install.sh` ensures an AUR helper exactly like the Hyprland
  installer: it prefers `paru`, then `yay`, and builds `yay` from the AUR with
  `git` + `base-devel` when neither is present, so AUR-only extras are not
  silently skipped. Other distros keep those extras optional.
- For the plugin set: `cliphist` (clipboard), `fd` (file search) and `jq`
  (scan/registry) in addition to the shell's own dependencies. On Debian/Ubuntu
  the `fd-find` package installs `fdfind`, not `fd`.
- The shared equisdots payload (Quickshell shell, `~/.config/hypr/scripts`,
  settings.json, palettes) from the other repositories, deployed by
  `niri-meta`; this repository does not duplicate those scripts. `install.sh`
  warns when the payload is missing and calls a meta installer when present.

## License

See `LICENSE`.
