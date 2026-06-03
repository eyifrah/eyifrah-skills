#!/usr/bin/env bash
#
# provision.sh — Region-aware Firebase App Hosting provisioner for vibe apps.
#
# Improves on the original (firebase-provision-app) by removing the hardcoded
# us-east4 assumption. App Hosting enforces a HARD cap of 10 backends per region
# that cannot be raised via self-service quota — so when a region fills up,
# provisioning must move to the next region. This script does that automatically.
#
# It performs the two admin actions Rotem used to do by hand, in whichever region
# has free capacity:
#   1. Add the app's <region> hosted.app domain to Firebase Auth authorized domains.
#   2. Create the App Hosting backend, wired to the central monorepo + root dir,
#      and set its default traffic policy.
# Optionally (--deploy) it kicks off the first rollout.
#
# Region selection:
#   - Walks REGION_PRIORITY in order and picks the FIRST region that has BOTH
#       (a) fewer than CAP (10) backends, and
#       (b) an authorized GitHub connection with a repo link to the monorepo.
#   - --region <r> forces a specific region (still validated for capacity + link).
#
# Auth: reuses the Firebase CLI's stored credentials (~/.config/configstore).
#       You must be `firebase login`'d as a user with Editor/Owner on the project.
#
# Usage:
#   provision.sh <APP_NAMESPACE> [--no-deploy] [--branch <branch>] [--region <region>] [--dry-run]
#
# By default it provisions AND kicks off the first rollout (so the app goes live
# in one shot). Pass --no-deploy to provision only. (--deploy still accepted as a
# no-op for backwards compatibility.)
#
set -euo pipefail

# ---- Org config -------------------------------------------------------------
PROJECT="rotem-vibe-app"
MONOREPO_CLONE_URI="https://github.com/augurysys/vibe-apps-claude.git"
SERVICE_ACCOUNT="firebase-app-hosting-compute@rotem-vibe-app.iam.gserviceaccount.com"
CAP=10  # App Hosting hard limit: backends per region
# Region preference order (edit to taste). First with free capacity + a linked
# monorepo connection wins.
REGION_PRIORITY=(us-east4 us-central1 us-east5 europe-west4)

APPHOSTING_API="https://firebaseapphosting.googleapis.com/v1beta"
IDTOOLKIT_API="https://identitytoolkit.googleapis.com/admin/v2"
DEVCONNECT_API="https://developerconnect.googleapis.com/v1"
FB_CLIENT_ID="563584335869-fgrhgmd47bqnekij5i8b5pr03ho849e6.apps.googleusercontent.com"
FB_CLIENT_SECRET="j9iVZfS8kkCEFUPaAeJV0sAi"
CONFIGSTORE="$HOME/.config/configstore/firebase-tools.json"

# ---- Args -------------------------------------------------------------------
NS="${1:-}"
DEPLOY=1   # deploy by default; --no-deploy to skip
BRANCH="master"
FORCE_REGION=""
DRY_RUN=0
shift || true
while [ $# -gt 0 ]; do
  case "$1" in
    --no-deploy) DEPLOY=0 ;;
    --deploy) DEPLOY=1 ;;  # accepted for backwards compatibility (now the default)
    --branch) shift; BRANCH="${1:-master}" ;;
    --region) shift; FORCE_REGION="${1:-}" ;;
    --dry-run) DRY_RUN=1 ;;
    *) echo "Unknown option: $1" >&2; exit 2 ;;
  esac
  shift
done

if [ -z "$NS" ]; then
  echo "Usage: provision.sh <APP_NAMESPACE> [--no-deploy] [--branch <b>] [--region <r>] [--dry-run]" >&2
  exit 2
fi
if ! printf '%s' "$NS" | grep -qE '^[a-z0-9][a-z0-9-]{1,38}[a-z0-9]$'; then
  echo "ERROR: namespace '$NS' is not a valid backend id (lowercase letters, digits, hyphens)." >&2
  exit 2
fi
command -v jq >/dev/null   || { echo "ERROR: jq is required."; exit 1; }
command -v curl >/dev/null || { echo "ERROR: curl is required."; exit 1; }

# ---- Access token -----------------------------------------------------------
get_token() {
  [ -f "$CONFIGSTORE" ] || { echo "ERROR: $CONFIGSTORE not found. Run 'firebase login' first." >&2; exit 1; }
  local refresh tok
  refresh="$(jq -r '.tokens.refresh_token // empty' "$CONFIGSTORE")"
  [ -n "$refresh" ] || { echo "ERROR: no refresh token in configstore. Run 'firebase login' first." >&2; exit 1; }
  tok="$(curl -s -X POST https://oauth2.googleapis.com/token \
    -d "client_id=${FB_CLIENT_ID}" -d "client_secret=${FB_CLIENT_SECRET}" \
    -d "refresh_token=${refresh}" -d "grant_type=refresh_token" | jq -r '.access_token // empty')"
  [ -n "$tok" ] || { echo "ERROR: failed to refresh access token." >&2; exit 1; }
  printf '%s' "$tok"
}
TOKEN="$(get_token)"
AUTH=(-H "Authorization: Bearer ${TOKEN}")

# ---- Region helpers ---------------------------------------------------------
# Count backends in a region.
backend_count() {
  curl -s "${AUTH[@]}" "${APPHOSTING_API}/projects/${PROJECT}/locations/$1/backends" \
    | jq '(.backends // []) | length'
}

# Find a COMPLETE connection in a region that links the monorepo; echo the full
# gitRepositoryLink resource name, or nothing.
find_repo_link() {
  local region="$1" conns conn links link
  conns="$(curl -s "${AUTH[@]}" "${DEVCONNECT_API}/projects/${PROJECT}/locations/${region}/connections" \
    | jq -r '[.connections[]? | select(.installationState.stage=="COMPLETE") | .name] | .[]')"
  for conn in $conns; do
    link="$(curl -s "${AUTH[@]}" "${DEVCONNECT_API}/${conn}/gitRepositoryLinks" \
      | jq -r --arg uri "$MONOREPO_CLONE_URI" '.gitRepositoryLinks[]? | select(.cloneUri==$uri) | .name' \
      | head -1)"
    [ -n "$link" ] && { printf '%s' "$link"; return 0; }
  done
  return 1
}

# Pick a region: forced one if given, else first in priority with capacity + link.
pick_region() {
  local candidates=("${REGION_PRIORITY[@]}")
  [ -n "$FORCE_REGION" ] && candidates=("$FORCE_REGION")
  local r cnt link
  for r in "${candidates[@]}"; do
    cnt="$(backend_count "$r")"
    if [ "$cnt" -ge "$CAP" ]; then
      echo "    $r: $cnt/$CAP backends — FULL, skipping." >&2
      continue
    fi
    if link="$(find_repo_link "$r")"; then
      echo "    $r: $cnt/$CAP backends, monorepo linked — SELECTED." >&2
      printf '%s\t%s' "$r" "$link"
      return 0
    else
      echo "    $r: $cnt/$CAP backends but NO authorized monorepo link — skipping." >&2
      echo "       (authorize a GitHub connection in $r and link $MONOREPO_CLONE_URI)" >&2
    fi
  done
  return 1
}

echo "==> Selecting region (priority: ${REGION_PRIORITY[*]}${FORCE_REGION:+; forced=$FORCE_REGION})"
SEL="$(pick_region)" || { echo "ERROR: no region has free capacity AND a linked monorepo connection." >&2; exit 1; }
REGION="$(printf '%s' "$SEL" | cut -f1)"
REPO_LINK="$(printf '%s' "$SEL" | cut -f2)"
HOSTED_SUFFIX="--${PROJECT}.${REGION}.hosted.app"
DOMAIN="${NS}${HOSTED_SUFFIX}"
ROOT_DIR="apps/${NS}"
URL="https://${DOMAIN}"

echo "==> Provisioning '$NS'  (project=$PROJECT region=$REGION branch=$BRANCH)"
echo "    repo link: $REPO_LINK"
if [ "$DRY_RUN" = "1" ]; then
  if [ "$DEPLOY" = "1" ]; then
    echo "    [dry-run] would add auth domain, create backend, set traffic, AND roll out branch '$BRANCH'. Exiting."
  else
    echo "    [dry-run] would add auth domain, create backend, set traffic (no rollout: --no-deploy). Exiting."
  fi
  echo "    URL would be: $URL"
  exit 0
fi

# ---- Step 1: authorized domain (idempotent) ---------------------------------
echo "--> [1/3] Firebase Auth authorized domain: $DOMAIN"
CFG="$(curl -s "${AUTH[@]}" "${IDTOOLKIT_API}/projects/${PROJECT}/config")"
if printf '%s' "$CFG" | jq -e --arg d "$DOMAIN" '.authorizedDomains | index($d)' >/dev/null; then
  echo "    already present — skipping."
else
  NEW_DOMAINS="$(printf '%s' "$CFG" | jq --arg d "$DOMAIN" '.authorizedDomains + [$d]')"
  RESP="$(curl -s -X PATCH "${AUTH[@]}" -H "Content-Type: application/json" \
    "${IDTOOLKIT_API}/projects/${PROJECT}/config?updateMask=authorizedDomains" \
    -d "$(jq -n --argjson ad "$NEW_DOMAINS" '{authorizedDomains:$ad}')")"
  if printf '%s' "$RESP" | jq -e --arg d "$DOMAIN" '.authorizedDomains | index($d)' >/dev/null; then
    echo "    added."
  else
    echo "ERROR: failed to add authorized domain:" >&2
    printf '%s\n' "$RESP" | jq . >&2 || printf '%s\n' "$RESP" >&2
    exit 1
  fi
fi

# ---- Step 2: create backend (idempotent) ------------------------------------
echo "--> [2/3] App Hosting backend: $NS  (root: $ROOT_DIR)"
EXISTING="$(curl -s "${AUTH[@]}" "${APPHOSTING_API}/projects/${PROJECT}/locations/${REGION}/backends/${NS}")"
if printf '%s' "$EXISTING" | jq -e '.name? // empty' >/dev/null; then
  echo "    backend already exists — skipping creation."
else
  BODY="$(jq -n --arg repo "$REPO_LINK" --arg root "$ROOT_DIR" --arg sa "$SERVICE_ACCOUNT" \
    '{servingLocality:"GLOBAL_ACCESS",
      codebase:{repository:$repo, rootDirectory:$root},
      serviceAccount:$sa,
      labels:{"firebase-tool":"apphosting"}}')"
  OP="$(curl -s -X POST "${AUTH[@]}" -H "Content-Type: application/json" \
    "${APPHOSTING_API}/projects/${PROJECT}/locations/${REGION}/backends?backendId=${NS}" -d "$BODY")"
  OP_NAME="$(printf '%s' "$OP" | jq -r '.name // empty')"
  if [ -z "$OP_NAME" ]; then
    echo "ERROR: backend creation failed:" >&2
    printf '%s\n' "$OP" | jq . >&2 || printf '%s\n' "$OP" >&2
    exit 1
  fi
  echo "    operation started, waiting for completion..."
  for i in $(seq 1 60); do
    OPST="$(curl -s "${AUTH[@]}" "${APPHOSTING_API}/${OP_NAME}")"
    if printf '%s' "$OPST" | jq -e '.done == true' >/dev/null; then
      if printf '%s' "$OPST" | jq -e '.error' >/dev/null; then
        echo "ERROR: backend creation operation failed:" >&2
        printf '%s\n' "$OPST" | jq '.error' >&2
        exit 1
      fi
      echo "    backend created."
      break
    fi
    sleep 5
    [ "$i" = "60" ] && { echo "ERROR: timed out waiting for backend creation." >&2; exit 1; }
  done
fi

# ---- Step 3: default traffic policy -----------------------------------------
echo "--> [3/3] Traffic policy: codebaseBranch=$BRANCH, disabled=true"
TRAFFIC_BODY="$(jq -n --arg b "$BRANCH" \
  --arg name "projects/${PROJECT}/locations/${REGION}/backends/${NS}/traffic" \
  '{name:$name, rolloutPolicy:{codebaseBranch:$b, disabled:true}}')"
TR="$(curl -s -X PATCH "${AUTH[@]}" -H "Content-Type: application/json" \
  "${APPHOSTING_API}/projects/${PROJECT}/locations/${REGION}/backends/${NS}/traffic?updateMask=rolloutPolicy" \
  -d "$TRAFFIC_BODY")"
if printf '%s' "$TR" | jq -e '.name? // .metadata? // empty' >/dev/null; then
  echo "    traffic policy set."
else
  echo "    WARNING: traffic policy response unexpected (continuing):" >&2
  printf '%s\n' "$TR" | jq . >&2 || printf '%s\n' "$TR" >&2
fi

# ---- First rollout (default; disable with --no-deploy) ----------------------
if [ "$DEPLOY" = "1" ]; then
  echo "--> Triggering first rollout from branch '$BRANCH' (requires code already on GitHub)..."
  if command -v firebase >/dev/null; then
    # -b/--force keep this non-interactive (a bare rollouts:create prompts for a
    # branch). Retry a couple times: just after backend creation the repo link
    # can briefly lag before a rollout is accepted.
    rolled_out=0
    for attempt in 1 2 3; do
      if firebase apphosting:rollouts:create "$NS" -b "$BRANCH" --force --project "$PROJECT"; then
        echo "    rollout started — app will be live in a few minutes."
        rolled_out=1
        break
      fi
      [ "$attempt" -lt 3 ] && { echo "    rollout attempt $attempt failed; retrying in 10s..."; sleep 10; }
    done
    if [ "$rolled_out" = "0" ]; then
      echo "    WARNING: rollout failed after 3 attempts (often because code isn't on GitHub yet)." >&2
      echo "    The next push to $ROOT_DIR will deploy automatically via GitHub Actions," >&2
      echo "    or re-run: firebase apphosting:rollouts:create $NS -b $BRANCH --force --project $PROJECT" >&2
    fi
  else
    echo "    WARNING: firebase CLI not found — skipping rollout." >&2
  fi
fi

echo ""
echo "==> Done. App will be served at:"
echo "    $URL"
echo ""
echo "    Region:   $REGION"
echo "    Backend:  $NS"
echo "    Root dir: $ROOT_DIR"
echo "    Auth domain authorized: $DOMAIN"
