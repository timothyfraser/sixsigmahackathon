#!/bin/bash

# testme.sh
# A helper script to test the FastAPI app locally.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

python -m uvicorn app:app --host 0.0.0.0 --port 8000
