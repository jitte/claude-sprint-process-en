#!/bin/bash
# Check that every Test ID of TEST.md exists in the test source code (files that match the tests globs of the config) (skip is allowed)
# For the BUILD gate — right after build-red, skips are expected
#
# Environment variables (entry point for the tests):
#   TDD_TEST_MD     path of TEST.md (default: resolved from the active sprint in .sprint/flags.json)
#   TDD_ID_PATTERN  regex of the Test ID (same default as tdd-audit.sh)
set -euo pipefail
. "$(dirname "$(readlink -f "$0")")/../lib/env.sh"
sprint_config_require
ROOT=$(sprint_root)
TEST_MD="${TDD_TEST_MD:-}"
if [ -z "$TEST_MD" ]; then
  FLAGS="$ROOT/.sprint/flags.json"
  ID=$(jq -r '.active // ""' "$FLAGS")
  DIR=$(jq -r --arg id "$ID" '.sprints[$id].sprint_dir // ""' "$FLAGS")
  TEST_MD="$ROOT/$DIR/TEST.md"
fi

[ -f "$TEST_MD" ] || { echo "TEST.md not found: $TEST_MD"; exit 1; }

# Format of the Test ID. It matches both TEST-<sprint_id>-<major>.<minor> and TEST-<major>.<minor>.
# Use the same default as tdd-audit.sh.
ID_PATTERN="${TDD_ID_PATTERN:-TEST-[0-9]+(-[0-9]+)*\.[0-9]+[a-z]?}"

# Target only the Test ID column (the first column) of the test definition table.
# Exclude mentions in the text (IDs to delete, descriptions of modifications, references in the coverage matrix),
# because they do not mean "that test must exist".
# Take the result with || true so that set -e does not end silently on 0 hits. The branch below prints the reason.
SPEC_IDS=$(sed -nE "s/^[[:space:]]*\|[[:space:]]*(${ID_PATTERN})[[:space:]]*\|.*/\1/p" "$TEST_MD" | sort -u || true)

if [ -z "$SPEC_IDS" ]; then
  # When the text has IDs but none can be taken from the definition table, the format of TEST.md is unexpected.
  # A pass without any check would miss the gap, so stop with an error.
  if grep -qE "$ID_PATTERN" "$TEST_MD"; then
    echo "TEST.md has Test IDs, but none can be extracted from the test definition table (the table whose first column is the Test ID)"
    exit 1
  fi
  echo "warn: no Test ID found in TEST.md"
  exit 0
fi

FAIL=0
MISSING=""
FOUND=0

# Scan targets = files that match the tests globs of the config
mapfile -t TEST_GLOBS < <(sprint_component_globs tests)
TEST_FILES=$(sprint_glob_files "${TEST_GLOBS[@]}" | sed "s|^|$ROOT/|")

for tid in $SPEC_IDS; do
  HITS=$(printf '%s\n' "$TEST_FILES" | xargs -r -d '\n' grep -n "$tid" 2>/dev/null || true)

  if [ -z "$HITS" ]; then
    MISSING="$MISSING  $tid\n"
    FAIL=1
    continue
  fi
  FOUND=$((FOUND + 1))
done

TOTAL=$(echo "$SPEC_IDS" | wc -w)

if [ -n "$MISSING" ]; then
  echo "MISSING (Test ID in TEST.md but not in test source):"
  printf "$MISSING"
fi

if [ "$FAIL" -ne 0 ]; then
  echo "tdd-exists: $FOUND/$TOTAL found"
  exit 1
fi

echo "ok: $FOUND/$TOTAL test IDs exist in source"
