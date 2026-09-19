#!/bin/bash
# stage-tokens.sh — record the token usage per stage.
#   sprint.sh calls it at a stage transition (when it has judged that the advance to the next stage is allowed).
#   Aggregate the tokens used since the previous snapshot (cursor) from the transcript JSONL,
#   and append 1 line to .sprint/logs/stage-tokens.jsonl.
#
# Keep each record self-contained so that it "can be reconstructed later without gaps":
#   - exact boundaries since/until (UTC, cursor values)
#   - main: breakdown of message.usage (in/out/cache_w/cache_r, per model)
#   - subagent: extract subagent_tokens reliably from the tool_result linked to the tool_use_id of Agent
#     (a scan of the full transcript also picks up display text from investigations, so limit it by tool_use_id correlation)
#   This file is responsible for the completeness of the record. It provides no display (the way to view it changes each time).
#   The output is pino NDJSON, so `tail -F | pino-pretty` reads it as is.
#
# Invariant: never stop sprint.sh. exit 0 on any failure.
#   Advance the cursor only when the aggregation succeeds (a failed part carries over to the next time).
#
# Usage: stage-tokens.sh <sprint_id> <from_stage> <to_stage>
set -u
. "$(dirname "$(readlink -f "$0")")/../lib/env.sh"
ROOT=$(sprint_root)
LOGDIR="$ROOT/.sprint/logs"
CURSOR="$LOGDIR/.stage-tokens-cursor"
OUT="$LOGDIR/stage-tokens.jsonl"
SPRINT="${1:-?}"; FROM="${2:-?}"; TO="${3:-?}"

mkdir -p "$LOGDIR" 2>/dev/null
TS_JST=$(sprint_date '+%Y-%m-%dT%H:%M:%S' 2>/dev/null)
NOW_UTC=$(date -u '+%Y-%m-%dT%H:%M:%S.000Z' 2>/dev/null)
MS=$(date +%s%3N 2>/dev/null)
case "$MS" in ''|*[!0-9]*) MS=$(( $(date +%s 2>/dev/null) * 1000 )) ;; esac

# Transcript directory = $HOME/.claude/projects/<slug of the root> (`/` and `.` replaced with `-`)
TDIR="$HOME/.claude/projects/$(printf '%s' "$ROOT" | sed 's#[/.]#-#g')"
[ -d "$TDIR" ] || exit 0

# First time (no cursor): initialize only (the start point of the later differences)
if [ ! -f "$CURSOR" ]; then
  echo "$NOW_UTC" > "$CURSOR" 2>/dev/null
  jq -nc --argjson ms "$MS" --arg ts "$TS_JST" --arg until "$NOW_UTC" --arg sp "$SPRINT" --arg f "$FROM" --arg t "$TO" \
    '{level:30, time:$ms, name:"tokens", msg:"\($sp)  cursor-init",
      ts:$ts, since:null, until:$until, sprint:$sp, from:$f, to:$t, note:"cursor-init", total_tokens:0}' >> "$OUT" 2>/dev/null
  exit 0
fi

SINCE=$(cat "$CURSOR" 2>/dev/null)
# Only transcripts updated after the cursor (narrowed by mtime)
FILES=$(find "$TDIR" -maxdepth 1 -name '*.jsonl' -newer "$CURSOR" 2>/dev/null)

TMP=$(mktemp 2>/dev/null) || exit 0
if [ -n "$FILES" ]; then
  # shellcheck disable=SC2086
  jq -sc --argjson ms "$MS" --arg since "$SINCE" --arg until "$NOW_UTC" --arg ts "$TS_JST" --arg sp "$SPRINT" --arg f "$FROM" --arg t "$TO" '
    def agg(arr): { msgs:(arr|length),
      in:     (arr|[.[].message.usage.input_tokens]|add // 0),
      out:    (arr|[.[].message.usage.output_tokens]|add // 0),
      cache_w:(arr|[.[].message.usage.cache_creation_input_tokens]|add // 0),
      cache_r:(arr|[.[].message.usage.cache_read_input_tokens]|add // 0) };
    ( [ .[] | select(.type=="assistant" and ((.timestamp // "") > $since) and (.message.usage != null)) ] ) as $m
    | ( [ .[] | select(.type=="assistant") | .message.content[]?
          | select(.type=="tool_use" and (.name=="Task" or .name=="Agent")) | .id ] ) as $aids
    | ( [ .[] | select(.type=="user" and ((.timestamp // "") > $since)) | .message.content[]?
          | select(.type=="tool_result" and ((.tool_use_id) as $id | ($aids | index($id)) != null)) ] ) as $res
    # The subagent usage is in the body of <task-notification>, not in tool_result.
    # The tool_result of an asynchronous Agent is only the launch response and has no usage (D3).
    # The notation is the XML tag <subagent_tokens>N</subagent_tokens> (not `: N`).
    # The target is the text blocks of user messages (also picks up content that is a string).
    | ( [ .[] | select(.type=="user" and ((.timestamp // "") > $since)) | .message.content
          | if type=="string" then . else ([.[]? | select(.type=="text") | .text] | join("\n")) end
          | select(. != null) | scan("<subagent_tokens>([0-9]+)</subagent_tokens>") | .[0] | tonumber ] ) as $st
    | (agg($m)) as $ma
    | (($ma.in + $ma.out + $ma.cache_w + $ma.cache_r) + ($st|add // 0)) as $tot
    | {
        level: 30,
        time: $ms,
        name: "usage",
        msg: "\($sp)  \($f) → \($t)  total=\($tot)  main=\($ma.in + $ma.out)(+cache \($ma.cache_w + $ma.cache_r))  sub=\($st|add // 0)(\($st|length) results)",
        ts:$ts, since:$since, until:$until, sprint:$sp, from:$f, to:$t,
        main: ($ma + { by_model: ($m | group_by(.message.model) | map({ (.[0].message.model // "?"): agg(.) }) | add) }),
        subagent: { calls: ($res|length), results: ($st|length), tokens: ($st|add // 0) },
        total_tokens: $tot
      }
  ' $FILES > "$TMP" 2>/dev/null
else
  # No new transcript update → 0 usage (the boundaries are recorded)
  jq -nc --argjson ms "$MS" --arg since "$SINCE" --arg until "$NOW_UTC" --arg ts "$TS_JST" --arg sp "$SPRINT" --arg f "$FROM" --arg t "$TO" \
    '{level:30, time:$ms, name:"tokens", msg:"\($sp)  \($f) → \($t)  total=0",
      ts:$ts, since:$since, until:$until, sprint:$sp, from:$f, to:$t,
      main:{msgs:0,in:0,out:0,cache_w:0,cache_r:0}, subagent:{calls:0,results:0,tokens:0}, total_tokens:0}' > "$TMP" 2>/dev/null
fi

if [ -s "$TMP" ]; then
  cat "$TMP" >> "$OUT" 2>/dev/null
  echo "$NOW_UTC" > "$CURSOR" 2>/dev/null   # advance the cursor only on success
fi
rm -f "$TMP" 2>/dev/null
exit 0
