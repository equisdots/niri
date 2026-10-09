# generated/

Runtime-generated niri config fragments. They are included with
`optional=true` at the end of `../config.kdl`, so niri loads fine before the
first write and live-reloads the whole tree when any of them changes.

Do not commit the `.kdl` files: only this README and `.gitkeep` are tracked
(see the repository `.gitignore`). Each writer regenerates the whole fragment
from its own source of truth, so partial edits do not survive.

| File | Writer | Content |
| --- | --- | --- |
| `theme-colors.kdl` | `scripts/niri_write_borders.sh` (called by the shell backend) | `layout { border { active-color ... inactive-color ... } }`, deep-merged over `modules/layout.kdl`. |
| `theme-effects.kdl` | `scripts/niri_effects.sh` | Generated `layout { gaps; struts; border { width }; shadow { ... } }` and the global `blur { passes; offset }` block. |
| `outputs.kdl` | `scripts/niri_monitor_apply.sh` (save) / `scripts/niri_monitor_manager.sh save` | One `output "make model serial" { mode; scale; position; transform; variable-refresh-rate; off }` block per saved monitor. |
| `user-binds.kdl` | shell Config.qml under niri (pending port) | `binds { ... }` generated from `settings.json`. |
| `user-startup.kdl` | shell Config.qml under niri (pending port) | Extra `spawn-at-startup` / `spawn-sh-at-startup` entries. |

Notes:

- `theme-colors.kdl` is included before `theme-effects.kdl`, and both before
  `outputs.kdl`; later includes deep-merge over earlier ones.
- The state file behind `theme-effects.kdl` lives at
  `~/.config/niri/window-effects.json` and is managed by
  `scripts/niri_effects.sh`.
- `~/.config/niri/generated/` is created by the writers; it must already exist
  for niri's config watcher to see the files appear.
