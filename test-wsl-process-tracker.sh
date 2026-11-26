#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
TRACKER="$ROOT/wsl-process-tracker.py"
command -v python3 >/dev/null 2>&1 || { echo 'python3 is required' >&2; exit 1; }
TMP=$(mktemp -d)
PID=''
TARGET_PID=''
DURING_PID=''
FILTER_PID=''
FILTER_TARGET_PID=''
cleanup() {
    [[ -n $TARGET_PID ]] && kill "$TARGET_PID" 2>/dev/null || true
    [[ -n $DURING_PID ]] && kill "$DURING_PID" 2>/dev/null || true
    [[ -n $FILTER_TARGET_PID ]] && kill "$FILTER_TARGET_PID" 2>/dev/null || true
    [[ -n $FILTER_PID ]] && kill "$FILTER_PID" 2>/dev/null || true
    [[ -n $PID ]] && kill "$PID" 2>/dev/null || true
    rm -rf "$TMP"
}
trap cleanup EXIT

python3 "$TRACKER" \
    --output "$TMP/processes.jsonl" \
    --stop-file "$TMP/stop" \
    --pause-file "$TMP/pause" \
    --interval-ms 250 >"$TMP/monitor.out" 2>"$TMP/monitor.err" &
PID=$!

for _ in $(seq 1 30); do
    grep -q '"type":"monitor_start"' "$TMP/processes.jsonl" 2>/dev/null && break
    sleep 0.1
done
grep -q '"type":"monitor_start"' "$TMP/processes.jsonl"

# A five-second process spans the pause; observed runtime should exclude the paused interval.
sleep 5 &
TARGET_PID=$!
for _ in $(seq 1 30); do
    grep -q "\"type\":\"process_seen\".*\"pid\":$TARGET_PID.*\"process\":\"sleep\"" "$TMP/processes.jsonl" 2>/dev/null && break
    sleep 0.1
done
grep -q "\"type\":\"process_seen\".*\"pid\":$TARGET_PID.*\"process\":\"sleep\"" "$TMP/processes.jsonl"
sleep 0.6
: > "$TMP/pause"
for _ in $(seq 1 30); do
    grep -q '"type":"monitor_pause"' "$TMP/processes.jsonl" 2>/dev/null && break
    sleep 0.1
done
grep -q '"type":"monitor_pause"' "$TMP/processes.jsonl"

# This process starts and finishes entirely while paused; it must not be observed.
sleep 0.8 &
DURING_PID=$!
wait "$DURING_PID"
sleep 1.5
rm -f "$TMP/pause"
for _ in $(seq 1 30); do
    grep -q '"type":"monitor_resume"' "$TMP/processes.jsonl" 2>/dev/null && break
    sleep 0.1
done
grep -q '"type":"monitor_resume"' "$TMP/processes.jsonl"

wait "$TARGET_PID" || true
: > "$TMP/stop"
wait "$PID"
PID=''

# process_usage for the process spanning pause must exclude paused elapsed time.
USAGE=$(grep "\"type\":\"process_usage\".*\"pid\":$TARGET_PID.*\"process\":\"sleep\"" "$TMP/processes.jsonl" | tail -n 1 || true)
[[ -n $USAGE ]]
RUNTIME=$(sed -n 's/.*\"runtime_seconds\":\([0-9][0-9]*\).*/\1/p' <<< "$USAGE")
[[ $RUNTIME =~ ^[0-9]+$ ]] && (( RUNTIME >= 2 && RUNTIME <= 4 )) || {
    echo "paused duration was not excluded as expected (runtime=${RUNTIME:-missing})" >&2
    exit 1
}

# No process events may be written between the pause and resume markers.
awk '
  /"type":"monitor_pause"/ { paused=1; next }
  /"type":"monitor_resume"/ { paused=0; next }
  paused && /"type":"process_(seen|exit|usage)"/ { bad=1 }
  END { exit bad }
' "$TMP/processes.jsonl"

# The process that existed only while paused is not present in the log.
if grep -q "\"pid\":$DURING_PID" "$TMP/processes.jsonl" 2>/dev/null; then
    echo 'process that existed only while paused was unexpectedly observed' >&2
    exit 1
fi

grep -q '"type":"monitor_stop"' "$TMP/processes.jsonl"

# Verify default, custom and disabled process filters.
assert_process_seen() {
    local log=$1 pid=$2 process=$3 expected=$4
    local pattern="\"type\":\"process_seen\".*\"pid\":$pid.*\"process\":\"$process\""

    if [[ $expected == present ]]; then
        grep -q "$pattern" "$log" || {
            echo "Expected $process (PID $pid) to be present" >&2
            return 1
        }
    else
        if grep -q "$pattern" "$log"; then
            echo "Expected $process (PID $pid) to be filtered" >&2
            return 1
        fi
    fi
}

run_filter_case() {
    local label=$1 filter=$2 sleep_expected=$3 bash_expected=$4
    local log="$TMP/filter-$label.jsonl"
    local stop="$TMP/filter-$label.stop"
    local shell_pid=$BASHPID
    local -a filter_args=()

    if [[ $filter != DEFAULT ]]; then
        filter_args=(--ignore-processes "$filter")
    fi

    python3 "$TRACKER" \
        --output "$log" \
        --stop-file "$stop" \
        --interval-ms 250 \
        "${filter_args[@]}" \
        >"$TMP/filter-$label.out" 2>"$TMP/filter-$label.err" &
    FILTER_PID=$!

    for _ in $(seq 1 30); do
        grep -q '"type":"monitor_start"' "$log" 2>/dev/null && break
        sleep 0.1
    done
    grep -q '"type":"monitor_start"' "$log"

    # This shell remains alive throughout the collector test.
    sleep 2 &
    FILTER_TARGET_PID=$!
    local target_pid=$FILTER_TARGET_PID

    for _ in $(seq 1 30); do
        grep -q "\"type\":\"process_seen\".*\"pid\":$FILTER_TARGET_PID.*\"process\":\"sleep\"" "$log" 2>/dev/null && break
        sleep 0.1
    done

    wait "$FILTER_TARGET_PID" || true
    : > "$stop"
    wait "$FILTER_PID"
    FILTER_PID=''
    FILTER_TARGET_PID=''

    assert_process_seen "$log" "$shell_pid" bash "$bash_expected"
    assert_process_seen "$log" "$target_pid" sleep "$sleep_expected"
}

run_filter_case default DEFAULT present absent
run_filter_case custom sleep absent present
run_filter_case none none present present

printf 'WSL process filter tests: PASS (default/custom/none)\n'

printf 'WSL /proc collector test: PASS\n'
printf 'Pause-excluded sleep runtime: %ss\n' "$RUNTIME"
