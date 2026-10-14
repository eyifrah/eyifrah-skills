---
name: iot-bi-watch
description: Check every IoT BI Platform board for unusual days, as of today or as of a past date. Use when the user says /iot-bi-watch, asks what is unusual on the IoT BI platform, asks to "run the BI watch" (optionally "as of <date>" / "up to <date>"), or asks a follow-up about a bi-watch report. Also runs unattended every day at noon from cron.
---

# IoT BI Watch

Code: `~/iot-bi-watch/` (fetch.py, detect.py, summary.py, publish_repo.py, run.sh, daily.sh). Runs land in
`~/investigations/iot-bi-watch/<date>/` (raw/ = board JSON, flags.json = result).
Report: https://github.com/augurysys/iot-bi-watch (README = latest run, reports/<date>.md = every run).
Alerts: an issue in that repo when something is unusual; the user gets it in Slack through the GitHub app.
The noon run is cron -> `daily.sh`, plain scripts, no Claude. This skill is for asking it things by hand.

## Arguments

- none: run for today.
- a date (`2026-10-01`, "as of Oct 1", "up to Oct 1"): run as if it were that day. Only data before that date is used.
  The platform keeps 90 days, so older dates fail with a clear message. Boards that only show the current state
  (ep-config, phase, uplink, drain, gcp-migration) are skipped for past dates; say so.

## Steps

1. Run `/home/eyifrah/iot-bi-watch/run.sh [DATE]` (always this full path). It fetches all boards with the user's
   gcloud login, flags unusual days and prints a JSON line `{flagged, title, body}` last. If gcloud is logged out the
   fetch fails: tell the user to run `! gcloud auth login`, and stop.
2. Save it to the repo: `python3 /home/eyifrah/iot-bi-watch/publish_repo.py DATE` (add `--latest` only for today's
   date, so a past-date run never replaces the README). Open no issue: issues are the noon run's job.
3. Reply with the title and body, the report link, and for a past date which boards were skipped.

## Rules

- Report numbers, the board, and the series key exactly as the detector gives them. Never guess what a series means,
  why it moved, or invent labels or thresholds. If the user asks why, look at the raw board JSON or the platform code
  (augurysys/vibe-apps-claude, apps/iot-bi-platform/server.js) and say what the data shows; if it doesn't show it,
  say so.
- The detector compares the last complete day with the previous 28 days. Tuning lives in the constants at the top of
  `detect.py`; change them only when the user asks.
- A board that fails to load is a finding: include the platform's error message when asked.
