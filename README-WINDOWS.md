# Pomo 1.9.0 — Windows + WSL activity integration (development build)

This build keeps Pomo's original Linux desktop tracker and adds two optional
collectors when Pomo runs inside WSL:

- `windows-tracker.ps1`: Windows foreground application, idle and aggregate
  keyboard/mouse activity.
- `wsl-process-tracker.py`: Linux `/proc` process observations for the current
  WSL user.

The Bash TUI remains the controller. Both collectors start only for a focus
session, pause with Pomo's pause/menu state, and stop when that focus session
ends.

## Install into the repository checkout

Back up the current files first, then copy these three files into the root of
the Pomo repository, replacing `pomo` and the Windows tracker and adding the
WSL tracker:

```bash
cp pomo pomo.before-wsl-process
cp windows-tracker.ps1 windows-tracker.before-wsl.ps1 2>/dev/null || true
cp wsl-process-tracker.py wsl-process-tracker.before.py 2>/dev/null || true
chmod +x pomo wsl-process-tracker.py
bash -n ./pomo
python3 -m py_compile ./wsl-process-tracker.py
./pomo config
```

Run `./pomo`, not an older globally installed `pomo` command, while testing.
Python 3 is required for the WSL `/proc` collector. No third-party Python
packages or root privileges are required.

## Configuring WSL process filters

The WSL process collector has a default ignore list:

```ini
WSL_IGNORED_PROCESSES=systemd,_sd-pam_,bash,sh,dash,zsh,fish,powershell.exe,pwsh.exe
```

Set this option in `~/.config/pomo/pomo.conf`, or in
`$XDG_CONFIG_HOME/pomo/pomo.conf` when XDG_CONFIG_HOME is set.

The value is a comma-separated list of process names. A custom list replaces
the default list; it does not append to it. Names are normalized to lowercase.

For example, to also hide Python and sleep processes:

```ini
WSL_IGNORED_PROCESSES=systemd,_sd-pam_,bash,sh,dash,zsh,fish,powershell.exe,pwsh.exe,sleep,python3
```

To disable all filtering and show every visible process:

```ini
WSL_IGNORED_PROCESSES=none
```

The environment variable `POMO_WSL_IGNORED_PROCESSES` takes precedence over
the config file. For example:

```bash
POMO_WSL_IGNORED_PROCESSES=none ./pomo start
```

The setting is read when Pomo starts. Changes apply to subsequent Pomo runs.

## What is recorded

### Windows collector

- Foreground Windows executable name and app-change timestamps.
- One-second app/idle samples.
- Aggregate keyboard key-down and mouse button-down counts.
- No typed text, key codes, button identities, mouse coordinates, clipboard,
  window titles, or screenshots.

### WSL process collector

- Process names for processes owned by the Linux user running Pomo.
- First-observed and exit events, with PID used only to correlate a process
  instance in the raw local event log.
- Cumulative observed runtime per process name, based on one-second `/proc`
  sampling.
- No command-line arguments, environment variables, file contents, or input.

The WSL collector reads `/proc/<pid>/status`, `comm`, and `stat`. It does not
read `/proc/<pid>/cmdline` or `/proc/<pid>/environ`. Processes shorter than the
poll interval can be missed. A process already running when monitoring starts
is recorded as `process_seen`, not claimed to have started during the focus
session. The scope is all visible processes owned by the current Linux user,
including shells and background tools; it is not limited to programs launched
after Focus starts. Process runtime is not foreground/active-use time; processes
can run concurrently, so summed process runtime can exceed the focus duration.

Both collectors pause when Pomo is paused or the menu is open. The WSL monitor
uses `monitor_pause` and `monitor_resume` markers and does not add paused time
to process runtime.

## Data files

Under `$XDG_DATA_HOME/pomo` or `~/.local/share/pomo`:

- `windows-*.jsonl`: Windows app changes, samples, input totals and lifecycle.
- `wsl-process-*.jsonl`: WSL process observations, exits, runtime and lifecycle.
- `activity.log`: compact session recap. New rows append WSL process totals as
  an eleventh field; older ten-field rows remain readable.

Inspect a recent WSL process log:

```bash
latest=$(ls -t ~/.local/share/pomo/wsl-process-*.jsonl | head -n 1)
grep -E '"type":"(process_seen|process_exit|process_usage|monitor_pause|monitor_resume)"' "$latest"
./pomo recap last
```

The recap labels WSL values as **observed process runtime**, not as active
application time.

## Tests

Run the static/import compatibility tests. These also verify WSL filter configuration parsing and environment-variable precedence:

```bash
./test-pomo-wsl-integration.sh
```

Run the real `/proc` collector tests. These verify default, custom and disabled
process filters, as well as pause/resume boundaries:

```bash
./test-wsl-process-tracker.sh
```

Then test a real short focus session:

```bash
POMO_FOCUS_SECONDS=30 POMO_ANIMATION=off ./pomo start
```

Open a terminal in WSL and run a process such as `sleep 8` or a small Python
script while the focus session is active. After the session:

```bash
./pomo recap last
ls -lt ~/.local/share/pomo/wsl-process-*.jsonl | head
```

## Limitations

This is a development integration build, not yet a released Debian package.
The existing Linux desktop tracker is unchanged. Windows monitoring is used
when WSL is detected and no Linux desktop backend is active. WSL process
monitoring is independent and can run alongside either desktop backend.
