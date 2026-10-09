# systemd user units

Optional user units for the equisdots niri session. They are **not** required:
`modules/autostart.kdl` already starts the shell, the wallpaper daemon, the
focus daemon and the shared scripts through `spawn-sh-at-startup`. The units
exist so a daemon can be monitored, restarted and ordered individually.

Every unit uses the same session dependency block:

```ini
[Unit]
PartOf=graphical-session.target
After=graphical-session.target
Requisite=graphical-session.target
```

`PartOf=` ties the unit's start/stop to the target, `After=` orders it after
the target, and `Requisite=` ensures it only starts when the target is active.

| Unit | Purpose |
| --- | --- |
| `swayidle.service` | Idle: lock, `niri msg action power-off-monitors`, suspend. |
| `quickshell.service` | The Quickshell bar/shell. |
| `xwww.service` | The xwww wallpaper daemon. |
| `focus-daemon.service` | The focus-time tracker for the shell panel. |

## Install

Copy the units into the user unit directory, then reload and attach them to
`niri.service`:

```sh
mkdir -p ~/.config/systemd/user
cp systemd/*.service ~/.config/systemd/user/
systemctl --user daemon-reload

systemctl --user add-wants niri.service swayidle.service
systemctl --user add-wants niri.service quickshell.service
systemctl --user add-wants niri.service xwww.service
systemctl --user add-wants niri.service focus-daemon.service
```

`add-wants` creates symlinks under
`~/.config/systemd/user/niri.service.wants/`; anything linked there starts with
`niri.service` and stops when it exits.

Do not enable `quickshell.service`, `xwww.service` or `focus-daemon.service`
while the matching `spawn-sh-at-startup` lines are still present in
`modules/autostart.kdl`; you would start two instances. Remove the line first.

## Remove / inspect

```sh
rm ~/.config/systemd/user/niri.service.wants/swayidle.service
systemctl --user daemon-reload

systemctl --user status swayidle.service
systemctl --user restart swayidle.service
journalctl --user-unit=niri -b --no-pager
```

`niri_idle_mode.sh` uses `swayidle.service` automatically when it is installed;
otherwise it starts a detached `swayidle` process (the old hypridle behavior).
