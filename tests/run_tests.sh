#!/usr/bin/env bash
#
# tests/run_tests.sh — test suite untuk pomo, murni Bash tanpa framework.
# Menjalankan skenario CLI/non-TUI: versi, help, stats, validasi durasi,
# penulisan & pembacaan riwayat, dan guard self-update —
# plus unit test TUI (read_key, draw_ui, menu, overlay, prompt_continue,
# run_timer) dengan men-source pomo dan mensimulasikan stdin via process
# substitution.
#
# Jalankan dari mana saja: tests/run_tests.sh

# shellcheck source=/dev/null
# shellcheck disable=SC2030,SC2031,SC2034,SC2329  # unit test berjalan di subshell terisolasi, menyetel global & mock fungsi pomo yang di-source
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
changelog_ver=$(sed -n '1s/^pomo (\([^)-]*\)[^)]*).*/\1/p' "$ROOT/debian/changelog")
assert_eq '--version cocok dengan versi teratas debian/changelog' "$out" "pomo $changelog_ver"

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
assert_contains '--help menyebut subcommand resume' "$out" 'pomo resume'
assert_contains '--help menyebut file konfigurasi' "$out" 'pomo.conf'
assert_contains '--help menyebut hook notifikasi' "$out" 'NOTIFY_CMD'

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
out=$(bash "$POMO" theme 2>&1); rc=$?
assert_eq 'file config tema rusak: exit code 1' "$rc" '1'
assert_contains 'file config tema rusak: pesan error' "$out" "unknown theme: 'ga-fdak'"
out=$(bash "$POMO" --version 2>&1); rc=$?
assert_eq 'file config tema rusak: --version tetap jalan' "$rc" '0'
out=$(bash "$POMO" theme default 2>&1); rc=$?
assert_eq 'file config tema rusak: pomo theme default bisa memulihkan' "$rc" '0'
rm -f "$XDG_CONFIG_HOME/pomo/theme"

# --------------------------------------------- unit: apply_theme + cycle_theme
unit_rc=0
(
    set -e
    export XDG_DATA_HOME="$TMP/data-theme"
    source "$POMO"

    # shellcheck disable=SC2034   # dipakai oleh fungsi pomo yang di-source
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
    theme_valid bogus && exit 1

    # pixel_anim (intro): reveal 0 = semua piksel tersembunyi
    out=$(pixel_anim '█████' 0 0 0)
    [[ $out == '     ' ]]
    # reveal 100: glyph utuh tanpa modifikasi
    out=$(pixel_anim '█████' 0 0 100)
    [[ $out == '█████' ]]
    # reveal parsial: campuran spasi dan block, lebar tetap 5
    out=$(pixel_anim '█████' 0 0 50)
    [[ ${#out} == 5 && $out == *█* && $out == *' '* ]]
)
unit_rc=$?
assert_eq 'apply_theme + cycle_theme + set_mode_colors: benar' "$unit_rc" '0'


# --------------------------------------------------- validasi durasi < 0
out=$(POMO_FOCUS_SECONDS=0 bash "$POMO" start </dev/null 2>&1); rc=$?
assert_eq 'durasi 0 ditolak: exit code 1' "$rc" '1'
assert_contains 'durasi 0 ditolak: pesan error' "$out" 'invalid duration'

out=$(POMO_SHORT_BREAK_SECONDS=abc bash "$POMO" -w 2>&1); rc=$?
assert_eq 'durasi non-numerik ditolak: exit code 1' "$rc" '1'

# ------------------------------------------------------------ config file
mkdir -p "$XDG_CONFIG_HOME/pomo"
printf '# komentar penuh\n# FOCUS_SECONDS=999\n   # SHORT_BREAK_SECONDS=999\nfocus_seconds=1200\t# 20 menit\nSHORT_BREAK_SECONDS=240\nUNKNOWN_KEY=x\n' \
    > "$XDG_CONFIG_HOME/pomo/pomo.conf"
out=$(bash "$POMO" config 2>&1)
assert_contains 'config: file terdeteksi aktif' "$out" '(active)'
assert_contains 'config: kunci lowercase + komentar inline & tab dibaca' "$out" 'Focus         : 1200 s (20 min)'
assert_contains 'config: kunci kedua dibaca' "$out" 'Short break   : 240 s (4 min)'
assert_contains 'config: kunci tak dikenal diabaikan' "$out" 'Long break    : 900 s (15 min)'
assert_contains 'config: menampilkan pengaturan audio' "$out" 'Focus sound :'
out=$(POMO_FOCUS_SECONDS=333 bash "$POMO" config 2>&1)
assert_contains 'config: env meng-override file' "$out" 'Focus         : 333 s (5 min)'
printf 'FOCUS_SECONDS=abc\n' > "$XDG_CONFIG_HOME/pomo/pomo.conf"
out=$(bash "$POMO" config 2>&1); rc=$?
assert_eq 'config: nilai rusak exit code 1' "$rc" '1'
assert_contains 'config: nilai rusak pesan jelas' "$out" 'FOCUS_SECONDS must be a positive integer'
out=$(bash "$POMO" --help 2>&1); rc=$?
assert_eq 'config rusak: --help tetap jalan' "$rc" '0'
rm -f "$XDG_CONFIG_HOME/pomo/pomo.conf"

# ------------------------------------------------------ status: idle tanpa sesi
out=$(bash "$POMO" status 2>&1); rc=$?
assert_contains 'status tanpa sesi: mencetak idle' "$out" 'idle'
assert_eq 'status tanpa sesi: exit code 1' "$rc" '1'

out=$(bash "$POMO" status --json 2>&1); rc=$?
assert_contains 'status --json tanpa sesi: class idle' "$out" '"class":["idle"]'
assert_eq 'status --json tanpa sesi: exit code 1' "$rc" '1'

# ------------------------------------------- status: sesi end-to-end (timer asli)
export XDG_DATA_HOME="$TMP/data-status"
mkdir -p "$XDG_RUNTIME_DIR"
PATH="$TMP/fakebin:$PATH" POMO_FOCUS_SECONDS=4 POMO_ANIMATION=off \
    bash "$POMO" start </dev/null >/dev/null 2>&1 &
pomo_pid=$!
sleep 2
out=$(bash "$POMO" status 2>&1); rc=$?
assert_eq 'status saat sesi jalan: exit code 0' "$rc" '0'
assert_contains 'status saat sesi jalan: mode + sisa waktu' "$out" 'focus 00:0'
out=$(bash "$POMO" status --json 2>&1); rc=$?
assert_eq 'status --json saat sesi jalan: exit code 0' "$rc" '0'
assert_contains 'status --json: class berisi mode' "$out" '"class":["focus"]'
assert_contains 'status --json: field text' "$out" '"text":"focus 00:0'
assert_contains 'status --json: paused false' "$out" '"paused":false'
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
if [[ -f $XDG_RUNTIME_DIR/pomo.state ]]; then
    ok 'status: state basi dibiarkan agar bisa diresume'
else
    ko 'status: state basi dibiarkan agar bisa diresume' 'file terhapus'
fi

# ---------------------------------------------- resume: end-to-end (kill -9)
export XDG_DATA_HOME="$TMP/data-resume"
rm -f "$XDG_RUNTIME_DIR/pomo.state"
PATH="$TMP/fakebin:$PATH" POMO_FOCUS_SECONDS=5 POMO_ANIMATION=off \
    bash "$POMO" start </dev/null >/dev/null 2>&1 &
victim=$!
sleep 2
kill -9 "$victim"
wait "$victim" 2>/dev/null || true
if [[ -f $XDG_RUNTIME_DIR/pomo.state ]]; then
    ok 'resume: kill -9 meninggalkan state'
else
    ko 'resume: kill -9 meninggalkan state' 'file state tidak ada'
fi
PATH="$TMP/fakebin:$PATH" POMO_FOCUS_SECONDS=5 POMO_ANIMATION=off \
    bash "$POMO" resume </dev/null >/dev/null 2>&1
rc=$?
assert_eq 'resume: sesi sisa selesai dengan exit 0' "$rc" '0'
if [[ ! -f $XDG_RUNTIME_DIR/pomo.state ]]; then
    ok 'resume: state dibersihkan setelah selesai'
else
    ko 'resume: state dibersihkan setelah selesai' "sisa: $(cat "$XDG_RUNTIME_DIR/pomo.state")"
fi
if grep -q '|focus|5$' "$XDG_DATA_HOME/pomo/history.log"; then
    ok 'resume: durasi penuh ter-log'
else
    ko 'resume: durasi penuh ter-log' 'history tanpa baris fokus 5s'
fi

# ---------------------------------------------------- resume: tanpa state
rm -f "$XDG_RUNTIME_DIR/pomo.state"
out=$(bash "$POMO" resume 2>&1); rc=$?
assert_eq 'resume tanpa state: exit code 1' "$rc" '1'
assert_contains 'resume tanpa state: pesan jelas' "$out" 'no interrupted session to resume'

# ---------------------------------------------------- resume: kedaluwarsa
bash -c 'sleep 0.05' & dead2=$!
wait "$dead2"
printf 'focus|%s|%s|1500|0|0\n' "$dead2" "$(( $(date +%s) - 10 ))" > "$XDG_RUNTIME_DIR/pomo.state"
out=$(bash "$POMO" resume 2>&1); rc=$?
assert_eq 'resume kedaluwarsa: exit code 1' "$rc" '1'
assert_contains 'resume kedaluwarsa: pesan jelas' "$out" 'already ran out of time'
if [[ ! -f $XDG_RUNTIME_DIR/pomo.state ]]; then
    ok 'resume kedaluwarsa: state dibuang'
else
    ko 'resume kedaluwarsa: state dibuang' 'file masih ada'
fi

# ------------------------------------------------------ notify hook (env)
export XDG_DATA_HOME="$TMP/data-notify"
# shellcheck disable=SC2016
out=$(PATH="$TMP/fakebin:$PATH" POMO_FOCUS_SECONDS=2 POMO_ANIMATION=off \
    POMO_NOTIFY_CMD='printf HOOK:%s:%s "$1" "$2"' bash "$POMO" start </dev/null 2>&1)
assert_contains 'notify hook: dipanggil dengan judul' "$out" 'HOOK:Focus session complete:'
assert_contains 'notify hook: menerima isi pesan' "$out" 'minutes of focus logged'

# ------------------------------------------------ notify hook lewat pomo.conf
printf 'NOTIFY_CMD=paplay bell.ogg\n' > "$XDG_CONFIG_HOME/pomo/pomo.conf"
out=$(bash "$POMO" config 2>&1)
assert_contains 'config: notify_cmd dari file ditampilkan' "$out" 'Notify hook : paplay bell.ogg'
out=$(POMO_NOTIFY_CMD='envhook cmd' bash "$POMO" config 2>&1)
assert_contains 'config: env notify meng-override file' "$out" 'Notify hook : envhook cmd'
rm -f "$XDG_CONFIG_HOME/pomo/pomo.conf"

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
    out=$(show_status --json)
    # text tanpa akhiran "(paused)": status pause sudah ada di class/paused
    [[ $out == *'"text":"short break 01:15"'* ]]
    [[ $out == *'"class":["short_break","paused"]'* ]]
    [[ $out == *'"paused":true'* ]]
    [[ $out == *'SHORT BREAK'* ]]

    # shellcheck disable=SC2034   # dipakai oleh write_state dari skrip pomo
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
)
unit_rc=$?
assert_eq 'unit: write_state + show_status + clear_state' "$unit_rc" '0'

# ------------------------------------------ unit: resume_read_state
unit_rc=0
(
    set -e
    export XDG_RUNTIME_DIR="$TMP/run-resume"
    mkdir -p "$XDG_RUNTIME_DIR"
    source "$POMO"

    # terputus dalam kondisi pause: sisa = frozen
    bash -c 'sleep 0.05' & d=$!
    wait "$d"
    printf 'short_break|%s|%s|300|1|123\n' "$d" "$(( $(now) + 100 ))" > "$STATE_FILE"
    resume_read_state
    [[ $RESUME_MODE == short_break ]]
    [[ $RESUME_REMAINING == 123 ]]

    # penulis masih hidup: rc 3 (sesi masih berjalan)
    sleep 30 & live=$!
    printf 'focus|%s|%s|1500|0|0\n' "$live" "$(( $(now) + 100 ))" > "$STATE_FILE"
    rc=0; resume_read_state || rc=$?
    [[ $rc == 3 ]]
    kill "$live" 2>/dev/null
    wait "$live" 2>/dev/null || true

    # state rusak: rc 1
    printf 'garbage\n' > "$STATE_FILE"
    rc=0; resume_read_state || rc=$?
    [[ $rc == 1 ]]
    [[ -z $RESUME_MODE ]]
)
unit_rc=$?
assert_eq 'unit: resume_read_state (paused/hidup/rusak)' "$unit_rc" '0'

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
)
unit_rc=$?
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
)
unit_rc=$?
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

# ------------------------------------------ unit: read_key (tombol & arrow keys)
unit_rc=0
(
    set -e
    source "$POMO"
    # EOF -> rc 1
    rc=0; read_key k </dev/null || rc=$?
    [[ $rc == 1 ]]
    # tombol biasa diteruskan apa adanya
    k=$(printf 'a' | { read_key k; printf '%s' "$k"; })
    [[ $k == a ]]
    # arrow keys diterjemahkan dari escape sequence
    k=$(printf '\033[B' | { read_key k; printf '%s' "$k"; })
    [[ $k == DOWN ]]
    k=$(printf '\033[A' | { read_key k; printf '%s' "$k"; })
    [[ $k == UP ]]
    # Enter -> string kosong
    k=$(printf '\n' | { read_key k; printf '%s' "$k"; })
    [[ -z $k ]]
    # Esc murni -> ESC (dibedakan dari Enter, tidak bocor ke pembacaan berikutnya)
    k=$(printf '\033' | { read_key k; printf '%s' "$k"; })
    [[ $k == ESC ]]
)
unit_rc=$?
assert_eq 'unit: read_key (EOF, tombol biasa, arrow, Enter, Esc)' "$unit_rc" '0'

# ------------------------------------------ unit: draw_ui (rounded card, siklus, gradient, anti-flicker)
unit_rc=0
(
    set -e
    source "$POMO"
    COLOR_ENABLED=1
    apply_theme default
    set_mode_colors focus
    ANIM_ENABLED=0
    TERM_COLS=80 TERM_LINES=24
    CYCLE_DOTS='●●○○'
    out=$(draw_ui 754 1500 'FOCUS SESSION' 0)
    plain=$(sed -E 's/\x1b\[[0-9;?]*[A-Za-z]//g' <<< "$out")
    [[ $plain == *'╭─ ● FOCUS SESSION'* ]]
    [[ $plain == *'Cycle: ●●○○ ─╮'* ]]
    [[ $plain == *'Elapsed 12:26 of 25:00'* ]]
    [[ $plain == *'━'* && $plain == *'╰'* && $plain == *'╯'* ]]
    [[ $plain == *'p pause  ·  s skip  ·  m menu  ·  q quit'* ]]
    # status PAUSED: header berubah menjadi ❚❚ PAUSED + hint resume
    out_p=$(draw_ui 754 1500 'FOCUS SESSION' 1)
    plain_p=$(sed -E 's/\x1b\[[0-9;?]*[A-Za-z]//g' <<< "$out_p")
    [[ $plain_p == *'╭─ ❚❚ PAUSED'* ]]
    [[ $plain_p == *'p resume'* ]]
    # terminal terlalu kecil: pesan muncul TANPA clear penuh (anti-flicker)
    TERM_COLS=30 TERM_LINES=10
    out=$(draw_ui 754 1500 'FOCUS SESSION' 0)
    [[ $out == *'Terminal too small'* ]]
    [[ $out != *$'\033[2J'* ]]
)
unit_rc=$?
assert_eq 'unit: draw_ui (rounded card, siklus, paused, anti-flicker terminal kecil)' "$unit_rc" '0'

# ------------------------------------------ unit: open_menu (tombol, arrow, penanda aktif)
unit_rc=0
(
    set -e
    source "$POMO"
    COLOR_ENABLED=1
    apply_theme default
    set_mode_colors focus
    INTERACTIVE=1
    TERM_COLS=80 TERM_LINES=30
    CURRENT_MODE=long_break
    out_file="$TMP/menu.out"

    # tombol langsung
    MENU_RESULT=''
    open_menu >"$out_file" < <(printf '2')
    [[ $MENU_RESULT == short_break ]]

    # Enter default = back (seleksi awal ada di "Back to timer")
    MENU_RESULT=''
    open_menu >"$out_file" < <(printf '\n')
    [[ $MENU_RESULT == back ]]

    # q = quit
    MENU_RESULT=''
    open_menu >"$out_file" < <(printf 'q')
    [[ $MENU_RESULT == quit ]]

    # arrow: dari back (idx 9) DOWN -> quit (10), DOWN -> focus (0), Enter
    MENU_RESULT=''
    open_menu >"$out_file" < <(printf '\033[B\033[B\n')
    [[ $MENU_RESULT == focus ]]

    # REGRESI: Enter pada item overlay (help/stats/durations/theme) harus
    # menjalankan action-nya dan menu tetap terbuka — bukan return dengan
    # MENU_RESULT berisi nama action (dulu bikin timer beku/"crash").
    # help: 5x DOWN dari idx 9 -> idx 4, Enter buka help, 'x' tutup, 'b' back
    MENU_RESULT=''
    open_menu >"$out_file" < <(printf '\033[B\033[B\033[B\033[B\033[B\nxb')
    [[ $MENU_RESULT == back ]]
    out=$(<"$out_file")
    [[ $out == *'Menu keys'* ]]

    # stats: 6x DOWN -> idx 5, Enter buka stats, 'x' tutup, 'b' back
    MENU_RESULT=''
    open_menu >"$out_file" < <(printf '\033[B\033[B\033[B\033[B\033[B\033[B\nxb')
    [[ $MENU_RESULT == back ]]
    out=$(<"$out_file")
    [[ $out == *'STATS'* ]]

    # durations: 7x DOWN -> idx 6, Enter buka overlay, 'b' ke menu, 'b' back
    MENU_RESULT=''
    open_menu >"$out_file" < <(printf '\033[B\033[B\033[B\033[B\033[B\033[B\033[B\nbb')
    [[ $MENU_RESULT == back ]]
    out=$(<"$out_file")
    [[ $out == *'CUSTOMIZE DURATIONS'* ]]

    # theme: 8x DOWN -> idx 7, Enter ganti tema, lalu 'b' back
    MENU_RESULT=''
    THEME_NAME=default
    THEME_CHANGED=0
    open_menu >"$out_file" < <(printf '\033[B\033[B\033[B\033[B\033[B\033[B\033[B\033[B\nb')
    [[ $MENU_RESULT == back ]]
    [[ $THEME_NAME == dracula && $THEME_CHANGED == 1 ]]

    # penanda (active) pada mode berjalan + overlay help bisa dibuka dari menu
    MENU_RESULT=''
    open_menu >"$out_file" < <(printf 'hxb')
    [[ $MENU_RESULT == back ]]
    out=$(<"$out_file")
    [[ $out == *'Long break (15 min)  (active)'* ]]
    [[ $out == *'Menu keys'* ]]
)
unit_rc=$?
assert_eq 'unit: open_menu (tombol langsung, arrow+Enter, Enter=back, q, penanda aktif, help)' "$unit_rc" '0'

# ------------------------------------------ unit: prompt_continue (shortcut antar-sesi)
unit_rc=0
(
    set -e
    export XDG_DATA_HOME="$TMP/data-pc"
    source "$POMO"
    COLOR_ENABLED=1
    apply_theme default
    set_mode_colors focus
    INTERACTIVE=1
    TERM_COLS=80 TERM_LINES=30
    PROMPT_NEXT_MODE=''
    out_file="$TMP/pc.out"

    # Enter = lanjut, tanpa override
    rc=0; prompt_continue 'T' 'm' 'NEXT' >"$out_file" < <(printf '\n') || rc=$?
    [[ $rc == 0 && -z $PROMPT_NEXT_MODE ]]

    # q = berhenti
    rc=0; prompt_continue 'T' 'm' 'NEXT' >/dev/null < <(printf 'q') || rc=$?
    [[ $rc == 1 ]]

    # m lalu 3: mode berikutnya di-override dari menu
    rc=0; prompt_continue 'T' 'm' 'NEXT' >/dev/null < <(printf 'm3') || rc=$?
    [[ $rc == 0 && $PROMPT_NEXT_MODE == long_break ]]
    PROMPT_NEXT_MODE=''

    # t: overlay stats muncul, lalu Enter lanjut
    rc=0; prompt_continue 'T' 'm' 'NEXT' >"$out_file" < <(printf 't\n\n') || rc=$?
    [[ $rc == 0 ]]
    out=$(<"$out_file")
    [[ $out == *'No sessions recorded yet.'* ]]

    # non-interaktif: selalu berhenti (rc 1) dengan pesan satu baris
    INTERACTIVE=0
    rc=0; out=$(prompt_continue 'T' 'm' 'NEXT' </dev/null 2>&1) || rc=$?
    [[ $rc == 1 && $out == 'T — m' ]]
)
unit_rc=$?
assert_eq 'unit: prompt_continue (Enter, q, override via menu, stats, non-interaktif)' "$unit_rc" '0'

# ------------------------------------------ unit: show_stats_overlay (bar chart 7 hari)
unit_rc=0
(
    set -e
    export XDG_DATA_HOME="$TMP/data-stats-tui"
    mkdir -p "$XDG_DATA_HOME/pomo"
    today=$(date +%F)
    printf '%s|focus|1500\n%s|focus|1500\n%s|short_break|300\n' "$today" "$today" "$today" \
        > "$XDG_DATA_HOME/pomo/history.log"
    source "$POMO"
    COLOR_ENABLED=1
    apply_theme default
    set_mode_colors focus
    TERM_COLS=80 TERM_LINES=40
    read_key() { return 1; }   # overlay tidak menunggu tombol
    out=$(show_stats_overlay 2>&1)
    [[ $out == *"Today — $today"* ]]
    [[ $out == *'Focus sessions : 2'* ]]
    [[ $out == *'Last 7 days:'* ]]
    [[ $out == *"$today  2 sess  50 min"* ]]
    [[ $out == *'7-day total: 2 sessions · 50 minutes'* ]]
)
unit_rc=$?
assert_eq 'unit: show_stats_overlay menampilkan bar chart 7 hari' "$unit_rc" '0'

# ------------------------------------------ unit: run_timer konfirmasi quit
unit_rc=0
(
    set -e
    export XDG_RUNTIME_DIR="$TMP/run-tui"
    mkdir -p "$XDG_RUNTIME_DIR"
    source "$POMO"
    COLOR_ENABLED=1
    apply_theme default
    set_mode_colors focus
    INTERACTIVE=1
    ANIM_ENABLED=0
    TERM_COLS=80 TERM_LINES=24

    # q lalu q: konfirmasi -> quit (rc 1)
    rc=0; run_timer 1 'FOCUS SESSION' >/dev/null 2>&1 < <(printf 'qq') || rc=$?
    [[ $rc == 1 ]]

    # q lalu tombol lain: batal -> timer jalan sampai selesai (rc 0)
    rc=0; run_timer 1 'FOCUS SESSION' >/dev/null 2>&1 < <(printf 'qx') || rc=$?
    [[ $rc == 0 ]]
)
unit_rc=$?
assert_eq 'unit: run_timer konfirmasi quit (qq=quit, qx=batal)' "$unit_rc" '0'

# ------------------------------------------ unit: run_cycle mengisi CYCLE_DOTS (end-to-end)
unit_rc=0
(
    set -e
    export XDG_DATA_HOME="$TMP/data-cycle"
    export XDG_RUNTIME_DIR="$TMP/run-cycle"
    mkdir -p "$XDG_RUNTIME_DIR"
    export POMO_FOCUS_SECONDS=2 POMO_SHORT_BREAK_SECONDS=2 POMO_LONG_BREAK_SECONDS=2
    export POMO_ANIMATION=off POMO_NOTIFY_CMD=true
    source "$POMO"
    COLOR_ENABLED=1
    apply_theme default
    INTERACTIVE=1
    ANIM_ENABLED=0
    TERM_COLS=80 TERM_LINES=24

    # fokus 2s selesai -> Enter -> short break (focus_done=1 -> ●○○○) -> q berhenti
    rc=0
    run_cycle focus >/dev/null 2>&1 < <(sleep 3; printf '\n'; sleep 3; printf 'q') || rc=$?
    [[ $rc == 0 ]]
    [[ $CYCLE_DOTS == '●○○○' ]]
)
unit_rc=$?
assert_eq 'unit: run_cycle mengisi CYCLE_DOTS (●○○○ setelah 1 fokus selesai)' "$unit_rc" '0'

# ------------------------------------------ help: KEY_HELP mencakup tombol baru
out=$(bash "$POMO" --help 2>&1)
assert_contains '--help: blok Between sessions' "$out" 'Between sessions:'
assert_contains '--help: menu dengan navigasi arrow' "$out" 'navigate with'
assert_contains '--help: quit dengan konfirmasi' "$out" 'Quit (asks for confirmation)'

# ------------------------------------------ regresi: save_duration_config pertahankan config lain
unit_rc=0
(
    set -e
    export XDG_CONFIG_HOME="$TMP/cfg-preserve"
    mkdir -p "$XDG_CONFIG_HOME/pomo"
    cat > "$XDG_CONFIG_HOME/pomo/pomo.conf" <<'EOF'
# custom user comment
NOTIFY_CMD=my-notify "$1" "$2"
FOCUS_SOUND=/custom/focus.oga
BREAK_SOUND=/custom/break.oga
FOCUS_SECONDS=1500
EOF
    source "$POMO"
    FOCUS_SECONDS=1800
    SHORT_BREAK_SECONDS=360
    LONG_BREAK_SECONDS=1200
    read_key() { return 0; }
    save_duration_config >/dev/null
    cfg=$(<"$CONFIG_FILE")
    [[ $cfg == *'# custom user comment'* ]]
    # shellcheck disable=SC2016
    [[ $cfg == *'NOTIFY_CMD=my-notify "$1" "$2"'* ]]
    [[ $cfg == *'FOCUS_SOUND=/custom/focus.oga'* ]]
    [[ $cfg == *'BREAK_SOUND=/custom/break.oga'* ]]
    [[ $cfg == *'FOCUS_SECONDS=1800'* ]]
    [[ $cfg == *'SHORT_BREAK_SECONDS=360'* ]]
    [[ $cfg == *'LONG_BREAK_SECONDS=1200'* ]]
    [[ $cfg != *'FOCUS_SECONDS=1500'* ]]
)
unit_rc=$?
assert_eq 'regresi: save_duration_config mempertahankan NOTIFY_CMD & audio di pomo.conf' "$unit_rc" '0'

# ------------------------------------------ regresi: duration overlay aman dari arrow keys & Esc
unit_rc=0
(
    set -e
    export XDG_CONFIG_HOME="$TMP/cfg-arrows"
    mkdir -p "$XDG_CONFIG_HOME/pomo"
    source "$POMO"
    COLOR_ENABLED=0
    TERM_COLS=80 TERM_LINES=30
    # Panah atas (\033[A) tidak boleh memicu [a] save_duration_config;
    # Panah bawah (\033[B) tidak boleh memicu [b] keluar sebelum 'r' dijalankan;
    # Lalu 'r' reset dan Esc menutup overlay.
    FOCUS_SECONDS=1800
    show_duration_config_overlay >/dev/null < <(printf '\033[A\033[Br\033')
    [[ ! -f $CONFIG_FILE ]]
    [[ $FOCUS_SECONDS == 1500 ]]
)
unit_rc=$?
assert_eq 'regresi: duration overlay mengabaikan arrow keys (tidak salah trigger a/b)' "$unit_rc" '0'

# ------------------------------------------ regresi: Esc di menu & prompt_continue ≠ Enter
unit_rc=0
(
    set -e
    source "$POMO"
    COLOR_ENABLED=0
    INTERACTIVE=1
    TERM_COLS=80 TERM_LINES=30
    CURRENT_MODE=focus
    # Geser kursor ke focus (2x DOWN dari idx 9), lalu Esc -> harus back (bukan focus)
    MENU_RESULT=''
    open_menu >/dev/null < <(printf '\033[B\033[B\033')
    [[ $MENU_RESULT == back ]]
    # Di prompt_continue: Esc tidak boleh start sesi; diikuti 'q' harus quit (rc 1)
    rc=0; prompt_continue 'T' 'm' 'NEXT' >/dev/null < <(printf '\033q') || rc=$?
    [[ $rc == 1 ]]
)
unit_rc=$?
assert_eq 'regresi: Esc di menu -> back, Esc di prompt_continue tidak start sesi' "$unit_rc" '0'

# ------------------------------------------ regresi: skip fokus pertama -> short break (bukan long)
unit_rc=0
(
    set -e
    export XDG_DATA_HOME="$TMP/data-skip"
    export XDG_RUNTIME_DIR="$TMP/run-skip"
    mkdir -p "$XDG_RUNTIME_DIR"
    export POMO_FOCUS_SECONDS=10 POMO_SHORT_BREAK_SECONDS=5 POMO_LONG_BREAK_SECONDS=15
    export POMO_ANIMATION=off POMO_NOTIFY_CMD=true
    source "$POMO"
    COLOR_ENABLED=0
    INTERACTIVE=1
    TERM_COLS=80 TERM_LINES=24
    out_file="$TMP/skip.out"
    # Skip fokus pertama ('s'), lalu 'q' di layar konfirmasi antar-sesi
    rc=0; run_cycle focus >"$out_file" 2>&1 < <(printf 'sq') || rc=$?
    [[ $rc == 0 ]]
    out=$(<"$out_file")
    [[ $out == *'SHORT BREAK'* ]]
    [[ $out != *'LONG BREAK'* ]]
)
unit_rc=$?
assert_eq 'regresi: skip sesi fokus pertama menawarkan SHORT BREAK (bukan LONG BREAK)' "$unit_rc" '0'

# ------------------------------------------ regresi: draw_ui >= 100 menit kotak tetap sejajar
unit_rc=0
(
    set -e
    source "$POMO"
    COLOR_ENABLED=0
    ANIM_ENABLED=0
    TERM_COLS=80 TERM_LINES=24
    out=$(draw_ui 6000 7200 'FOCUS SESSION' 0)
    # 6 glyph ("100:00"): 5*6 + 2 + 5*2 = 42 kolom + 10 padding = 52 inner -> 52 garis '─'
    expected_bar='╰────────────────────────────────────────────────────╯'
    [[ $out == *"$expected_bar"* ]]
)
unit_rc=$?
assert_eq 'regresi: draw_ui dengan durasi >= 100 menit lebar rounded card sesuai 6 glyph' "$unit_rc" '0'

# ------------------------------------------ unit: font rounded half-block + gradient adaptif
unit_rc=0
(
    set -e
    source "$POMO"
    # pixel_anim menangani ▄ dan ▀ selain █
    out=$(pixel_anim '▄████▄' 0 0 0)
    [[ $out == '      ' ]]
    out=$(pixel_anim '▄████▄' 0 0 100)
    [[ $out == '▄████▄' ]]
    out=$(pixel_anim '▀████▀' 0 0 100)
    [[ $out == '▀████▀' ]]

    # gradient adaptif: default memakai ANSI palette, dracula 256 & truecolor, mono tanpa warna
    COLOR_ENABLED=1
    TRUECOLOR=0
    apply_theme default
    set_mode_colors focus
    [[ ${#C_DIGIT_GRAD[@]} == 5 ]]
    [[ ${C_DIGIT_GRAD[0]} == *"$C_CYAN"* && ${C_DIGIT_GRAD[4]} == $'\033[32m' ]]

    apply_theme dracula
    set_mode_colors focus
    [[ ${C_DIGIT_GRAD[0]} == $'\033[38;5;117m' ]]

    TRUECOLOR=1
    set_mode_colors focus
    [[ ${C_DIGIT_GRAD[0]} == $'\033[38;2;139;233;253m' ]]

    apply_theme mono
    set_mode_colors focus
    [[ -z ${C_DIGIT_GRAD[2]} ]]
)
unit_rc=$?
assert_eq 'unit: rounded half-block pixel_anim + adaptive vertical gradient (ANSI/256/RGB/mono)' "$unit_rc" '0'

# ------------------------------------------ regresi: run_timer memanggil update_term_size saat RESIZED=1
unit_rc=0
(
    set -e
    export XDG_RUNTIME_DIR="$TMP/run-resize"
    mkdir -p "$XDG_RUNTIME_DIR"
    source "$POMO"
    COLOR_ENABLED=0
    INTERACTIVE=1
    ANIM_ENABLED=0
    TERM_COLS=80 TERM_LINES=24
    resized_called=0
    update_term_size() { resized_called=1; TERM_COLS=90; TERM_LINES=30; }
    RESIZED=1
    rc=0; run_timer 5 'FOCUS SESSION' >/dev/null 2>&1 < <(printf 's') || rc=$?
    [[ $rc == 2 && $resized_called == 1 && $TERM_COLS == 90 ]]
)
unit_rc=$?
assert_eq 'regresi: run_timer memanggil update_term_size saat RESIZED=1' "$unit_rc" '0'

# ------------------------------------------ regresi: show_stats mewarnai bar chart
unit_rc=0
(
    set -e
    export XDG_DATA_HOME="$TMP/data-stats-color"
    mkdir -p "$XDG_DATA_HOME/pomo"
    today=$(date +%F)
    printf '%s|focus|1500\n' "$today" > "$XDG_DATA_HOME/pomo/history.log"
    source "$POMO"
    COLOR_ENABLED=1
    apply_theme default
    out=$(show_stats)
    [[ $out == *"${C_GREEN}▓▓"* ]]
)
unit_rc=$?
assert_eq 'regresi: show_stats mewarnai grafik bar saat COLOR_ENABLED=1' "$unit_rc" '0'

# ------------------------------------------ unit: activity tracking (normalize, sample, idle, recap)
unit_rc=0
(
    set -e
    export XDG_DATA_HOME="$TMP/data-activity"
    source "$POMO"

    # Normalisasi nama aplikasi
    [[ $(normalize_app_name 'com.mitchellh.ghostty') == ghostty ]]
    [[ $(normalize_app_name 'org.mozilla.firefox.desktop') == firefox ]]
    [[ $(normalize_app_name 'Code-OSS') == code ]]
    [[ $(normalize_app_name 'google-chrome-stable') == chrome ]]
    [[ $(normalize_app_name 'bad|app,name=1') == badappname1 ]]
    [[ $(normalize_app_name '') == unknown ]]

    # Sampling, perpindahan app, dan deteksi idle berbasis signature
    IDLE_THRESHOLD_SECONDS=60
    activity_reset
    activity_record_sample 'Code-OSS' 'main.sh' '100, 200' -1 2 1000
    activity_record_sample 'Code-OSS' 'main.sh' '105, 200' -1 2 1002
    activity_record_sample 'org.mozilla.firefox' 'Docs' '120, 220' -1 2 1004
    # Tetap di firefox, title & cursor sama > 60s -> dihitung idle
    activity_record_sample 'org.mozilla.firefox' 'Docs' '120, 220' -1 2 1070
    [[ $ACT_SAMPLES == 4 ]]
    [[ $ACT_SWITCHES == 1 ]]
    [[ ${ACT_APP_SECS[code]} == 4 ]]
    [[ ${ACT_APP_SECS[firefox]} == 4 ]]
    [[ $ACT_ACTIVE_SECS == 6 ]]
    [[ $ACT_IDLE_SECS == 2 ]]

    # Deteksi idle berbasis idle_ms (mis. xprintidle)
    activity_reset
    activity_record_sample 'ghostty' 'bash' '' 5000 2 2000
    activity_record_sample 'ghostty' 'bash' '' 75000 2 2002
    [[ $ACT_ACTIVE_SECS == 2 && $ACT_IDLE_SECS == 2 ]]

    # log_activity + sanitasi task + show_recap (today & last)
    SESSION_TASK='Kerjakan | Bab 3'
    activity_reset
    activity_record_sample 'Code-OSS' 'pomo' '1,1' -1 120 3000
    activity_record_sample 'firefox' 'Docs' '2,2' -1 60 3002
    log_activity 180
    [[ -f $ACTIVITY_FILE ]]
    out_today=$(show_recap today)
    [[ $out_today == *'Focus Activity Recap'* ]]
    [[ $out_today == *'[Kerjakan   Bab 3]'* ]]
    [[ $out_today == *'code'* && $out_today == *'firefox'* ]]
    out_last=$(show_recap last)
    [[ $out_last == *'Last Focus Recap'* ]]
    [[ $out_last == *'100% active'* && $out_last == *'1 app switches'* ]]

    # show_stats ikut menampilkan Top Apps Today bila activity.log ada
    log_session focus 180
    out_stats=$(show_stats)
    [[ $out_stats == *'Top Apps Today'* ]]
    [[ $out_stats == *'code'* ]]

    # draw_focus_recap menampilkan rounded recap card dengan app bars, task, & indikator Idle
    TERM_COLS=80 TERM_LINES=24
    ACT_IDLE_SECS=20
    recap_ui=$(draw_focus_recap 200 'SHORT BREAK' | sed -E 's/\x1b\[[0-9;?]*[A-Za-z]//g')
    [[ $recap_ui == *'╭─ ✓ FOCUS COMPLETE'* ]]
    [[ $recap_ui == *'Kerjakan   Bab 3'* ]]
    [[ $recap_ui == *'Activity : 90% active'* ]]
    [[ $recap_ui == *'Idle     : 10% idle (20s)'* ]]
    [[ $recap_ui == *'Apps used:'* ]]
    [[ $recap_ui == *'code'* && $recap_ui == *'━'* ]]
    [[ $recap_ui == *'╰'* && $recap_ui == *'╯'* ]]

    # draw_ui menampilkan indikator tracking saat focus & backend aktif
    CURRENT_MODE=focus
    TRACKER_BACKEND=hyprland
    ANIM_ENABLED=0
    ui_tr=$(draw_ui 600 1500 'FOCUS SESSION' 0 | sed -E 's/\x1b\[[0-9;?]*[A-Za-z]//g')
    [[ $ui_tr == *'·  tracking'* ]]
    TRACKER_BACKEND=off
    ui_no=$(draw_ui 600 1500 'FOCUS SESSION' 0 | sed -E 's/\x1b\[[0-9;?]*[A-Za-z]//g')
    [[ $ui_no != *'tracking'* ]]
)
unit_rc=$?
assert_eq 'unit: activity tracking, normalisasi, idle, recap card, & Top Apps Today' "$unit_rc" '0'

# ------------------------------------------ CLI: recap, -t/--task, & POMO_TRACKING=off
export XDG_DATA_HOME="$TMP/data-recap-empty"
out=$(bash "$POMO" recap 2>&1); rc=$?
assert_eq 'recap tanpa data: exit code 0' "$rc" '0'
assert_contains 'recap tanpa data: pesan ramah' "$out" 'No focus activity recaps recorded yet'

out=$(bash "$POMO" recap bogus 2>&1); rc=$?
assert_eq 'recap opsi tidak dikenal: exit code 1' "$rc" '1'

out=$(bash "$POMO" -t 2>&1); rc=$?
assert_eq '-t tanpa argumen: exit code 1' "$rc" '1'
assert_contains '-t tanpa argumen: pesan error jelas' "$out" 'requires a task description'

out=$(POMO_TRACKING=off bash "$POMO" config 2>&1)
assert_contains 'config: POMO_TRACKING=off ditampilkan' "$out" 'Tracking    : off'

out=$(bash "$POMO" --help 2>&1)
assert_contains '--help menyebut subcommand recap' "$out" 'pomo recap'
assert_contains '--help menyebut opsi -t task' "$out" '-t "task"'

# ------------------------------------------ unit: swayidle Wayland idle watcher & fallback
unit_rc=0
(
    set -e
    export XDG_RUNTIME_DIR="$TMP/run-idle"
    mkdir -p "$XDG_RUNTIME_DIR" "$TMP/swaybin"
    cat > "$TMP/swaybin/hyprctl" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
    cat > "$TMP/swaybin/swayidle" <<'EOF'
#!/usr/bin/env bash
sleep 30 &
wait $!
EOF
    chmod +x "$TMP/swaybin/hyprctl" "$TMP/swaybin/swayidle"

    PATH="$TMP/swaybin:/usr/bin:/bin"
    HYPRLAND_INSTANCE_SIGNATURE='test-sig'
    source "$POMO"
    detect_tracker_backend
    [[ $TRACKER_BACKEND == hyprland ]]
    idle_watcher_supported

    start_idle_watcher
    [[ -n $IDLE_WATCHER_PID && -f $IDLE_STATE_FILE ]]
    [[ $(<"$IDLE_STATE_FILE") == 0 ]]
    kill -0 "$IDLE_WATCHER_PID" 2>/dev/null

    # State 0 -> active (PROBE_IDLE_MS=0)
    PROBE_IDLE_MS=-1
    read_wayland_idle_ms
    [[ $PROBE_IDLE_MS == 0 ]]

    # State 1 -> idle (>= threshold * 1000)
    printf '1\n' > "$IDLE_STATE_FILE"
    read_wayland_idle_ms
    [[ $PROBE_IDLE_MS == $(( IDLE_THRESHOLD_SECONDS * 1000 )) ]]

    # Stop watcher -> proses & file state dibersihkan, fallback return 1
    state_path=$IDLE_STATE_FILE
    stop_idle_watcher
    [[ -z $IDLE_WATCHER_PID && -z $IDLE_STATE_FILE && ! -e $state_path ]]
    read_wayland_idle_ms && exit 1

    # show_config mendeteksi swayidle (keyboard+pointer)
    cfg_out=$(show_config)
    [[ $cfg_out == *'swayidle (keyboard+pointer)'* ]]
)
unit_rc=$?
assert_eq 'unit: swayidle Wayland keyboard+pointer idle watcher & cleanup' "$unit_rc" '0'

# --------------------------------------------------------------- ringkasan
printf '\n%d passed, %d failed\n' "$PASS" "$FAIL"
(( FAIL == 0 )) || exit 1
