#!/bin/bash
# Gate for docs sprints: check that the deliverable documents listed in README §2 (and other sections) exist.
# Used in the TEST gate (BUILD→TEST) = checks that BUILD is complete = the deliverable documents are written.
# Of the docs/...\.md paths in README, take those outside this sprint (outside docs.sprintRoot) as deliverable candidates.
# Pass when all exist. When a deliverable that must be created is not written yet, fail with MISSING.
set -euo pipefail
. "$(dirname "$(readlink -f "$0")")/../lib/env.sh"
sprint_config_require
ROOT=$(sprint_root)
FLAGS="$ROOT/.sprint/flags.json"
ID=$(jq -r '.active // ""' "$FLAGS")
DIR=$(jq -r --arg id "$ID" '.sprints[$id].sprint_dir // ""' "$FLAGS")
README="$ROOT/$DIR/README.md"
SPRINT_ROOT_REL=$(sprint_config '.docs.sprintRoot')

[ -f "$README" ] || { echo "README.md not found: $README"; exit 1; }

# Extract the docs/...\.md paths from README (candidates for deliverables and reference documents)
FILES=$(grep -oE 'docs/[A-Za-z0-9_./-]+\.md' "$README" | sort -u || true)
[ -n "$FILES" ] || { echo "warn: no docs document path found in README"; exit 0; }

FAIL=0
MISSING=""
FOUND=0
for f in $FILES; do
  # Exclude this sprint's own documents (README/SPEC/TEST under sprintRoot)
  case "$f" in
    "$SPRINT_ROOT_REL"/*) continue ;;
  esac
  if [ -f "$ROOT/$f" ]; then
    FOUND=$((FOUND + 1))
  else
    MISSING="$MISSING  $f\n"
    FAIL=1
  fi
done

if [ "$FAIL" -ne 0 ]; then
  echo "MISSING deliverable/reference documents (listed in README but do not exist):"
  printf "$MISSING"
  exit 1
fi

echo "ok: $FOUND documents exist"
