# pomo

An eye-catching pomodoro timer for your terminal — pure Bash, no external
dependencies beyond `coreutils`, `tput` (ncurses) and `notify-send`.

```
                FOCUS SESSION

              ┌─────────────────────────────────┐
              │ █████  █████     █████  █████   │
              │ █████  █████     █████  █████   │
              │  ...
              └─────────────────────────────────┘

           ▓▓▓▓▓▓▓▓▓▓▓▓▓▓░░░░░░░░░░░░░░░░░░░░░░
           Elapsed 10:30 of 25:00  ·  42%
           [q] quit   [p] pause   [s] skip
```

> Screenshot placeholder — run `pomo` and take a real screenshot, then drop it
> here as `screenshot.png`.

## Features

- Large `MM:SS` timer rendered from Unicode block characters (`█`)
- Horizontal progress bar (`▓` filled / `░` remaining)
- Unicode box border around the timer
- Per-mode colors: focus = green/cyan, short break = yellow, long break = blue/magenta
- Flicker-free redraw (ANSI cursor-home, no full-screen clear per tick)
- Non-blocking key input: `p` pause, `s` skip, `q` quit
- Automatic cycle: every 4th completed focus session earns a long break,
  the others a short break (you confirm before the next session starts)
- Desktop notification (`notify-send -u critical`) + terminal bell when a
  session ends
- Session history and `pomo stats` with today's summary and a 7-day chart
- Safe terminal restore on Ctrl+C (alternate screen, cursor, `stty`)

## Requirements

- Linux, bash 4.0 or newer
- `tput` (ncurses), standard `coreutils`
- `notify-send` (optional — the bell works without it)

## Usage

```console
$ pomo              # start a 25 minute focus session
$ pomo start        # same as above
$ pomo -w           # short break (5 minutes)
$ pomo -W           # long break (15 minutes)
$ pomo stats        # session statistics
$ pomo --help       # usage help
$ pomo --version    # version
```

Keys while the timer is running:

| Key | Action           |
|-----|------------------|
| `p` | Pause / resume   |
| `s` | Skip session     |
| `q` | Quit             |

Sessions are only logged when they complete — a skipped session writes
nothing.

## Configuration

Default durations are constants at the top of the `pomo` script:

```bash
FOCUS_SECONDS="${POMO_FOCUS_SECONDS:-1500}"        # 25 minutes
SHORT_BREAK_SECONDS="${POMO_SHORT_BREAK_SECONDS:-300}"  # 5 minutes
LONG_BREAK_SECONDS="${POMO_LONG_BREAK_SECONDS:-900}"    # 15 minutes
readonly CYCLES_BEFORE_LONG=4
```

Change the defaults by editing those lines, or override per run:

```console
$ POMO_FOCUS_SECONDS=1800 pomo    # 30 minute focus session
```

## Data

Completed sessions are appended to
`~/.local/share/pomo/history.log` (respects `XDG_DATA_HOME`) as:

```
2026-10-16|focus|1500
2026-10-16|short_break|300
```

## Installation

### Manual

```console
$ sudo install -Dm755 pomo /usr/local/bin/pomo
```

Or without root: `install -Dm755 pomo ~/.local/bin/pomo` (make sure
`~/.local/bin` is on your `PATH`).

### Debian package

Build the `.deb` (on Debian/Ubuntu, or anywhere `dpkg-deb` is installed):

```console
$ ./build-deb.sh
# -> build/pomo_1.0.0-1_all.deb
$ sudo apt install ./build/pomo_1.0.0-1_all.deb   # installs /usr/bin/pomo
```

Full debhelper build is also available inside `debian/`:

```console
$ dpkg-buildpackage -us -uc
```

## License

MIT — see [LICENSE](LICENSE).
