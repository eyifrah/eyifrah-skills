---
name: firebase-provision-app-multiregion
description: >-
  Region-aware Firebase App Hosting provisioner for vibe apps. Creates the App
  Hosting backend and authorizes its auth domain, automatically choosing the
  first region with free quota (App Hosting caps backends at 10 per region and
  that cap can't be self-service raised). Use whenever a new vibe app needs its
  Firebase backend created — especially when the default region (us-east4) is at
  its 10-backend cap, or when someone says 'provision the app', 'create the
  firebase backend', 'set up hosting for <app>', 'the region is full', or 'make
  the app live in another region'. Discovers the GitHub connection + monorepo
  repo link per region dynamically, so it works in any region that's been
  authorized.
---

# Firebase App Provisioner (multi-region)

Region-aware successor to `firebase-provision-app`. Same two admin actions
(authorize the auth domain + create the App Hosting backend wired to the
`augurysys/vibe-apps-claude` monorepo), but it **picks the region automatically**
instead of hardcoding `us-east4`.

## Why this exists

App Hosting enforces a **hard cap of 10 backends per region** that **cannot be
raised via self-service quota** (the Cloud Console quota editor only accepts
0–10). When a region fills up, the only options are: delete a backend, or move
to another region. This skill walks a priority list of regions and provisions
into the first one with free capacity **and** an authorized monorepo connection.

## Prerequisites

- `firebase login` as a project Editor/Owner (creds read from `~/.config/configstore`).
- `jq`, `curl`, and the `firebase` CLI on PATH.
- The target region must have an **authorized GitHub connection** (Developer
  Connect, state `COMPLETE`) with a **repo link** to
  `https://github.com/augurysys/vibe-apps-claude.git`. See "Authorizing a new
  region" below — this is a one-time, browser-based step per region.

## Usage

`NS` is the app namespace (the backend id), e.g. `weekly-wins-a3f8b2`.

```bash
# Auto-pick region AND deploy (default): provisions, then kicks off the first
# rollout so the app goes live in one shot. Code must already be on master
# under apps/<NS>/.  (priority: us-east4 → us-central1 → us-east5 → europe-west4)
bash ~/.claude/skills/firebase-provision-app-multiregion/scripts/provision.sh <NS>

# Provision only, no rollout (e.g. code isn't pushed yet)
bash ~/.claude/skills/firebase-provision-app-multiregion/scripts/provision.sh <NS> --no-deploy

# Force a specific region
bash ~/.claude/skills/firebase-provision-app-multiregion/scripts/provision.sh <NS> --region us-central1

# Preview region selection without changing anything
bash ~/.claude/skills/firebase-provision-app-multiregion/scripts/provision.sh <NS> --dry-run
```

The script is **idempotent** (re-running skips an existing auth domain / backend)
and the served URL is region-specific:
`https://<NS>--rotem-vibe-app.<region>.hosted.app`

**Rollout is on by default** — no separate step or second chat needed. The
rollout call is non-interactive (`-b <branch> --force`) and retries a few times
since the repo link can briefly lag right after backend creation. Pass
`--no-deploy` to skip it. (`--deploy` is still accepted as a no-op.)

## What the script does

1. Refreshes a Google access token from the Firebase CLI's stored refresh token.
2. **Region selection** — walks `REGION_PRIORITY`; for each region checks
   backend count `< 10` AND finds a `COMPLETE` GitHub connection with a repo link
   to the monorepo. First match wins (or `--region` forces one, still validated).
3. **Auth domain** — appends `<NS>--rotem-vibe-app.<region>.hosted.app` to
   Identity Toolkit `authorizedDomains` (idempotent).
4. **Backend** — POSTs to the App Hosting API with the region's discovered repo
   link and `rootDirectory=apps/<NS>`, polls the LRO to completion.
5. **Traffic policy** — follows branch `master`, auto-deploy `disabled` (matching
   existing vibe backends — GitHub Actions / explicit rollouts deploy).
6. **Deploy** (default; skip with `--no-deploy`) — `firebase
   apphosting:rollouts:create <NS> -b <branch> --force`, retried up to 3×.

## Config (top of provision.sh — edit to taste)

| Key | Value |
|---|---|
| `PROJECT` | `rotem-vibe-app` |
| `MONOREPO_CLONE_URI` | `https://github.com/augurysys/vibe-apps-claude.git` |
| `CAP` | `10` (App Hosting per-region hard limit) |
| `REGION_PRIORITY` | `us-east4 us-central1 us-east5 europe-west4` |
| `SERVICE_ACCOUNT` | `firebase-app-hosting-compute@rotem-vibe-app.iam.gserviceaccount.com` |

## Authorizing a new region (one-time, browser step)

If a region has no authorized connection, the script skips it and tells you. To
enable it:

1. Create a connection (returns a `PENDING_USER_OAUTH` action URL):
   ```bash
   curl -s -X POST -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" \
     "https://developerconnect.googleapis.com/v1/projects/rotem-vibe-app/locations/<REGION>/connections?connectionId=apphosting-github-conn-<suffix>" \
     -d '{"githubConfig":{"githubApp":"FIREBASE"}}'
   ```
2. Open the connection's `installationState.actionUri` in a browser, sign in with
   the GitHub robot account, and authorize Developer Connect for the
   `augurysys/vibe-apps-claude` repo. The connection moves to `COMPLETE`.
3. Create the repo link:
   ```bash
   curl -s -X POST -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" \
     "https://developerconnect.googleapis.com/v1/projects/rotem-vibe-app/locations/<REGION>/connections/<conn>/gitRepositoryLinks?gitRepositoryLinkId=augurysys-vibe-apps-claude" \
     -d '{"cloneUri":"https://github.com/augurysys/vibe-apps-claude.git"}'
   ```
As of this skill's creation, **us-east4, us-central1, us-east5, and europe-west4
are all authorized and linked.**

## Troubleshooting

- **"no region has free capacity AND a linked monorepo connection"** → every
  priority region is either full (10/10) or unauthorized. Free a slot
  (`firebase apphosting:backends:delete <NS> --force`) or authorize another region.
- **"NO authorized monorepo link" for a region** → complete the browser auth +
  repo-link steps above for that region.
- **403 / permission denied** → the logged-in user lacks Editor/Owner.
- **rollout fails right after provisioning** → code isn't on GitHub yet; push
  `apps/<NS>/**` to `master`.
