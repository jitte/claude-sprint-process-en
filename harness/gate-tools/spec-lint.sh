#!/bin/bash
# spec-lint — machine check of the specification (REVIEW / build-red gate).
#
# Usage: spec-lint.sh [check ...]
#   check = graph | refs | test-id (all when omitted. Run all, then aggregate)
#   graph   : harness/tools/spec-graph.sh verify (clause references V1 to V3 / V5 / V6 / V8 to V11)
#   refs    : §0 (Referenced common clauses) of the SPEC.md of the active sprint states the handling and the reason
#   test-id : the ID in each test definition row of the TEST.md of the active sprint has the form TEST-<sprint_id>-<major>.<minor>
#
# Environment variables (test entry points):
#   SPEC_GRAPH_ROOT   scan root of graph
#   SPEC_REFS_TARGET  SPEC.md that refs reads (when omitted, resolved from active in flags.json)
#   TID_TEST_MD       TEST.md that test-id reads (same as above)
#   TID_SPRINT_ID     sprint id that test-id expects (same as above)
#
# Exit code: 0 = pass / 1 = spec problem (back to PLAN) / 4 = unknown check
set -uo pipefail
. "$(dirname "$(readlink -f "$0")")/../lib/env.sh"
sprint_config_require
ROOT=$(sprint_root)
FLAGS="$ROOT/.sprint/flags.json"
CHECKS=("$@")
[ ${#CHECKS[@]} -gt 0 ] || CHECKS=(graph refs test-id)
FAIL=0

active_id()  { jq -r '.active // ""' "$FLAGS" 2>/dev/null; }
active_dir() { jq -r --arg id "$(active_id)" '.sprints[$id].sprint_dir // ""' "$FLAGS" 2>/dev/null; }

check_graph() {
  local out
  out=$(bash "$(dirname "$(readlink -f "$0")")/../tools/spec-graph.sh" verify 2>&1) || { echo "$out"; FAIL=1; return; }
  echo "$out"
}

# Check that "Test handling" and "Test ID / reason" are filled in on each §0 table row. Do not check whether the content is valid.
# Accept only table rows in the new notation [ID](path#ID). Do not pick up the old double-bracket notation as a table row
# (if it stays accepted, nothing pushes the move to the new notation). Read only 1 file: the SPEC.md of the active sprint.
check_refs() {
  local spec section ref_cell rows n=0 bad=0 row cid handling evidence pair col val
  spec="${SPEC_REFS_TARGET:-$ROOT/$(active_dir)/SPEC.md}"
  [ -f "$spec" ] || { echo "SPEC.md not found: $spec"; FAIL=1; return; }
  if ! grep -q '^## 0\. Referenced common clauses' "$spec"; then
    echo "§0 (## 0. Referenced common clauses) heading not found"
    echo "  You cannot skip the check by omitting the whole section. Follow the template docs/06_process/templates/SPEC.md"
    FAIL=1; return
  fi
  section=$(awk '/^## 0\. Referenced common clauses/{f=1;next} f&&/^## /{exit} f{print}' "$spec")
  ref_cell='\[[A-Z]{2,6}-[0-9]+\]\([^)]*#[A-Z]{2,6}-[0-9]+\)'
  rows=$(printf '%s\n' "$section" | grep -E "^\|[[:space:]]*${ref_cell}[[:space:]]*\|" || true)
  if [ -z "$rows" ]; then
    if grep -qE '^\|[[:space:]]*\(no references\)[[:space:]]*\|' <<<"$section"; then
      echo "refs ok: §0 has zero references (the decision is recorded with a (no references) row)"
      return
    fi
    echo "§0 has no clause reference table row and no (no references) row"
    echo "  Write each referenced clause in column 1 in the form [ID](<relative path>#ID)"
    echo "  The old double-bracket notation is not accepted. The notation is in docs/05_specifications/README.md §3"
    echo "  If the spec does not depend on common clauses, write the following 1 row:"
    echo "  | (no references) | — | none | Does not depend on common clauses |"
    FAIL=1; return
  fi
  while IFS= read -r row; do
    n=$((n + 1))
    cid=$(printf '%s' "$row" | awk -F'|' '{gsub(/^[ \t]+|[ \t]+$/,"",$2); print $2}')
    handling=$(printf '%s' "$row" | awk -F'|' '{gsub(/^[ \t]+|[ \t]+$/,"",$4); print $4}')
    evidence=$(printf '%s' "$row" | awk -F'|' '{gsub(/^[ \t]+|[ \t]+$/,"",$5); print $5}')
    for pair in "Test handling:$handling" "Test ID / reason:$evidence"; do
      col="${pair%%:*}"; val="${pair#*:}"
      case "$val" in
        ""|"—"|"-"|"TBD") echo "$cid: \"${col}\" is empty"; bad=1 ;;
      esac
    done
    case "$handling" in
      new|modify|reuse|none|""|"—"|"-"|"TBD") ;;
      *) echo "$cid: \"Test handling\" is not one of the 4 values (new / modify / reuse / none): $handling"; bad=1 ;;
    esac
  done <<< "$rows"
  if [ "$bad" -ne 0 ]; then echo "refs NG ($n rows checked)"; FAIL=1; return; fi
  echo "refs ok: all $n rows in §0 have a handling and a reason"
}

# Prefix each Test ID with the sprint ID to make it unique across all sprints. Fail if even 1 ID in the old form (no prefix)
# remains. Do not rewrite old-form IDs (their shape differs, so they do not collide with the new form).
# The old design (match against the TEST.md of other sprints by the pair (ID, file)) could not build the pair for a past TEST.md
# without a test file column, and let it pass unchecked. A change of the ID scheme is the real solution.
check_test_id() {
  local sprint_id test_md expect ids bad total
  sprint_id="${TID_SPRINT_ID:-$(active_id)}"
  test_md="${TID_TEST_MD:-$ROOT/$(active_dir)/TEST.md}"
  [ -n "$sprint_id" ] || { echo "cannot resolve the active sprint id"; FAIL=1; return; }
  [ -f "$test_md" ] || { echo "TEST.md not found: $test_md"; FAIL=1; return; }
  expect="TEST-${sprint_id}-"
  # Test definition rows (rows whose first cell is a Test ID). Pick up both the new and the old forms (to detect and fail the old form)
  ids=$(
    grep -E '^[[:space:]]*\|' "$test_md" \
    | awk -F'|' '{ gsub(/^[ \t]+|[ \t]+$/, "", $2); gsub(/\*/, "", $2); print $2 }' \
    | grep -E '^TEST-[0-9]+(-[0-9]+)*\.[0-9]+[a-z]?$' || true
  )
  if [ -z "$ids" ]; then echo "test-id ok (no test definition rows)"; return; fi
  bad=$(grep -v -F "$expect" <<<"$ids" || true)
  if [ -n "$bad" ]; then
    echo "Old-form Test IDs remain. Renumber them to the form ${expect}<major>.<minor> to make them unique across all sprints."
    echo "$bad" | sort -u | sed 's/^/  /'
    FAIL=1; return
  fi
  total=$(wc -l <<<"$ids" | tr -d ' ')
  echo "test-id ok (all $total in the ${expect} form)"
}

for c in "${CHECKS[@]}"; do
  case "$c" in
    graph)   check_graph ;;
    refs)    check_refs ;;
    test-id) check_test_id ;;
    *) echo "unknown check: $c"; exit 4 ;;
  esac
done

[ "$FAIL" -eq 0 ] || exit 1
exit 0
