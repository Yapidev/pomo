#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
POMO="$ROOT/pomo"
TRACKER="$ROOT/wsl-process-tracker.py"

bash -n "$POMO"
python3 -m py_compile "$TRACKER"
printf 'Bash syntax: OK\nPython syntax: OK\n'

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
export XDG_DATA_HOME="$TMP/data"
export XDG_CONFIG_HOME="$TMP/config"
export XDG_RUNTIME_DIR="$TMP/run"
mkdir -p "$XDG_RUNTIME_DIR"

cat > "$TMP/wsl-fixture.jsonl" <<'JSONL'
{"ts":"2026-11-27T00:00:00Z","type":"monitor_start","source":"wsl","scope":"current_user"}
{"ts":"2026-11-27T00:00:01Z","type":"process_seen","source":"wsl","pid":101,"process":"python3"}
{"ts":"2026-11-27T00:00:02Z","type":"process_seen","source":"wsl","pid":102,"process":"bash"}
{"ts":"2026-11-27T00:00:05Z","type":"process_usage","source":"wsl","process":"python3","runtime_seconds":4}
{"ts":"2026-11-27T00:00:05Z","type":"process_usage","source":"wsl","process":"bash","runtime_seconds":2}
{"ts":"2026-11-27T00:00:05Z","type":"monitor_stop","source":"wsl"}
JSONL

POMO_PATH="$POMO" FIXTURE="$TMP/wsl-fixture.jsonl" bash <<'BASH'
set -euo pipefail
unset POMO_WSL_IGNORED_PROCESSES
source "$POMO_PATH"
activity_reset
WSL_PROCESS_LOG=$FIXTURE
import_wsl_process_activity
[[ $ACT_WSL_PROCESS_EVENTS == 2 ]]
[[ ${ACT_WSL_PROCESS_SECS[python3]} == 4 ]]
[[ ${ACT_WSL_PROCESS_SECS[bash]} == 2 ]]
log_activity 30
last=$(show_recap last)
[[ $last == *'WSL processes (observed runtime)'* ]]
[[ $last == *'python3'* && $last == *'4s'* ]]
[[ $last == *'bash'* && $last == *'2s'* ]]
today=$(show_recap today)
[[ $today == *'WSL Process Activity Today'* ]]

# TUI recap and timer show the WSL collector without changing old Linux tracker behavior.
ACT_WSL_PROCESS_SECS=([python3]=4 [bash]=2)
TERM_COLS=80 TERM_LINES=24
recap_ui=$(draw_focus_recap 30 'SHORT BREAK' | sed -E 's/\x1b\[[0-9;?]*[A-Za-z]//g')
[[ $recap_ui == *'WSL processes (runtime)'* && $recap_ui == *'python3'* ]]
CURRENT_MODE=focus
WINDOWS_TRACKER_STATUS=active
WSL_PROCESS_STATUS=active
TRACKER_BACKEND=none
timer_ui=$(draw_ui 20 30 'FOCUS SESSION' 0 | sed -E 's/\x1b\[[0-9;?]*[A-Za-z]//g')
[[ $timer_ui == *'Win:ON WSL:ON'* ]]


# WSL filter configuration parsing.
mkdir -p "$CONFIG_DIR"

cat > "$CONFIG_FILE" <<'CONF'
WSL_IGNORED_PROCESSES=custom-one,python3
CONF
load_config
[[ $WSL_IGNORED_PROCESSES == "custom-one,python3" ]]

cat > "$CONFIG_FILE" <<'CONF'
WSL_IGNORED_PROCESSES=none
CONF
load_config
[[ $WSL_IGNORED_PROCESSES == "none" ]]

# Environment variable must override the config file.
cat > "$CONFIG_FILE" <<'CONF'
WSL_IGNORED_PROCESSES=config-value
CONF

POMO_PATH="$POMO_PATH" \
XDG_CONFIG_HOME="$XDG_CONFIG_HOME" \
POMO_WSL_IGNORED_PROCESSES=env-value \
bash -c '
    set -euo pipefail
    source "$POMO_PATH"
    load_config
    [[ $WSL_IGNORED_PROCESSES == "env-value" ]]
'

printf 'WSL filter config and environment precedence: OK\n'

# Old 10-field activity.log rows must remain readable alongside the new 11-field format.
printf '%s|23:59|10||0|0|0||0|0\n' "$(date +%F)" >> "$ACTIVITY_FILE"
last_after_old=$(show_recap last)
[[ $last_after_old == *'Last Focus Recap'* ]]
printf 'Pomo import/recap compatibility: OK\n'
BASH

printf 'Integration fixture tests: PASS\n'
