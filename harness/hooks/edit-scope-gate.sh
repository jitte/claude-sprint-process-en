#!/bin/bash
export PATH="${PATH:+$PATH:}/usr/local/bin:/usr/bin:/bin"   # prefer the caller's PATH; guarantee the basic commands even in the minimal hook environment
# PreToolUse hook: edit scope gate
#
# Deny an out-of-scope edit by the combination of the Write/Edit caller (agent_type. main when missing) and
# the target path. The matrix is in scope-lib.sh (the source of truth). The only part specific to this file is
# the UNSEAL region check of qa on TEST.md (it looks at old_string of Edit / the content hash of Write).
# Writes through Bash are not judged. Write src / tests with Edit / Write.
# When sprint.config.json does not exist, do not judge and pass through (no output, exit 0).

INPUT=$(cat)
HERE=$(readlink -f "$0"); HERE=${HERE%/*}
. "$HERE/../lib/env.sh"
sprint_config_exists || exit 0

# Read the input with 1 jq call. The separator is US (0x1f). Do not use a whitespace character, so that an empty field (no agent_type) is not dropped
IFS=$'\x1f' read -r TOOL_NAME AGENT_TYPE FILE_PATH < <(printf '%s' "$INPUT" | jq -r '[.tool_name, (.agent_type // ""), (.tool_input.file_path // "")] | join("\u001f")')
case "$TOOL_NAME" in Write|Edit) ;; *) exit 0 ;; esac

. "$HERE/scope-lib.sh"
SCOPE_TABLE=$(_scope_table)   # build the decision table only once (scope_* read it)

ACTOR="${AGENT_TYPE:-main}"

# Build the deny JSON in bash (1 fewer jq call). Escape only \ and " and newlines in the reason text
emit_deny() {
  local r="$1"
  r="${r//\\/\\\\}"; r="${r//\"/\\\"}"; r="${r//$'\n'/\\n}"
  printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"%s"}}\n' "$r"
  exit 0
}

TYPE=$(scope_classify "$FILE_PATH")
DECISION=$(scope_decision "$ACTOR" "$TYPE")

case "$DECISION" in
  allow) exit 0 ;;
  deny)
    case "$TYPE" in
      state)
        case "$FILE_PATH" in
          */spec-hashes.json) emit_deny "spec-hashes.json is a generated file. Do not edit it directly. Update it with bash harness/bin/sprint seal." ;;
          *) emit_deny "Update flags.json only through harness/bin/sprint (bash harness/bin/sprint stage and other subcommands). Direct edits are forbidden to prevent stage skips." ;;
        esac ;;
      spec)
        case "$ACTOR" in
          qa) emit_deny "SPEC.md is the implementation contract for backend/frontend. The qa agent has read-only access." ;;
          *)  emit_deny "SPEC.md is a specification that main drafts. The ${ACTOR} agent has read-only access." ;;
        esac ;;
      testmd) emit_deny "TEST.md is a specification that main drafts. The ${ACTOR} agent has read-only access." ;;
      *) emit_deny "${ACTOR} cannot edit ${TYPE} code (${FILE_PATH}). Delegate to $(scope_owner "$TYPE")." ;;
    esac ;;
esac

# ── unseal: qa × TEST.md. Allow only inside the <!-- UNSEAL --> block ──
SEAL="$HERE/../tools/spec-seal.sh"
[ -f "$SEAL" ] || exit 0
UNSEALED=$(bash "$SEAL" regions-unsealed "$FILE_PATH" 2>/dev/null || true)
[ -n "$UNSEALED" ] || emit_deny "TEST.md is sealed in full. Mark the unsealed region with <!-- UNSEAL:BEGIN/END -->. Ask main for spec changes."
if [ "$TOOL_NAME" = "Edit" ]; then
  OLD=$(echo "$INPUT" | jq -r '.tool_input.old_string // ""')
  NEW=$(echo "$INPUT" | jq -r '.tool_input.new_string // ""')
  case "$OLD$NEW" in
    *"SEAL:BEGIN"*|*"SEAL:END"*) emit_deny "The qa agent cannot edit the seal markers (<!-- (UN)SEAL --> )." ;;
  esac
  case "$UNSEALED" in
    *"$OLD"*) exit 0 ;;
    *) emit_deny "The qa agent cannot edit the sealed region of TEST.md. It can edit only the unsealed region (inside <!-- UNSEAL -->). Ask main for spec changes." ;;
  esac
else
  CONTENT=$(echo "$INPUT" | jq -r '.tool_input.content // ""')
  NEWHASH=$(printf '%s\n' "$CONTENT" | bash "$SEAL" hash-stdin 2>/dev/null || true)
  CURHASH=$(bash "$SEAL" manifest-get "$FILE_PATH" 2>/dev/null || true)
  if [ -n "$CURHASH" ] && [ "$NEWHASH" != "$CURHASH" ]; then
    emit_deny "This Write by the qa agent changes the sealed region of TEST.md. Edit only the unsealed region."
  fi
fi
exit 0
