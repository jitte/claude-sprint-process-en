#!/bin/bash
# Mix the subagent lifecycle into the same stream of tools.jsonl.
# Target events: SubagentStart / SubagentStop / TaskCompleted
#
# Purpose: "follow the exchange with subagents with tail -F".
# The Pre record of the Agent tool holds the outgoing side (the prompt) as input.prompt.
# This hook records the incoming side (the final report) in full as the msg of AgentStop.
#
# The output format is pino NDJSON (to read it with `tail -F * | pino-pretty`).
#   level: 30 / time: epoch ms / name: agent_type / msg: text for a human to read
# The msg of AgentStop holds the **full** final report of the agent. Do not truncate it.
# Reading it is the purpose itself, and a report does not become as large as tool output.
# Recorded fields: evt(AgentStart|AgentStop) / actor(agent_type) / tool("Agent")
#           id(agent_id) / report(final report, full text) / tp(path of the subagent transcript)
#
# Invariant: never block, whatever happens. Always return {"continue":true} and exit 0.
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
  (.hook_event_name // "?") as $e |
  (if $e == "SubagentStart" then "AgentStart"
   elif $e == "SubagentStop" then "AgentStop"
   else $e end) as $evt |
  (.agent_type // "?") as $actor |
  ((.last_assistant_message // "") | tostring) as $report |
  {
    level: 30,
    time: $ms,
    name: $actor,
    msg: (if $evt == "AgentStart" then "⇢ launch"
          elif $evt == "AgentStop" then "⇠ done\n\($report)"
          else $evt end),
    ts: $ts,
    evt: $evt,
    actor: $actor,
    tool: "Agent",
    id: (.agent_id // ""),
    tp: (.agent_transcript_path // null)
  }
  + (if $report != "" then {report: $report} else {} end)
' >> "$LOGDIR/tools.jsonl" 2>/dev/null

echo '{"continue":true}'
exit 0
