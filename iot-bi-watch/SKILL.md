---
name: iot-bi-watch
description: Check every IoT BI Platform board for unusual days, as of today or as of a past date. Use when the user says /iot-bi-watch, asks what is unusual on the IoT BI platform, asks to "run the BI watch" (optionally "as of <date>" / "up to <date>"), or asks a follow-up about a bi-watch report. Also runs unattended every day from 10:00 via cron (catch-up every 15 min).
---

# IoT BI Watch

Code: `~/iot-bi-watch/` (browse.py, look.sh, detect.py, research.py, watch.py (watch list: watchlist.json), summary.py, publish_repo.py, run.sh, daily.sh, catchup.sh). Runs land in
`~/investigations/iot-bi-watch/<date>/`: raw/ = the JSON each board page received, shots/ = a picture of every chart,
charts.json = where each series is drawn (board, chart title, legend line, link), visual.json = what Claude saw on
screen, flags.json = the result.

How it works: browse.py opens every board in headless Chromium (Playwright) with the user's gcloud token in the
`X-Id-Token` header and the board's own default filters, rewound with `#<board>?from&to`, and again per Node type (`&nodeTypes=Cassia|Node2|ULRPM`) on every board
that has that filter. Findings are grouped per board > chart > line, listing each view (All, Node type: X) that is out
of range; views identical to All are dropped (the filter doesn't affect that chart); identical numbers on several
boards are one finding with "also on". Visual notes skip empty charts in Node type views and the window's first day. look.sh has Claude look at
every chart picture. releases.py reads when each node/EP firmware version reached each gradual-release channel
(early_bird_il > early_bird > night_owl > pre_stable > stable) from `gs://augury-production-iot-gradual-release`
(first appearance of the version's file); every flag lists releases from 3 days before it started to its last day,
with their offset from the start. detect.py checks each of the last 3 days of every daily series against its previous 28 days. research.py adds a 50-word BigQuery "Research:" line (nodes, sites, timing) to Offline Nodes findings.
Report: https://github.com/augurysys/iot-bi-watch (README = latest run, reports/<date>.md = every run).
Alerts: an issue in that repo when something is unusual; the user gets it in Slack through the GitHub app.
The daily run is cron (every 15 min from 10:00) -> `catchup.sh` -> `daily.sh` once a day, plain scripts, no Claude. This skill is for asking it things by hand.

## Arguments

- none: run for today.
- a date (`2026-10-01`, "as of Oct 1", "up to Oct 1"): run as if it were that day. Only data before that date is used.
  The platform keeps 90 days, so older dates fail with a clear message. Boards that only show the current state
  (ep-config, phase, uplink, drain, gcp-migration) are skipped for past dates; say so.

## Steps

1. Run `/home/eyifrah/iot-bi-watch/run.sh [DATE]` (always this full path; takes about 10 minutes). It opens every
   board, looks at the charts, flags unusual days and prints a JSON line `{flagged, title, body}` last. If gcloud is logged out the
   fetch fails: tell the user to run `! gcloud auth login`, and stop.
2. Save it to the repo: `python3 /home/eyifrah/iot-bi-watch/publish_repo.py DATE` (add `--latest` only for today's
   date, so a past-date run never replaces the README). Open no issue: issues are the daily run's job.
3. Reply with the title and body, the report link, and for a past date which boards were skipped.

## Rules

- Always point to where a person sees it: board > chart title > line, plus the board link. Report numbers exactly as
  the detector gives them. Never guess what a series means,
  why it moved, or invent labels or thresholds. If the user asks why, look at the raw board JSON or the platform code
  (augurysys/vibe-apps-claude, apps/iot-bi-platform/server.js) and say what the data shows; if it doesn't show it,
  say so.
- The detector compares the last complete day with the previous 28 days. Tuning lives in the constants at the top of
  `detect.py`; change them only when the user asks.
- Known patterns live in `~/iot-bi-watch/expected.json` (board, series, release kind, reason). A matching flag during
  a matching release is dropped: not shown in the issue or the report at all (it stays in flags.json). Add a rule only when the user states the pattern; record
  their reason and the date.
- The report and issue are split into big sections: Nodes, EPs, Other boards, by the board's own title (Node(s) ->
  Nodes, EP(s) -> EPs, both or neither -> Other boards). Move a board only when the user says, via SIDE_OVERRIDES in
  summary.py. Keep the per-finding layout (heading, table with a row per view, releases, Where, chart picture).
- A release near a flag is context, not a cause: say what landed when, never that the release caused it.
- A board that fails to load is a finding: include the platform's error message when asked.
