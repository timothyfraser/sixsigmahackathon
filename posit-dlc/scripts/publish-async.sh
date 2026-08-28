#!/usr/bin/env bash
# publish-async.sh — upload the committed bundle, start the deploy, DO NOT BLOCK.
#
# Uses the Connect REST API directly. Deliberately does NOT run rsconnect, so:
#   - the committed manifest is never regenerated from this machine (core/03)
#   - rsconnect-python issue #532 (env key vs --api-key flag) cannot bite
#
# Blocking on Connect's server-side environment restore bills that build to your
# CI minute meter. One repo doing that burned ~1,160 Actions minutes in a month.
# The build belongs on Connect; the waiting does not. See core/04-deploy-verify.md.
#
# Prints no credential. Exits nonzero on a FAILED task; 'detached' is a normal,
# healthy outcome and is reported as itself -- never as success.

set -euo pipefail
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/_common.sh"

WATCH_SECONDS="${WATCH_SECONDS:-60}"

pdlc_load_target
pdlc_load_credentials

[ -f manifest.json ] || pdlc_die "no manifest.json here. It is a COMMITTED artifact (core/03)."

echo "posit-dlc publish (async)"
echo "  server : ${CONNECT_SERVER}"
echo "  guid   : ${CONTENT_GUID}"
echo

# --- bundle: exactly the files the manifest lists, plus the manifest itself ---
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
BUNDLE="$TMP/bundle.tar.gz"

"$(pdlc_python)" - "$BUNDLE" <<'PYEOF'
import json, os, sys, tarfile
out = sys.argv[1]
with open("manifest.json", encoding="utf-8") as fh:
    files = list((json.load(fh).get("files") or {}).keys())
missing = [f for f in files if not os.path.exists(f)]
if missing:
    sys.exit("ERROR: manifest lists missing files: %s\n  Run check-manifest.sh." % missing)
with tarfile.open(out, "w:gz") as tar:
    tar.add("manifest.json", arcname="manifest.json")
    for f in files:
        tar.add(f, arcname=f)
print("  bundled: %d file(s) + manifest.json" % len(files))
PYEOF

api() {  # api <method> <path> [curl args...]  -> body on stdout, dies on !2xx
  local method="$1" path="$2"; shift 2
  local resp code body
  resp="$(curl -sS -w '\n%{http_code}' -X "$method" \
            -H "Authorization: Key ${CONNECT_API_KEY}" "${API_BASE}${path}" "$@")"
  code="$(printf '%s' "$resp" | tail -1)"
  body="$(printf '%s' "$resp" | sed '$d')"
  case "$code" in 2*) printf '%s' "$body" ;;
    *) pdlc_die "HTTP ${code} on ${method} ${path}
  ${body}" ;;
  esac
}

json_field() { printf '%s' "$1" | sed -n "s/.*\"$2\"[[:space:]]*:[[:space:]]*\"\([^\"]*\)\".*/\1/p" | head -1; }

echo "  uploading bundle..."
UP="$(api POST "/content/${CONTENT_GUID}/bundles" \
        -H 'Content-Type: application/x-gzip' --data-binary "@${BUNDLE}")"
BUNDLE_ID="$(json_field "$UP" id)"
[ -n "$BUNDLE_ID" ] || pdlc_die "no bundle id in upload response"
echo "  bundle id : ${BUNDLE_ID}"

echo "  starting deploy (not waiting for it)..."
DEP="$(api POST "/content/${CONTENT_GUID}/deploy" \
        -H 'Content-Type: application/json' \
        --data "{\"bundle_id\":\"${BUNDLE_ID}\"}")"
TASK_ID="$(json_field "$DEP" task_id)"
[ -n "$TASK_ID" ] || pdlc_die "no task_id in deploy response"
echo "  task id   : ${TASK_ID}"
echo

# --- watch for a SHORT bounded window, then let go ---
DEADLINE=$(( $(date +%s) + WATCH_SECONDS ))
STATUS="detached"
while [ "$(date +%s)" -lt "$DEADLINE" ]; do
  T="$(api GET "/tasks/${TASK_ID}?wait=5")"
  case "$T" in
    *'"finished":true'*|*'"finished": true'*)
      case "$T" in
        *'"code":0'*|*'"code": 0'*) STATUS="succeeded" ;;
        *) STATUS="failed"; echo "$T" ;;
      esac
      break ;;
  esac
done

echo "deploy_status=${STATUS}"
case "$STATUS" in
  succeeded) echo "  Connect finished inside the ${WATCH_SECONDS}s watch window." ;;
  detached)  echo "  Upload and deploy were ACCEPTED. The watch window ended first."
             echo "  This is normal and healthy. It does NOT mean the app is up." ;;
  failed)    echo "  Connect's deploy task FAILED. Read the task log on the server --"
             echo "  the real message is there, not in this client's output." >&2
             exit 1 ;;
esac
echo
echo "GREEN IS NOT LIVE. Verify with: ./posit-dlc/scripts/verify.sh"
