#!/bin/bash
# tdd-audit.sh — verify the Test IDs of TEST.md against the "execution evidence (evidence contract JSON)"
#
# Design principle: judge only by "what happened when it ran" (reporter JSON),
# not by "how the test code is written" (grep).
# Variants of skip syntax, commenting out, .only, an ID written in a comment,
# piggybacking on a same-name ID of a past sprint — in each case the execution evidence does not meet the requirement and the check fails.
#
# Matching rules:
#   1. Treat as test definition rows only the table rows of TEST.md whose "first cell is a Test ID"
#      (the coverage matrix and ID mentions in the text are out of scope)
#   2. A test definition row must name a test file (*.test.* / *.spec.*) (FORMAT fail when missing)
#   3. From tests[] of the evidence of every (component, test|e2e) of the config,
#      collect the tests "whose name contains the ID and whose file name matches the row" (.partial.json is not read)
#   4. 0 hits → MISSING / any status other than passed (skipped, todo, pending, failed, flaky...) → fail
#      all passed → ok
#
# Generalization (for use in other projects): these environment variables override the defaults
#   TDD_TEST_MD      path of TEST.md (default: resolved from the active sprint in .sprint/flags.json)
#   TDD_ID_PATTERN   regex of the Test ID (default TEST-[0-9]+(-[0-9]+)*\.[0-9]+[a-z]?)
#                    It matches both TEST-<sprint_id>-<major>.<minor> and TEST-<major>.<minor>.
#
# Exit code = failure class (gate-check.sh §failure class). It depends on the failure:
#   1 = TEST.md missing, or FORMAT (test definition row without a file) = spec problem → PLAN
#   3 = MISSING / NOT-PASS (the execution evidence does not meet the requirement) = test problem → BUILD
#   4 = no evidence at all (tests not run = procedure problem) → stay
# When several are mixed, return the most upstream one (the smallest number).
set -euo pipefail

CLS=0
note() { # $1 = class code. Keep the more upstream one (smaller value)
  if [ "$CLS" -eq 0 ] || [ "$1" -lt "$CLS" ]; then CLS="$1"; fi
}

. "$(dirname "$(readlink -f "$0")")/../lib/env.sh"
. "$(dirname "$(readlink -f "$0")")/../lib/evidence.sh"
sprint_config_require
ROOT=$(sprint_root)
ID_PATTERN="${TDD_ID_PATTERN:-TEST-[0-9]+(-[0-9]+)*\.[0-9]+[a-z]?}"

# ── resolve TEST.md ─────────────────────────────────────────
TEST_MD="${TDD_TEST_MD:-}"
if [ -z "$TEST_MD" ]; then
  FLAGS="$ROOT/.sprint/flags.json"
  if [ -f "$FLAGS" ]; then
    ACTIVE=$(jq -r '.active // ""' "$FLAGS")
    DIR=$(jq -r --arg id "$ACTIVE" '.sprints[$id].sprint_dir // ""' "$FLAGS")
    [ -n "$DIR" ] && TEST_MD="$ROOT/$DIR/TEST.md"
  fi
fi
if [ -z "$TEST_MD" ] || [ ! -f "$TEST_MD" ]; then
  echo "TEST.md not found: ${TEST_MD:-unset} (set TDD_TEST_MD)"
  exit 1
fi

# ── evidence → common format (file <TAB> status <TAB> name) ── (evidence.sh parses it)
EVIDENCE=$(mktemp)
trap 'rm -f "$EVIDENCE"' EXIT

if ! evidence_tests_tsv > "$EVIDENCE"; then
  echo "no test evidence found in $(evidence_dir) — run the full test suites first"
  exit 4
fi

# ── extract the test definition rows (first cell = Test ID) from TEST.md ──────
declare -A ID_FILES
ID_ORDER=()

while IFS= read -r line; do
  first_cell=$(sed -E 's/^[[:space:]]*\|[[:space:]]*([^|]*)\|.*/\1/' <<<"$line" | tr -d '[:space:]')
  if ! grep -qE "^${ID_PATTERN}$" <<<"$first_cell"; then
    continue
  fi
  tid="$first_cell"
  # Absorb a grep non-match (no test file named) so that pipefail does not stop the script.
  # Judge "no file named" below by whether files_trimmed is empty, and report it as FORMAT.
  files=$(grep -oE '[A-Za-z0-9_./-]+\.(test|spec)\.[A-Za-z]+' <<<"$line" | sort -u | tr '\n' ' ' || true)
  if [ -z "${ID_FILES[$tid]:-}" ]; then
    ID_ORDER+=("$tid")
    ID_FILES[$tid]="$files"
  else
    ID_FILES[$tid]="${ID_FILES[$tid]} $files"
  fi
done < <(grep -E '^[[:space:]]*\|' "$TEST_MD")

if [ "${#ID_ORDER[@]}" -eq 0 ]; then
  echo "warn: no test definition row (a table row whose first cell is a Test ID) found in TEST.md (a spec exploration sprint?)"
  exit 0
fi

# ── matching ─────────────────────────────────────────────────
FAIL=0
OK=0
ERRORS=""

for tid in "${ID_ORDER[@]}"; do
  files="${ID_FILES[$tid]}"
  files_trimmed=$(tr -s ' ' <<<"$files" | sed 's/^ //; s/ $//')

  if [ -z "$files_trimmed" ]; then
    ERRORS+="  FORMAT   $tid: the test definition row names no test file (*.test.* / *.spec.*)\n"
    FAIL=1
    note 1
    continue
  fi

  # Narrow the run results whose test name contains the ID by the named file names (basename)
  # Match the ID "with a boundary". A plain substring match makes TEST-2.1
  # match the run name of TEST-2.15, and a pass of TEST-2.15 satisfies TEST-2.1
  # even when no real test of TEST-2.1 exists (piggybacking by prefix inclusion).
  # Prevent this: require that the character right after the ID is not alphanumeric.
  tid_re=$(sed 's/\./\\./g' <<<"$tid")

  hits=""
  while IFS=$'\t' read -r f s n; do
    [ -n "$f" ] || continue
    grep -qE "${tid_re}([^0-9A-Za-z]|$)" <<<"$n" || continue
    bn=$(basename "$f")
    for ef in $files_trimmed; do
      if [ "$(basename "$ef")" = "$bn" ]; then
        hits+="${s}\t${f}\t${n}\n"
        break
      fi
    done
  done < "$EVIDENCE"

  if [ -z "$hits" ]; then
    ERRORS+="  MISSING  $tid: no matching test in the run results (target: ${files_trimmed})\n"
    FAIL=1
    note 3
    continue
  fi

  bad=$(printf '%b' "$hits" | awk -F'\t' '$1 != "passed"' || true)
  if [ -n "$bad" ]; then
    first_bad=$(head -1 <<<"$bad")
    ERRORS+="  NOT-PASS $tid: $(cut -f1 <<<"$first_bad") — $(cut -f2- <<<"$first_bad" | tr '\t' ' ')\n"
    FAIL=1
    note 3
    continue
  fi

  OK=$((OK + 1))
done

TOTAL="${#ID_ORDER[@]}"

if [ "$FAIL" -ne 0 ]; then
  echo "tdd-audit (runtime evidence): $OK/$TOTAL passed"
  printf '%b' "$ERRORS"
  exit "$CLS"
fi

echo "ok: $OK/$TOTAL test IDs verified against runtime evidence"
