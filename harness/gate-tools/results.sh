#!/bin/bash
# results — check the freshness and green of the execution evidence. Reads only the evidence contract JSON (lib/evidence.sh parses it).
#
# Usage: results.sh [check ...]
#   check = fresh | green (all when omitted)
#   fresh : for every (component, task) of the config, an evidence file exists and its finished_at is not older than
#           the last update of the source (files that match src ∪ tests of all components)
#   green : status is pass; for test / e2e, counts.failed = 0 and counts.skipped = 0;
#           for lint / typecheck / build, errors = 0 and warnings = 0 (warnings are ignored when GATE_ALLOW_WARN=1)
#           (.sprint/test-fails.json is not read. The hook writes it only right after a Bash call of main, so it becomes stale on a rerun in the gate)
#   .partial.json is not read.
#
# Exit code = failure class (gate-check.sh). It depends on the failure:
#   2 = lint / typecheck / build failure (implementation problem → BUILD)
#   3 = test failure or skipped (test problem → BUILD)
#   4 = evidence file missing or stale (tests not run = procedure problem → stay)
# When several are mixed, return the most upstream one (the smallest number).
set -uo pipefail
. "$(dirname "$(readlink -f "$0")")/../lib/env.sh"
. "$(dirname "$(readlink -f "$0")")/../lib/evidence.sh"
sprint_config_require
ROOT=$(sprint_root)
CHECKS=("$@")
[ ${#CHECKS[@]} -gt 0 ] || CHECKS=(fresh green)

FAIL=0
CLS=0
note() { # $1 = class code. Keep the more upstream one (smaller value)
  if [ "$CLS" -eq 0 ] || [ "$1" -lt "$CLS" ]; then CLS="$1"; fi
  FAIL=1
}

# Last update of the source (epoch seconds). The maximum over the files that match src ∪ tests
latest_source_mtime() {
  local globs
  mapfile -t globs < <(sprint_component_globs src; sprint_component_globs tests)
  [ ${#globs[@]} -gt 0 ] || return 0
  sprint_glob_files "${globs[@]}" | sed "s|^|$ROOT/|" | xargs -r -d '\n' stat -c '%Y' 2>/dev/null | sort -rn | head -1
}

check_fresh() {
  local latest c t s st fl sk er wa fin
  latest=$(latest_source_mtime)
  [ -n "$latest" ] || { echo "no source files found"; note 4; return; }
  while read -r c t; do
    [ -n "$c" ] || continue
    s=$(evidence_summary "$c" "$t")
    [ -n "$s" ] || { echo "$c.$t.json not found"; note 4; continue; }
    read -r st fl sk er wa fin <<<"$s"
    if [ "${fin:-0}" -lt "$latest" ]; then
      echo "$c.$t is stale (finished=$fin < source=$latest)"
      note 4
    fi
  done < <(evidence_required)
}

check_green() {
  local c t s st fl sk er wa fin
  while read -r c t; do
    [ -n "$c" ] || continue
    s=$(evidence_summary "$c" "$t")
    [ -n "$s" ] || { echo "$c.$t.json not found"; note 4; continue; }
    read -r st fl sk er wa fin <<<"$s"
    case "$t" in
      test|e2e)
        if [ "${fl:-0}" -gt 0 ]; then
          echo "$c.$t: $fl failed"; note 3
        elif [ "$st" != "pass" ]; then
          echo "$c.$t: status $st"; note 3
        fi
        if [ "${sk:-0}" -gt 0 ]; then
          echo "$c.$t: $sk skipped"; note 3
        fi
        ;;
      *)
        if [ "${er:-0}" -gt 0 ]; then
          echo "$c.$t: $er errors"; note 2
        elif [ "$st" != "pass" ]; then
          echo "$c.$t: status $st"; note 2
        fi
        if [ "${wa:-0}" -gt 0 ] && [ "${GATE_ALLOW_WARN:-0}" != "1" ]; then
          echo "$c.$t: $wa warnings"; note 2
        fi
        ;;
    esac
  done < <(evidence_required)
}

for c in "${CHECKS[@]}"; do
  case "$c" in
    fresh) check_fresh ;;
    green) check_green ;;
    *) echo "unknown check: $c"; exit 4 ;;
  esac
done

[ "$FAIL" -eq 0 ] || exit "$CLS"
echo "ok (${CHECKS[*]})"
