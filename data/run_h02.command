#!/bin/zsh
set -e
cd "$(dirname "$0")/.."
rscript_bin="${RSCRIPT_BIN:-Rscript}"
if ! command -v "$rscript_bin" >/dev/null 2>&1; then
  if [[ -x ../../work/r-runtime/bin/Rscript ]]; then
    rscript_bin=../../work/r-runtime/bin/Rscript
  else
    print -u2 "Rscript is unavailable. Install R or set RSCRIPT_BIN to its executable."
    exit 1
  fi
fi
"$rscript_bin" data/generate_data.R
python3 tests/validate_schema.py
python3 data/check_scenarios.py
print "Generation and validation passed."
