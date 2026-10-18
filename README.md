# pomo

A pretty pomodoro timer for your terminal — one Bash file, nothing else
to install.

![pomo focus session](assets/screenshot_new.png)

Big block-digit countdown, progress bar, colors, desktop notifications
and a session log. Press `pomo` and start focusing.

## Install

One command, no root:

```console
mkdir -p ~/.local/bin \
    && curl -fsSL https://raw.githubusercontent.com/Yapidev/pomo/main/pomo \
        -o ~/.local/bin/pomo \
    && chmod +x ~/.local/bin/pomo \
    && echo "Installed $(~/.local/bin/pomo --version)"
```

No `curl`? Swap it for `wget -O ~/.local/bin/pomo <same-url>`.

Open a new terminal (so `~/.local/bin` is on your `PATH`) and run:

```console
pomo
```

- `pomo: command not found`? Add the bin dir:
  `echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.bashrc`
- Update later with `pomo update`
- Uninstall with `rm ~/.local/bin/pomo` (your history stays)
- It is one plain script — `less ~/.local/bin/pomo` before your first run
  if you like to know what you execute

<details>
<summary>Debian package</summary>

```console
./build-deb.sh
sudo apt install ./build/pomo_*_all.deb
```

</details>

<details>
<summary>From a clone</summary>

```console
sudo install -Dm755 pomo /usr/local/bin/pomo
```

</details>

## Keys

While the timer runs:

| Key | Action         |
|-----|----------------|
| `p` | Pause / resume |
| `s` | Skip session   |
| `m` | Menu           |
| `q` | Quit           |

Inside the menu (`m`): `1` focus · `2` short break · `3` long break ·
`c` cycle theme · `t` stats · `h` help · `b` back · `q` quit.

Only **completed** sessions are logged — skipping or switching writes nothing.

## Commands

| Command         | What it does                       |
|-----------------|------------------------------------|
| `pomo`          | Start a focus session (25 min)     |
| `pomo -w`       | Short break (5 min)                 |
| `pomo -W`       | Long break (15 min)                |
| `pomo resume`   | Resume an interrupted session       |
| `pomo stats`    | Today's summary + 7-day chart      |
| `pomo status`   | One-line status for status bars    |
| `pomo config`   | Show config file + durations       |
| `pomo theme`    | Show / pick a color theme          |
| `pomo update`   | Self-update from GitHub            |
| `pomo --help`   | Everything above, in the terminal |

The cycle is automatic: every 4th completed focus session is followed by
a long break, the others by a short break. You confirm before each next
session starts.

## Themes

Seven looks are built in: `default`, `dracula`, `gruvbox`, `nord`,
`solarized`, `matrix`, `mono`.

```console
pomo theme nord       # switch (saved in ~/.config/pomo/theme)
POMO_THEME=matrix pomo # just for this one run
```

Or press `c` in the menu to flip through them live — each pick is
saved automatically.

## Custom durations

Per run:

```console
POMO_FOCUS_SECONDS=1800 pomo        # 30 min focus
POMO_SHORT_BREAK_SECONDS=600 pomo -w # 10 min short break
POMO_LONG_BREAK_SECONDS=1200 pomo -W # 20 min long break
POMO_ANIMATION=off pomo             # disable the pixel animations
```

Or permanently, in `~/.config/pomo/pomo.conf`:

```console
FOCUS_SECONDS=1800        # 30 min
SHORT_BREAK_SECONDS=600
LONG_BREAK_SECONDS=1200
```

Keys are case-insensitive, `#` starts a comment, unknown keys are ignored.
Precedence: environment variable > `pomo.conf` > default.
`pomo config` shows the file path and the durations currently in effect.

## Status bar

`pomo status` prints one plain line — `focus 12:34`,
`short break 03:21 (paused)`, or `idle` — and exits `0` while a
session is running (`1` otherwise). Drop it straight into a bar:

```console
# tmux
set -g status-right '#(pomo status)'
```

```json
// waybar
"custom/pomo": { "exec": "pomo status", "interval": 1 }
```

The running timer publishes its state in
`${XDG_RUNTIME_DIR:-~/.local/share/pomo}/pomo.state`, so `pomo status`
works from any other terminal.

## Interrupted sessions

If pomo is killed or the terminal closes mid-session, the remaining time
is kept — `pomo resume` continues where it stopped, with the progress
bar still scaled to the full session. Completed sessions are logged with
their full duration, even when finished across multiple sittings.

A session that already ran out of time while pomo was closed is
discarded: `pomo resume` says so and logs nothing.

## Notifications

By default pomo rings the terminal bell and sends a desktop
notification with `notify-send`. Want a sound, a webhook, or something
else instead? Set a hook (in `pomo.conf` or via `POMO_NOTIFY_CMD`):

```console
NOTIFY_CMD=paplay /usr/share/sounds/freedesktop/stereo/complete.oga
NOTIFY_CMD=notify-send -u normal pomo "$1" && paplay bell.ogg
```

The hook receives the title and the message as `$1` and `$2`.

The timer animates like a pixel display: digits light up pixel by pixel
at session start and the colon blinks every second —
`POMO_ANIMATION=off` turns all of it off.

## Where is my data?

Completed sessions are appended to
`~/.local/share/pomo/history.log` (`XDG_DATA_HOME` respected) as
`date|type|seconds`, e.g.:

```
2026-10-16|focus|1500
```

Plain text — grep it, back it up, or delete it. That is all pomo stores.

## Development

```console
tests/run_tests.sh    # pure-Bash test suite, no framework needed
```

## License

MIT — see [LICENSE](LICENSE).
