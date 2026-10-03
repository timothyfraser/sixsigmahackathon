#!/bin/bash
# manifestme.sh
#
# Write a Posit deployment manifest for this FastAPI app.
# Run from anywhere: ./manifestme.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

echo "Installing rsconnect-python (if needed)..."
python -m pip install rsconnect-python

echo "Writing manifest.json for FastAPI app..."
# Entry point is app.py with ASGI object named 'app'. FastAPI is ASGI, so the mode is
# `fastapi` (the older `api` mode is WSGI and fails on Connect).
rsconnect write-manifest fastapi . --entrypoint app:app

echo "Done. manifest.json created in: $SCRIPT_DIR"
