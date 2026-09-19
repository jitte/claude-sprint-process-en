#!/bin/bash
# PreToolUse hook: stop `cd <path>` in a Bash command.
# The CWD is always the project root. Run tasks with bin/sprint run. Refer to files with absolute paths.
# When sprint.config.json does not exist, do not judge and pass through (no output, exit 0).
. "$(dirname "$(readlink -f "$0")")/../lib/env.sh"
sprint_config_exists || exit 0
ROOT=$(sprint_root)

cmd=$(jq -r '.tool_input.command // ""')

# Stop only a cd in command position whose argument has the shape of a path (alphanumerics . / ~ $ - quotes).
# Words in documents (inside a heredoc) such as `| cd` followed by a Japanese word do not match, because the argument is Japanese.
if grep -qE '(^|[;&|]\s*)cd[[:space:]]+["'"'"'./~$A-Za-z0-9_-]' <<<"$cmd"; then
  tasks=$(sprint_tasks | tr '\n' ' ')
  cat <<JSON
{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"cd is forbidden. The CWD is always $ROOT.\n\nRun tasks through the runner:\n  bash harness/bin/sprint run <task> [<component>]   task = ${tasks}\n  bash harness/bin/sprint run all\n\nUse absolute paths to refer to files (example: $ROOT/...)."}}
JSON
  exit 0
fi

echo '{"continue":true}'
