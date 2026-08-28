#!/usr/bin/env bash
# _common.sh — shared config loading for the posit-dlc scripts.
#
# NEVER prints a credential. Reads connect-target.yaml with grep/sed so the
# bundle has no YAML-parser dependency.
#
# Usage from a sibling script:  . "$(dirname "$0")/_common.sh"

set -euo pipefail

PDLC_TARGET_FILE="${PDLC_TARGET_FILE:-connect-target.yaml}"

pdlc_die() { echo "ERROR: $*" >&2; exit 1; }

# The interpreter that actually runs. On Windows `python3` is often a Microsoft
# Store alias stub that resolves on PATH and then refuses to execute, so probe
# rather than trust `command -v`.
pdlc_python() {
  for c in python3 python py; do
    if command -v "$c" >/dev/null 2>&1 && "$c" -c "import sys" >/dev/null 2>&1; then
      echo "$c"; return 0
    fi
  done
  echo "ERROR: no working Python interpreter found on PATH." >&2
  return 1
}

# yaml_get <key>  — flat or one-level-nested scalar, quotes stripped.
pdlc_yaml_get() {
  local key="$1"
  sed -n "s/^[[:space:]]*${key}:[[:space:]]*[\"']\{0,1\}\([^\"'#]*\)[\"']\{0,1\}[[:space:]]*\$/\1/p" \
    "$PDLC_TARGET_FILE" | head -1 | sed 's/[[:space:]]*$//'
}

pdlc_load_target() {
  [ -f "$PDLC_TARGET_FILE" ] || pdlc_die \
    "no $PDLC_TARGET_FILE here. Copy posit-dlc/connect-target.example.yaml and fill it in."

  API_PREFIX="$(pdlc_yaml_get api_prefix)"
  CONTENT_GUID="$(pdlc_yaml_get guid)"
  CONTENT_TITLE="$(pdlc_yaml_get title)"
  HEALTH_PATH="$(pdlc_yaml_get health_path)"
  TARGET_SERVER_URL="$(pdlc_yaml_get server_url)"

  : "${API_PREFIX:=/__api__/v1}"
  : "${HEALTH_PATH:=/health}"

  # Sentinels fail loudly. A human provisions content once, by hand.
  case "$CONTENT_GUID" in
    ""|PUT_GUID_HERE)
      pdlc_die "content.guid is still the sentinel.
  A human must create the content item on Connect ONCE, then paste its GUID
  into $PDLC_TARGET_FILE. Automation does not invent GUIDs.
  See posit-dlc/core/01-connect-target.md." ;;
  esac
  case "$TARGET_SERVER_URL" in
    ""|PUT_SERVER_URL_HERE)
      pdlc_die "server_url is still the sentinel in $PDLC_TARGET_FILE." ;;
  esac
}

# Credentials come from the environment only. Optionally seeded by a gitignored
# .env. Values are never echoed.
pdlc_load_credentials() {
  if [ -f .env ]; then
    set -a; . ./.env; set +a
  fi
  [ -n "${CONNECT_SERVER:-}" ] || pdlc_die \
    "CONNECT_SERVER is not set. Put it in a gitignored .env or export it."
  [ -n "${CONNECT_API_KEY:-}" ] || pdlc_die \
    "CONNECT_API_KEY is not set. Put it in a gitignored .env or export it.
  It is never committed and never printed. See core/02-publisher-credentials.md."
  CONNECT_SERVER="${CONNECT_SERVER%/}"
  API_BASE="${CONNECT_SERVER}${API_PREFIX}"
}
