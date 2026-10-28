#!/usr/bin/env bash
# Shell-only patcher for the Bash pomo application.
# Run this from the project directory containing ./pomo.
set -euo pipefail

TARGET="./pomo"
if [[ ! -f "$TARGET" ]]; then
  printf 'ERROR: ./pomo tidak ditemukan. Jalankan script ini dari folder project pomo.\n' >&2
  exit 1
fi
if grep -Eq '^[[:space:]]*play_speaker\(\) \{' "$TARGET"; then
  printf 'ERROR: play_speaker() sudah ada. Patch dibatalkan agar tidak menduplikasi perubahan.\n' >&2
  exit 1
fi

BACKUP="./pomo.before-features.$(date +%Y%m%d-%H%M%S)"
cp -p "$TARGET" "$BACKUP"
NORM=$(mktemp)
OUT=$(mktemp)
AWKPROG=$(mktemp)
cleanup() { rm -f "$NORM" "$OUT" "$AWKPROG"; }
trap cleanup EXIT

# Normalize CRLF to LF in the temporary copy only.
sed 's/\r$//' "$TARGET" > "$NORM"

check_one() {
  local needle="$1" description="$2" count
  count=$(grep -Fxc -- "$needle" "$NORM" || true)
  if [[ "$count" != 1 ]]; then
    printf "ERROR: pola '%s' ditemukan %s kali; file asli tidak diubah.\n" "$description" "${count:-0}" >&2
    printf 'Backup: %s\n' "$BACKUP" >&2
    exit 1
  fi
}

check_one 'NOTIFY_CMD="${POMO_NOTIFY_CMD:-}"' 'konfigurasi NOTIFY_CMD'
check_one '                [[ -z ${POMO_NOTIFY_CMD:-} ]] && NOTIFY_CMD=$value' 'parser NOTIFY_CMD'
check_one 'ring_bell() {' 'fungsi ring_bell'
check_one '                    log_session focus "$duration"' 'akhir sesi focus'
check_one '                    log_session short_break "$duration"' 'akhir sesi short break'
check_one '                    log_session long_break "$duration"' 'akhir sesi long break'
check_one "        ''|start)" 'cabang startup'

cat > "$AWKPROG" <<'AWK'
function emit_prompt() {
  print "            local answer"
  print "            printf \"\\nMulai sesi fokus sekarang? [y/N]: \""
  print "            if [[ -t 0 ]]; then"
  print "                IFS= read -r answer || answer=\"\""
  print "            else"
  print "                answer=\"\""
  print "            fi"
  print ""
  print "            case \"${answer,,}\" in"
  print "                y|yes)"
  print "                    start_session focus"
  print "                    ;;"
  print "                *)"
  print "                    printf \"Sesi fokus belum dimulai.\\n\""
  print "                    ;;"
  print "            esac"
}
function emit_config_cases() {
  print "            SPEAKER_CMD)"
  print "                value=$raw"
  print "                value=${value#\"${value%%[![:space:]]*}\"}"
  print "                value=${value%\"${value##*[![:space:]]}\"}"
  print "                [[ -z ${POMO_SPEAKER_CMD:-} ]] && SPEAKER_CMD=$value"
  print "                ;;"
  print "            SPEAKER_SOUND)"
  print "                value=$raw"
  print "                value=${value#\"${value%%[![:space:]]*}\"}"
  print "                value=${value%\"${value##*[![:space:]]}\"}"
  print "                [[ -z ${POMO_SPEAKER_SOUND:-} ]] && SPEAKER_SOUND=$value"
  print "                ;;"
  print "            FOCUS_SOUND)"
  print "                value=$raw"
  print "                value=${value#\"${value%%[![:space:]]*}\"}"
  print "                value=${value%\"${value##*[![:space:]]}\"}"
  print "                [[ -z ${POMO_FOCUS_SOUND:-} ]] && FOCUS_SOUND=$value"
  print "                ;;"
  print "            BREAK_SOUND)"
  print "                value=$raw"
  print "                value=${value#\"${value%%[![:space:]]*}\"}"
  print "                value=${value%\"${value##*[![:space:]]}\"}"
  print "                [[ -z ${POMO_BREAK_SOUND:-} ]] && BREAK_SOUND=$value"
  print "                ;;"
}
{
  sub(/\r$/, "")

  if ($0 == "NOTIFY_CMD=\"${POMO_NOTIFY_CMD:-}\"") {
    print
    print ""
    print "# Audio output. Focus and break use separate sounds; both break lengths share BREAK_SOUND."
    print "SPEAKER_CMD=\"${POMO_SPEAKER_CMD:-}\""
    print "SPEAKER_SOUND=\"${POMO_SPEAKER_SOUND:-/usr/share/sounds/freedesktop/stereo/complete.oga}\""
    print "FOCUS_SOUND=\"${POMO_FOCUS_SOUND:-}\""
    print "BREAK_SOUND=\"${POMO_BREAK_SOUND:-/usr/share/sounds/freedesktop/stereo/bell.oga}\""
    next
  }

  if ($0 == "                [[ -z ${POMO_NOTIFY_CMD:-} ]] && NOTIFY_CMD=$value") {
    print
    in_notify_case = 1
    next
  }
  if (in_notify_case) {
    print
    if ($0 ~ /^[[:space:]]*;;[[:space:]]*$/) {
      emit_config_cases()
      in_notify_case = 0
    }
    next
  }

  if ($0 == "ring_bell() {") {
    print
    in_ring = 1
    next
  }
  if (in_ring) {
    print
    if ($0 == "}") {
      print ""
      print "play_speaker() {"
      print "    local sound_file=\"${1:-$SPEAKER_SOUND}\""
      print "    local fallback=\"${SPEAKER_SOUND:-/usr/share/sounds/freedesktop/stereo/complete.oga}\""
      print ""
      print "    if [[ -n ${SPEAKER_CMD:-} ]]; then"
      print "        bash -c \"$SPEAKER_CMD\" pomo \"$sound_file\" || true"
      print "        return 0"
      print "    fi"
      print ""
      print "    if command -v paplay >/dev/null 2>&1; then"
      print "        if [[ -n $sound_file && -f $sound_file ]] && paplay \"$sound_file\" >/dev/null 2>&1; then"
      print "            return 0"
      print "        fi"
      print "        if [[ -n $fallback && -f $fallback && $sound_file != \"$fallback\" ]] && paplay \"$fallback\" >/dev/null 2>&1; then"
      print "            return 0"
      print "        fi"
      print "    fi"
      print ""
      print "    if command -v aplay >/dev/null 2>&1 && [[ -n $sound_file && -f $sound_file ]]; then"
      print "        aplay -q \"$sound_file\" >/dev/null 2>&1 && return 0"
      print "    fi"
      print ""
      print "    if command -v beep >/dev/null 2>&1; then"
      print "        beep >/dev/null 2>&1 && return 0"
      print "    fi"
      print "    ring_bell"
      print "    return 0"
      print "}"
      in_ring = 0
    }
    next
  }

  if ($0 == "                    log_session focus \"$duration\"") {
    print "                    play_speaker \"$FOCUS_SOUND\""
    print
    next
  }
  if ($0 == "                    log_session short_break \"$duration\"") {
    print "                    play_speaker \"$BREAK_SOUND\""
    print
    next
  }
  if ($0 == "                    log_session long_break \"$duration\"") {
    print "                    play_speaker \"$BREAK_SOUND\""
    print
    next
  }

  if ($0 == "        \047\047|start)") {
    print
    waiting_for_start = 1
    next
  }
  if (waiting_for_start) {
    if ($0 == "            start_session focus") {
      emit_prompt()
      waiting_for_start = 0
      next
    }
    waiting_for_start = 0
  }

  print
}
END {
  if (in_notify_case || in_ring || waiting_for_start) {
    exit 9
  }
}
AWK
awk -f "$AWKPROG" "$NORM" > "$OUT"

if ! bash -n "$OUT"; then
  printf 'ERROR: hasil patch gagal pemeriksaan sintaks Bash; file asli tidak diubah.\n' >&2
  printf 'Backup: %s\n' "$BACKUP" >&2
  exit 1
fi

# Ensure key features are present before installing the patched script.
grep -Fq 'FOCUS_SOUND=' "$OUT"
grep -Fq 'BREAK_SOUND=' "$OUT"
grep -Fq 'play_speaker() {' "$OUT"
grep -Fq 'Mulai sesi fokus sekarang? [y/N]:' "$OUT"
chmod --reference="$TARGET" "$OUT"
cat "$OUT" > "$TARGET"
printf 'OK: patch shell-only berhasil diterapkan.\n'
printf 'Bash syntax check: PASS\n'
printf 'Backup: %s\n' "$BACKUP"
printf 'Aplikasi tetap Bash; patcher hanya menggunakan shell, awk, sed, grep, dan utilitas Linux.\n'
