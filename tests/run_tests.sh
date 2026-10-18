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
export XDG_CONFIG_HOME="$TMP/config"
export XDG_RUNTIME_DIR="$TMP/run"   # isolasi file status "pomo status"

# Stub notify-send supaya test end-to-end tidak memunculkan notifikasi desktop
mkdir -p "$TMP/fakebin"
printf '#!/usr/bin/env bash\nexit 0\n' > "$TMP/fakebin/notify-send"
chmod +x "$TMP/fakebin/notify-send"

# --------------------------------------------------------------- version
out=$(bash "$POMO" --version 2>&1)
assert_contains '--version mencetak nama dan versi' "$out" 'pomo '
assert_contains '--version cocok dengan changelog 1.4.0' "$out" 'pomo 1.4.0'

# ------------------------------------------------------------------ help
out=$(bash "$POMO" --help 2>&1)
assert_contains '--help mencetak usage' "$out" 'Usage:'
assert_contains '--help menyebut subcommand stats' "$out" 'pomo stats'
assert_contains '--help menyebut subcommand update' "$out" 'pomo update'
assert_contains '--help menyebut tombol pause' "$out" 'Pause / resume'
assert_contains '--help menyebut subcommand theme' "$out" 'pomo theme'
assert_contains '--help menyebut daftar tema' "$out" 'Available themes: default, dracula'
assert_contains '--help menyebut subcommand status' "$out" 'pomo status'
assert_contains '--help menyebut subcommand config' "$out" 'pomo config'
assert_contains '--help menyebut file konfigurasi' "$out" 'pomo.conf'

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

# ---------------------------------------------------------------- theme
out=$(bash "$POMO" theme 2>&1)
assert_contains 'theme tanpa argumen: tema aktif' "$out" 'Current theme : default'
assert_contains 'theme tanpa argumen: daftar semua tema' "$out" 'dracula'
assert_contains 'theme tanpa argumen: daftar tema mono' "$out" 'mono'

out=$(bash "$POMO" theme nord 2>&1); rc=$?
assert_eq 'theme nord: exit code 0' "$rc" '0'
assert_contains 'theme nord: konfirmasi' "$out" 'Theme set to nord'
assert_contains 'theme nord: tersimpan di file config' "$(cat "$XDG_CONFIG_HOME/pomo/theme")" 'nord'

out=$(bash "$POMO" theme 2>&1)
assert_contains 'theme tersimpan dibaca ulang' "$out" 'Current theme : nord'

out=$(POMO_THEME=matrix bash "$POMO" theme 2>&1)
assert_contains 'POMO_THEME meng-override file config' "$out" 'Current theme : matrix'

out=$(bash "$POMO" theme bogus 2>&1); rc=$?
assert_eq 'theme tidak dikenal: exit code 1' "$rc" '1'
assert_contains 'theme tidak dikenal: pesan error' "$out" "unknown theme: 'bogus'"
assert_contains 'theme tidak dikenal: daftar tema disebut' "$out" 'Available themes:'

printf 'ga-fdak\n' > "$XDG_CONFIG_HOME/pomo/theme"
out=$(bash "$POMO" --version 2>&1); rc=$?
assert_eq 'file config tema rusak: exit code 1' "$rc" '1'
assert_contains 'file config tema rusak: pesan error' "$out" "unknown theme: 'ga-fdak'"
rm -f "$XDG_CONFIG_HOME/pomo/theme"

# --------------------------------------------- unit: apply_theme + cycle_theme
unit_rc=0
(
    set -e
    export XDG_DATA_HOME="$TMP/data-theme"
    source "$POMO"

    COLOR_ENABLED=1
    apply_theme dracula
    [[ $THEME_NAME == dracula ]]
    [[ $C_GREEN == $'\033[38;5;120m' ]]
    [[ $C_WHITE == $'\033[38;5;255m' ]]

    apply_theme mono
    [[ -z $C_GREEN && -z $C_YELLOW && -z $C_WHITE ]]

    apply_theme default
    cycle_theme
    [[ $THEME_NAME == dracula && $THEME_CHANGED == 1 ]]
    [[ $(<"$THEME_FILE") == dracula ]]   # langsung tersimpan saat 'c'
    cycle_theme
    [[ $THEME_NAME == gruvbox ]]

    apply_theme dracula
    set_mode_colors focus
    [[ $C_DIGITS == $'\033[38;5;120m' ]]   # warna mode ikut tema baru

    apply_theme matrix
    set_mode_colors focus
    [[ $C_DIGITS == $'\033[38;5;46m' ]]

    apply_theme default
    [[ $C_GREEN == $'\033[92m' ]]
    [[ $C_CYAN == $'\033[96m' ]]
    [[ $C_YELLOW == $'\033[93m' ]]

    theme_valid nord
    ! theme_valid bogus

    # pixel_anim (intro): reveal 0 = semua piksel tersembunyi
    out=$(pixel_anim '█████' 0 0 0)
    [[ $out == '     ' ]]
    # reveal 100: glyph utuh tanpa modifikasi
    out=$(pixel_anim '█████' 0 0 100)
    [[ $out == '█████' ]]
    # reveal parsial: campuran spasi dan block, lebar tetap 5
    out=$(pixel_anim '█████' 0 0 50)
    [[ ${#out} == 5 && $out == *█* && $out == *' '* ]]
) || unit_rc=$?
assert_eq 'apply_theme + cycle_theme + set_mode_colors: benar' "$unit_rc" '0'


# --------------------------------------------------- validasi durasi < 0
out=$(POMO_FOCUS_SECONDS=0 bash "$POMO" start 2>&1); rc=$?
assert_eq 'durasi 0 ditolak: exit code 1' "$rc" '1'
assert_contains 'durasi 0 ditolak: pesan error' "$out" 'invalid duration'

out=$(POMO_SHORT_BREAK_SECONDS=abc bash "$POMO" -w 2>&1); rc=$?
assert_eq 'durasi non-numerik ditolak: exit code 1' "$rc" '1'

# ------------------------------------------------------------ config file
mkdir -p "$XDG_CONFIG_HOME/pomo"
printf '# komentar penuh\nfocus_seconds=1200   # 20 menit\nSHORT_BREAK_SECONDS=240\nUNKNOWN_KEY=x\n' \
    > "$XDG_CONFIG_HOME/pomo/pomo.conf"
out=$(bash "$POMO" config 2>&1)
assert_contains 'config: file terdeteksi aktif' "$out" '(active)'
assert_contains 'config: kunci lowercase + komentar inline dibaca' "$out" 'Focus         : 1200 s (20 min)'
assert_contains 'config: kunci kedua dibaca' "$out" 'Short break   : 240 s (4 min)'
assert_contains 'config: kunci tak dikenal diabaikan' "$out" 'Long break    : 900 s (15 min)'
out=$(POMO_FOCUS_SECONDS=333 bash "$POMO" config 2>&1)
assert_contains 'config: env meng-override file' "$out" 'Focus         : 333 s (5 min)'
printf 'FOCUS_SECONDS=abc\n' > "$XDG_CONFIG_HOME/pomo/pomo.conf"
out=$(bash "$POMO" --version 2>&1); rc=$?
assert_eq 'config: nilai rusak exit code 1' "$rc" '1'
assert_contains 'config: nilai rusak pesan jelas' "$out" 'FOCUS_SECONDS must be a positive integer'
rm -f "$XDG_CONFIG_HOME/pomo/pomo.conf"

# ------------------------------------------------------ status: idle tanpa sesi
out=$(bash "$POMO" status 2>&1); rc=$?
assert_contains 'status tanpa sesi: mencetak idle' "$out" 'idle'
assert_eq 'status tanpa sesi: exit code 1' "$rc" '1'

# ------------------------------------------- status: sesi end-to-end (timer asli)
export XDG_DATA_HOME="$TMP/data-status"
mkdir -p "$XDG_RUNTIME_DIR"
PATH="$TMP/fakebin:$PATH" POMO_FOCUS_SECONDS=4 POMO_ANIMATION=off \
    bash "$POMO" start >/dev/null 2>&1 &
pomo_pid=$!
sleep 2
out=$(bash "$POMO" status 2>&1); rc=$?
assert_eq 'status saat sesi jalan: exit code 0' "$rc" '0'
assert_contains 'status saat sesi jalan: mode + sisa waktu' "$out" 'focus 00:0'
wait "$pomo_pid"
out=$(bash "$POMO" status 2>&1); rc=$?
assert_contains 'status setelah sesi selesai: idle' "$out" 'idle'
assert_eq 'status setelah sesi selesai: exit code 1' "$rc" '1'

# -------------------------------------------- status: state basi (pid mati)
bash -c 'sleep 0.05' & dead=$!
wait "$dead"
printf 'focus|%s|%s|1500|0|0\n' "$dead" "$(( $(date +%s) + 100 ))" > "$XDG_RUNTIME_DIR/pomo.state"
out=$(bash "$POMO" status 2>&1); rc=$?
assert_contains 'status: state basi dibaca sebagai idle' "$out" 'idle'
assert_eq 'status: state basi exit code 1' "$rc" '1'
if [[ ! -f $XDG_RUNTIME_DIR/pomo.state ]]; then
    ok 'status: state basi dibersihkan dari disk'
else
    ko 'status: state basi dibersihkan dari disk' 'file masih ada'
fi

# ------------------------------------------ unit: write_state + show_status
unit_rc=0
(
    set -e
    export XDG_DATA_HOME="$TMP/data-state"
    export XDG_RUNTIME_DIR="$TMP/run-unit"
    source "$POMO"

    CURRENT_MODE=focus
    write_state "$(( $(now) + 120 ))" 1500 0 120
    out=$(show_status)
    [[ $out == 'focus 02:00' ]]

    CURRENT_MODE=short_break
    write_state "$(( $(now) + 120 ))" 300 1 75
    out=$(show_status)
    [[ $out == 'short break 01:15 (paused)' ]]

    CURRENT_MODE=long_break
    write_state "$(( $(now) - 10 ))" 900 0 0
    out=$(show_status)
    [[ $out == 'long break 00:00' ]]

    clear_state
    [[ ! -f $STATE_FILE ]]
    [[ $(show_status) == 'idle' ]]

    # clear_state milik pid lain: file dibiarkan, exit tetap 0 (trap EXIT)
    bash -c 'sleep 0.05' & other=$!
    wait "$other"
    printf 'focus|%s|%s|1500|0|0\n' "$other" "$(( $(now) + 100 ))" > "$STATE_FILE"
    clear_state
    [[ -f $STATE_FILE ]]
    rm -f "$STATE_FILE"

    printf 'garbage\n' > "$XDG_RUNTIME_DIR/pomo.state"
    [[ $(show_status) == 'idle' ]]
) || unit_rc=$?
assert_eq 'unit: write_state + show_status + clear_state' "$unit_rc" '0'

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
