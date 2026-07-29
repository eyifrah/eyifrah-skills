---
name: port-sisense-board
description: >-
  Port a Sisense "IOT - Live" dashboard into the in-house IoT BI Platform vibe app
  (augurysys/vibe-apps-claude, apps/iot-bi-platform). Use whenever the user wants to add,
  reproduce, migrate, or "port" a Sisense board to the platform, replace a Sisense OTA/FW
  dashboard, or fix/validate a ported board. Wraps the full reproduce → validate → build →
  deploy → manual-sign-off flow and every hard-won nuance (filter traps, drift, latest-snapshot
  tables, DUPCOUNT semantics, the not-validated banner).
---

# Port a Sisense board to the IoT BI Platform

The platform replaces the Sisense dashboards the FW-release team uses. It reads BigQuery directly,
reproducing **Sisense's own queries** — never invented ones. App: `augurysys/vibe-apps-claude`,
`apps/iot-bi-platform/` (Express `server.js` + `private/app.html`, ECharts, @augury SSO, Firestore
1h cache). Live: `https://iot-bi-platform--rotem-vibe-app.us-east5.hosted.app/app`.

## The prime directive
**Reproduce ONLY Sisense's exact query. Never invent measures, thresholds, or labels.** You don't
own the semantics; guessing creates bugs. Where a measure won't fit, surface the specific gap and
reconcile with the user — do not paper over it. A board is only *done* after the user **manually**
eyeballs it against live Sisense (the auto JAQL-vs-BQ check is necessary, not sufficient).

## Flow (per board)

1. **Fetch the board.** Get the current oid (dashboards get deleted/republished — verify it still
   exists in the live list). Save widgets + dashboard def.
2. **Resolve measures.** For each non-RICHTEXT widget, resolve every `[HASH]` context ref to its
   `table.column` and any member filter. Note category (breakdown) columns and the value agg.
3. **Pull live Sisense targets** via the JAQL API (rendered values) with the baseline filter set.
4. **Reproduce in BQ** from Sisense's verbatim import-query SQL + the same joins/filters. Diff every
   number against the live Sisense value. Match, or reconcile the gap with the user.
5. **Build** the server endpoint + frontend view (patterns below).
6. **Render-test** the frontend headless (0 JS errors, charts drawn).
7. **Deploy** (branch → PR → squash-merge), then **verify the new route is live** (302, not 200).
8. **Add the board unvalidated** (banner on) and **prompt the user to manually validate**. Record in
   `~/cockpit-data/specs/iot-bi-platform-validation-state.md`.

Read `references/flow.md` for the exact API calls, SQL scaffolds, and deploy commands.

## Non-negotiable nuances (each cost us a bug)

- **Validate against LIVE Sisense, not saved targets.** Rendered values drift — an active OTA rollout
  moved an app_version bucket 8135→8642 in 2 days. If a number looks off, re-pull the Sisense value
  *now* before concluding it's a bug.
- **Filter-state trap.** The saved `.dash` carries stale `company_name`/`facility_name`/`uuid`
  selections that are **turned off** in the live view (nested `filter.turnedOff`). Ignore them. Use
  the **baseline**: 5 mainline OTA channels (`gradual_deploy_early_bird`, `_early_bird_il`,
  `_night_owl`, `_pre_stable`, `stable`) + `is_installed=true` + exclude demo companies
  (`Augury - Live Demo`,`Demo`,`QA`,`Tests`) + the date window. Confirm by matching live JAQL.
- **Window.** `isNotCurrentPeriod:true` ⇒ **exclude today**. Board default windows vary (Time-to-Cloud
  7d, Nodes/Smart/Status 90d, Conn-type 7d). Individual widgets can **override** the window (e.g.
  network_type = last 1 day). Honor per-widget overrides.
- **"Latest per entity" snapshot tables** (`latest_node_state`, `latest_ep_connection_event`): one
  row per node/mac, **no day grain** — pies over them use dim filters only, not the day window. If the
  view still has history, dedup to newest row per key (`QUALIFY ROW_NUMBER() OVER(PARTITION BY key
  ORDER BY timestamp DESC)=1`).
- **JAQL measure semantics.** `DUPCOUNT(x)` = `COUNT(x)` over **all** rows (non-distinct);
  `count(x)`/`COUNT(DISTINCT x)` = distinct. A ratio `(dupcount(x), member-filter)/dupcount(x)` =
  `COUNTIF(member)/COUNT(x)`. Distribution "communicating" counts usually = `COUNT(DISTINCT uuid/mac)`
  grouped by a dim column.
- **Drop broken source widgets — flag, don't fake.** The BLE "normalized per 1,000 nodes" widget
  divided by a `DUPCOUNT(dwh_dim_nodes.uuid)` that swung 20→92,276/day (meaningless). We dropped it and
  noted it. Do the same for any measure that's broken at the source; never substitute a "corrected" one.
- **Deleted source boards can't be ported** (EPs Only vanished from Sisense). State it; don't fabricate.
- **`dwh_dim_endpoints` is allowlist-sensitive** — normally needs explicit user permission. Its
  device-config OTA comes via a mongo-config join that can return all-null; omit that widget if so.
- **UI rules:** no "Sisense" or "OTA" strings in the app; no decorative emojis (use SVG + plain text);
  cache 1h with a "results are X min old — hit Refresh" indicator.
- **Cost:** bill jobs to `bi-production-336411`, cross-project read `production-02cb28ec`; label jobs
  `{app: 'iot-bi-platform'}`; cost is incurred only on cache miss. Combine per-scan measures with
  `GROUP BY GROUPING SETS` to avoid re-scanning big facts (endpoint_connections/downstream are huge).

## The "not manually validated" banner
Every board renders an amber banner until signed off. Mechanism: a `VALIDATED` map in `app.html`
(`{'<board-id>': false, …}`) and an `#unval` strip toggled in `__load` via
`uv.classList.toggle('show', !VALIDATED[activeBoard])`. **New boards ship with their entry `false`.**
On the user's manual sign-off: flip that entry to `true`, flip MANUAL ✅ in the validation-state doc,
redeploy — the banner disappears for that board only. Never pre-flip it yourself.

## Token & auth
Sisense token at `~/.sisense.token` — **KEEP, never delete** (user directive). Sisense needs a browser
`User-Agent` (Cloudflare 403s otherwise) + `Bearer`. BigQuery needs `gcloud auth login` (a login only
the user can do; prompt with `! gcloud auth login --update-adc` if `bq` fails auth).

See `references/flow.md` for concrete commands, the server/frontend code patterns, and the deploy +
render-test recipes.
