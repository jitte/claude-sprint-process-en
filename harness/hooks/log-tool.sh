#!/bin/bash
# PreToolUse / PostToolUse logging hook.
# Append every tool call to .sprint/logs/tools.jsonl, 1 line each (to stream it with tail -F).
#
# Invariant: never block a tool. Always return {"continue":true} and exit 0.
#   No error (jq failure, missing directory, or any other) stops the tool run.
#
# The output format is pino NDJSON (to read it with `tail -F * | pino-pretty`).
#   level: fixed 30 / time: epoch ms / name: actor / msg: 1 line for a human to read
#   ts also holds the JST ISO time (for following the raw log by eye)
# Recorded fields: evt(Pre|Post) / actor / tool / id(tool_use_id)
#           Pre: input(tool_input as is)
#           Post: dur_ms / out_len(total length of tool_response)
#
# Why the body of tool_response is not recorded: the full text is the same as toolUseResult in the
# transcript under ~/.claude, which stays as the source of truth (confirmed by measurement). tools.jsonl is
# a view "to follow in real time as 1 stream", not a copy of the source of truth.
# To read the output, look it up in the transcript. Only the length stays, as out_len.
. "$(dirname "$(readlink -f "$0")")/../lib/env.sh"
sprint_config_exists || exit 0
ROOT=$(sprint_root)
LOGDIR="$ROOT/.sprint/logs"
INPUT=$(cat)

mkdir -p "$LOGDIR" 2>/dev/null
TS=$(sprint_date '+%Y-%m-%dT%H:%M:%S' 2>/dev/null)
MS=$(date +%s%3N 2>/dev/null)
case "$MS" in ''|*[!0-9]*) MS=$(( $(date +%s 2>/dev/null) * 1000 )) ;; esac

printf '%s' "$INPUT" | jq -c --arg ts "$TS" --argjson ms "$MS" '
  ((.hook_event_name // "") | sub("ToolUse"; "")) as $evt |
  (.agent_type // "main") as $actor |
  (.tool_name // "?") as $tool |
  ((.tool_input // {}) | tostring | gsub("[\n\r]"; " ") | .[0:160]) as $head |
  {
    level: 30,
    time: $ms,
    name: $actor,
    msg: (if $evt == "Pre" then "▶ \($tool)  \($head)"
          else "✓ \($tool)  \(.duration_ms // 0)ms" end),
    ts: $ts,
    evt: $evt,
    actor: $actor,
    tool: $tool,
    id: (.tool_use_id // ""),
    dur_ms: (.duration_ms // null)
  }
  + (if $evt == "Pre"  then {input: (.tool_input // {})} else {} end)
  + (if $evt == "Post" then {out_len: ((.tool_response // "") | tostring | length)} else {} end)
' >> "$LOGDIR/tools.jsonl" 2>/dev/null

echo '{"continue":true}'
exit 0
