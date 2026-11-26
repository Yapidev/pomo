#!/usr/bin/env python3
"""Pomo WSL process monitor.

Records process names and observed runtime for processes owned by the current
Linux user. It never reads command-line arguments, environment variables,
file contents, terminal input, or window data.
"""

from __future__ import annotations

import argparse
import datetime as dt
import json
import os
import re
import signal
import sys
import time
from pathlib import Path
from typing import Dict, Tuple

ProcessKey = Tuple[int, int]  # PID + /proc starttime ticks; protects against PID reuse.

# Long-lived session/collector infrastructure adds noise to the recap. Keep
# actual commands (python3, git, sleep, vim, etc.) visible.
DEFAULT_IGNORED_PROCESS_NAMES = {
    "systemd", "_sd-pam_", "bash", "sh", "dash", "zsh", "fish",
    "powershell.exe", "pwsh.exe",
}
IGNORED_PROCESS_NAMES = set(DEFAULT_IGNORED_PROCESS_NAMES)


def utc_now() -> str:
    return dt.datetime.now(dt.timezone.utc).isoformat(timespec="milliseconds").replace("+00:00", "Z")


def safe_process_name(raw: str) -> str:
    name = raw.strip().lower()
    name = re.sub(r"[^a-z0-9_.+\-]", "_", name)
    return (name[:32] or "unknown")


def read_process_snapshot(proc_root: Path, owner_uid: int, own_pid: int) -> Dict[ProcessKey, str]:
    """Return visible processes owned by current UID, using /proc only."""
    current: Dict[ProcessKey, str] = {}
    try:
        entries = list(proc_root.iterdir())
    except OSError:
        return current

    for entry in entries:
        if not entry.name.isdigit():
            continue
        pid = int(entry.name)
        if pid == own_pid:
            continue
        try:
            status_text = (entry / "status").read_text(encoding="utf-8", errors="replace")
            real_uid = None
            for line in status_text.splitlines():
                if line.startswith("Uid:"):
                    fields = line.split()
                    if len(fields) >= 2:
                        real_uid = int(fields[1])
                    break
            if real_uid != owner_uid:
                continue

            raw_name = (entry / "comm").read_text(encoding="utf-8", errors="replace").strip()
            stat_text = (entry / "stat").read_text(encoding="utf-8", errors="replace")
            # comm can contain spaces/parentheses; the final ") " ends field 2.
            closing = stat_text.rfind(") ")
            if closing < 0:
                continue
            fields_after_comm = stat_text[closing + 2 :].split()
            # fields_after_comm[0] is stat field 3; starttime is field 22.
            if len(fields_after_comm) <= 19:
                continue
            start_ticks = int(fields_after_comm[19])
            process_name = safe_process_name(raw_name)
            if process_name in IGNORED_PROCESS_NAMES:
                continue
            current[(pid, start_ticks)] = process_name
        except (OSError, ValueError, IndexError, PermissionError):
            # A process may exit while /proc is being sampled.
            continue
    return current


class JsonlWriter:
    def __init__(self, path: Path) -> None:
        path.parent.mkdir(parents=True, exist_ok=True)
        self._file = path.open("a", encoding="utf-8", buffering=1)

    def emit(self, record: dict) -> None:
        self._file.write(json.dumps(record, separators=(",", ":"), ensure_ascii=True) + "\n")
        self._file.flush()

    def close(self) -> None:
        self._file.close()


def main() -> int:
    global IGNORED_PROCESS_NAMES
    parser = argparse.ArgumentParser(description="Monitor current-user WSL processes during a Pomo focus session.")
    parser.add_argument("--output", required=True, help="JSONL output path")
    parser.add_argument("--stop-file", default="", help="stop when this file appears")
    parser.add_argument("--pause-file", default="", help="pause sampling while this file exists")
    parser.add_argument("--interval-ms", type=int, default=1000)
    parser.add_argument(
        "--ignore-processes",
        default=",".join(sorted(DEFAULT_IGNORED_PROCESS_NAMES)),
        help="comma-separated process names to ignore, or none to disable filtering",
    )
    parser.add_argument("--proc-root", default="/proc", help=argparse.SUPPRESS)
    args = parser.parse_args()

    raw_ignored = args.ignore_processes.strip().lower()
    if raw_ignored == "none":
        IGNORED_PROCESS_NAMES = set()
    else:
        ignored_items = [item.strip() for item in raw_ignored.split(",")]
        if not ignored_items or any(not re.fullmatch(r"[a-z0-9_.+-]+", item) for item in ignored_items):
            parser.error("--ignore-processes must contain comma-separated process names or none")
        IGNORED_PROCESS_NAMES = {safe_process_name(item) for item in ignored_items}

    if not 200 <= args.interval_ms <= 10000:
        parser.error("--interval-ms must be between 200 and 10000")

    output = Path(args.output)
    stop_file = Path(args.stop_file) if args.stop_file else None
    pause_file = Path(args.pause_file) if args.pause_file else None
    proc_root = Path(args.proc_root)
    if not proc_root.is_dir():
        print(f"WSL process tracker: proc filesystem not available: {proc_root}", file=sys.stderr)
        return 2

    writer = JsonlWriter(output)
    owner_uid = os.getuid()
    own_pid = os.getpid()
    interval = args.interval_ms / 1000.0
    tracked: Dict[ProcessKey, dict] = {}
    paused = False
    last_scan = None
    active_elapsed = 0.0
    started = time.monotonic()
    stop_requested = False

    def request_stop(_signum, _frame):
        nonlocal stop_requested
        stop_requested = True

    signal.signal(signal.SIGTERM, request_stop)
    signal.signal(signal.SIGINT, request_stop)

    def finish_process(key: ProcessKey, reason: str) -> None:
        item = tracked.pop(key, None)
        if item is None:
            return
        writer.emit({
            "ts": utc_now(),
            "type": "process_exit",
            "source": "wsl",
            "pid": key[0],
            "process": item["name"],
            "reason": reason,
        })
        runtime = int(item["seconds"] + 0.5)
        if runtime > 0:
            writer.emit({
                "ts": utc_now(),
                "type": "process_usage",
                "source": "wsl",
                "pid": key[0],
                "process": item["name"],
                "runtime_seconds": runtime,
            })

    writer.emit({
        "ts": utc_now(),
        "type": "monitor_start",
        "source": "wsl",
        "poll_interval_ms": args.interval_ms,
        "scope": "current_user",
    })
    print(f"Pomo WSL process monitor is ACTIVE. Output: {output}", flush=True)

    try:
        while not stop_requested:
            if stop_file is not None and stop_file.exists():
                break

            is_paused = pause_file is not None and pause_file.exists()
            if is_paused:
                if not paused:
                    writer.emit({"ts": utc_now(), "type": "monitor_pause", "source": "wsl"})
                    paused = True
                time.sleep(min(interval, 0.25))
                continue
            if paused:
                writer.emit({"ts": utc_now(), "type": "monitor_resume", "source": "wsl"})
                paused = False
                last_scan = None  # Never count elapsed pause time.

            now_mono = time.monotonic()
            current = read_process_snapshot(proc_root, owner_uid, own_pid)
            if last_scan is None:
                delta = 0.0
            else:
                delta = max(0.0, min(now_mono - last_scan, interval * 1.5))
                active_elapsed += delta

            for key, name in current.items():
                if key in tracked:
                    tracked[key]["seconds"] += delta
                else:
                    tracked[key] = {"name": name, "seconds": 0.0}
                    writer.emit({
                        "ts": utc_now(),
                        "type": "process_seen",
                        "source": "wsl",
                        "pid": key[0],
                        "process": name,
                    })

            for key in list(tracked):
                if key not in current:
                    finish_process(key, "exited")

            last_scan = now_mono
            time.sleep(interval)
    finally:
        # Close all currently observed process intervals when monitoring ends.
        for key in list(tracked):
            finish_process(key, "monitor_stop")
        writer.emit({
            "ts": utc_now(),
            "type": "monitor_stop",
            "source": "wsl",
            "elapsed_seconds": round(time.monotonic() - started, 2),
            "active_seconds": round(active_elapsed, 2),
        })
        writer.close()
        print("Pomo WSL process monitor stopped.", flush=True)

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
