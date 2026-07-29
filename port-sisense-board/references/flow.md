# Port flow — concrete recipes

Scratchpad is ephemeral (wiped on session resume). Persistent Sisense defs live in
`~/cockpit-data/sisense-dash/` (`import_queries.json` = every table's verbatim SQL, `model_iot_live.json`,
`<oid>.json`, `<oid>.widgets.json`). If scratchpad `server.js`/`app.html` are gone, pull them from repo
master (they're the source of truth).

## 1. Fetch board (Sisense API)
Base `https://augury.sisense.com`. Always send a browser `User-Agent` + `Authorization: Bearer <token>`
(`tr -d ' \t\r\n' < ~/.sisense.token`).

- Confirm the oid still exists: `GET /api/v1/dashboards` (list all; a deleted board is simply absent).
- Widgets: `GET /api/v1/dashboards/{oid}/widgets` → each `metadata.panels[].items[].jaql`.
  If it 404s but the board exists in the list, the oid is stale — find the current one in the list.
- Dashboard filters: `GET /api/v1/dashboards/{oid}` → `.filters[].jaql` (`.filter.last` = window,
  `.filter.filter.turnedOff` = disabled). Save `<oid>.widgets.json`.

## 2. Resolve measures
Per widget, per value/category item: `jaql.formula` with `jaql.context[HASH] = {table,column,filter}`.
Substitute each `[HASH]` → `table.column`. `filter.members` = member filter. Skip `RICHTEXT_MAIN`.

## 3. Pull live Sisense targets (rendered values)
`POST /api/datasources/{urlencoded 'IOT - Live'}/jaql` body
`{datasource, metadata:[<verbatim widget items> + <baseline filters as {jaql,panel:'scope'}>], count:N}`
→ `.values` (rows of `{data,text}`). Baseline filter jaql:
```
status_ota_channel members=[5 mainline]; is_installed members=['true'];
company_name exclude.members=[demo set]; dwh_dim_time.day_date level='days'
  filter={last:{count:<window>,offset:0}, isNotCurrentPeriod:true}
```
Indicator widgets sometimes error via this POST — get their value from a sibling pie/aggregate instead.
Include a widget's own `panel:'filters'` items when it has a window/member override.

## 4. Reproduce in BQ
Bill `bi-production-336411`, read `production-02cb28ec`. Build CTEs from `import_queries.json` verbatim,
join, filter, diff vs the live target. Standard joins:
`node_states.node_uuid = dwh_dim_nodes.uuid`; `endpoint_connections.node_uuid = dwh_dim_nodes.uuid`;
`sample_stats.nodeId = dwh_dim_nodes.uuid`; `*.timestamp_id = dwh_dim_time.day_id`;
`downstream.node_uuid`; `vw_ble_adapter_failures.node_uuid`; `latest_*` on node_uuid/mac.
Window (exclude today): `t.day_date >= DATE_SUB(CURRENT_DATE(), INTERVAL <N> DAY) AND t.day_date < CURRENT_DATE()`.
`ROLLUP(day)` gives per-day rows + a grand-total row (day IS NULL) in one scan. `GROUP BY GROUPING SETS`
gives several distributions + a total in one scan (tag rows with `GROUPING()`).
Bool-ish columns may be BOOL or 'true'/'false' strings → `SAFE_CAST(col AS BOOL)`.

## 5. Build — server.js
- Embed each Sisense import query **verbatim** as a `const IQ_<table> = "<json-escaped SQL>";`
  (generate with `json.dumps(sql)` so newlines/quotes/backticks survive).
- Reuse helpers: `dimClause(f)` (installed/company/channel on alias `n`, param-bound);
  `whereClause(f)` (adds day window on alias `t`; `f.exclToday` toggles the isNotCurrentPeriod form);
  `runQuery(sql,params,types)` (labels `{app:'iot-bi-platform'}`).
- Per board: `async function fetch<Board>Data(f)` runs the queries (`Promise.all`), maps rows → arrays
  `days:[...]` + per-series arrays / pie `[{name,value}]`, returns `{kpi, ...series, options, filters}`.
- Route `app.get('/api/<board>', requireAuth, …)`: clamp days, csv filters, Firestore 1h cache keyed on
  filters (`CACHE_TTL_MS`), `refresh=true` bypass. Copy an existing route verbatim and swap the fetch fn.

## 5. Build — private/app.html
- `DASHBOARDS[]` (sidebar; drop `soon:true` to enable), `BOARDS{}` (`{id:{title,endpoint,defaultDays,
  render}}`), `VALIDATED{}` (`id:false`). `__switchBoard` sets title, resets `filters.days` to the
  board default, reloads. `__load` fetches `BOARDS[activeBoard].endpoint`, calls its `render`, and
  toggles `#unval` via `!VALIDATED[activeBoard]`.
- `render<Board>Grid(d)` builds `#grid` innerHTML from `indicator(...)` / `chartWidget(...)` cells
  (12-col), then `charts.push(...)` with the draw helpers:
  `drawMulti(id,days,series,yFmt,tipFmt)` (bar/line, multi-series), `drawPie(id,[{name,value}])` (donut),
  `drawStacked(id,cats,series)` (stacked bar). Formatters: `bigNum`, `fmtInt`, `fmtPct1` (0–1 ratio),
  percent-of-100 → `v.toFixed(0)+'%'`.
- A per-day chart needs the measure grouped by day; a snapshot pie uses dim-only data.

## 6. Render-test (catches JS errors — no `node` in env)
Transform `app.html` → a harness: replace the firebase import/auth block with
`window.fetch = async()=>({ok:true,json:async()=>FIX})` (FIX = a synthetic or real fixture),
stub `window.__signOut`, then at module end `showApp({email:'t@augury.com',...}); setTimeout(()=>
__switchBoard('<id>'),50);` and capture `pageerror`. Load with Playwright + system Chrome
(`channel="chrome", args=["--no-sandbox"]`), assert 0 errors and expected `.w`/`canvas` counts.

## 7. Deploy (master is protected)
```
BR=<board>-board; MASTER=$(gh api repos/OWNER/REPO/git/ref/heads/master --jq .object.sha)
gh api repos/.../git/refs -f ref=refs/heads/$BR -f sha=$MASTER   # or PATCH --force to reset
# PUT each file: base64 -w0, gh api -X PUT contents/<path> --input - with {message,content,sha,branch}
gh pr create --base master --head $BR ...; gh pr merge <n> --squash --admin
```
Repo `augurysys/vibe-apps-claude`; files `apps/iot-bi-platform/server.js` +
`apps/iot-bi-platform/private/app.html`. Branch names: lowercase, no slashes.

## 8. Verify live (never assume)
App Hosting (project `rotem-vibe-app`, backend `iot-bi-platform`) rebuilds async after merge — watch the
GH Action, then **poll the new route**: `curl -s -o /dev/null -w '%{http_code}' <url>/api/<board>` must
become **302** (auth redirect = route exists). A **200** means it hit the catch-all login page = not
deployed yet. `/` returns 200 (login) and its `<title>` confirms the app is up.

## 9. Hand off
Add the board with its `VALIDATED` entry `false` (banner on), update
`~/cockpit-data/specs/iot-bi-platform-validation-state.md`, and prompt the user to eyeball it against
live Sisense with the board's default filters. On sign-off: flip `VALIDATED[id]=true`, mark MANUAL ✅,
redeploy.

## Known deferrals / gaps to state, not hide
- Status·Nodes: 3 "per-version over time" line charts not ported.
- Status·EP: device-config-OTA widget omitted (mongo join null).
- EPs Conn&Consumption: 9 exotic widgets deferred (cross-fact "% consumed samples",
  `vw_ep_sample_consumption_error_type` + `fact_endpoints` breakdowns).
- Nodes connection type: `network_type` pie ~4.5k vs Sisense 3.5k top bucket — under reconciliation.
- EPs Only: source dashboard deleted — unportable.
