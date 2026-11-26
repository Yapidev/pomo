#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd -- "$(dirname -- "$0")" && pwd)"
POMO="$ROOT/pomo"
TRACKER="$ROOT/windows-tracker.ps1"

[[ -f $POMO ]] || { echo "pomo tidak ditemukan di $ROOT" >&2; exit 1; }
[[ -f $TRACKER ]] || { echo "windows-tracker.ps1 tidak ditemukan di $ROOT" >&2; exit 1; }

bash -n "$POMO"
echo 'Bash syntax: OK'

command -v powershell.exe >/dev/null 2>&1 || {
    echo 'powershell.exe tidak ditemukan dari WSL' >&2
    exit 1
}
command -v wslpath >/dev/null 2>&1 || {
    echo 'wslpath tidak ditemukan; jalankan tes dari WSL' >&2
    exit 1
}

OUT="$ROOT/windows-tracker-integration-test.jsonl"
OUT_WIN="$(wslpath -w "$OUT")"
TRACKER_WIN="$(wslpath -w "$TRACKER")"
rm -f "$OUT"

echo 'Menjalankan collector selama 20 detik.'
echo 'Selama tes, ketik di beberapa aplikasi Windows dan lakukan beberapa klik mouse.'
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass \
  -File "$TRACKER_WIN" -OutputPath "$OUT_WIN" \
  -DurationSeconds 20 -PollIntervalMs 1000 -IdleThresholdSeconds 60

[[ -s $OUT ]] || { echo 'Log tidak dibuat.' >&2; exit 1; }
printf '\nInput hook availability: '
grep -m1 -o '"input_hooks_available":[^,}]*' "$OUT" | cut -d: -f2- || true
printf 'App change events: '
grep -c '"type":"app_change"' "$OUT" || true
printf 'Samples: '
grep -c '"type":"sample"' "$OUT" || true
printf 'Keyboard events: '
grep -E '"type":"(sample|input_sample)"' "$OUT" \
  | sed -n 's/.*"keyboard_events":\([0-9][0-9]*\).*/\1/p' \
  | awk '{ n += $1 } END { print n + 0 }'
printf 'Mouse clicks: '
grep -E '"type":"(sample|input_sample)"' "$OUT" \
  | sed -n 's/.*"mouse_clicks":\([0-9][0-9]*\).*/\1/p' \
  | awk '{ n += $1 } END { print n + 0 }'
echo "Log: $OUT"
