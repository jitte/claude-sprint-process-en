# clause-anchors.py — the core. Start it through harness/tools/clause-anchors.sh (argv[1] = scan root; with --check it does not write).
# Read the layout (living documents, templates) from sprint.config.json.
import os
import re
import sys

sys.dont_write_bytecode = True  # do not create __pycache__ in lib/
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "lib"))
import config  # noqa: E402

ROOT = sys.argv[1]
CHECK = "--check" in sys.argv[2:]
CFG = config.load(ROOT)

# Living documents. Defined by docs.livingDirs in sprint.config.json (shared with spec-graph.py and xref.sh).
#   Targets for anchor placement = an md under these directories that declares xref-prefix in its frontmatter (the same definition as a
#   clause file in spec-graph).
#   Targets for the conversion of references [[ID]] = the md files under these directories + the md files directly under the repository root.
LIVING_DIRS = tuple(CFG["docs"]["livingDirs"])
# Out of scope for the machine conversion. A relative path in a template is written for the depth of the copy destination, so
# a path calculated from the location of the referrer breaks. Write the references in templates by hand. The location is docs.templates in the config.
TEMPLATE_PREFIX = CFG["docs"]["templates"].rstrip("/") + "/"

FENCE_RE = re.compile(r"^\s*(```|~~~)")
DECL_HEAD_RE = re.compile(r"^(#{1,6})\s+.*?\[([A-Z]{2,6}-[0-9]+)\](?!\()")
REF_RE = re.compile(r"\[\[([A-Z]{2,6}-[0-9]+)\]\]")
CODE_SPAN_RE = re.compile(r"(`[^`]*`)")
FM_KEY_RE = re.compile(r"^([A-Za-z0-9_-]+):\s*(.*)$")


def anchor_of(cid):
    return '<a id="%s"></a>' % cid


def read(rel):
    with open(os.path.join(ROOT, rel), encoding="utf-8") as f:
        return f.read().split("\n")


def declared_prefix(rel):
    """xref-prefix in the frontmatter. "" if it is absent."""
    lines = read(rel)
    if not lines or lines[0].strip() != "---":
        return ""
    for ln in lines[1:]:
        if ln.strip() == "---":
            break
        m = FM_KEY_RE.match(ln)
        if m and m.group(1) == "xref-prefix":
            return m.group(2).strip().strip("\"'")
    return ""


def living_files():
    out = []
    for d in LIVING_DIRS:
        base = os.path.join(ROOT, d)
        if not os.path.isdir(base):
            continue
        for dirpath, dirnames, filenames in os.walk(base):
            dirnames.sort()
            for fn in sorted(filenames):
                if fn.endswith(".md"):
                    out.append(os.path.relpath(os.path.join(dirpath, fn), ROOT))
    return sorted(set(out))


def ref_files():
    """Targets for reference conversion. Do not convert templates."""
    out = [rel for rel in living_files() if not rel.startswith(TEMPLATE_PREFIX)]
    if os.path.isdir(ROOT):
        for fn in sorted(os.listdir(ROOT)):
            if fn.endswith(".md") and os.path.isfile(os.path.join(ROOT, fn)):
                out.append(fn)
    return sorted(set(out))


def build_index():
    """Clause ID -> declaring file. Do not count pseudo-headings inside fences."""
    index, dups = {}, []
    anchor_files = set()
    for rel in living_files():
        if not declared_prefix(rel):
            continue
        anchor_files.add(rel)
        infence = False
        for ln in read(rel):
            if FENCE_RE.match(ln):
                infence = not infence
                continue
            if infence:
                continue
            m = DECL_HEAD_RE.match(ln)
            if m:
                if m.group(2) in index:
                    dups.append((m.group(2), index[m.group(2)], rel))
                else:
                    index[m.group(2)] = rel
    return index, dups, anchor_files


def link_for(cid, src_rel, index):
    """The link string for 1 reference. Do not write a relative path for the same file."""
    dst = index[cid]
    if dst == src_rel:
        return "[%s](#%s)" % (cid, cid)
    path = os.path.relpath(dst, os.path.dirname(src_rel) or ".")
    return "[%s](%s#%s)" % (cid, path, cid)


def convert(rel, index, add_anchors, missing):
    """Return the lines of 1 converted file. Do not touch the inside of fences or inline code."""
    out = []
    infence = False
    for ln in read(rel):
        if FENCE_RE.match(ln):
            infence = not infence
            out.append(ln)
            continue
        if infence:
            out.append(ln)
            continue

        if add_anchors:
            m = DECL_HEAD_RE.match(ln)
            if m and (not out or out[-1].strip() != anchor_of(m.group(2))):
                out.append(anchor_of(m.group(2)))

        # Do not convert inside inline code. The odd-numbered parts are code spans.
        parts = CODE_SPAN_RE.split(ln)
        for i in range(0, len(parts), 2):
            def repl(m):
                cid = m.group(1)
                if cid not in index:
                    missing.append((rel, cid))
                    return m.group(0)
                return link_for(cid, rel, index)
            parts[i] = REF_RE.sub(repl, parts[i])
        out.append("".join(parts))
    return out


def main():
    index, dups, anchor_files = build_index()
    for cid, a, b in dups:
        print("duplicate clause ID: %s (%s / %s)" % (cid, a, b))
    if dups:
        return 1
    print("read %d clauses from %d files" % (len(index), len(set(index.values()))))

    missing = []
    changed, anchors_added, refs_converted = [], 0, 0
    for rel in sorted(set(ref_files()) | anchor_files):
        before = read(rel)
        after = convert(rel, index, rel in anchor_files, missing)
        if before == after:
            continue
        changed.append(rel)
        anchors_added += sum(1 for ln in after if ln.strip().startswith('<a id="')) \
            - sum(1 for ln in before if ln.strip().startswith('<a id="'))
        refs_converted += sum(len(REF_RE.findall(ln)) for ln in before) \
            - sum(len(REF_RE.findall(ln)) for ln in after)
        if not CHECK:
            with open(os.path.join(ROOT, rel), "w", encoding="utf-8") as f:
                f.write("\n".join(after))

    for rel, cid in missing:
        print("target clause not found (left unconverted): %s [[%s]]" % (rel, cid))

    verb = "change needed" if CHECK else "changed"
    print("%s: %d files (anchors +%d / %d references turned into links)"
          % (verb, len(changed), anchors_added, refs_converted))
    for rel in changed:
        print("  %s" % rel)
    if missing:
        return 1
    return 1 if (CHECK and changed) else 0


sys.exit(main())
