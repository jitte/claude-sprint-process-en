#!/bin/bash
# scope-lib.sh — the write scope matrix (the source of truth). edit-scope-gate.sh (Write / Edit) sources it.
# To change the matrix, change only this file. Read the layout (location of sprint documents, tests, src of components) from
# sprint.config.json. The source of truth in the documents is PROC-1 of sprint-process.md.
#
#   scope_classify <path>          → state | spec | testmd | test | <component> | other
#   scope_decision  <actor> <type>  → deny | allow | unseal
#
# path can be absolute or relative to the working tree. For an absolute path, remove the prefix of the project root (`sprint_root`. the caller
# reads lib/env.sh first), then judge. If it is still absolute after that (outside the working tree. /tmp or other), it is other.
# Do not treat a partial match of "/tmp/" as outside the working tree. That would misjudge `<src>/tmp/x` in the working tree as other,
# and a hook pointed at a fixture (under /tmp) would judge every path as other.
# actor is agent_type (missing or unknown = main).
# unseal means "only the <!-- UNSEAL --> blocks of TEST.md are allowed". edit-scope-gate.sh judges the region from the arguments.
#
# Order of judgment (D-5): state → spec / testmd → other (docs/**) → test (matches any tests)
#   → <component> (matches any src. returns the component name) → other

# Get the decision table from the config with 1 jq call (a hook makes 1 check per call, so the number of jq calls is the delay).
# The caller runs SCOPE_TABLE=$(_scope_table) only once and keeps it.
#   Line shape: <type>\t<glob>   type = spec | testmd | test | <component>
#           role\t<component>\t<role>
# Put the table in <root>/.sprint/scope-table.cache. Read it when it is newer than the config (saves 1 jq launch.
# The hook runs on every edit). When .sprint/ does not exist, do not cache.
_scope_table() {
  if [ -n "${SCOPE_TABLE:-}" ]; then printf '%s\n' "$SCOPE_TABLE"; return 0; fi
  local cfg cache
  cfg=$(sprint_config_path)
  cache="$(sprint_root)/.sprint/scope-table.cache"
  if [ -f "$cache" ] && [ "$cache" -nt "$cfg" ]; then printf '%s\n' "$(<"$cache")"; return 0; fi
  _scope_table_build "$cfg" | { if [ -d "${cache%/*}" ]; then tee "$cache"; else cat; fi; }
}

_scope_table_build() { # <config>
  jq -r '
    (.docs.sprintRoot) as $sr
    | ["spec\t\($sr)/**/SPEC.md", "testmd\t\($sr)/**/TEST.md"]
    + [ .components[] | (.tests // [])[] | "test\t\(.)" ]
    + [ .components | to_entries[] | .key as $c | (.value.src // [])[] | "\($c)\t\(.)" ]
    + [ .components | to_entries[] | "role\t\(.key)\t\(.value.role // "")" ]
    | .[]' "$1"
}

scope_classify() {
  local p="$1" root line kind glob
  root=$(sprint_root)
  case "$p" in "$root"/*) p="${p#"$root"/}" ;; esac
  case "$p" in
    /*) echo other; return ;;
    .sprint/flags.json|.sprint/spec-hashes.json) echo state; return ;;
  esac
  local table
  table=$(_scope_table)
  # 1. spec / testmd
  while IFS=$'\t' read -r kind glob; do
    case "$kind" in spec|testmd) sprint_glob_match "$glob" "$p" && { echo "$kind"; return; } ;; esac
  done <<<"$table"
  # 2. Other files under docs are other, even with a test extension
  case "$p" in docs/*) echo other; return ;; esac
  # 3. test (matches the tests of any component)
  while IFS=$'\t' read -r kind glob; do
    [ "$kind" = "test" ] && sprint_glob_match "$glob" "$p" && { echo test; return; }
  done <<<"$table"
  # 4. <component> (matches any src)
  while IFS=$'\t' read -r kind glob; do
    case "$kind" in spec|testmd|test|role) continue ;; esac
    sprint_glob_match "$glob" "$p" && { echo "$kind"; return; }
  done <<<"$table"
  echo other
}

_scope_role() { # <component>
  local kind comp role
  while IFS=$'\t' read -r kind comp role; do
    [ "$kind" = "role" ] && [ "$comp" = "$1" ] && { echo "$role"; return 0; }
  done < <(_scope_table)
  echo ""
}

scope_decision() {
  local actor="$1" type="$2" role
  case "$type" in
    state)    echo deny ;;
    other)    echo allow ;;
    spec)     case "$actor" in main|"") echo allow ;; *) echo deny ;; esac ;;
    testmd)   case "$actor" in main|"") echo allow ;; qa) echo unseal ;; *) echo deny ;; esac ;;
    test)     case "$actor" in tester) echo allow ;; *) echo deny ;; esac ;;
    *)
      # src of a component: allow only the caller whose role matches
      role=$(_scope_role "$type")
      if [ -n "$role" ] && [ "$actor" = "$role" ]; then echo allow; else echo deny; fi ;;
  esac
}

# Owner per type (the deny text shows whom to delegate to)
scope_owner() {
  local role
  case "$1" in
    test)        echo "tester agent" ;;
    spec|testmd) echo "main" ;;
    state|other) echo "" ;;
    *)
      role=$(_scope_role "$1")
      [ -n "$role" ] && echo "$role agent" || echo "" ;;
  esac
}
