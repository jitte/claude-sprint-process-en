#!/bin/bash
# Gate for docs sprints: read the verdict table in the UNSEAL block of TEST.md (the first table whose header row has a "Verdict" column),
# and check that the verdict of the latest round (the last row with a filled-in verdict) is 🟢.
# Used in the DOCS/SHIP gates = checks that TEST is complete = the document consistency check is green (the docs version of green in results).
#
# Look only at table cells. 🔴 or 🟢 in the prose of UNSEAL is not used for the verdict.
# A verdict cell holds exactly one of 🟢 / 🟡 / 🔴. Skip the template row before fill-in (🔴🟡🟢) as not filled in.
set -euo pipefail
. "$(dirname "$(readlink -f "$0")")/../lib/env.sh"
sprint_config_require
ROOT=$(sprint_root)
FLAGS="$ROOT/.sprint/flags.json"
ID=$(jq -r '.active // ""' "$FLAGS")
DIR=$(jq -r --arg id "$ID" '.sprints[$id].sprint_dir // ""' "$FLAGS")
TEST_MD="$ROOT/$DIR/TEST.md"

[ -f "$TEST_MD" ] || { echo "TEST.md not found: $TEST_MD"; exit 1; }

# From the verdict table in the UNSEAL block (where qa fills in the results), print the filled-in verdict cells in row order
VERDICTS=$(awk '
  /UNSEAL:BEGIN/ { f = 1; next }
  /UNSEAL:END/   { f = 0 }
  !f { next }
  /^[[:space:]]*\|/ {
    n = split($0, c, "|")
    if (col == 0) {                       # find the header row
      for (i = 2; i < n; i++) { gsub(/^[[:space:]]+|[[:space:]]+$/, "", c[i]); if (c[i] == "Verdict") { col = i; break } }
      next
    }
    if (done) next
    if ($0 ~ /^[[:space:]]*\|[[:space:]]*-+/) next   # separator row
    v = c[col]; gsub(/^[[:space:]]+|[[:space:]]+$/, "", v)
    if (v == "🟢" || v == "🟡" || v == "🔴") print v
    next
  }
  { if (col > 0) done = 1 }                # the table ended
' "$TEST_MD")

LAST=$(printf '%s\n' "$VERDICTS" | tail -1)
if [ -z "$LAST" ]; then
  echo "TEST.md UNSEAL has no row with a filled-in verdict (write 🟢 / 🟡 / 🔴 in the Verdict column of the verdict table)"
  exit 1
fi
if [ "$LAST" != "🟢" ]; then
  echo "TEST.md: the verdict of the latest round is $LAST (not 🟢)"
  exit 1
fi

echo "ok: TEST.md consistency check green (latest round)"
