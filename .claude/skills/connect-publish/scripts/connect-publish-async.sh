#!/usr/bin/env bash
# connect-publish-async.sh -- publish an app to Posit Connect from its COMMITTED
# manifest.json, using plain curl calls. No rsconnect on the runner.
#
# Used by deploy-fastapi.yml, deploy-plumber.yml, deploy-shiny-r.yml and
# deploy-shiny-py.yml. Copy it to .github/scripts/ in your own repo.
#
# Adapted from timothyfraser/fastapi-connect-demo (MIT), the pattern that has
# deployed green repeatedly. The one idea that matters:
#
#   manifest.json is an ENVIRONMENT FINGERPRINT of the machine that wrote it
#   (R or Python version, package versions, a checksum per file). `rsconnect
#   deploy` REWRITES it on whatever machine it runs on. On a CI runner that
#   records the runner instead of your laptop, and Connect then fails to build
#   it. So: write the manifest on your own machine, commit it, and let CI ship
#   it untouched. Nothing in this script can rewrite it.
#
# What it does:
#   0. find your content item on Connect by CONTENT_NAME, or create it the
#      first time (or use CONTENT_GUID if you set one)
#   1. tar up manifest.json + exactly the files the manifest lists
#   2. POST /__api__/v1/content/{guid}/bundles
#   3. POST /__api__/v1/content/{guid}/deploy
#   4. watch GET /__api__/v1/tasks/{id} for POLL_BUDGET_SECONDS, streaming
#      Connect's own log (prefixed `connect>`), then detach
#
# Required env:
#   CONNECT_SERVER    Connect base URL (a repo secret; never printed)
#   CONNECT_API_KEY   Connect publisher API key (a repo secret; never printed)
#   BUNDLE_DIR        folder that holds manifest.json and the app files
#   CONTENT_NAME      unique name for the content item (letters, digits, - _)
# Optional env:
#   CONTENT_TITLE        human title shown in Connect (default: CONTENT_NAME)
#   CONTENT_GUID         deploy to this exact existing item instead of by name.
#                        A WRONG GUID OVERWRITES whatever it points at.
#   POLL_BUDGET_SECONDS  how long to watch the deploy before detaching (120)
#
# Outputs (to $GITHUB_OUTPUT): content_guid, content_url, task_id,
#   deploy_status=succeeded|detached
# Exit 0 = deployed, or still deploying on Connect (detached). Exit 1 = failed.
set -euo pipefail

: "${CONNECT_SERVER:?CONNECT_SERVER is required (add it as a repo secret)}"
: "${CONNECT_API_KEY:?CONNECT_API_KEY is required (add it as a repo secret)}"
: "${BUNDLE_DIR:?BUNDLE_DIR is required}"
: "${CONTENT_NAME:?CONTENT_NAME is required}"
CONTENT_TITLE="${CONTENT_TITLE:-$CONTENT_NAME}"
CONTENT_GUID="${CONTENT_GUID:-}"
POLL_BUDGET_SECONDS="${POLL_BUDGET_SECONDS:-120}"

SERVER="${CONNECT_SERVER%/}"
AUTH=(-H "Authorization: Key ${CONNECT_API_KEY}")
WORKDIR="$(mktemp -d)"
trap 'rm -rf "$WORKDIR"' EXIT

fail() { echo "::error::$*" >&2; exit 1; }
emit() { if [ -n "${GITHUB_OUTPUT:-}" ]; then printf '%s\n' "$1" >> "$GITHUB_OUTPUT"; fi; }

command -v jq >/dev/null || fail "jq is required"
[ -f "${BUNDLE_DIR}/manifest.json" ] \
  || fail "no manifest.json in '${BUNDLE_DIR}'. Write it on YOUR machine and commit it (see .claude/skills/connect-publish/README.md step 3)."

# Connect content names allow only letters, digits, '-' and '_' (max 64).
CONTENT_NAME=$(printf '%s' "$CONTENT_NAME" | tr -c 'A-Za-z0-9_-' '-' | cut -c1-64)

# ------------------------------------------------- 0. find or create content --
if [ -z "$CONTENT_GUID" ]; then
  Q_BODY="${WORKDIR}/find.json"
  Q_CODE=$(curl -sS -o "$Q_BODY" -w '%{http_code}' "${AUTH[@]}" \
    "${SERVER}/__api__/v1/content?name=${CONTENT_NAME}") \
    || fail "could not reach CONNECT_SERVER. Is the secret a full https:// URL?"
  case "$Q_CODE" in
    200) ;;
    401|403) fail "Connect said HTTP ${Q_CODE}: the CONNECT_API_KEY secret is wrong or expired." ;;
    *) fail "looking up content '${CONTENT_NAME}' returned HTTP ${Q_CODE}: $(head -c 300 "$Q_BODY")" ;;
  esac
  CONTENT_GUID=$(jq -r '.[0].guid // empty' "$Q_BODY" | tr -d '\r')
  if [ -z "$CONTENT_GUID" ]; then
    echo "No content named '${CONTENT_NAME}' yet -- creating it (first deploy)."
    C_BODY="${WORKDIR}/create.json"
    C_CODE=$(curl -sS -o "$C_BODY" -w '%{http_code}' "${AUTH[@]}" \
      -X POST "${SERVER}/__api__/v1/content" -H "Content-Type: application/json" \
      -d "$(jq -n --arg n "$CONTENT_NAME" --arg t "$CONTENT_TITLE" '{name: $n, title: $t}')")
    [ "$C_CODE" = "200" ] || [ "$C_CODE" = "201" ] \
      || fail "creating content failed (HTTP ${C_CODE}): $(head -c 300 "$C_BODY"). A 409 means another user already owns that name: change CONTENT_NAME."
    CONTENT_GUID=$(jq -r '.guid' "$C_BODY" | tr -d '\r')
  fi
fi
[ -n "$CONTENT_GUID" ] && [ "$CONTENT_GUID" != "null" ] || fail "no content guid"

T_INFO="${WORKDIR}/content.json"
I_CODE=$(curl -sS -o "$T_INFO" -w '%{http_code}' "${AUTH[@]}" \
  "${SERVER}/__api__/v1/content/${CONTENT_GUID}")
[ "$I_CODE" = "200" ] || fail "content ${CONTENT_GUID} returned HTTP ${I_CODE} (does this key own it?)"
CONTENT_URL=$(jq -r '.content_url' "$T_INFO" | tr -d '\r')
echo "target: '$(jq -r '.title // .name' "$T_INFO" | tr -d '\r')'  guid=${CONTENT_GUID}"
emit "content_guid=${CONTENT_GUID}"
emit "content_url=${CONTENT_URL}"

# ---------------------------------------------------------------- 1. bundle --
# Files = the manifest's own file list + manifest.json. `tr -d '\r'` keeps
# this working from Git Bash on Windows too, where jq prints CRLF.
mapfile -t FILES < <(jq -r '.files | keys[]' "${BUNDLE_DIR}/manifest.json" | tr -d '\r')
[ "${#FILES[@]}" -gt 0 ] || fail "manifest.json lists no files"
MISSING=0
for f in "${FILES[@]}"; do
  if [ ! -f "${BUNDLE_DIR}/${f}" ]; then
    echo "::error::manifest.json lists '${f}' but it is not in ${BUNDLE_DIR}" >&2
    MISSING=1
  fi
done
[ "$MISSING" -eq 0 ] || fail "stale manifest. Re-write it on your machine and commit it."

TARBALL="${WORKDIR}/bundle.tar.gz"
tar -czf "$TARBALL" -C "$BUNDLE_DIR" manifest.json "${FILES[@]}"
echo "bundle: ${#FILES[@]} files + manifest.json ($(wc -c < "$TARBALL") bytes)"

# ---------------------------------------------------------------- 2. upload --
UP_BODY="${WORKDIR}/upload.json"
UP_CODE=$(curl -sS -o "$UP_BODY" -w '%{http_code}' "${AUTH[@]}" \
  -X POST "${SERVER}/__api__/v1/content/${CONTENT_GUID}/bundles" \
  -H "Content-Type: application/gzip" --data-binary @"$TARBALL")
[ "$UP_CODE" = "200" ] || [ "$UP_CODE" = "201" ] \
  || fail "bundle upload failed (HTTP ${UP_CODE}): $(head -c 300 "$UP_BODY")"
BUNDLE_ID=$(jq -r '.id' "$UP_BODY" | tr -d '\r')
[ -n "$BUNDLE_ID" ] && [ "$BUNDLE_ID" != "null" ] || fail "no bundle id in upload response"
echo "uploaded bundle id=${BUNDLE_ID}"

# ---------------------------------------------------------------- 3. deploy --
DEP_BODY="${WORKDIR}/deploy.json"
DEP_CODE=$(curl -sS -o "$DEP_BODY" -w '%{http_code}' "${AUTH[@]}" \
  -X POST "${SERVER}/__api__/v1/content/${CONTENT_GUID}/deploy" \
  -H "Content-Type: application/json" -d "{\"bundle_id\": \"${BUNDLE_ID}\"}")
[ "$DEP_CODE" = "200" ] || [ "$DEP_CODE" = "202" ] \
  || fail "deploy request failed (HTTP ${DEP_CODE}): $(head -c 300 "$DEP_BODY")"
TASK_ID=$(jq -r '.task_id' "$DEP_BODY" | tr -d '\r')
[ -n "$TASK_ID" ] && [ "$TASK_ID" != "null" ] || fail "no task_id in deploy response"
echo "deploy task started: ${TASK_ID}"
emit "task_id=${TASK_ID}"

# ----------------------------------------------- 4. bounded watch, then detach
# Stopping the watch cancels nothing: the build runs on Connect either way.
DEADLINE=$(( $(date +%s) + POLL_BUDGET_SECONDS ))
FIRST=0
while [ "$(date +%s)" -lt "$DEADLINE" ]; do
  T_BODY="${WORKDIR}/task.json"
  T_CODE=$(curl -sS -o "$T_BODY" -w '%{http_code}' "${AUTH[@]}" \
    "${SERVER}/__api__/v1/tasks/${TASK_ID}?wait=5&first=${FIRST}") || T_CODE=000
  if [ "$T_CODE" != "200" ]; then
    echo "task poll HTTP ${T_CODE} (transient?) -- retrying" >&2
    sleep 5
    continue
  fi
  jq -r '.output[]?' "$T_BODY" | sed 's/^/   connect> /'
  FIRST=$(jq -r '.last // 0' "$T_BODY" | tr -d '\r')
  if [ "$(jq -r '.finished' "$T_BODY" | tr -d '\r')" = "true" ]; then
    CODE=$(jq -r '.code' "$T_BODY" | tr -d '\r')
    if [ "$CODE" = "0" ]; then
      echo "deploy finished successfully."
      emit "deploy_status=succeeded"
      exit 0
    fi
    fail "Connect's deploy FAILED (code=${CODE}): $(jq -r '.error // "read the connect> lines above"' "$T_BODY")"
  fi
done

echo "Still building on Connect after ${POLL_BUDGET_SECONDS}s -- detaching (not a failure)."
echo "The next step checks whether the app actually answers."
emit "deploy_status=detached"
exit 0
