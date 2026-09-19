#!/bin/bash
# PreToolUse hook: Sprint stage-based agent gate
#
# Allow or deny agent launch by the stage of the active sprint in .sprint/flags.json.
# edit-scope-gate.sh (the matrix in scope-lib.sh) judges the write constraints.
# When sprint.config.json does not exist, do not judge and pass through (no output, exit 0).

INPUT=$(cat)
TOOL_NAME=$(echo "$INPUT" | jq -r '.tool_name')

[ "$TOOL_NAME" != "Agent" ] && exit 0

# Define deny before its first call (the early deny on a missing flags.json uses it)
deny() {
  echo "{\"hookSpecificOutput\":{\"hookEventName\":\"PreToolUse\",\"permissionDecision\":\"deny\",\"permissionDecisionReason\":\"$1\"}}"
  exit 0
}

. "$(dirname "$(readlink -f "$0")")/../lib/env.sh"
sprint_config_exists || exit 0
SUBAGENT_TYPE=$(echo "$INPUT" | jq -r '.tool_input.subagent_type // ""')

# Always allow agents that collect information
case "$SUBAGENT_TYPE" in
  Explore|general-purpose|claude-code-guide|Plan|statusline-setup|"") exit 0 ;;
esac

FLAGS="$(sprint_root)/.sprint/flags.json"

# No flags.json or no active set → agents cannot be launched
if [ ! -f "$FLAGS" ]; then
  deny "No sprint is set. Create .sprint/flags.json."
fi

ACTIVE=$(jq -r '.active // ""' "$FLAGS")

if [ -z "$ACTIVE" ]; then
  deny "No active sprint is set. Set active in flags.json."
fi

STAGE=$(jq -r --arg id "$ACTIVE" '.sprints[$id].stage // ""' "$FLAGS")
STATUS=$(jq -r --arg id "$ACTIVE" '.sprints[$id].status // ""' "$FLAGS")

if [ -z "$STAGE" ]; then
  deny "The stage of sprint ${ACTIVE} is not set."
fi

# Allow check per stage

ALLOWED=""
case "$STAGE" in
  PLAN)
    deny "You cannot launch agents in the ${STAGE} stage. Do the work in main." ;;
  SHIP)
    case "$SUBAGENT_TYPE" in qa) ALLOWED=1 ;; esac
    [ -z "$ALLOWED" ] && deny "In the SHIP stage, you can launch only qa. You cannot launch ${SUBAGENT_TYPE}." ;;
  REVIEW)
    [ "$STATUS" = "closed" ] && deny "REVIEW is complete (status=closed). You cannot run it again. Wait for the user's instruction at the 🚧 gate. To apply the findings, roll back with 'bash harness/bin/sprint stage PLAN', then do the work."
    case "$SUBAGENT_TYPE" in qa) ALLOWED=1 ;; esac ;;
  build-red)
    case "$SUBAGENT_TYPE" in tester) ALLOWED=1 ;; esac
    [ -z "$ALLOWED" ] && deny "In the build-red phase, you can launch only tester. You cannot launch ${SUBAGENT_TYPE}." ;;
  BUILD)
    case "$SUBAGENT_TYPE" in frontend|backend|tester) ALLOWED=1 ;; esac ;;
  TEST)
    [ "$STATUS" = "closed" ] && deny "TEST is complete (status=closed). You cannot run it again. Wait for the user's instruction at the 🚧 gate. If a fix is necessary, roll back with 'bash harness/bin/sprint stage BUILD' (or another earlier stage), then do the work."
    case "$SUBAGENT_TYPE" in tester|qa) ALLOWED=1 ;; esac ;;
  DOCS)
    case "$SUBAGENT_TYPE" in qa) ALLOWED=1 ;; esac ;;
  CLOSED)
    ALLOWED=1 ;;
  *)
    ALLOWED=1 ;;
esac

if [ -z "$ALLOWED" ]; then
  deny "You cannot launch ${SUBAGENT_TYPE} in the ${STAGE} stage."
fi

exit 0
