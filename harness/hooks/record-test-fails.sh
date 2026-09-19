#!/bin/bash
# PostToolUse hook: right after `sprint run` runs in Bash, record the test failure count from the evidence contract JSON
# to .sprint/test-fails.json. The `bin/sprint status` display uses it.
# Does not read results (green) of gate-check (looks at the evidence itself).
# When sprint.config.json does not exist, do not judge and pass through (no output, exit 0).
#
# Format: { "total": n, "tasks": { "<component>.<task>": n, ... }, "recorded_at": "..." }
#   n is counts.failed for test / e2e, errors for lint / typecheck, and 1 for build when status is fail
. "$(dirname "$(readlink -f "$0")")/../lib/env.sh"
sprint_config_exists || exit 0
. "$(dirname "$(readlink -f "$0")")/../lib/evidence.sh"
ROOT=$(sprint_root)
FAILS_FILE="$ROOT/.sprint/test-fails.json"
INPUT=$(cat)

# Get the command of the Bash tool
COMMAND=$(printf '%s' "$INPUT" | jq -r '.tool_input.command // ""' 2>/dev/null)

# Do nothing unless it is sprint run
case "$COMMAND" in
  *"sprint run"*|*"sprint\" run"*) ;;
  *) echo '{"continue":true}'; exit 0 ;;
esac

total=0
tasks="{}"
while read -r c t; do
  [ -n "$c" ] || continue
  [ -f "$(evidence_file "$c" "$t")" ] || continue
  case "$t" in
    test|e2e) n=$(evidence_counts "$c" "$t" failed) ;;
    build)    if [ "$(evidence_status "$c" "$t")" = "pass" ]; then n=0; else n=1; fi ;;
    *)        n=$(evidence_errors "$c" "$t") ;;
  esac
  n=${n:-0}
  total=$((total + n))
  tasks=$(jq -c --arg k "$c.$t" --argjson n "$n" '. + {($k): $n}' <<<"$tasks")
done < <(evidence_required)

TS=$(sprint_date '+%Y-%m-%dT%H:%M:%S%z' 2>/dev/null)
mkdir -p "$(dirname "$FAILS_FILE")" 2>/dev/null
jq -nc --argjson total "$total" --argjson tasks "$tasks" --arg ts "$TS" \
  '{total: $total, tasks: $tasks, recorded_at: $ts}' > "$FAILS_FILE"

echo '{"continue":true}'
exit 0
