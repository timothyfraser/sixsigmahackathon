#!/bin/bash
# deployme.sh

# Deploy FastAPI to Posit Connect.
# This script targets Posit Connect (not Connect Cloud).

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

python -m pip install rsconnect-python

# Optional: load CONNECT_SERVER and CONNECT_API_KEY from .env
if [ -f ".env" ]; then
  # shellcheck disable=SC1091
  source .env
fi

# If CONNECT_SERVER and CONNECT_API_KEY are set, use explicit auth.
# Otherwise this will use your existing rsconnect account configuration.
rsconnect deploy fastapi \
  ${CONNECT_SERVER:+--server "$CONNECT_SERVER"} \
  ${CONNECT_API_KEY:+--api-key "$CONNECT_API_KEY"} \
  --entrypoint app:app \
  .
