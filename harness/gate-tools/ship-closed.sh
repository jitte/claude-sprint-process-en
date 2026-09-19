#!/bin/bash
# CLOSED gate: check that the SHIP stage is closed
# (prevents going to CLOSED without completing the work of SHIP)
set -euo pipefail
. "$(dirname "$(readlink -f "$0")")/../lib/env.sh"
sprint_config_require
ROOT=$(sprint_root)
FLAGS="$ROOT/.sprint/flags.json"

ACTIVE=$(jq -r '.active // ""' "$FLAGS")
[ -n "$ACTIVE" ] || { echo "active sprint not set"; exit 1; }

# The stage may already be CLOSED after the last stage transition, so
# sprint.sh guarantees that the source stage was SHIP (allowed_next allows only SHIP→CLOSED).
# Here, check "whether the SHIP output (the commit) exists".
# A filled-in commit hash in README §8 stands for it.
SPRINT_DIR=$(jq -r --arg id "$ACTIVE" '.sprints[$id].sprint_dir // ""' "$FLAGS")
README="$ROOT/$SPRINT_DIR/README.md"

if [ ! -f "$README" ]; then
  echo "README.md not found: $README"
  exit 1
fi

if grep -q 'Commit hash:$' "$README" || grep -q 'Commit hash: *$' "$README"; then
  echo "README §8 has no commit hash filled in (SHIP is not complete)"
  exit 1
fi

exit 0
