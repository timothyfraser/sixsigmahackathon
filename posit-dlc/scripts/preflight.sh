#!/usr/bin/env bash
# preflight.sh — GATE 2. READ-ONLY.
#
# Prints the TITLE of whatever content the configured GUID actually points at,
# before a single byte of bundle is uploaded.
#
# WHY: a wrong GUID does not fail harmlessly. It OVERWRITES whatever content it
# does point at, with no confirmation and no undo.
# See posit-dlc/core/02-publisher-credentials.md.
#
# Makes exactly one GET. Writes nothing. Prints no credential.

set -euo pipefail
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/_common.sh"

pdlc_load_target
pdlc_load_credentials

echo "posit-dlc preflight (read-only)"
echo "  server        : ${CONNECT_SERVER}"
echo "  api prefix    : ${API_PREFIX}"
echo "  target GUID   : ${CONTENT_GUID}"
echo "  expected title: ${CONTENT_TITLE:-<none declared>}"
echo

RESP="$(curl -sS -w '\n%{http_code}' \
  -H "Authorization: Key ${CONNECT_API_KEY}" \
  "${API_BASE}/content/${CONTENT_GUID}")" || pdlc_die "request failed"

CODE="$(printf '%s' "$RESP" | tail -1)"
BODY="$(printf '%s' "$RESP" | sed '$d')"

case "$CODE" in
  200) ;;
  404) pdlc_die "404 from ${API_BASE}/content/${CONTENT_GUID}
  Either the GUID does not exist on this server, or the api_prefix is wrong.
  It must be /__api__/v1 — a missing prefix 404s and reads like a permissions
  problem. See core/01-connect-target.md." ;;
  401|403) pdlc_die "${CODE} — the key is not authorized for this content.
  On an ACL-gated server this can be the release schedule rather than an outage.
  See core/01-connect-target.md." ;;
  *) pdlc_die "unexpected HTTP ${CODE} from Connect" ;;
esac

json_field() {
  printf '%s' "$BODY" | sed -n "s/.*\"$1\"[[:space:]]*:[[:space:]]*\"\([^\"]*\)\".*/\1/p" | head -1
}

LIVE_TITLE="$(json_field title)"
LIVE_NAME="$(json_field name)"
LIVE_OWNER="$(json_field owner_guid)"
LIVE_URL="$(json_field content_url)"

echo "  LIVE title    : ${LIVE_TITLE:-<untitled>}"
echo "  LIVE name     : ${LIVE_NAME:-<unnamed>}"
echo "  LIVE owner    : ${LIVE_OWNER:-<unknown>}"
echo "  LIVE url      : ${LIVE_URL:-<unknown>}"
echo

if [ -n "${CONTENT_TITLE:-}" ] && [ -n "$LIVE_TITLE" ] && [ "$CONTENT_TITLE" != "$LIVE_TITLE" ]; then
  echo "  !! WARNING: declared title and live title DIFFER."
  echo "  !! declared: ${CONTENT_TITLE}"
  echo "  !! live    : ${LIVE_TITLE}"
  echo "  !! Publishing now would overwrite the LIVE content above. There is no undo."
  echo
fi

echo "GATE 2: a human must confirm the LIVE content above is what they intend"
echo "        to overwrite. An agent does not clear this gate on its own."
