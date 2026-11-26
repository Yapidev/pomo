#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd -- "$(dirname -- "$0")" && pwd)"
POMO="$ROOT/pomo"
TRACKER="$ROOT/windows-tracker.ps1"
[[ -f $POMO && -f $TRACKER ]]
bash -n "$POMO"
echo 'Bash syntax: OK'

# Unit-test import parsing without launching Windows PowerShell.
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
export XDG_DATA_HOME="$TMP/data"
mkdir -p "$XDG_DATA_HOME/pomo"
# Source the app; initialize its global state and provide a synthetic collector log.
source "$POMO"
WINDOWS_TRACKER_LOG="$TMP/windows.jsonl"
IDLE_THRESHOLD_SECONDS=60
cat > "$WINDOWS_TRACKER_LOG" <<'EOF'
{"ts":"2026-11-27T00:00:00Z","type":"monitor_start","source":"windows","input_hooks_available":true}
{"ts":"2026-11-27T00:00:01Z","type":"app_change","source":"windows","app":"chrome"}
{"ts":"2026-11-27T00:00:01Z","type":"sample","source":"windows","app":"chrome","idle_ms":0,"idle":false,"keyboard_events":12,"mouse_clicks":3,"input_hooks_available":true}
{"ts":"2026-11-27T00:00:02Z","type":"input_sample","source":"windows","keyboard_events":2,"mouse_clicks":1}
{"ts":"2026-11-27T00:00:03Z","type":"monitor_pause","source":"windows"}
{"ts":"2026-11-27T00:00:04Z","type":"monitor_resume","source":"windows","input_hooks_available":true}
{"ts":"2026-11-27T00:00:05Z","type":"sample","source":"windows","app":"discord","idle_ms":0,"idle":false,"keyboard_events":5,"mouse_clicks":2,"input_hooks_available":true}
EOF
activity_reset
import_windows_activity
[[ $ACT_KEYBOARD_EVENTS == 19 ]]
[[ $ACT_MOUSE_CLICKS == 6 ]]
[[ $ACT_SWITCHES == 1 ]]
[[ ${ACT_APP_SECS[chrome]} == 1 && ${ACT_APP_SECS[discord]} == 1 ]]
SESSION_TASK='input aggregate test'
log_activity 2
line=$(tail -n 1 "$ACTIVITY_FILE")
[[ $line == *'|19|6' ]]
recap=$(show_recap last)
[[ $recap == *'19 keyboard events · 6 mouse clicks'* ]]
# Append an older eight-field line and ensure legacy recaps still parse.
printf '%s|12:00|60|legacy|1|55|5|chrome=55\n' "$(date +%F)" >> "$ACTIVITY_FILE"
legacy=$(show_recap last)
[[ $legacy == *'Last Focus Recap'* && $legacy == *'chrome'* ]]
[[ $legacy != *'keyboard events'* ]]
echo 'Windows input aggregation: OK'
echo 'Legacy activity.log compatibility: OK'
