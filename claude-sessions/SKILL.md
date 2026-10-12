---
name: claude-sessions
description: >-
  Track which Claude Code sessions are live on this machine and resume them after a
  reboot. Use when the user asks which sessions were open before a reboot, wants to
  restore or reopen their previous Claude sessions, or asks about the session snapshot.
---

# Claude sessions tracker

A cron job runs `scripts/sessions.py snapshot` every minute. It reads
`~/.claude/sessions/*.json`, keeps the interactive sessions whose process is still
alive, and writes them to `~/claude-sessions/live.json` with session id, name, cwd,
original CLI flags, and the boot id.

An empty result is never written, so a snapshot taken mid-shutdown does not wipe the
list. Side effect: if every session was closed by hand before a reboot, the old list
survives and restore would reopen them.

## Commands

```
~/.claude/skills/claude-sessions/scripts/sessions.py list      # show the last snapshot and whether it is from this boot
~/.claude/skills/claude-sessions/scripts/sessions.py restore   # open each one in a gnome-terminal tab: claude --resume <id> <flags>
~/.claude/skills/claude-sessions/scripts/sessions.py snapshot  # take a snapshot now
```

`restore` skips sessions that are already running. Run `list` first and show the user
what will be reopened before running `restore`.
