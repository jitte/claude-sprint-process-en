#!/bin/bash
# harness/lib/evidence.sh — reading the execution evidence (the evidence contract JSON) (the source of truth).
#
# This is the only place that reads the evidence. Readers: gate-tools/results.sh, gate-tools/verify.sh,
# gate-tools/tdd-audit.sh, hooks/record-test-fails.sh, bin/sprint status.
# Read env.sh first (this file uses sprint_root and sprint_config).
#
# Evidence files (bin/sprint run writes the output of the adapter's convert-evidence):
#   <evidence.dir>/<component>.<task>.json           1 file per run
#   <evidence.dir>/<component>.<task>.partial.json   partial run with extra args. Gates do not read it
#   <evidence.dir>/raw/<component>.<task>/           runner-specific output (text and JSON). Not read here
#
# JSON fields: schemaVersion / component / task / adapter / status(pass|fail) /
#   counts{passed,failed,skipped} / errors / warnings / tests[]{file,name,status} / started_at / finished_at
#
# Functions:
#   evidence_dir                          evidence directory (absolute)
#   evidence_file <component> <task>      path of the evidence file
#   evidence_required                     print all (component, task) pairs of the config as "<component> <task>"
#   evidence_status <c> <t>               pass | fail (empty when missing)
#   evidence_counts <c> <t> <key>         counts.<key> (0 when missing)
#   evidence_errors <c> <t>               errors (0 when missing)
#   evidence_warnings <c> <t>             warnings (0 when missing)
#   evidence_finished_at <c> <t>          finished_at (epoch seconds. 0 when missing)
#   evidence_summary <c> <t>              print "status failed skipped errors warnings finished_at" in 1 line (an empty line when missing)
#   evidence_tests_tsv                    print tests[] of all (component, test|e2e) pairs of the config as "file<TAB>status<TAB>name".
#                                         Returns 1 when no evidence exists. Does not read partial

evidence_dir() {
  sprint_abs_path "$(sprint_config '.evidence.dir // ".sprint/test-result"')"
}

evidence_file() { # <component> <task>
  printf '%s/%s.%s.json\n' "$(evidence_dir)" "$1" "$2"
}

evidence_required() {
  sprint_required_tasks
}

_evidence_get() { # <component> <task> <jq filter> <default>
  local f
  f=$(evidence_file "$1" "$2")
  [ -f "$f" ] || { printf '%s\n' "$4"; return 0; }
  jq -r "$3 // \"$4\"" "$f" 2>/dev/null || printf '%s\n' "$4"
}

evidence_status() { # <c> <t>
  _evidence_get "$1" "$2" '.status' ""
}

evidence_counts() { # <c> <t> <key>
  _evidence_get "$1" "$2" ".counts.$3" 0
}

evidence_errors() { # <c> <t>
  _evidence_get "$1" "$2" '.errors' 0
}

evidence_warnings() { # <c> <t>
  _evidence_get "$1" "$2" '.warnings' 0
}

evidence_finished_at() { # <c> <t>
  _evidence_get "$1" "$2" '.finished_at' 0
}

evidence_summary() { # <c> <t>
  local f
  f=$(evidence_file "$1" "$2")
  [ -f "$f" ] || { echo ""; return 0; }
  jq -r '[(.status // ""), (.counts.failed // 0), (.counts.skipped // 0), (.errors // 0), (.warnings // 0), (.finished_at // 0)] | map(tostring) | join(" ")' "$f" 2>/dev/null || echo ""
}

evidence_tests_tsv() {
  local c t f found=0
  while read -r c t; do
    [ -n "$c" ] || continue
    case "$t" in test|e2e) ;; *) continue ;; esac
    f=$(evidence_file "$c" "$t")
    [ -f "$f" ] || continue
    jq -r '.tests[]? | [.file, .status, .name] | @tsv' "$f" 2>/dev/null
    found=1
  done < <(evidence_required)
  [ "$found" -eq 1 ]
}
