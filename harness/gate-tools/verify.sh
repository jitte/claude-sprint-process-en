#!/bin/bash
# verify — check that the tasks of the config (lint / typecheck / build / test / e2e) pass.
#
# Usage: verify.sh [task ...]
#   task = one of the tasks of the config (all in the order of tasks when omitted)
#
# Run each task with `bin/sprint run <task>` and judge by the evidence contract JSON (lib/evidence.sh parses it).
#   - test / e2e: counts.failed = 0 and counts.skipped = 0
#   - lint / typecheck / build: errors = 0. warnings > 0 fails. Passes only when GATE_ALLOW_WARN=1 (the user judged go)
#
# Environment variables:
#   GATE_ALLOW_WARN   when 1, let warnings pass
#
# Exit code: 0 = pass / 2 = implementation problem (back to BUILD) / 4 = unknown task
set -uo pipefail
HARNESS="$(dirname "$(readlink -f "$0")")/.."
. "$HARNESS/lib/env.sh"
. "$HARNESS/lib/evidence.sh"
sprint_config_require

STEPS=("$@")
[ ${#STEPS[@]} -gt 0 ] || mapfile -t STEPS < <(sprint_tasks)

check_task() { # <task>
  local t="$1" c n st ok=1
  while read -r c tt; do
    [ "$tt" = "$t" ] || continue
    st=$(evidence_status "$c" "$t")
    case "$t" in
      test|e2e)
        n=$(evidence_counts "$c" "$t" failed)
        [ "${n:-0}" -eq 0 ] || { echo "$c.$t: $n failed"; ok=0; }
        n=$(evidence_counts "$c" "$t" skipped)
        [ "${n:-0}" -eq 0 ] || { echo "$c.$t: $n skipped"; ok=0; }
        ;;
      *)
        n=$(evidence_errors "$c" "$t")
        [ "${n:-0}" -eq 0 ] || { echo "$c.$t: $n errors (must be fixed. no override)"; ok=0; }
        n=$(evidence_warnings "$c" "$t")
        if [ "${n:-0}" -gt 0 ]; then
          if [ "${GATE_ALLOW_WARN:-0}" = "1" ]; then
            echo "$c.$t: $n warning(s). Passed because the user gave go"
          else
            echo "$c.$t: $n warnings (the user judges go/no-go. For go, rerun with GATE_ALLOW_WARN=1)"; ok=0
          fi
        fi
        ;;
    esac
    [ "$st" = "pass" ] || { echo "$c.$t: status $st"; ok=0; }
  done < <(evidence_required)
  [ "$ok" -eq 1 ]
}

for s in "${STEPS[@]}"; do
  grep -qx "$s" <<<"$(sprint_tasks)" || { echo "unknown task: $s"; exit 4; }
  bash "$HARNESS/bin/sprint" run "$s" > /dev/null 2>&1 || true
  check_task "$s" || { echo "$s failed"; exit 2; }
  echo "$s ok"
done
exit 0
