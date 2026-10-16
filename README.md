# pomo

An eye-catching pomodoro timer for your terminal — pure Bash, no external
dependencies beyond `coreutils`, `tput` (ncurses) and `notify-send`.

![pomo focus session](assets/screenshot.png)

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
pomo              # start a 25 minute focus session
pomo start        # same as above
pomo -w           # short break (5 minutes)
pomo -W           # long break (15 minutes)
pomo stats        # session statistics
pomo update       # update to the latest version from GitHub
pomo --help       # usage help
pomo --version    # version
```

Keys while the timer is running:

| Key | Action                                |
|-----|---------------------------------------|
| `p` | Pause / resume                        |
| `s` | Skip session                          |
| `m` | Open the menu                         |
| `q` | Quit                                  |

Menu (opened with `m`, the timer is frozen while it is open):

| Key | Action                                  |
|-----|-----------------------------------------|
| `1` | Start a focus session                   |
| `2` | Start a short break                     |
| `3` | Start a long break                      |
| `h` | Help                                    |
| `t` | Session statistics                      |
| `b` | Back to the timer (Enter works too)     |
| `q` | Quit                                    |

Switching sessions from the menu abandons the current session without
logging it, exactly like `s` (skip).

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
POMO_FOCUS_SECONDS=1800 pomo    # 30 minute focus session
```

## Data

Completed sessions are appended to
`~/.local/share/pomo/history.log` (respects `XDG_DATA_HOME`) as:

```
2026-10-16|focus|1500
2026-10-16|short_break|300
```

## Installation

### Quick install (one command)

Downloads the single self-contained script into `~/.local/bin` (no root
required), then run `pomo` from any terminal:

```console
mkdir -p ~/.local/bin \
    && curl -fsSL https://raw.githubusercontent.com/Yapidev/pomodoro_cli/main/pomo \
        -o ~/.local/bin/pomo \
    && chmod +x ~/.local/bin/pomo
```

No `curl`? Use `wget` instead:

```console
mkdir -p ~/.local/bin \
    && wget -O ~/.local/bin/pomo \
        https://raw.githubusercontent.com/Yapidev/pomodoro_cli/main/pomo \
    && chmod +x ~/.local/bin/pomo
```

Open a **new terminal** (so the refreshed `PATH` is picked up) and start it:

```console
pomo
```

If your shell says `pomo: command not found`, `~/.local/bin` is not on your
`PATH` yet — add it:

```console
echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.bashrc && source ~/.bashrc
```

Notes:

- The URL tracks the `main` branch, so the one-liner always installs the
  latest version. To pin a release, replace `main` with a tag
  (`https://raw.githubusercontent.com/Yapidev/pomodoro_cli/v1.0.0/pomo`).
- Updating = run `pomo update` (downloads the latest version from GitHub and
  replaces itself), or simply re-run the install command above — the file is
  overwritten either way. Session history is never touched.
- Uninstalling = `rm ~/.local/bin/pomo`. Your session history in
  `~/.local/share/pomo/` is left untouched.
- Prefer to inspect what you run? It is one plain Bash file:
  `less ~/.local/bin/pomo` before your first run.

### Manual

Download the script however you like (clone, browser, etc.), then:

```console
sudo install -Dm755 pomo /usr/local/bin/pomo
```

Or without root: `install -Dm755 pomo ~/.local/bin/pomo` (make sure
`~/.local/bin` is on your `PATH`).

### Debian package

Build the `.deb` (on Debian/Ubuntu, or anywhere `dpkg-deb` is installed):

```console
./build-deb.sh
# -> build/pomo_1.0.0-1_all.deb
sudo apt install ./build/pomo_1.0.0-1_all.deb   # installs /usr/bin/pomo
```

Full debhelper build is also available inside `debian/`:

```console
dpkg-buildpackage -us -uc
```

## License

MIT — see [LICENSE](LICENSE).
