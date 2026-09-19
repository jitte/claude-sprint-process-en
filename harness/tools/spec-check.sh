#!/bin/bash
# spec-check.sh — structure check of SPEC.md / TEST.md (self-check before the seal)
#
# A tool to find 🔴 findings of the type "a change does not reach all nodes" with a machine check on each update, and to fix them without help.
# The target is the active sprint (an argument can override sprint_dir).
#
# Usage: bash harness/bin/sprint spec-check [sprint_dir]

set -u
. "$(dirname "$(readlink -f "$0")")/../lib/env.sh"
ROOT=$(sprint_root)
DIR="${1:-}"
if [ -z "$DIR" ]; then
  DIR=$(jq -r '.sprints[.active].sprint_dir // ""' "$ROOT/.sprint/flags.json" 2>/dev/null)
fi
[ -z "$DIR" ] && { echo "cannot determine sprint_dir. Pass it as an argument." >&2; exit 2; }

SPEC="$ROOT/$DIR/SPEC.md"
TEST="$ROOT/$DIR/TEST.md"
for f in "$SPEC" "$TEST"; do
  [ -f "$f" ] || { echo "not found: $f" >&2; exit 2; }
done

T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
RC=0
note() { echo "  $*"; }
fail() { echo "  ✗ $*"; RC=1; }

# EARS definitions and the matrix
grep -oE '^\- \*\*(N|E)-[0-9]+\.[0-9]+[a-z]?[0-9]?\*\*' "$SPEC" \
  | sed -E 's/^- \*\*//; s/\*\*$//' | sort -u > "$T/ears"
awk '/^## Coverage matrix/,/^## Run commands/' "$TEST" \
  | grep -oE '^\| (N|E)-[0-9]+\.[0-9]+[a-z]?[0-9]? ' | tr -d '| ' | sort -u > "$T/mat"

echo "== 1. EARS ↔ coverage matrix =="
note "EARS $(wc -l < "$T/ears") / matrix $(wc -l < "$T/mat")"
D=$(comm -3 "$T/ears" "$T/mat"); [ -n "$D" ] && fail "difference:"$'\n'"$D"

echo "== 2. Assignment to implementation units =="
sed -n '/^## Implementation units and dependencies/,/^## EARS requirements/p' "$SPEC" > "$T/units"
python3 - "$T" <<'PY'
import re,sys,io
T=sys.argv[1]
units=io.open(T+'/units',encoding='utf-8').read()
ears=[l.strip() for l in io.open(T+'/ears',encoding='utf-8') if l.strip()]
def expand(spec):
    cov=set()
    for m in re.finditer(r'(N|E)-\d+\.\d+[a-z]?\d?', spec): cov.add(m.group(0))
    for m in re.finditer(r'(N-\d+\.\d+[a-z]?\d?) to (N-\d+\.\d+[a-z]?\d?)', spec):
        pa=re.match(r'N-(\d+)\.(\d+)',m.group(1)); pb=re.match(r'N-(\d+)\.(\d+)',m.group(2))
        lo=(int(pa.group(1)),int(pa.group(2))); hi=(int(pb.group(1)),int(pb.group(2)))
        for e in ears:
            pe=re.match(r'N-(\d+)\.(\d+)',e)
            if pe and lo<=(int(pe.group(1)),int(pe.group(2)))<=hi: cov.add(e)
    return cov
owner={}; dup=[]
for unit,spec in re.findall(r"^\| ([A-Z]-[0-9a-z']+) \|[^|]*\|[^|]*\| ([^|]*) \|", units, re.M):
    for e in expand(spec):
        if e in ears:
            if e in owner: dup.append((e,owner[e],unit))
            else: owner[e]=unit
miss=[e for e in ears if e not in owner]
print("  unassigned: %d %s" % (len(miss), miss if miss else ""))
print("  assigned twice: %d %s" % (len(dup), dup if dup else ""))
sys.exit(1 if (miss or dup) else 0)
PY
[ $? -ne 0 ] && RC=1

echo "== 3. Test ID definitions ↔ references =="
# Accept both the new Test ID format TEST-<sprint_id>-<major>.<minor> (docs/06_process/gate-tools.md §3.1.3) and
# the old format TEST-<major>.<minor>. PFX is the part without minor.
PFX=$(grep -oE '^\| TEST-[0-9]+(-[0-9]+)*\.' "$TEST" | sed -E 's/^\| //; s/\.$//' \
      | sort | uniq -c | sort -rn | head -1 | awk '{print $2}')
# The TEST.md of kind=docs has no Test IDs (only static verification items S-x). Skip checks 3 and 4 and go to 5
if [ -z "$PFX" ]; then
  note "no Test ID definition rows (kind=docs). Checks 3 and 4 skipped"
else
awk '/^## Test specification/,/^## Existing tests to modify/' "$TEST" \
  | grep -oE "^\| ${PFX}\.[0-9]+" | tr -d '| ' | sort -u > "$T/t1"
awk '/^## Coverage matrix/,/^## Run commands/' "$TEST" \
  | grep -oE "${PFX}\.[0-9]+" | sort -u > "$T/t2"
note "definitions $(wc -l < "$T/t1") / references $(wc -l < "$T/t2")"
D=$(comm -3 "$T/t1" "$T/t2"); [ -n "$D" ] && fail "difference:"$'\n'"$D"
MAX=$(sed -E "s/.*${PFX}\.([0-9]+).*/\1/" "$T/t1" | sort -n | tail -1)
for i in $(seq 1 "${MAX:-0}"); do
  grep -q "${PFX}\.$i " "$TEST" || fail "missing number ${PFX}.$i"
done

echo "== 4. Rows separated from the table (a markdown table split by a blank line) =="
awk -v p="$PFX" '$0 ~ "^\\| *"p"\\." { if (prev ~ /^[[:space:]]*$/) print "  ✗ separated: line " NR } { prev=$0 }' "$TEST" \
  | tee "$T/sep"; [ -s "$T/sep" ] && RC=1
fi

echo "== 5. Referenced test files exist =="
for f in $(grep -oE '`(backend|frontend)/[A-Za-z0-9/_.-]+\.(ts|tsx)`' "$TEST" | tr -d '`' | sort -u); do
  [ -e "$ROOT/$f" ] || note "not found (for a new file, check that it matches the declaration in TEST.md): $f"
done

echo
[ $RC -eq 0 ] && echo "spec-check: OK" || echo "spec-check: needs fixes"
exit $RC
