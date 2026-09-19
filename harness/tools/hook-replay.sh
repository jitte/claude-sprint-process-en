#!/bin/bash
# hook-replay.sh — feed the recorded tool calls to 2 versions of the hooks and count the verdict differences.
#
# Build the hook input {tool_name, tool_input, agent_type, cwd} from the Pre records (Write / Edit / Agent) of
# .sprint/logs/tools.jsonl, and feed it to both the hooks of <base> (taken out with git show) and
# the hooks of the working tree. Compare permissionDecision and permissionDecisionReason, and print
# the records with a difference. Use it to verify a hook cleanup (a change that keeps the behavior).
#
# Usage: hook-replay.sh <base-ref> [tools.jsonl]
# Output: number of replays and number of verdict differences (1 line per difference). exit 0 when there are 0 differences
# Environment variables:
#   HOOK_REPLAY_HOOKS   hook directory of the working tree (default harness/hooks). For base, take out harness/hooks
#                       when base has it, otherwise the former layout (.claude/hooks)
#
# Precondition: run both versions with the same CLAUDE_PROJECT_DIR (the root of the working tree). Both read the current
# stage and seal state, so agreement with the verdict at record time is not guaranteed. Only the 2 versions are compared.
set -uo pipefail
. "$(dirname "$(readlink -f "$0")")/../lib/env.sh"
ROOT=$(sprint_root)
WORK_HOOKS="$ROOT/${HOOK_REPLAY_HOOKS:-harness/hooks}"
BASE="${1:-}"; LOG="${2:-$ROOT/.sprint/logs/tools.jsonl}"
[ -n "$BASE" ] || { echo "usage: hook-replay.sh <base-ref> [tools.jsonl]" >&2; exit 2; }
[ -f "$LOG" ] || { echo "not found: $LOG" >&2; exit 2; }

OLD=$(mktemp -d); trap 'rm -rf "$OLD"' EXIT
# Location of the base hooks. Take out harness/hooks when base has it, otherwise the former layout (.claude/hooks + scripts/lib)
if git -C "$ROOT" cat-file -e "$BASE:harness/hooks/edit-scope-gate.sh" 2>/dev/null; then
  BASE_HOOKS="harness/hooks"
  mkdir -p "$OLD/harness/hooks" "$OLD/harness/lib"
  for f in agent-gate.sh edit-scope-gate.sh scope-lib.sh; do
    git -C "$ROOT" show "$BASE:harness/hooks/$f" > "$OLD/harness/hooks/$f" 2>/dev/null || : > "$OLD/harness/hooks/$f"
  done
  for f in env.sh config.sh evidence.sh; do
    git -C "$ROOT" show "$BASE:harness/lib/$f" > "$OLD/harness/lib/$f" 2>/dev/null || true
  done
  # For the neighbor tools/spec-seal.sh (UNSEAL check), use the base version
  mkdir -p "$OLD/harness/tools"
  git -C "$ROOT" show "$BASE:harness/tools/spec-seal.sh" > "$OLD/harness/tools/spec-seal.sh" 2>/dev/null || true
  chmod +x "$OLD"/harness/hooks/*.sh
else
  BASE_HOOKS=".claude/hooks"
  mkdir -p "$OLD/.claude/hooks" "$OLD/scripts/lib"
  for f in agent-gate.sh edit-scope-gate.sh scope-lib.sh; do
    git -C "$ROOT" show "$BASE:.claude/hooks/$f" > "$OLD/.claude/hooks/$f" 2>/dev/null || : > "$OLD/.claude/hooks/$f"
  done
  # In case the old version reads lib (which base may not have) or scope-lib with a fixed path, make it read the taken-out files
  git -C "$ROOT" show "$BASE:scripts/lib/env.sh" > "$OLD/scripts/lib/env.sh" 2>/dev/null || true
  # For the old version (which reads scope-lib.sh with a fixed-path default), make it read the taken-out file, whatever the default is
  sed -i -E "s|\"\\$\{CLAUDE_PROJECT_DIR:-[^}]*\}/.claude/hooks/scope-lib.sh\"|\"$OLD/.claude/hooks/scope-lib.sh\"|" "$OLD/.claude/hooks/edit-scope-gate.sh"
  chmod +x "$OLD"/.claude/hooks/*.sh
fi

export CLAUDE_PROJECT_DIR="$ROOT"
run_hook() { # <hook-path> <json>
  printf '%s' "$2" | bash "$1" 2>/dev/null | jq -c '[.hookSpecificOutput.permissionDecision // "allow", .hookSpecificOutput.permissionDecisionReason // ""]' 2>/dev/null || echo '["error",""]'
}

n=0; diff=0
while IFS= read -r rec; do
  n=$((n + 1))
  input=$(jq -c --arg cwd "$ROOT" '{tool_name: .tool, tool_input: .input, cwd: $cwd} + (if .actor != "main" then {agent_type: .actor} else {} end)' <<<"$rec")
  case "$(jq -r .tool <<<"$rec")" in
    Agent) h=agent-gate.sh ;;
    *)     h=edit-scope-gate.sh ;;
  esac
  a=$(run_hook "$OLD/$BASE_HOOKS/$h" "$input")
  b=$(run_hook "$WORK_HOOKS/$h" "$input")
  if [ "$a" != "$b" ]; then
    diff=$((diff + 1))
    echo "DIFF #$n $(jq -r '.tool + " " + (.actor // "main") + " " + ((.input.file_path // .input.subagent_type) // "")' <<<"$rec")"
    echo "  base: $a"
    echo "  work: $b"
  fi
done < <(jq -c 'select(.evt=="Pre" and (.tool=="Edit" or .tool=="Write" or .tool=="Agent"))' "$LOG")

echo "replayed: $n  diff: $diff"
[ "$diff" -eq 0 ]
