#!/usr/bin/env bash
# SessionStart hook: print a tiny status so the agent starts oriented.
# Fast (bash builtins only, no grep or awk), read-only, and it never fails
# the session (always exit 0). Its stdout becomes context, so keep it short.
cd "$(dirname "$0")/../.." 2>/dev/null || exit 0

fill=0
if [ -f SPEC.md ]; then
  while IFS= read -r line; do
    case "$line" in *"FILL IN."* | *"FILL IN,"*) fill=$((fill + 1)) ;; esac
  done < SPEC.md
fi
echo "SPEC.md: $fill FILL IN line(s) still to fill."

# CONTRACT.yaml: remember the last task id, print it when its status is in_progress.
active=""
if [ -f CONTRACT.yaml ]; then
  id=""
  while IFS= read -r line; do
    case "$line" in
      *"- id:"*) id="${line#*- id:}"; id="${id//[ \"\']/}" ;;
      *"status:"*"in_progress"*) case "$line" in "#"*) ;; *) active="$active$id " ;; esac ;;
    esac
  done < CONTRACT.yaml
fi
echo "In progress: ${active:-none}"

if [ -f docs/plan.md ]; then
  echo "docs/plan.md: exists."
else
  echo "docs/plan.md: not written yet."
fi

echo "Type /superagent and describe your app (or 'what's next')."
exit 0
