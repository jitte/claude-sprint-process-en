#!/bin/bash
# harness/lib/config.sh — reading sprint.config.json (the source of truth).
#
# The harness core (lib / tools / gate-tools / hooks / bin) reads components, layout, tasks,
# evidence, sets, and gates only through this file. Do not write technology names or layout into the harness core.
# sprint_root (env.sh) must be defined first. env.sh reads this file, so
# the caller reads only env.sh.
#
# Environment variables:
#   SPRINT_CONFIG   path of the config file (default <sprint_root>/sprint.config.json)
#
# Functions:
#   sprint_config_path                 path of the config file
#   sprint_config_check                check that the config exists and its schemaVersion. On failure, print the reason in 1 line and return 4
#   sprint_config_require              on sprint_config_check failure, print the reason and exit 4 (for bin / gate-tools)
#   sprint_config_exists               0 when the config exists (for the pass-through check of hooks)
#   sprint_config <jq filter>          print the result of jq -r
#   sprint_config_json <jq filter>     print the result of jq -c
#   sprint_abs_path <path>             absolute: as is; relative: prefix <sprint_root>/
#   sprint_glob_regex <glob>           convert a glob to a regex (** → any depth, * / ? do not cross a directory level)
#   sprint_glob_match <glob> <path>    0 on match / 1 on no match
#   sprint_glob_files [-r <root>] <glob>...   list the files that match the globs, relative to <root>
#                                      (excludes the trees under directory names written in <root>/.gitignore (for example `name/`))
#   sprint_ignored_dirs [root]         directory names excluded from the scan (`name/` lines of .gitignore)
#   sprint_components                  print the component names in the config order
#   sprint_tasks                       print the verbs in the order of tasks
#   sprint_required_tasks              print "<component> <task>" in the order of tasks × the order of components
#   sprint_component_globs <src|tests> [component]   print the globs, 1 per line (all when component is omitted)

sprint_config_path() {
  printf '%s\n' "${SPRINT_CONFIG:-$(sprint_root)/sprint.config.json}"
}

sprint_config_check() {
  local p v
  p=$(sprint_config_path)
  [ -f "$p" ] || { echo "sprint.config.json not found: $p"; return 4; }
  v=$(jq -r '.schemaVersion // "null"' "$p" 2>/dev/null) || v="null"
  [ "$v" = "1" ] || { echo "sprint.config.json schemaVersion $v is not supported (supported: 1)"; return 4; }
  return 0
}

sprint_config_require() {
  local out
  out=$(sprint_config_check) || { echo "$out"; exit 4; }
}

# Pass-through check of hooks. To add no jq calls to a hook that makes 1 check per call, look only at the file's
# existence and the schemaVersion line (sprint_config_check checks the value).
sprint_config_exists() {
  local p body
  p=$(sprint_config_path)
  [ -f "$p" ] || return 1
  body=$(<"$p")
  [[ "$body" =~ \"schemaVersion\"[[:space:]]*:[[:space:]]*1[[:space:]]*(,|$|\}) ]]
}

sprint_config() { # <jq filter>
  jq -r "$1" "$(sprint_config_path)"
}

sprint_config_json() { # <jq filter>
  jq -c "$1" "$(sprint_config_path)"
}

sprint_abs_path() { # <path>
  case "$1" in
    /*) printf '%s\n' "$1" ;;
    *)  printf '%s\n' "$(sprint_root)/$1" ;;
  esac
}

# glob → regex. The rules are the same as glob_match in config.py.
#   **/  → (.*/)?   (0 or more directories)
#   **   → .*
#   *    → [^/]*
#   ?    → [^/]
#   .    → \.       (escape the other symbols too)
# Also put the result in the variable SPRINT_GLOB_RE (so the hook check does not create a subshell each time).
sprint_glob_regex() { # <glob>
  local g="$1" out="" i c
  local n=${#g}
  i=0
  while [ "$i" -lt "$n" ]; do
    c="${g:$i:1}"
    if [ "$c" = "*" ] && [ "${g:$((i+1)):1}" = "*" ]; then
      if [ "${g:$((i+2)):1}" = "/" ]; then
        out+='(.*/)?'; i=$((i+3))
      else
        out+='.*'; i=$((i+2))
      fi
      continue
    fi
    case "$c" in
      '*') out+='[^/]*' ;;
      '?') out+='[^/]' ;;
      '.'|'+'|'('|')'|'['|']'|'{'|'}'|'^'|'$'|'|'|'\') out+="\\$c" ;;
      *) out+="$c" ;;
    esac
    i=$((i+1))
  done
  SPRINT_GLOB_RE="^$out\$"
  printf '%s\n' "$SPRINT_GLOB_RE"
}

sprint_glob_match() { # <glob> <path>
  sprint_glob_regex "$1" >/dev/null
  [[ "$2" =~ $SPRINT_GLOB_RE ]]
}

# Fixed prefix of the glob (up to the segment before the first one with a wildcard). Used as the start point of the scan.
_sprint_glob_prefix() { # <glob>
  local g="$1" seg out="" IFS='/'
  local -a parts
  read -r -a parts <<<"$g"
  for seg in "${parts[@]}"; do
    case "$seg" in *'*'*|*'?'*|*'['*) break ;; esac
    out+="${seg}/"
  done
  printf '%s\n' "${out%/}"
}

# Do not scan directories excluded from version control (where dependencies and generated files go). Take the names from the
# `name/` lines of <root>/.gitignore (no wildcards and no / in the middle). The tool holds no names.
sprint_ignored_dirs() { # [root]
  local root="${1:-$(sprint_root)}" line
  [ -f "$root/.gitignore" ] || return 0
  while IFS= read -r line; do
    line="${line%%#*}"; line="${line%"${line##*[![:space:]]}"}"
    case "$line" in ''|'!'*|*'*'*|*'?'*|*'['*|/*) continue ;; esac
    case "$line" in */) line="${line%/}" ;; *) continue ;; esac
    case "$line" in */*) continue ;; esac
    printf '%s\n' "$line"
  done < "$root/.gitignore"
}

sprint_glob_files() { # [-r <root>] <glob>...
  local root
  root=$(sprint_root)
  if [ "${1:-}" = "-r" ]; then root="$2"; shift 2; fi
  local g prefix re base d
  local -a prune=()
  while IFS= read -r d; do [ -n "$d" ] && prune+=(-name "$d" -prune -o); done < <(sprint_ignored_dirs "$root")
  for g in "$@"; do
    prefix=$(_sprint_glob_prefix "$g")
    base="$root${prefix:+/$prefix}"
    [ -d "$base" ] || continue
    re=$(sprint_glob_regex "$g")
    find "$base" \( "${prune[@]}" -type f -print \) 2>/dev/null \
      | sed "s|^$root/||" | grep -E "$re" || true
  done | sort -u
}

sprint_components() {
  sprint_config '.components | keys_unsorted[]'
}

sprint_tasks() {
  sprint_config '.tasks[]'
}

sprint_required_tasks() {
  jq -r '.tasks[] as $t | .components | to_entries[] | select(.value.adapters[$t] != null) | "\(.key) \($t)"' \
    "$(sprint_config_path)"
}

sprint_component_globs() { # <src|tests> [component]
  local kind="$1" c="${2:-}"
  if [ -n "$c" ]; then
    jq -r --arg c "$c" --arg k "$kind" '.components[$c][$k] // [] | .[]' "$(sprint_config_path)"
  else
    jq -r --arg k "$kind" '.components[] | .[$k] // [] | .[]' "$(sprint_config_path)"
  fi
}
