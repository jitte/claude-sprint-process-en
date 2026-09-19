#!/bin/bash
# Spec seal
#
# Record the hash of the "sealed region" of <docs.sprintRoot>/**/SPEC.md and TEST.md
# in .sprint/spec-hashes.json, and detect changes.
#
# Sealed region = whole file − UNSEAL blocks.
#   Only the inside of <!-- UNSEAL:BEGIN --> … <!-- UNSEAL:END --> can change.
#   A file without UNSEAL markers is a sealed region in full.
#
# qa cannot write the manifest and cannot write the sealed region (edit-scope-gate.sh controls this).
# When main finalizes the spec, update the manifest with `bash harness/bin/sprint seal` (= approve).
#
# Subcommands:
#   seal              rehash all target files and update the manifest
#   verify            compare the manifest with the current state (exit 1 on mismatch)
#   list              list the target files
#   hash-file <path>  print the seal hash of the given file
#   hash-stdin        print the seal hash of the stdin content
#   regions-unsealed <path>  print the content of the unsealed region
#   manifest-get <path>      print the value recorded in the manifest

set -euo pipefail
export PATH="${PATH:+$PATH:}/usr/local/bin:/usr/bin:/bin"   # prefer the caller's PATH; guarantee the basic commands even in the minimal hook environment

. "$(dirname "$(readlink -f "$0")")/../lib/env.sh"
sprint_config_require
ROOT=$(sprint_root)
MANIFEST="$ROOT/.sprint/spec-hashes.json"
SPRINT_ROOT_DIR=$(sprint_abs_path "$(sprint_config '.docs.sprintRoot')")

# Normalize the "sealed region" of a file and write it to stdout.
# Remove the content of UNSEAL blocks, but keep the marker lines (to fix their position).
_sealed_stream() {
  awk '
    /<!-- UNSEAL:BEGIN -->/ { print; skip=1; next }
    /<!-- UNSEAL:END -->/   { print; skip=0; next }
    skip==1 { next }
    { print }
  ' | sed 's/\r$//; s/[[:space:]]*$//'
}

# Write the content outside the seal (inside the UNSEAL blocks) to stdout.
_unsealed_stream() {
  awk '
    /<!-- UNSEAL:BEGIN -->/ { skip=1; next }
    /<!-- UNSEAL:END -->/   { skip=0; next }
    skip==1 { print }
  '
}

_hash_stream() {
  _sealed_stream | sha256sum | cut -d' ' -f1
}

_rel() {
  # absolute/relative path → relative to ROOT
  local p="$1"
  case "$p" in
    /*) realpath --relative-to="$ROOT" "$p" 2>/dev/null || echo "$p" ;;
    *)  realpath --relative-to="$ROOT" "$ROOT/$p" 2>/dev/null || echo "$p" ;;
  esac
}

_targets() {
  find "$SPRINT_ROOT_DIR" \( -name SPEC.md -o -name TEST.md \) 2>/dev/null | sort
}

cmd="${1:-}"
case "$cmd" in
  hash-file)
    [ -f "$2" ] || { echo "no such file: $2" >&2; exit 2; }
    _hash_stream < "$2"
    ;;

  hash-stdin)
    _hash_stream
    ;;

  regions-unsealed)
    [ -f "$2" ] || exit 0
    _unsealed_stream < "$2"
    ;;

  manifest-get)
    [ -f "$MANIFEST" ] || { echo ""; exit 0; }
    rel=$(_rel "$2")
    jq -r --arg k "$rel" '.[$k] // ""' "$MANIFEST"
    ;;

  list)
    _targets | while read -r f; do _rel "$f"; done
    ;;

  seal)
    mkdir -p "$ROOT/.sprint"
    tmp=$(mktemp)
    echo '{}' > "$tmp"
    _targets | while read -r f; do
      rel=$(_rel "$f")
      h=$(_hash_stream < "$f")
      jq --arg k "$rel" --arg v "$h" '.[$k]=$v' "$tmp" > "$tmp.next" && mv "$tmp.next" "$tmp"
    done
    jq -S '.' "$tmp" > "$MANIFEST"
    rm -f "$tmp"
    echo "sealed $(jq 'length' "$MANIFEST") files -> ${MANIFEST#"$ROOT"/}"
    ;;

  verify)
    if [ ! -f "$MANIFEST" ]; then
      echo "FAIL: manifest not found ($MANIFEST). Run bash harness/bin/sprint seal." >&2
      exit 1
    fi
    fail=0
    # Verify each entry of the manifest
    while read -r rel; do
      [ -z "$rel" ] && continue
      f="$ROOT/$rel"
      if [ ! -f "$f" ]; then
        echo "FAIL: a sealed file is missing: $rel" >&2
        fail=1
        continue
      fi
      want=$(jq -r --arg k "$rel" '.[$k]' "$MANIFEST")
      got=$(_hash_stream < "$f")
      if [ "$want" != "$got" ]; then
        echo "FAIL: the sealed region is changed: $rel" >&2
        fail=1
      fi
    done < <(jq -r 'keys[]' "$MANIFEST")
    # Warn about target files not registered in the manifest
    while read -r f; do
      rel=$(_rel "$f")
      if ! jq -e --arg k "$rel" 'has($k)' "$MANIFEST" >/dev/null; then
        echo "WARN: unsealed spec file: ${rel} (seal it with bash harness/bin/sprint seal)" >&2
        fail=1
      fi
    done < <(_targets)
    if [ "$fail" -ne 0 ]; then
      exit 1
    fi
    echo "spec-verify: OK ($(jq 'length' "$MANIFEST") files)"
    ;;

  *)
    echo "usage: spec-seal.sh {seal|verify|list|hash-file <p>|hash-stdin|regions-unsealed <p>|manifest-get <p>}" >&2
    exit 2
    ;;
esac
