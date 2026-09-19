#!/bin/bash
# Stage gate check runner
#
# Usage: gate-check.sh <STAGE>
#
# Read the tool list of the given stage from gates.<kind>.<STAGE> of sprint.config.json,
# look for <dir>/<tool>.sh in the order of gateToolsDirs, and run it.
# When at least one fails (exit != 0), the whole check returns fail.
#
# On failure, show the "failure class" and the "recommended stage" (§failure class).
# It does not run the transition itself — a human decides the rollback target.
set -euo pipefail

. "$(dirname "$(readlink -f "$0")")/../lib/env.sh"
sprint_config_require
ROOT=$(sprint_root)
FLAGS="$ROOT/.sprint/flags.json"
STAGE="${1:-}"
# Location of the tools (gateToolsDirs of the config. The first one found is used)
mapfile -t TOOLS_DIRS < <(sprint_config '.gateToolsDirs[]' | while IFS= read -r d; do sprint_abs_path "$d"; done)

# ── failure class ──────────────────────────────────────────────
# Divide gate failures into 4 classes and show the recommended stage. The class is chosen by "where to go back to fix it".
#   1 = spec problem     → PLAN
#   2 = impl problem     → BUILD
#   3 = test problem     → BUILD
#   4 = infra/procedure  → stay (repair in the current stage. no transition necessary)
#
# When a tool returns exit code 2/3/4, use it (tools whose class depends on
# the failure = results / impl-sync / tdd-audit / size-audit). A tool with exit 1 follows
# the default class below. Write the default class of project-specific tools (the 2nd and later gateToolsDirs) in
# gateToolClasses of the config ({ "<tool>": 1 to 4 }). When missing, 2.
default_class() {
  local c
  c=$(jq -r --arg t "$1" '.gateToolClasses[$t] // empty' "$(sprint_config_path)" 2>/dev/null)
  case "$c" in 1|2|3|4) echo "$c"; return ;; esac
  case "$1" in
    spec-files-exist|spec-seal)  echo 1 ;;  # spec artifact missing or changed
    spec-lint)                   echo 1 ;;  # broken clause references, §0 not filled in, Test ID format (spec structure)
    impl-sync)                   echo 1 ;;  # returns a dynamic class (1/2/4). exit 1 = spec
    tdd-audit)                   echo 1 ;;  # exit 1 = TEST.md missing or format (the dynamic class returns 3/4)
    verify|size-audit)           echo 2 ;;  # implementation does not pass, size over the limit (size-audit is dynamic 2)
    doc-exists)                  echo 2 ;;  # in docs, writing = implementation
    tdd-exists|doc-verified)     echo 3 ;;  # tests missing, verification not filled in
    results|ship-closed)         echo 4 ;;  # procedure gap (results returns dynamic 2/3/4)
    *)                           echo 2 ;;
  esac
}

class_label() {
  case "$1" in
    1) echo "spec" ;;
    2) echo "impl" ;;
    3) echo "test" ;;
    4) echo "infra" ;;
    *) echo "unknown" ;;
  esac
}

suggest() {
  case "$1" in
    1) echo "Roll back to PLAN (fix SPEC/TEST → REVIEW → bash harness/bin/sprint seal → build-red)" ;;
    2) echo "Roll back to BUILD (fix the implementation)" ;;
    3) echo "Roll back to BUILD (fix the tests, remove the skips, run again)" ;;
    4) echo "Stay in the stage (environment or procedure problem. Fix it by rerunning the tests or filling in the missing entries)" ;;
    *) echo "Unknown class. Check the output" ;;
  esac
}

[ -n "$STAGE" ] || { echo "Usage: gate-check.sh <STAGE>" >&2; exit 1; }

# Select the gate set by the kind of the active sprint (code|docs, code when unset)
KIND="code"
if [ -f "$FLAGS" ]; then
  AID=$(jq -r '.active // ""' "$FLAGS" 2>/dev/null || echo "")
  [ -n "$AID" ] && KIND=$(jq -r --arg id "$AID" '.sprints[$id].kind // "code"' "$FLAGS" 2>/dev/null || echo "code")
fi

# Get the tool list of the stage (per kind)
TOOLS=$(jq -r --arg k "$KIND" --arg s "$STAGE" '.gates[$k][$s] // [] | .[]' "$(sprint_config_path)" 2>/dev/null)

if [ -z "$TOOLS" ]; then
  echo "gate ($STAGE): no checks defined — pass"
  exit 0
fi

FAIL=0
TOTAL=0
PASSED=0
CLASSES=""

# Tell the tools that they run through the gate.
# The tools are launched as `bash "$SCRIPT"` without arguments, so a flag cannot be passed.
# A subshell inherits the environment, so one export before the loop lets every tool tell
# (the tools read it with sprint_via_gate of lib/env.sh).
# Example: size-audit treats 🟡 as a failure (1) when run by hand, and as a pass (0) when run through the gate.
export SPRINT_GATE=1

echo "=== Gate Check: $STAGE (kind=$KIND) ==="
for tool in $TOOLS; do
  TOTAL=$((TOTAL + 1))
  # Look in the order of gateToolsDirs
  SCRIPT=""
  for d in "${TOOLS_DIRS[@]}"; do
    [ -f "$d/${tool}.sh" ] && { SCRIPT="$d/${tool}.sh"; break; }
  done

  if [ -z "$SCRIPT" ]; then
    echo "  ✗ $tool [infra] — script not found: ${tool}.sh (${TOOLS_DIRS[*]})"
    FAIL=1
    CLASSES="$CLASSES 4"
    continue
  fi

  OUTPUT=$(bash "$SCRIPT" 2>&1) && RC=0 || RC=$?

  if [ "$RC" -eq 0 ]; then
    echo "  ✓ $tool"
    PASSED=$((PASSED + 1))
    continue
  fi

  # 2/3/4 are the dynamic classes that the tool returned. Every other code (1 = no class, and
  # unexpected codes such as 123 from set -e / pipefail) goes to the default class map.
  case "$RC" in
    2|3|4) CLS="$RC" ;;
    *)     CLS=$(default_class "$tool") ;;
  esac

  # With empty output the cause cannot be found, so add the exit code
  [ -n "$OUTPUT" ] || OUTPUT="(no output. exit code ${RC})"

  echo "  ✗ $tool [$(class_label "$CLS")] — $OUTPUT"
  FAIL=1
  CLASSES="$CLASSES $CLS"
done

echo "--- $PASSED/$TOTAL passed ---"

if [ "$FAIL" -ne 0 ]; then
  echo "=== GATE BLOCKED ==="
  # Base the recommendation on the most upstream class (the smallest number).
  WORST=$(printf '%s\n' $CLASSES | sort -n | head -1)
  LABELS=""
  for c in $(printf '%s\n' $CLASSES | sort -nu); do LABELS="$LABELS $(class_label "$c")"; done
  echo "Failure class:$LABELS"
  echo "Recommended: $(suggest "$WORST")"
  echo "(The transition does not run automatically. The user decides the rollback target)"
  exit 1
fi

echo "=== GATE PASSED ==="
exit 0
