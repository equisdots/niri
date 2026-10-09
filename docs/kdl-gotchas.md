# niri KDL gotchas

Practical notes on the KDL syntax niri accepts, and how a syntax error behaves
at runtime. The config here targets niri 26.04.

## The one-line block gotcha

KDL allows children on the same line as their parent, but niri's parser
requires the last child in a block to be terminated by `;` or a newline before
the closing `}`. A one-line block whose last node is not terminated is a parse
error.

```kdl
// INVALID: no ; or newline before }
window-rule { match app-id="^(kitty)$"; open-floating true }
focus-ring { off }

// VALID: multi-line block (preferred)
window-rule {
    match app-id="^(kitty)$"
    open-floating true
}
focus-ring {
    off
}

// VALID: one-line block with a trailing ;
window-rule { match app-id="^(kitty)$"; open-floating true; }
focus-ring { off; }
```

Either keep blocks multi-line (what `modules/window-rules.kdl` and every
generated fragment do here) or terminate the last node with `;`.

## What happens on an invalid config

niri does not stop with a visible error. It **silently falls back to its
default config**, which looks like a grey screen plus the "Important Hotkeys"
overlay. The session is running; it is just not using your config. If the
desktop suddenly looks default after an edit, suspect a parse error first.

Because a bad fragment can be written and loaded between checks, the runtime
generators run `niri validate` before forcing a reload (`scripts/lib/common.sh`
provides `niri_validate` / `niri_reload`), so a broken fragment is not applied
to a live session.

## Generated fragments

Everything under `generated/` is produced by a writer (a script or the shell
backend) and must be **valid multi-line KDL**:

- `borders.kdl` — shell backend (`Compositor.setWindowBorders`)
- `theme-colors.kdl` — `scripts/niri_write_borders.sh`
- `theme-effects.kdl` — `scripts/niri_effects.sh`
- `outputs.kdl` — `scripts/niri_monitor_apply.sh` / `niri_monitor_manager.sh save`
- `user-binds.kdl`, `user-startup.kdl` — the shell

They are atomically replaced (write to a temp file, then `mv`), and a partial
edit does not survive: the next write regenerates the whole file. Do not edit
them by hand.

## include ordering and optional

`config.kdl` includes the static modules first, then the generated fragments at
the end, so the generated values win. Includes are positional and later
definitions deep-merge over earlier ones for the same section/property.

```kdl
include "modules/layout.kdl"

include optional=true "generated/theme-colors.kdl"
include optional=true "generated/borders.kdl"   // after theme-colors, so it wins
include optional=true "generated/theme-effects.kdl"
```

`optional=true` (niri 26.04) downgrades a missing file to a warning, so the
config loads before the first writer has run and still reloads when the file
appears. Keep the `generated/` directory itself present; niri's watcher only
sees files appear inside a directory it already knows.

Some sections are single-occurrence (`input`, `animations`, `blur`): defining
them twice, for example in a module and in a generated fragment, is a
`niri validate` error rather than a merge.

## Validate

Always validate the assembled tree before starting or trusting a session:

```sh
niri validate -c ~/.config/niri/config.kdl
```

`niri validate` exits non-zero and prints the offending line on a parse error.
A running niri also live-reloads watched files on save, so a valid edit applies
without a restart; a quick `niri validate` after editing is still the fastest
way to catch the one-line-block mistake.
