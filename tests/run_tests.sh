#!/usr/bin/env bash
#
# tests/run_tests.sh — test suite untuk pomo, murni Bash tanpa framework.
# Menjalankan skenario CLI/non-TUI: versi, help, stats, validasi durasi,
# penulisan & pembacaan riwayat, dan guard self-update.
#
# Jalankan dari mana saja: tests/run_tests.sh

set -u

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
POMO="$ROOT/pomo"

PASS=0
FAIL=0

ok() {
    PASS=$(( PASS + 1 ))
    printf 'ok   %s\n' "$1"
}

ko() {
    FAIL=$(( FAIL + 1 ))
    printf 'FAIL %s\n' "$1"
    [[ -n ${2:-} ]] && printf '     %s\n' "$2"
}

# assert_contains <deskripsi> <output> <substring>
assert_contains() {
    local desc=$1 out=$2 needle=$3
    if [[ $out == *"$needle"* ]]; then
        ok "$desc"
    else
        ko "$desc" "expected '$needle' in: $out"
    fi
}

# assert_eq <deskripsi> < aktual> <ekspektasi>
assert_eq() {
    local desc=$1 actual=$2 expected=$3
    if [[ $actual == "$expected" ]]; then
        ok "$desc"
    else
        ko "$desc" "got '$actual', expected '$expected'"
    fi
}

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

# --------------------------------------------------------------- version
out=$(bash "$POMO" --version 2>&1)
assert_contains '--version mencetak nama dan versi' "$out" 'pomo '
assert_contains '--version cocok dengan changelog 1.1.0' "$out" 'pomo 1.1.0'

# ------------------------------------------------------------------ help
out=$(bash "$POMO" --help 2>&1)
assert_contains '--help mencetak usage' "$out" 'Usage:'
assert_contains '--help menyebut subcommand stats' "$out" 'pomo stats'
assert_contains '--help menyebut subcommand update' "$out" 'pomo update'
assert_contains '--help menyebut tombol pause' "$out" 'Pause / resume'

# ------------------------------------------------------ stats tanpa data
export XDG_DATA_HOME="$TMP/data-empty"
out=$(bash "$POMO" stats 2>&1)
assert_contains 'stats tanpa history: pesan ramah' "$out" 'No sessions recorded yet'

# --------------------------------------------------------- stats berisi
export XDG_DATA_HOME="$TMP/data-full"
mkdir -p "$XDG_DATA_HOME/pomo"
today=$(date +%F)
{
    printf '%s|focus|1500\n' "$today"
    printf '%s|focus|1500\n' "$today"
    printf '%s|short_break|300\n' "$today"
    printf '%s|long_break|900\n' "$today"
} > "$XDG_DATA_HOME/pomo/history.log"
out=$(bash "$POMO" stats 2>&1)
assert_contains 'stats: jumlah sesi fokus hari ini' "$out" 'Focus sessions : 2'
assert_contains 'stats: menit fokus hari ini' "$out" 'Focus minutes  : 50'
assert_contains 'stats: jumlah break hari ini' "$out" 'Breaks taken   : 2'
assert_contains 'stats: ringkasan 7 hari' "$out" '7-day total: 2 sessions'
assert_contains 'stats: menit total 7 hari' "$out" '50 minutes focused'

# baris rusak di history tidak boleh merusak agregasi
{
    printf 'garbage-tanpa-pipe\n'
    printf '9999-99-99|focus|1500\n'
    printf '%s|focus|abc\n' "$today"
} >> "$XDG_DATA_HOME/pomo/history.log"
out=$(bash "$POMO" stats 2>&1)
assert_contains 'stats: baris rusak diabaikan' "$out" 'Focus sessions : 2'

# ------------------------------------------------------ perintah tidak dikenal
out=$(bash "$POMO" bogus 2>&1); rc=$?
assert_eq 'perintah tidak dikenal: exit code 1' "$rc" '1'
assert_contains 'perintah tidak dikenal: pesan error' "$out" "unknown command or option: 'bogus'"

# --------------------------------------------------- validasi durasi < 0
out=$(POMO_FOCUS_SECONDS=0 bash "$POMO" start 2>&1); rc=$?
assert_eq 'durasi 0 ditolak: exit code 1' "$rc" '1'
assert_contains 'durasi 0 ditolak: pesan error' "$out" 'invalid duration'

out=$(POMO_SHORT_BREAK_SECONDS=abc bash "$POMO" -w 2>&1); rc=$?
assert_eq 'durasi non-numerik ditolak: exit code 1' "$rc" '1'

# ---------------------------------------------- unit: log_session + read_history
unit_rc=0
(
    set -e
    export XDG_DATA_HOME="$TMP/data-unit"
    source "$POMO"

    log_session focus 1500
    log_session focus 1800
    log_session short_break 300

    [[ -f $HISTORY_FILE ]] || { echo "missing history file"; exit 1; }

    read_history
    d=$(date +%F)
    [[ ${FOCUS_COUNT[$d]} == 2 ]] || exit 1
    [[ $(( ${FOCUS_SECS[$d]} )) == 3300 ]] || exit 1
    [[ ${BREAK_COUNT[$d]} == 1 ]] || exit 1
) || unit_rc=$?
assert_eq 'log_session + read_history: agregasi benar' "$unit_rc" '0'

# --------------------------------------------- unit: log_session menolak input rusak
unit_rc=0
(
    set -e
    export XDG_DATA_HOME="$TMP/data-invalid"
    source "$POMO"
    log_session focus abc && exit 1   # harus gagal, bukan menulis
    log_session '' 1500 && exit 1
    [[ ! -e $HISTORY_FILE ]]
) || unit_rc=$?
assert_eq 'log_session: input rusak tidak menulis file' "$unit_rc" '0'

# ------------------------------------------------- update: file read-only
install_dir="$TMP/readonly-bin"
mkdir -p "$install_dir"
cp "$POMO" "$install_dir/pomo"
chmod 444 "$install_dir/pomo"
out=$(bash "$install_dir/pomo" update 2>&1); rc=$?
assert_eq 'update pada file read-only: exit code 1' "$rc" '1'
assert_contains 'update read-only: pesan error' "$out" 'is not writable'
chmod 644 "$install_dir/pomo"

# --------------------------------------------------------------- ringkasan
printf '\n%d passed, %d failed\n' "$PASS" "$FAIL"
(( FAIL == 0 )) || exit 1
