#!/usr/bin/env python3
"""Manage /home/eyifrah/nudges.md: add (with dedup), list, done.

The file is always rewritten sorted by person (case-insensitive), with each
person's rows kept in insertion order. Person names are canonicalized so
case/first-name variants ("nathan" vs "Nathan Gurfinkel") collapse to one.
"""
import re
import sys
from pathlib import Path

FILE = Path("/home/eyifrah/nudges.md")
HEADER = """# nudges

People who need to do something — I double-check they did it.

| Who | What | Status |
|-----|------|--------|
"""


def norm(text):
    """Lowercase, collapse whitespace — for comparison only."""
    return re.sub(r"\s+", " ", text).strip().lower()


def load():
    """Return list of (who, what, status) rows."""
    if not FILE.exists():
        return []
    rows = []
    for line in FILE.read_text().splitlines():
        line = line.strip()
        if not line.startswith("|"):
            continue
        cells = [c.strip() for c in line.strip("|").split("|")]
        if len(cells) != 3 or cells[0].lower() == "who" or set(cells[0]) <= {"-"}:
            continue
        rows.append(tuple(cells))
    return rows


def canonical_who(who, rows):
    """Reuse an existing person's display name if this refers to the same one.

    Match on the first name token, case-insensitive. Keep the longer (more
    complete) form as canonical.
    """
    first = norm(who).split(" ")[0]
    for existing, _, _ in rows:
        if norm(existing).split(" ")[0] == first:
            return existing if len(existing) >= len(who) else who
    return who


def is_dup(who, what, rows):
    """Same person + one 'what' contains the other → duplicate."""
    nwho, nwhat = norm(who), norm(what)
    for ewho, ewhat, _ in rows:
        if norm(ewho).split(" ")[0] != nwho.split(" ")[0]:
            continue
        a, b = nwhat, norm(ewhat)
        if a in b or b in a:
            return (ewho, ewhat)
    return None


def unify_names(rows):
    """Collapse first-name variants to one display form (longest, title-cased)."""
    best = {}
    for who, _, _ in rows:
        key = norm(who).split(" ")[0]
        if key not in best or len(who) > len(best[key]):
            best[key] = who
    return [(best[norm(w).split(" ")[0]].title(), t, s) for w, t, s in rows]


def save(rows):
    rows = unify_names(rows)
    rows = sorted(rows, key=lambda r: norm(r[0]))  # stable: person order preserved within
    lines = [f"| {w} | {t} | {s} |" for w, t, s in rows]
    FILE.write_text(HEADER + "\n".join(lines) + "\n")


def cmd_list():
    rows = load()
    if not rows:
        print("(no nudges)")
        return
    save(rows)  # normalize + re-sort on every read
    for w, t, s in load():
        print(f"| {w} | {t} | {s} |")


def cmd_add(who, what):
    rows = load()
    dup = is_dup(who, what, rows)
    if dup:
        print(f"skip (duplicate of): | {dup[0]} | {dup[1]} |")
        return
    who = canonical_who(who, rows)
    rows.append((who, what, "Open"))
    save(rows)
    print(f"added: | {who} | {what} | Open |")


def cmd_done(who, what_sub):
    rows = load()
    nwho, nsub = norm(who).split(" ")[0], norm(what_sub)
    hit = False
    out = []
    for w, t, s in rows:
        if norm(w).split(" ")[0] == nwho and nsub in norm(t):
            s, hit = "Done", True
            print(f"done: | {w} | {t} |")
        out.append((w, t, s))
    if not hit:
        print("no match")
        return
    save(out)


def main():
    args = sys.argv[1:]
    if not args:
        cmd_list()
        return
    cmd, rest = args[0], args[1:]
    if cmd == "list":
        cmd_list()
    elif cmd == "add" and len(rest) == 2:
        cmd_add(*rest)
    elif cmd == "done" and len(rest) == 2:
        cmd_done(*rest)
    else:
        print("usage: nudge.py [list] | add <who> <what> | done <who> <what-substring>")
        sys.exit(1)


if __name__ == "__main__":
    main()
