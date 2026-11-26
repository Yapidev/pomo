#!/usr/bin/env bash
set -euo pipefail

# Run from the Pomo repository root in WSL.
SCRIPT="$(pwd)/windows-tracker.ps1"
OUT="$(pwd)/windows-tracker-test.jsonl"

if ! command -v powershell.exe >/dev/null 2>&1; then
    echo "powershell.exe tidak ditemukan dari WSL. Pastikan WSL interop aktif." >&2
    exit 1
fi
if [[ ! -f "$SCRIPT" ]]; then
    echo "File tidak ditemukan: $SCRIPT" >&2
    echo "Simpan windows-tracker.ps1 di root repository Pomo terlebih dahulu." >&2
    exit 1
fi

rm -f "$OUT"
SCRIPT_WIN="$(wslpath -w "$SCRIPT")"
OUT_WIN="$(wslpath -w "$OUT")"

echo "Menjalankan Windows Tracker selama 30 detik..."
echo "Selama berjalan, pindah-pindah antara terminal ini, browser, Discord, atau aplikasi lain."
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass \
    -File "$SCRIPT_WIN" \
    -OutputPath "$OUT_WIN" \
    -DurationSeconds 30 \
    -PollIntervalMs 1000

echo
echo "Log tersimpan di: $OUT"
echo "Ringkasan app yang terdeteksi:"
if command -v jq >/dev/null 2>&1; then
    jq -r 'select(.type == "app_change") | [.ts, .app, .process_id] | @tsv' "$OUT"
else
    grep '"type":"app_change"' "$OUT" || true
fi
