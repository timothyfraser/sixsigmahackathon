#!/usr/bin/env bash
# verify.sh — poll the content's health route until it answers.
#
# THIS is the definition of done, not a green check. A successful upload means
# the bundle was accepted, not that the app came up.
# See posit-dlc/core/04-deploy-verify.md.

set -euo pipefail
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/_common.sh"

TIMEOUT="${TIMEOUT:-300}"
INTERVAL="${INTERVAL:-10}"

pdlc_load_target
pdlc_load_credentials

# content_url comes from Connect, so vanity URLs are handled for free.
INFO="$(curl -sS -H "Authorization: Key ${CONNECT_API_KEY}" \
          "${API_BASE}/content/${CONTENT_GUID}")"
CONTENT_URL="$(printf '%s' "$INFO" | sed -n 's/.*"content_url"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1)"
[ -n "$CONTENT_URL" ] || pdlc_die "could not read content_url for ${CONTENT_GUID}"

URL="${CONTENT_URL%/}${HEALTH_PATH}"
echo "posit-dlc verify"
echo "  GET ${URL}"
echo

DEADLINE=$(( $(date +%s) + TIMEOUT ))
while :; do
  RESP="$(curl -sS -m 20 -w '\n%{http_code}' \
            -H "Authorization: Key ${CONNECT_API_KEY}" "$URL" 2>/dev/null || true)"
  CODE="$(printf '%s' "$RESP" | tail -1)"
  BODY="$(printf '%s' "$RESP" | sed '$d')"

  if [ "$CODE" = "200" ]; then
    echo "  200 ${BODY}"
    echo "VERIFIED"
    exit 0
  fi

  case "$CODE" in
    401|403)
      echo "  ${CODE} -- on ACL-gated content this may be the release schedule,"
      echo "  not an outage. See core/01-connect-target.md. Not retrying."
      exit 2 ;;
  esac

  if [ "$(date +%s)" -ge "$DEADLINE" ]; then
    echo "  last: HTTP ${CODE:-<none>} ${BODY}" >&2
    echo "NOT VERIFIED after ${TIMEOUT}s." >&2
    echo "  The bundle may have uploaded fine and the process never started." >&2
    echo "  Read the deploy log ON CONNECT. See core/04-deploy-verify.md." >&2
    exit 1
  fi
  echo "  ${CODE:-...} -- not up yet, retrying in ${INTERVAL}s"
  sleep "$INTERVAL"
done
