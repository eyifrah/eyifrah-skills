#!/usr/bin/env python3
"""Track live Claude Code sessions so they can be resumed after a reboot.

  sessions.py snapshot   record live sessions to ~/claude-sessions/live.json (run by cron)
  sessions.py list       show the last snapshot
  sessions.py restore       reopen each snapshot session in a gnome-terminal tab via `claude --resume`
  sessions.py boot-restore  restore, but only if the snapshot is from a previous boot (login autostart)
"""
import json
import os
import shlex
import subprocess
import sys
import time
from pathlib import Path

SESSIONS_DIR = Path.home() / ".claude" / "sessions"
SNAPSHOT = Path.home() / "claude-sessions" / "live.json"


def boot_id():
    return Path("/proc/sys/kernel/random/boot_id").read_text().strip()


def proc_start(pid):
    # Field 22 of /proc/<pid>/stat; the session file stores it to guard against pid reuse.
    stat = Path(f"/proc/{pid}/stat").read_text()
    return stat.rsplit(")", 1)[1].split()[19]


def flags(pid):
    """Original CLI flags, minus resume/continue (restore adds its own --resume)."""
    args = [arg for arg in Path(f"/proc/{pid}/cmdline").read_bytes().decode().split("\0")[1:] if arg]
    kept = []
    skip_next = False
    for arg in args:
        if skip_next:
            skip_next = False
        elif arg in ("--resume", "-r"):
            skip_next = True
        elif arg not in ("--continue", "-c") and not arg.startswith("--resume="):
            kept.append(arg)
    return kept


def live_sessions():
    sessions = []
    for path in sorted(SESSIONS_DIR.glob("*.json")):
        try:
            meta = json.loads(path.read_text())
            pid = meta["pid"]
            if proc_start(pid) != meta.get("procStart"):
                continue
            sessions.append({
                "name": meta.get("name"),
                "sessionId": meta["sessionId"],
                "cwd": meta["cwd"],
                "flags": flags(pid),
                "kind": meta.get("kind"),
                "startedAt": meta.get("startedAt"),
            })
        except (OSError, ValueError, KeyError, IndexError):
            continue
    return [s for s in sessions if s["kind"] == "interactive"]


def snapshot():
    sessions = live_sessions()
    # An empty list usually means we are mid-shutdown and the terminals already died;
    # keep the previous snapshot so the reboot still has something to restore.
    if not sessions:
        return
    SNAPSHOT.parent.mkdir(parents=True, exist_ok=True)
    tmp = SNAPSHOT.with_suffix(".tmp")
    tmp.write_text(json.dumps({
        "bootId": boot_id(),
        "takenAt": time.strftime("%Y-%m-%d %H:%M:%S"),
        "sessions": sessions,
    }, indent=2))
    tmp.replace(SNAPSHOT)


def load():
    if not SNAPSHOT.exists():
        sys.exit(f"No snapshot at {SNAPSHOT}")
    return json.loads(SNAPSHOT.read_text())


def list_snapshot():
    data = load()
    same_boot = "this boot" if data["bootId"] == boot_id() else "previous boot"
    print(f"Snapshot {data['takenAt']} ({same_boot}), {len(data['sessions'])} sessions:")
    for session in data["sessions"]:
        print(f"  {session['name']:<14} {session['sessionId']}  {session['cwd']}  {' '.join(session['flags'])}")


def restore():
    data = load()
    running = {s["sessionId"] for s in live_sessions()}
    for session in data["sessions"]:
        if session["sessionId"] in running:
            print(f"skip {session['name']}: already running")
            continue
        command = shlex.join(["claude", "--resume", session["sessionId"], *session["flags"]])
        subprocess.Popen([
            "gnome-terminal", "--tab", f"--working-directory={session['cwd']}",
            "--", "bash", "-lc", f"{command}; exec bash",
        ])
        print(f"restored {session['name']} ({session['sessionId']}) in {session['cwd']}")


def boot_restore():
    """Login autostart: restore only when the snapshot predates this boot, so re-logins don't reopen."""
    if SNAPSHOT.exists() and load()["bootId"] != boot_id():
        restore()


COMMANDS = {"snapshot": snapshot, "list": list_snapshot, "restore": restore, "boot-restore": boot_restore}

if __name__ == "__main__":
    if len(sys.argv) != 2 or sys.argv[1] not in COMMANDS:
        sys.exit(__doc__)
    COMMANDS[sys.argv[1]]()
