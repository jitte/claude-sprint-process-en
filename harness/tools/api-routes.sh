#!/bin/bash
# api-routes.sh — compare, in both directions, the set of public routes in the implementation and the set of routes that the spec writes.
#
# The location of the spec is docs.specDir in the config. The command that prints the implementation set is sets.routes.implCmd in the config.
#
# **This script holds no route names.** Express the exclusion and expansion rules only with the
# ```api-routes fence declarations in the spec (expand / alias) and with normalization rules that
# do not depend on route names.
#
# Subcommands:
#   impl    Print the normalized implementation routes, 1 per line
#   spec    Print the normalized and expanded spec routes, 1 per line
#   verify  Print the difference in both directions. 0=match / 1=in the implementation but not in the spec / 2=in the spec but not in the implementation
#
# Environment variables:
#   API_ROUTES_ROOT      Start point of the spec scan (default: the repository root).
#                        Read <docs.specDir>/**/*.md under it (README.md excluded)
#   API_ROUTES_IMPL_CMD  Command that prints the implementation routes as JSON (default: sets.routes.implCmd in the config. Run with bash -c in the project root)
#
# Write failure messages to **stdout** (so that they stay in the gate output).
set -uo pipefail

. "$(dirname "$(readlink -f "$0")")/../lib/env.sh"
sprint_config_require
REPO_ROOT=$(sprint_root)
ROOT="${API_ROUTES_ROOT:-$REPO_ROOT}"
SPEC_REL=$(sprint_config '.docs.specDir')
case "$SPEC_REL" in /*) SPEC_DIR="$SPEC_REL" ;; *) SPEC_DIR="$ROOT/$SPEC_REL" ;; esac
IMPL_CMD="${API_ROUTES_IMPL_CMD:-$(sprint_config '.sets.routes.implCmd // empty')}"
[ -n "$IMPL_CMD" ] || { echo "api-routes: no command to get the implementation routes (API_ROUTES_IMPL_CMD or sets.routes.implCmd in the config)"; exit 4; }

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

die() { echo "$*"; exit 1; }

usage() {
  echo "usage: api-routes.sh <impl|spec|verify>"
  exit 1
}

# --------------------------------------------------------------------------
# Scan of the spec
# --------------------------------------------------------------------------

# Scan the Markdown under 05. Extract the declaration lines and the route occurrences.
#   D <TAB> file <TAB> lineno <TAB> declaration line        (inside a ```api-routes fence)
#   R <TAB> file <TAB> lineno <TAB> METHOD <TAB> path
# Do not extract routes inside a ```mermaid fence (N-3.4) or inside
# a ```api-routes fence (N-5.7).
# Check the preconditions of the scan. **Do this outside the function whose output the caller redirects.**
# If scan_spec_files calls die, the message goes into the file together with the scan result
# and is lost (the same kind of swallowed error as E-1.1).
check_spec_dir() {
  [ -d "$SPEC_DIR" ] || die "api-routes: spec directory not found: $SPEC_DIR"
  [ -n "$(find "$SPEC_DIR" -type f -name '*.md' ! -name 'README.md' | head -n 1)" ] \
    || die "api-routes: no spec Markdown found: $SPEC_DIR"
}

scan_spec_files() {
  local files
  files=$(find "$SPEC_DIR" -type f -name '*.md' ! -name 'README.md' | LC_ALL=C sort)

  # shellcheck disable=SC2086
  echo "$files" | while IFS= read -r f; do
    awk '
      function trim(s) { sub(/^[ \t]+/, "", s); sub(/[ \t]+$/, "", s); return s }
      {
        t = trim($0)
        if (t ~ /^```/) {
          if (infence) { infence = 0; info = "" }
          else {
            infence = 1
            info = t
            sub(/^`+/, "", info)
            info = trim(info)
            n = split(info, w, /[ \t]/)
            info = (n > 0 ? w[1] : "")
          }
          next
        }
        if (infence && info == "mermaid") next
        if (infence && info == "api-routes") {
          d = trim($0)
          if (d != "") printf "D\t%s\t%d\t%s\n", FILENAME, FNR, d
          next
        }

        # N-2.1 / N-2.1a: <METHOD> <path>. path starts with / + a letter, and
        # ends at the longest match of the character set A-Z a-z 0-9 / : { } _ . - *.
        s = $0
        while (match(s, /(GET|POST|PUT|PATCH|DELETE)[ \t]+\/[A-Za-z][A-Za-z0-9\/:{}_.*-]*/)) {
          # Do not take a method name that is inside a word (for example TARGET)
          if (RSTART > 1) {
            pc = substr(s, RSTART - 1, 1)
            if (pc ~ /[A-Za-z0-9]/) { s = substr(s, RSTART + 1); continue }
          }
          tok = substr(s, RSTART, RLENGTH)
          s = substr(s, RSTART + RLENGTH)
          split(tok, m, /[ \t]+/)
          printf "R\t%s\t%d\t%s\t%s\n", FILENAME, FNR, m[1], m[2]
        }
      }
    ' "$f"
  done
}

# --------------------------------------------------------------------------
# Normalization (N-3.1 / N-3.2 / N-2.4)
# --------------------------------------------------------------------------

# Normalize 1 path per line on stdin/stdout.
#   - Drop a trailing . or , (punctuation in prose)
#   - Remove the /api/v1 prefix
#   - Replace a path parameter /:xxx with /:p
normalize_path() {
  awk '{
    p = $0
    sub(/[.,]+$/, "", p)
    sub(/^\/api\/v1/, "", p)
    if (p == "") p = "/"
    gsub(/\/:[A-Za-z0-9_]+/, "/:p", p)
    print p
  }'
}

norm_one() { printf '%s\n' "$1" | normalize_path; }

# --------------------------------------------------------------------------
# Reading of declarations (§3)
# --------------------------------------------------------------------------

read_declarations() {
  check_spec_dir
  scan_spec_files > "$WORK/raw"

  : > "$WORK/expand"
  : > "$WORK/alias"

  # N-5.5 / E-1.2: check the vocabulary and the grammar.
  # **Check the grammar, not only the words.** If a declaration with correct words and a broken form (a missing `=` or `->`)
  # is silently dropped, the unexpanded placeholder
  # appears as "in the spec but not in the implementation" and misleads to failure class 2 (impl).
  # The cause is a mistake in the declaration, so a return to BUILD is wrong.
  local bad
  bad=$(awk -F'\t' -v root="$ROOT/" '
    function rel(p,   n) { n = length(root); return (substr(p, 1, n) == root) ? substr(p, n + 1) : p }
    function bad(f, l, msg) { printf "%s:%s: %s\n", rel(f), l, msg }
    $1 == "D" {
      split($4, w, /[ \t]+/)
      if (w[1] != "expand" && w[1] != "alias") {
        bad($2, $3, sprintf("unknown declaration word '\''%s'\'' (the only valid words are expand / alias)", w[1]))
        next
      }
      if (w[1] == "expand") {
        line = $4; sub(/^expand[ \t]+/, "", line)
        eq = index(line, "=")
        if (eq == 0) { bad($2, $3, "expand declaration has no '\''='\'' (expand <placeholder> = <value>, <value>)"); next }
        ph = substr(line, 1, eq - 1); vals = substr(line, eq + 1)
        gsub(/^[ \t]+|[ \t]+$/, "", ph); gsub(/^[ \t]+|[ \t]+$/, "", vals)
        if (ph == "")   bad($2, $3, "expand declaration has an empty placeholder")
        if (vals == "") bad($2, $3, "expand declaration has an empty value")
        next
      }
      line = $4; sub(/^alias[ \t]+/, "", line)
      arrow = index(line, "->")
      if (arrow == 0) { bad($2, $3, "alias declaration has no '\''->'\'' (alias <METHOD> <implementation path> -> <spec path>)"); next }
      left = substr(line, 1, arrow - 1); right = substr(line, arrow + 2)
      gsub(/^[ \t]+|[ \t]+$/, "", left); gsub(/^[ \t]+|[ \t]+$/, "", right)
      n = split(left, l, /[ \t]+/)
      if (n != 2)                bad($2, $3, "alias declaration left side is not in the form <METHOD> <path>: '\''" left "'\''")
      else if (l[2] !~ /^\//)    bad($2, $3, "alias declaration implementation path does not start with '\''/'\'': '\''" l[2] "'\''")
      if (right !~ /^\//)        bad($2, $3, "alias declaration spec path does not start with '\''/'\'': '\''" right "'\''")
    }
  ' "$WORK/raw")
  if [ -n "$bad" ]; then
    echo 'api-routes: cannot read the declarations in an api-routes fence'
    echo "$bad"
    exit 1
  fi

  # expand <placeholder> = v1, v2, ...  →  "<placeholder>\t<v1,v2,...>"
  awk -F'\t' '
    $1 == "D" && $4 ~ /^expand[ \t]/ {
      line = $4
      sub(/^expand[ \t]+/, "", line)
      eq = index(line, "=")
      if (eq == 0) next
      ph = substr(line, 1, eq - 1)
      vals = substr(line, eq + 1)
      sub(/^[ \t]+/, "", ph);   sub(/[ \t]+$/, "", ph)
      sub(/^[ \t]+/, "", vals); sub(/[ \t]+$/, "", vals)
      printf "%s\t%s\n", ph, vals
    }
  ' "$WORK/raw" > "$WORK/expand"

  # alias <METHOD> <implementation path> -> <spec path>  →  "<METHOD> <impl>\t<METHOD> <spec>" (normalized)
  awk -F'\t' '
    $1 == "D" && $4 ~ /^alias[ \t]/ {
      line = $4
      sub(/^alias[ \t]+/, "", line)
      arrow = index(line, "->")
      if (arrow == 0) next
      left  = substr(line, 1, arrow - 1)
      right = substr(line, arrow + 2)
      sub(/[ \t]+$/, "", left)
      sub(/^[ \t]+/, "", right); sub(/[ \t]+$/, "", right)
      split(left, l, /[ \t]+/)
      printf "%s\t%s\t%s\n", l[1], l[2], right
    }
  ' "$WORK/raw" > "$WORK/alias_raw"

  : > "$WORK/alias"
  while IFS=$'\t' read -r a_method a_impl a_spec; do
    [ -n "${a_method:-}" ] || continue
    printf '%s %s\t%s %s\n' "$a_method" "$(norm_one "$a_impl")" \
                            "$a_method" "$(norm_one "$a_spec")" >> "$WORK/alias"
  done < "$WORK/alias_raw"
}

# --------------------------------------------------------------------------
# Build of the spec routes (N-2.x / N-3.x / N-5.2)
# --------------------------------------------------------------------------

# Write the result to $WORK/spec_routes ("<METHOD> <path>\t<file>:<line>". On a duplicate, the first one wins).
# **Use the stdout of the function only for error messages.** If the caller redirects it,
# the reason for a failure is swallowed, so always put the result in a file.
build_spec_routes() {
  # N-3.3: exclude a path that contains * (generic notation)
  awk -F'\t' -v root="$ROOT/" '
    # Do not use ROOT as a regular expression. If the path contains metacharacters, the relative path calculation breaks
    function rel(p,   n) { n = length(root); return (substr(p, 1, n) == root) ? substr(p, n + 1) : p }
    $1 == "R" {
      p = $5
      sub(/[.,]+$/, "", p)
      if (index(p, "*") > 0) next
      sub(/^\/api\/v1/, "", p)
      if (p == "") p = "/"
      gsub(/\/:[A-Za-z0-9_]+/, "/:p", p)
      printf "%s %s\t%s:%s\n", $4, p, rel($2), $3
    }
  ' "$WORK/raw" > "$WORK/spec_pre"

  # N-5.2 / N-5.4 / E-1.3: apply the expand declarations and check for unmatched ones
  cp "$WORK/spec_pre" "$WORK/spec_exp"
  while IFS=$'\t' read -r ph vals; do
    [ -n "${ph:-}" ] || continue
    if ! grep -qF -- "$ph" "$WORK/spec_exp"; then
      echo "api-routes: expand declaration matches nothing: no spec route contains '$ph'"
      exit 1
    fi
    awk -v ph="$ph" -v vals="$vals" '
      function replace_all(s, from, to,   out, p) {
        out = ""
        while ((p = index(s, from)) > 0) {
          out = out substr(s, 1, p - 1) to
          s = substr(s, p + length(from))
        }
        return out s
      }
      {
        if (index($0, ph) == 0) { print; next }
        n = split(vals, V, ",")
        for (i = 1; i <= n; i++) {
          v = V[i]
          sub(/^[ \t]+/, "", v); sub(/[ \t]+$/, "", v)
          if (v == "") continue
          print replace_all($0, ph, v)
        }
      }
    ' "$WORK/spec_exp" > "$WORK/spec_exp.new" || exit 1
    mv "$WORK/spec_exp.new" "$WORK/spec_exp"
  done < "$WORK/expand"

  LC_ALL=C sort -t$'\t' -k1,1 -k2,2 "$WORK/spec_exp" | awk -F'\t' '!seen[$1]++' > "$WORK/spec_routes"
}

# --------------------------------------------------------------------------
# Build of the implementation routes (N-1.x / N-5.3 / E-1.1 / E-1.4)
# --------------------------------------------------------------------------

# Write the result to $WORK/impl_routes. For the same reason as build_spec_routes, use stdout
# only for error messages (so that "print the cause" of E-1.1 is not lost by a redirect
# in the caller).
build_impl_routes() {
  local out="$WORK/impl_stdout" err="$WORK/impl_stderr"
  if ! (cd "$REPO_ROOT" && bash -c "$IMPL_CMD") > "$out" 2> "$err"; then
    echo "api-routes: failed to get the implementation routes (API_ROUTES_IMPL_CMD)"
    echo "  cmd: $IMPL_CMD"
    cat "$err"
    exit 1
  fi

  if ! jq -e 'type == "array"' "$out" > /dev/null 2>&1; then
    echo "api-routes: the output of the implementation routes is not a JSON array"
    echo "  cmd: $IMPL_CMD"
    head -c 2000 "$out"
    exit 1
  fi

  jq -r '.[] | "\(.method) \(.path)"' "$out" | awk '{
    p = $2
    sub(/^\/api\/v1/, "", p)
    if (p == "") p = "/"
    gsub(/\/:[A-Za-z0-9_]+/, "/:p", p)
    print $1 " " p
  }' | LC_ALL=C sort -u > "$WORK/impl_pre"

  # E-1.4: fail if the implementation path of an alias does not exist (the compatibility route was removed but the declaration remains)
  cp "$WORK/impl_pre" "$WORK/impl_mapped"
  while IFS=$'\t' read -r from to; do
    [ -n "${from:-}" ] || continue
    if ! grep -qxF -- "$from" "$WORK/impl_pre"; then
      echo "api-routes: alias declaration matches nothing: '$from' is not in the implementation routes"
      exit 1
    fi
    awk -v from="$from" -v to="$to" '$0 == from { print to; next } { print }' \
      "$WORK/impl_mapped" > "$WORK/impl_mapped.new" || exit 1
    mv "$WORK/impl_mapped.new" "$WORK/impl_mapped"
  done < "$WORK/alias"

  LC_ALL=C sort -u "$WORK/impl_mapped" > "$WORK/impl_routes"
}

# --------------------------------------------------------------------------
# Subcommands
# --------------------------------------------------------------------------

cmd_spec() {
  read_declarations
  build_spec_routes
  cut -d$'\t' -f1 "$WORK/spec_routes"
}

cmd_impl() {
  read_declarations
  build_impl_routes
  cat "$WORK/impl_routes"
}

cmd_verify() {
  read_declarations

  # Get the implementation first. If getting it fails, do not treat it as an empty set. Stop there (E-1.1).
  build_impl_routes
  build_spec_routes

  cut -d$'\t' -f1 "$WORK/spec_routes" | LC_ALL=C sort -u > "$WORK/spec_set"
  LC_ALL=C sort -u "$WORK/impl_routes" > "$WORK/impl_set"

  LC_ALL=C comm -23 "$WORK/spec_set" "$WORK/impl_set" > "$WORK/spec_only"
  LC_ALL=C comm -13 "$WORK/spec_set" "$WORK/impl_set" > "$WORK/impl_only"

  local n_spec_only n_impl_only
  n_spec_only=$(wc -l < "$WORK/spec_only" | tr -d ' ')
  n_impl_only=$(wc -l < "$WORK/impl_only" | tr -d ' ')

  echo "=== In the spec but not in the implementation (${n_spec_only}) ==="
  if [ "$n_spec_only" -gt 0 ]; then
    # N-4.4: add the source file name and line number
    while IFS= read -r route; do
      local where
      where=$(awk -F'\t' -v r="$route" '$1 == r { print $2; exit }' "$WORK/spec_routes")
      echo "  $route  ($where)"
    done < "$WORK/spec_only"
  fi

  echo "=== In the implementation but not in the spec (${n_impl_only}) ==="
  if [ "$n_impl_only" -gt 0 ]; then
    sed 's/^/  /' "$WORK/impl_only"
  fi

  echo "--- spec $(wc -l < "$WORK/spec_set" | tr -d ' ') / impl $(wc -l < "$WORK/impl_set" | tr -d ' ') ---"

  # N-8.3: in the implementation but not in the spec -> failure class 1 (spec). It is upstream, so it takes priority
  if [ "$n_impl_only" -gt 0 ]; then exit 1; fi
  # N-8.4: in the spec but not in the implementation -> failure class 2 (impl)
  if [ "$n_spec_only" -gt 0 ]; then exit 2; fi
  exit 0
}

case "${1:-}" in
  impl)   cmd_impl ;;
  spec)   cmd_spec ;;
  verify) cmd_verify ;;
  *)      usage ;;
esac
