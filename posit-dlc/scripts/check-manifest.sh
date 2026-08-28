#!/usr/bin/env bash
# check-manifest.sh — hard-fail on a stale or lying manifest.
#
# A file listed in manifest.json but missing on disk is an ERROR, not a warning.
# Also prints the environment fingerprint fields so you can SEE what machine
# this manifest was generated on. See posit-dlc/core/03-manifest-hygiene.md.
#
# Reads only. Never regenerates. Regenerating is a human action on a
# representative machine — never in CI.

set -euo pipefail
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/_common.sh"

MANIFEST="${1:-manifest.json}"
[ -f "$MANIFEST" ] || { echo "ERROR: no $MANIFEST here." >&2; exit 1; }

"$(pdlc_python)" - "$MANIFEST" <<'PYEOF'
import json, os, sys

path = sys.argv[1]
with open(path, encoding="utf-8") as fh:
    m = json.load(fh)

print(f"posit-dlc manifest check: {path}")
print()
print("  environment fingerprint (properties of the machine that generated this,")
print("  NOT of your project -- see core/03-manifest-hygiene.md):")
print(f"    locale        : {m.get('locale', '<absent>')!r}")
py_block = m.get("python") or {}
pm = py_block.get("package_manager") or {}
print(f"    python.version: {py_block.get('version', '<absent>')}")
print(f"    pip version   : {pm.get('version', '<absent>')}")
print(f"    package_file  : {pm.get('package_file', '<absent>')}")
meta = m.get("metadata") or {}
print(f"    appmode       : {meta.get('appmode', '<absent>')}")
print(f"    entrypoint    : {meta.get('entrypoint', '<absent>')}")
print()

files = m.get("files") or {}
print(f"  files listed    : {len(files)}")

missing = [f for f in files if not os.path.exists(f)]

# Warn on things you probably cannot publish. Everything in the bundle goes up.
suspicious = [f for f in files
              if os.path.basename(f) in (".env", ".envrc")
              or f.startswith(".env")
              or "/secret" in f.lower()
              or os.path.basename(f).endswith((".pem", ".key"))]

rc = 0
if suspicious:
    print()
    print(f"  !! {len(suspicious)} file(s) look unpublishable and are in the bundle:")
    for f in suspicious:
        print(f"       {f}")
    print("  !! EVERYTHING in the manifest goes up to the server.")
    rc = 1

if missing:
    print()
    print(f"ERROR: manifest lists {len(missing)} file(s) that do not exist on disk:")
    for f in missing:
        print(f"    {f}")
    print()
    print("  The manifest is stale. Regenerate it on a REPRESENTATIVE MACHINE")
    print("  (not in CI), read the diff -- especially locale and python.version --")
    print("  then commit it. See core/03-manifest-hygiene.md RULE 1 and RULE 4.")
    sys.exit(1)

if rc:
    print()
    print("FAILED: remove the unpublishable files from the bundle and regenerate.")
    sys.exit(rc)

# entrypoint sanity for python content
if str(meta.get("appmode", "")).startswith("python") and not meta.get("entrypoint"):
    print()
    print("ERROR: python content with no explicit entrypoint.")
    print("  Autodetection is not worth the debugging. See core/03 RULE 8.")
    sys.exit(1)

print()
print("OK: every listed file exists; nothing obviously unpublishable is bundled.")
PYEOF

# .python-version is how you stop the manifest's requirement being an accident.
if [ ! -f .python-version ] && [ ! -f pyproject.toml ] && [ ! -f setup.cfg ]; then
  echo
  echo "  NOTE: no .python-version, pyproject.toml, or setup.cfg."
  echo "  rsconnect then falls back to 'whichever interpreter happened to run',"
  echo "  and the manifest's Python requirement is luck. Commit a .python-version."
  echo "  See core/03-manifest-hygiene.md RULE 2."
fi
