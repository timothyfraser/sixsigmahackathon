#!/usr/bin/env bash
# connect-publish-static-async.sh -- publish a folder of built files (a Vite
# `dist/`, a plain HTML site) to Posit Connect as STATIC content.
#
# Used by deploy-react-static.yml. Copy it to .github/scripts/ in your own repo,
# NEXT TO connect-publish-async.sh, which it hands off to.
#
# Why a static site may have its manifest written in CI when an app may not:
# a static manifest carries no R or Python fingerprint, only the file list and
# a checksum per file. Nothing about the runner can leak into it. So this
# script writes manifest.json into BUNDLE_DIR (appmode "static"), then runs
# connect-publish-async.sh to find-or-create, upload, deploy and watch.
#
# Required env: CONNECT_SERVER, CONNECT_API_KEY, BUNDLE_DIR (e.g. dist),
#   CONTENT_NAME. Optional: CONTENT_TITLE, CONTENT_GUID, POLL_BUDGET_SECONDS,
#   ENTRYPOINT (default index.html).
# Set DRY_RUN=1 to write the manifest and list what would ship, without
# contacting Connect.
set -euo pipefail

: "${BUNDLE_DIR:?BUNDLE_DIR is required (the built folder, e.g. dist)}"
ENTRYPOINT="${ENTRYPOINT:-index.html}"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

fail() { echo "::error::$*" >&2; exit 1; }

command -v python3 >/dev/null || fail "python3 is required"
[ -d "$BUNDLE_DIR" ] || fail "'${BUNDLE_DIR}' is not a folder. Did the build step run?"
[ -f "${BUNDLE_DIR%/}/${ENTRYPOINT}" ] \
  || fail "'${ENTRYPOINT}' not found in ${BUNDLE_DIR}. Did the build step run?"

BUNDLE_DIR="$BUNDLE_DIR" ENTRYPOINT="$ENTRYPOINT" python3 -X utf8 - <<'PY'
import hashlib, json, os, sys

bundle_dir = os.environ["BUNDLE_DIR"].rstrip("/\\")
entrypoint = os.environ["ENTRYPOINT"]
SKIP_DIRS = {".git", ".github", "node_modules", "__pycache__"}

def md5(path):
    h = hashlib.md5()
    with open(path, "rb") as fh:
        for chunk in iter(lambda: fh.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()

files = {}
for root, dirs, names in os.walk(bundle_dir):
    dirs[:] = sorted(d for d in dirs if d not in SKIP_DIRS)
    for name in sorted(names):
        rel = os.path.relpath(os.path.join(root, name), bundle_dir).replace(os.sep, "/")
        if rel != "manifest.json":
            files[rel] = {"checksum": md5(os.path.join(root, name))}

if entrypoint not in files:
    sys.exit("entrypoint %r is not among the built files" % entrypoint)

manifest = {
    "version": 1,
    "metadata": {"appmode": "static", "primary_html": entrypoint, "entrypoint": entrypoint},
    "files": files,
}
with open(os.path.join(bundle_dir, "manifest.json"), "w", encoding="utf-8", newline="\n") as fh:
    json.dump(manifest, fh, indent=2)
print("static manifest: %d files, entrypoint %s" % (len(files), entrypoint))
PY

if [ "${DRY_RUN:-0}" = "1" ]; then
  echo "DRY_RUN=1 -- would ship:"
  python3 -X utf8 -c "import json,sys; [print('   '+k) for k in json.load(open(sys.argv[1]))['files']]" \
    "${BUNDLE_DIR%/}/manifest.json"
  echo "DRY_RUN=1 -- Connect was not contacted."
  exit 0
fi

exec bash "${HERE}/connect-publish-async.sh"
