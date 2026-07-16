---
name: nudge
description: >-
  Manage the personal nudge list at /home/eyifrah/nudges.md — people who owe an
  action that the user double-checks got done. Use whenever the user says
  'nudge <person> to <do X>', 'add a nudge', 'who owes me', 'show my nudges',
  'mark <person>'s <thing> done', or reviews the list. Every add is deduped and
  the file is always rewritten sorted by person with names canonicalized, so the
  list stays clean without manual tidying.
---

# Nudge list

`/home/eyifrah/nudges.md` is a markdown table of people who owe an action. All
reads and writes go through `scripts/nudge.py` — never hand-edit the table, so
dedup + sort + name canonicalization stay enforced.

## Commands

```
python3 ~/.claude/skills/nudge/scripts/nudge.py            # list (also normalizes the file)
python3 ~/.claude/skills/nudge/scripts/nudge.py list
python3 ~/.claude/skills/nudge/scripts/nudge.py add  "<who>" "<what>"
python3 ~/.claude/skills/nudge/scripts/nudge.py done "<who>" "<what-substring>"
```

## What the script guarantees

- **Sorted by person** — rows grouped by person (case-insensitive), each
  person's rows in insertion order.
- **Dedup on add** — same person + one 'what' containing the other → skipped,
  reports the existing row. No duplicate nudges.
- **Name canonicalization** — first-name variants collapse to one title-cased
  display form (`nathan` + `Nathan Gurfinkel` → `Nathan Gurfinkel`). Runs on
  every write, so the whole file self-heals.
- `done` marks matching rows `Done` (matched by person + substring of 'what').

## Workflow

When the user creates or reads a nudge, run the script rather than editing the
file. On add, relay whether it was added or skipped as a dup. On list/review,
print the sorted table. The file is safe to normalize any time — `list` does it.
