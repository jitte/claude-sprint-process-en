# spec-graph.py — the core. Start it through harness/tools/spec-graph.sh (argv[1] = scan root, argv[2:] = subcommand).
# Read the layout (living documents, the location of sprint documents, templates, the test file globs) from sprint.config.json.
import hashlib
import json
import os
import re
import subprocess
import sys
import tempfile

sys.dont_write_bytecode = True  # do not create __pycache__ in lib/
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "lib"))
import config  # noqa: E402

ROOT = sys.argv[1]
ARGS = sys.argv[2:]
CFG = config.load(ROOT)

# ── Constants ────────────────────────────────────────────────
# layer is an optional note. If you write it, use one of the following (this fixes the columns of the `layers` summary table).
LAYERS = ("common", "core", "supporting", "generic", "operation", "frontend", "design")

# Living documents. Defined by docs.livingDirs in sprint.config.json (shared with xref.sh and clause-anchors.py).
#   A file that has clauses = an md under these directories that declares xref-prefix in its frontmatter.
#   The folder and the layer do not matter. README.md is not excluded either.
#   As a referrer, each file is a target of V3 / V8 / V9 / V11.
LIVING_DIRS = tuple(CFG["docs"]["livingDirs"])
# The location of sprint documents (SPEC.md is read as a referrer)
SPRINT_ROOT = CFG["docs"]["sprintRoot"]

# A reference has 2 forms (18-9 N-3.1). Both forms pick up only what matches the ID shape.
# A memory reference (for example [[project_*]]) has a different shape, so it is out of scope.
#   Old notation [[ID]]        — remains in the past sprint records in docs/07_plans. Keep accepting it
#   New notation [ID](path#ID) — GitHub / Obsidian can follow it. An empty path is a same-file reference
REF_RE = re.compile(r"\[\[([A-Z]{2,6}-[0-9]+)\]\]")
REF_LINK_RE = re.compile(r"\[([A-Z]{2,6}-[0-9]+)\]\(([^)#]*)#([A-Z]{2,6}-[0-9]+)\)")
# Explicit anchor (18-9 N-1.1). V9 checks that the target exists.
ANCHOR_RE = re.compile(r'<a id="([A-Z]{2,6}-[0-9]+)"></a>')
# Out of scope for V8 / V9. A relative path in a template is written for the depth of the copy destination. The location is docs.templates in the config.
TEMPLATE_PREFIX = CFG["docs"]["templates"].rstrip("/") + "/"
# A declaration is only an [ID] in a heading line or in the first cell of a table row. An [ID](...) with "(" directly after it
# is a link (a reference), not a declaration. (A table in a clause file can list clauses of other files in
# column 1.)
DECL_HEAD_RE = re.compile(r"^(#{1,6})\s+.*?\[([A-Z]{2,6}-[0-9]+)\](?!\()")
DECL_ROW_RE = re.compile(r"^\|\s*\*{0,2}\s*\[([A-Z]{2,6}-[0-9]+)\](?!\()")
HEAD_RE = re.compile(r"^(#{1,6})\s+")
FENCE_RE = re.compile(r"^\s*(```|~~~)")
FM_KEY_RE = re.compile(r"^([A-Za-z0-9_-]+):\s*(.*)$")
# V11: section-number reference. Pattern 1: a § comes within 8 characters after a file name (ending in .md).
# Pattern 2: § and a digit come directly after an identifier-shaped word (joined with _ or -, 2 or more uppercase
# letters, or 2 or more digits) or after a document alias (docs.docAliases in the config: an abbreviation that the
# file name does not give).
# A section number after an ordinary word (the forms "(§3)", "in §8") matches neither pattern.
# Inline code is in scope. The inside of a code fence is out of scope.
DOC_ALIASES = [a for a in CFG.get("docs", {}).get("docAliases", []) if a]
IDENT_WORD_RE = (
    r"(?<![A-Za-z0-9_-])"
    r"(?:[A-Za-z0-9]+(?:[_-][A-Za-z0-9]+)+|[A-Z][A-Z0-9]+|[0-9]{2,})"
)
SECTION_REF_RE = re.compile(
    r"[A-Za-z0-9_./-]+\.md[^§\n]{0,8}§"
    r"|(" + "|".join([IDENT_WORD_RE] + [re.escape(a) for a in DOC_ALIASES]) + r")\s*§[0-9]"
)

# Test files (referrers. They have no clauses). Read the [[ID]] in a test name as a reference (TSTD-6).
#   The collection scope is the globs of components[*].tests in the config. Do not collect under a .gitignore directory.
TEST_GLOBS = tuple(config.component_globs(CFG, "tests"))
# A test name line: a line that starts, after leading whitespace, with the form describe( / it( / test( / test.describe( / it.each(
# ((describe|it|test), then 0 or more .identifier, then "(").
TEST_NAME_RE = re.compile(r"^\s*(describe|it|test)(\.[A-Za-z_]\w*)*\(")

# A clause in a table row has no heading level. Treat it as the deepest level so that any heading ends its range.
ROW_LEVEL = 99

errors = []


def err(msg):
    errors.append(msg)


# ── File collection ────────────────────────────────────────
def _walk_md(root, reldir):
    base = os.path.join(root, reldir)
    if not os.path.isdir(base):
        return []
    out = []
    for dirpath, dirnames, filenames in os.walk(base):
        dirnames.sort()
        for fn in sorted(filenames):
            if fn.endswith(".md"):
                out.append(os.path.relpath(os.path.join(dirpath, fn), root))
    return out


def _declared_prefix(root, rel):
    """Read only xref-prefix in the frontmatter (do not parse the full text). Return "" if it is absent."""
    try:
        with open(os.path.join(root, rel), encoding="utf-8") as f:
            head = f.read(4096)
    except OSError:
        return ""
    lines = head.split("\n")
    if not lines or lines[0].strip() != "---":
        return ""
    for ln in lines[1:]:
        if ln.strip() == "---":
            break
        m = FM_KEY_RE.match(ln)
        if m and m.group(1) == "xref-prefix":
            return m.group(2).strip().strip("\"'")
    return ""


def living_files(root):
    out = []
    for d in LIVING_DIRS:
        out.extend(_walk_md(root, d))
    return sorted(set(out))


def target_files(root):
    """A file that has clauses = an md among the living documents that declares xref-prefix in its frontmatter."""
    return [rel for rel in living_files(root) if _declared_prefix(root, rel)]


def sealed_set(root):
    """The set of relative paths of sealed files. Do not verify a sealed SPEC as a referrer."""
    path = os.path.join(root, ".sprint", "spec-hashes.json")
    try:
        with open(path, encoding="utf-8") as f:
            return set(json.load(f).keys())
    except (OSError, ValueError):
        return set()


def test_source_files(root):
    """Test files (files that match the tests globs in the config). Do not collect under a .gitignore directory."""
    return config.glob_files(root, TEST_GLOBS)


def is_test_file(rel):
    return not rel.endswith(".md")


def ref_source_files(root):
    """Files to scan as referrers (targets of V3 / V8 / V9 / V11).

    Living documents (templates included) + SPEC.md under <docs.sprintRoot> + md files directly under the repository root
    + test files (only the [[ID]] in test names. Only V3 applies).
    The caller excludes sealed SPECs.
    """
    out = living_files(root)
    for rel in _walk_md(root, SPRINT_ROOT):
        if os.path.basename(rel) == "SPEC.md":
            out.append(rel)
    # Also verify md files directly under the repository root (for example CLAUDE.md) as referrers.
    for fn in sorted(os.listdir(root)) if os.path.isdir(root) else []:
        if fn.endswith(".md") and os.path.isfile(os.path.join(root, fn)):
            out.append(fn)
    out.extend(test_source_files(root))
    return sorted(set(out))


# ── Analysis ────────────────────────────────────────────────
def read_lines(path):
    with open(path, encoding="utf-8") as f:
        return f.read().split("\n")


def unfenced(lines):
    """Lines with the inside of code fences emptied (line numbers are kept). Inline code stays."""
    out = []
    in_fence = False
    for ln in lines:
        if FENCE_RE.match(ln):
            in_fence = not in_fence
            out.append("")
            continue
        out.append("" if in_fence else ln)
    return out


def scannable(lines):
    """Lines with the inside of code fences and inline code removed (line numbers are kept)."""
    return [re.sub(r"`[^`]*`", "", ln) for ln in unfenced(lines)]


def parse_frontmatter(lines):
    """Return (dict, body start line). If there is no frontmatter or it is not closed, return (None, 0)."""
    if not lines or lines[0].strip() != "---":
        return None, 0
    fm = {}
    for i in range(1, len(lines)):
        if lines[i].strip() == "---":
            return fm, i + 1
        m = FM_KEY_RE.match(lines[i])
        if m:
            fm[m.group(1)] = m.group(2).strip()
    return None, 0


def analyze_test(root, rel):
    """Analyze a test file. Read as references only the [[ID]] in test name lines (TEST_NAME_RE).

    When a line ends with "(", append the next line and read both (the 2-line form, where the name is on the next line).
    Do not read comments, fixture strings, or the body. A test file has no clauses. It is out of scope for V8 / V9 / V11
    (the path of each ref is None, and section_refs is empty).
    """
    raw = read_lines(os.path.join(root, rel))
    refs = []
    for i, ln in enumerate(raw):
        if not TEST_NAME_RE.match(ln):
            continue
        text = ln
        if ln.rstrip().endswith("(") and i + 1 < len(raw):
            text += raw[i + 1]
        for m in REF_RE.finditer(text):
            refs.append({"to": m.group(1), "line": i + 1, "path": None})
    return {"rel": rel, "fm": None, "clauses": [], "refs": refs, "section_refs": []}


def analyze(root, rel):
    if is_test_file(rel):
        return analyze_test(root, rel)
    raw = read_lines(os.path.join(root, rel))
    scan = scannable(raw)
    fm, body_start = parse_frontmatter(raw)

    heads = {}
    decls = []
    for i, ln in enumerate(scan):
        if i < body_start:
            continue
        m = HEAD_RE.match(ln)
        if m:
            heads[i] = len(m.group(1))
        m = DECL_HEAD_RE.match(ln)
        if m:
            title = re.sub(r"^#+\s*", "", raw[i]).replace("[%s]" % m.group(2), "").strip()
            decls.append({"id": m.group(2), "start": i, "level": len(m.group(1)), "title": title})
            continue
        m = DECL_ROW_RE.match(ln)
        if m:
            cells = [c.strip() for c in raw[i].strip().strip("|").split("|")]
            title = cells[1] if len(cells) > 1 else ""
            decls.append({"id": m.group(1), "start": i, "level": ROW_LEVEL, "title": title})

    decl_lines = {d["start"] for d in decls}
    for d in decls:
        end = len(raw)
        for j in range(d["start"] + 1, len(raw)):
            if j in decl_lines or (j in heads and heads[j] <= d["level"]):
                end = j
                break
        # The anchor line (<a id=…>) of the next clause is before its heading, so it falls in the range up to here.
        # Remove the trailing anchor lines and blank lines from the range, so that a new clause does not change the hash of the previous clause.
        while end > d["start"] + 1 and (
            not raw[end - 1].strip() or ANCHOR_RE.fullmatch(raw[end - 1].strip())
        ):
            end -= 1
        # The content hash range includes the declaration line.
        text = "\n".join(raw[d["start"]:end]).rstrip() + "\n"
        d["hash"] = hashlib.sha256(text.encode("utf-8")).hexdigest()[:12]
        d["end"] = end
        d["line"] = d["start"] + 1

    refs = []
    for i, ln in enumerate(scan):
        for m in REF_RE.finditer(ln):
            refs.append({"to": m.group(1), "line": i + 1, "path": None})
        for m in REF_LINK_RE.finditer(ln):
            refs.append({"to": m.group(3), "line": i + 1, "path": m.group(2)})
    refs.sort(key=lambda r: r["line"])

    # Target lines for V11. Check the lines with inline code kept.
    section_refs = [i + 1 for i, ln in enumerate(unfenced(raw)) if SECTION_REF_RE.search(ln)]

    return {"rel": rel, "fm": fm, "clauses": decls, "refs": refs, "section_refs": section_refs}


def clause_index(root):
    """Clause ID -> definition info. Only the clauses of files that have clauses become nodes."""
    index = {}
    dups = []
    prefixes = {}
    files = {}
    for rel in target_files(root):
        info = analyze(root, rel)
        files[rel] = info
        fm = info["fm"] or {}
        layer = fm.get("layer", "")
        prefix = fm.get("xref-prefix", "")
        if prefix:
            prefixes.setdefault(prefix, []).append(rel)
        for c in info["clauses"]:
            node = dict(c)
            node.update({"file": rel, "layer": layer, "prefix": prefix})
            if c["id"] in index:
                dups.append((c["id"], index[c["id"]], node))
            else:
                index[c["id"]] = node
    return index, dups, prefixes, files


def clause_of(info, line):
    """The clause ID whose range includes line number line, in info (the analysis result of a file that has clauses). None if there is none."""
    for c in info["clauses"]:
        if c["start"] < line <= c["end"]:
            return c["id"]
    return None


def ref_text(r):
    """Show a reference in its source form (for error messages)."""
    if r["path"] is None:
        return "[[%s]]" % r["to"]
    return "[%s](%s#%s)" % (r["to"], r["path"], r["to"])


_anchor_cache = {}


def anchor_ids(root, rel):
    """The set of explicit anchor IDs in rel. Do not count inside fences (the same semantics as scannable)."""
    if rel not in _anchor_cache:
        try:
            lines = scannable(read_lines(os.path.join(root, rel)))
        except OSError:
            lines = []
        _anchor_cache[rel] = set(ANCHOR_RE.findall("\n".join(lines)))
    return _anchor_cache[rel]


def check_link(root, rel, r):
    """V8 / V9: the relative path and the anchor of a new-notation link exist (18-9 N-3.2 / N-3.3).

    Exclude <docs.templates>/** from both. A relative path in a template
    is written at the depth that resolves from the copy destination (<docs.sprintRoot>/<major>_<slug>/<minor>_<slug>/SPEC.md),
    so it does not resolve from the location of the template itself. V9 also uses the same relative path to resolve
    the target file, so if you exclude only V8, the check still fails with the same count.
    """
    if r["path"] is None or rel.startswith(TEMPLATE_PREFIX):
        return
    if r["path"]:
        target = os.path.normpath(os.path.join(os.path.dirname(rel), r["path"]))
        if not os.path.isfile(os.path.join(root, target)):
            err("V8 link relative path does not exist: %s:%d %s" % (rel, r["line"], ref_text(r)))
            return
    else:
        target = rel
    if r["to"] not in anchor_ids(root, target):
        err("V9 no anchor in the target: %s:%d %s -> %s"
            % (rel, r["line"], ref_text(r), target))


def clause_body(root, node):
    """The body of a clause (the declaration line included). Drop the trailing blank lines."""
    raw = read_lines(os.path.join(root, node["file"]))
    body = raw[node["start"]:node["end"]]
    while body and not body[-1].strip():
        body.pop()
    return body


def clause_edges(index, tfiles):
    """The edges of the clause reference graph {from_id: set(to_id)}.

    A node is a clause. An edge is a reference in the body of a clause in a file that has clauses -> the target clause.
    A reference from a file that has no clauses (a consumer) does not become an edge (18-14 D-5).
    """
    adj = {}
    for rel, info in tfiles.items():
        for r in info["refs"]:
            src = clause_of(info, r["line"])
            if src is None or r["to"] not in index:
                continue
            adj.setdefault(src, set()).add(r["to"])
    return adj


def strongly_connected(adj):
    """Tarjan. Return only the components of size 2 or more, or with a self-reference (sorted in ascending ID order)."""
    sys.setrecursionlimit(10000)
    idx, low, stack, on, out, counter = {}, {}, [], set(), [], [0]

    def dfs(v):
        idx[v] = low[v] = counter[0]
        counter[0] += 1
        stack.append(v)
        on.add(v)
        for w in sorted(adj.get(v, ())):
            if w not in idx:
                dfs(w)
                low[v] = min(low[v], low[w])
            elif w in on:
                low[v] = min(low[v], idx[w])
        if low[v] == idx[v]:
            comp = []
            while True:
                w = stack.pop()
                on.discard(w)
                comp.append(w)
                if w == v:
                    break
            if len(comp) > 1 or v in adj.get(v, ()):
                out.append(sorted(comp))

    for v in sorted(adj):
        if v not in idx:
            dfs(v)
    return sorted(out)


def cycle_path(adj, comp):
    """Return 1 cycle in the component, in the form that returns to the start (A -> B -> A)."""
    start = comp[0]
    members = set(comp)
    if start in adj.get(start, ()):
        return [start, start]
    # Breadth-first: find the shortest path from start back to start.
    parent = {}
    queue = [start]
    seen = {start}
    while queue:
        v = queue.pop(0)
        for w in sorted(adj.get(v, ())):
            if w not in members:
                continue
            if w == start:
                path = [v]
                while path[-1] != start:
                    path.append(parent[path[-1]])
                path.reverse()
                return path + [start]
            if w not in seen:
                seen.add(w)
                parent[w] = v
                queue.append(w)
    return comp + [start]


# ── Subcommands ────────────────────────────────────────
def cmd_verify():
    index, dups, prefixes, tfiles = clause_index(ROOT)
    sealed = sealed_set(ROOT)

    # V6: frontmatter declarations
    for rel, info in sorted(tfiles.items()):
        fm = info["fm"] or {}
        prefix = fm.get("xref-prefix", "")
        if not re.fullmatch(r"[A-Z]{2,6}", prefix):
            err("V6 xref-prefix must be 2 to 6 uppercase letters: %s (%s)" % (rel, prefix))
        layer = fm.get("layer", "")
        if layer and layer not in LAYERS:
            err("V6 invalid layer value: %s (%s) — if you write it, use one of %s" % (rel, layer, "/".join(LAYERS)))
    # V6: a file that has a heading that declares a clause but has no xref-prefix (its clauses silently fall out of scope)
    for rel in living_files(ROOT):
        if rel in tfiles:
            continue
        info = analyze(ROOT, rel)
        heads_with_id = [c for c in info["clauses"] if c["level"] != ROW_LEVEL]
        if heads_with_id:
            err("V6 no xref-prefix: %s (clause heading %s:%d)"
                % (rel, heads_with_id[0]["id"], heads_with_id[0]["line"]))

    # V1: uniqueness of prefix
    for prefix, rels in sorted(prefixes.items()):
        if len(rels) > 1:
            err("V1 duplicate xref-prefix %s: %s" % (prefix, ", ".join(sorted(rels))))

    # V2: uniqueness of clause ID
    for cid, first, second in dups:
        err("V2 duplicate clause ID %s: %s:%d / %s:%d"
            % (cid, first["file"], first["line"], second["file"], second["line"]))

    # Precondition of V2: a clause ID uses the prefix that its file declares
    for rel, info in sorted(tfiles.items()):
        prefix = (info["fm"] or {}).get("xref-prefix", "")
        if not prefix:
            continue
        for c in info["clauses"]:
            if c["id"].rsplit("-", 1)[0] != prefix:
                err("V2 clause ID prefix differs from the file declaration: %s:%d %s (declared %s)"
                    % (rel, c["line"], c["id"], prefix))

    # V5: the impl path exists
    for rel, info in sorted(tfiles.items()):
        impl = (info["fm"] or {}).get("impl", "")
        if impl and not os.path.exists(os.path.join(ROOT, impl)):
            err("V5 impl path does not exist: %s (impl: %s)" % (rel, impl))

    # V3 / V8 / V9 / V11: the reference exists, the link resolves, no section-number reference
    for rel in ref_source_files(ROOT):
        if rel in sealed:
            continue
        info = tfiles.get(rel) or analyze(ROOT, rel)
        for r in info["refs"]:
            check_link(ROOT, rel, r)
            if r["to"] not in index:
                # Show a reference in a test name as the bare ID (N-1.3). Show a document reference in its source notation.
                shown = r["to"] if is_test_file(rel) else ref_text(r)
                err("V3 target clause does not exist: %s:%d %s" % (rel, r["line"], shown))
        for line in info["section_refs"]:
            err("V11 reference by section number: %s:%d" % (rel, line))

    # V10: cycles in the clause reference graph
    adj = clause_edges(index, tfiles)
    for comp in strongly_connected(adj):
        err("V10 reference cycle: %s" % " -> ".join(cycle_path(adj, comp)))

    if errors:
        for e in errors:
            print(e)
        print("verify: NG (%d errors)" % len(errors))
        return 1
    ref_count = sum(len(analyze(ROOT, rel)["refs"])
                    for rel in ref_source_files(ROOT) if rel not in sealed)
    print("verify: OK (%d clauses, %d refs, %d files)"
          % (len(index), ref_count, len(tfiles)))
    return 0


def build_graph(root):
    index, _, _, tfiles = clause_index(root)
    nodes = []
    for cid, c in sorted(index.items()):
        nodes.append({
            "id": cid,
            "file": c["file"],
            "line": c["line"],
            "layer": c["layer"],
            "prefix": c["prefix"],
            "title": c["title"],
            "hash": c["hash"],
            # The range of the clause (1-based, both ends included). The clause rate calculation does not need to copy the range calculation.
            "endLine": c["end"],
        })
    sealed = sealed_set(root)
    edges = []
    for rel in ref_source_files(root):
        if rel in sealed:
            continue
        info = tfiles.get(rel)
        # from is set only on a reference in the range of a clause in a file that has clauses (18-14 N-1.8).
        # A table row in a consumer file is not a clause.
        refs = info["refs"] if info else analyze(root, rel)["refs"]
        for r in refs:
            src = clause_of(info, r["line"]) if info else None
            edges.append({"from": src, "fromFile": rel, "line": r["line"], "to": r["to"]})
    return {"nodes": nodes, "edges": edges}


def cmd_index():
    print(json.dumps(build_graph(ROOT), ensure_ascii=False, indent=2))
    return 0


def references_to(root, cid):
    sealed = sealed_set(root)
    hits = []
    for rel in ref_source_files(root):
        info = analyze(root, rel)
        for r in info["refs"]:
            if r["to"] == cid:
                hits.append((rel, r["line"], rel in sealed))
    return hits


def cmd_reverse(cid):
    for rel, line, is_sealed in references_to(ROOT, cid):
        print("%s:%d%s" % (rel, line, "  (sealed)" if is_sealed else ""))
    return 0


def cmd_deps(path):
    rel = os.path.relpath(os.path.abspath(path), ROOT)
    full = os.path.join(ROOT, rel)
    if not os.path.isfile(full):
        print("file not found: %s" % path)
        return 1
    index, _, _, _ = clause_index(ROOT)
    for r in analyze(ROOT, rel)["refs"]:
        dst = index.get(r["to"])
        where = "%s:%d" % (dst["file"], dst["line"]) if dst else "(no target)"
        print("%s:%d -> %s  %s" % (rel, r["line"], r["to"], where))
    return 0


def cmd_diff(ref):
    rev = subprocess.run(["git", "-C", ROOT, "rev-parse", "--verify", "%s^{commit}" % ref],
                         capture_output=True, text=True)
    if rev.returncode != 0:
        print("cannot resolve git-ref: %s" % ref)
        return 1

    listing = subprocess.run(["git", "-C", ROOT, "ls-tree", "-r", "--name-only", ref, "--", "docs"],
                             capture_output=True, text=True)
    with tempfile.TemporaryDirectory() as tmp:
        for p in listing.stdout.split("\n"):
            if not p.endswith(".md"):
                continue
            blob = subprocess.run(["git", "-C", ROOT, "show", "%s:%s" % (ref, p)],
                                  capture_output=True, text=True)
            if blob.returncode != 0:
                continue
            dest = os.path.join(tmp, p)
            os.makedirs(os.path.dirname(dest), exist_ok=True)
            with open(dest, "w", encoding="utf-8") as f:
                f.write(blob.stdout)
        old, _, _, _ = clause_index(tmp)

    new, _, _, _ = clause_index(ROOT)

    changed = [cid for cid in sorted(set(old) & set(new)) if old[cid]["hash"] != new[cid]["hash"]]
    added = sorted(set(new) - set(old))
    removed = sorted(set(old) - set(new))

    def show(kind, cid, node):
        print("%s: %s  %s:%d" % (kind, cid, node["file"], node["line"]))
        for rel, line, is_sealed in references_to(ROOT, cid):
            print("    ← %s:%d%s" % (rel, line, "  (sealed)" if is_sealed else ""))

    for cid in changed:
        show("changed", cid, new[cid])
    for cid in added:
        show("added", cid, new[cid])
    for cid in removed:
        show("removed", cid, old[cid])

    print("diff %s: changed %d / added %d / removed %d"
          % (ref, len(changed), len(added), len(removed)))
    return 0


def refs_in_counts(root, index, tfiles):
    """Referenced count per file (from all referrers except sealed ones, to the file of the target clause)."""
    counts = {rel: 0 for rel in tfiles}
    sealed = sealed_set(root)
    for rel in ref_source_files(root):
        if rel in sealed:
            continue
        info = tfiles.get(rel) or analyze(root, rel)
        for r in info["refs"]:
            dst = index.get(r["to"])
            if dst:
                counts[dst["file"]] = counts.get(dst["file"], 0) + 1
    return counts


def cmd_files():
    """List of files that have clauses. Relative path, prefix, layer (- if absent), clause count, referenced count."""
    index, _, _, tfiles = clause_index(ROOT)
    clauses = {rel: 0 for rel in tfiles}
    for node in index.values():
        clauses[node["file"]] = clauses.get(node["file"], 0) + 1
    counts = refs_in_counts(ROOT, index, tfiles)
    for rel in sorted(tfiles):
        fm = tfiles[rel]["fm"] or {}
        print("%s  %s  %s  clauses=%d  refs-in=%d"
              % (rel, fm.get("xref-prefix", "-"), fm.get("layer", "") or "-",
                 clauses.get(rel, 0), counts.get(rel, 0)))
    return 0


def cmd_layers():
    """Table of the reference edges between files that have clauses, counted by referrer layer x target layer.

    The direction is a metric of the dependency structure, not a constraint (18-14 D-2). Count a file with no layer
    as `-`. 1 row per pair (referrer layer, target layer, reference count). Print only the pairs that occur.
    """
    index, _, _, tfiles = clause_index(ROOT)
    table = {}
    for rel, info in tfiles.items():
        src_layer = (info["fm"] or {}).get("layer", "") or "-"
        for r in info["refs"]:
            dst = index.get(r["to"])
            if dst is None:
                continue
            dst_layer = dst["layer"] or "-"
            table[(src_layer, dst_layer)] = table.get((src_layer, dst_layer), 0) + 1
    order = {l: i for i, l in enumerate(LAYERS + ("-",))}
    print("| Referrer layer | Target layer | References |")
    print("|---|---|---:|")
    for (src, dst), n in sorted(table.items(), key=lambda kv: (order[kv[0][0]], order[kv[0][1]])):
        print("| %s | %s | %d |" % (src, dst, n))
    return 0


def refs_in(lines):
    """Return the reference IDs in the lines, in order of appearance. Do not scan inside code fences."""
    out = []
    in_fence = False
    for ln in lines:
        if FENCE_RE.match(ln):
            in_fence = not in_fence
            continue
        if in_fence:
            continue
        bare = re.sub(r"`[^`]*`", "", ln)
        for rid in REF_RE.findall(bare) + [m[2] for m in REF_LINK_RE.findall(bare)]:
            if rid not in out:
                out.append(rid)
    return out


def cmd_resolve(path):
    """Print the source text unchanged, then list each reached clause once."""
    rel = os.path.relpath(os.path.abspath(path), ROOT)
    full = os.path.join(ROOT, rel)
    if not os.path.isfile(full):
        print("file not found: %s" % path)
        return 1

    index, _, _, _ = clause_index(ROOT)
    source = read_lines(full)

    # Build the transitive closure breadth-first. A visited clause is not expanded again, so a cycle terminates.
    order = []
    seen = set()
    missing = []
    origin = {}
    queue = [(rid, [rel]) for rid in refs_in(source)]
    cycles = []
    while queue:
        rid, path_ids = queue.pop(0)
        node = index.get(rid)
        if node is None:
            if rid not in missing:
                missing.append(rid)
            continue
        if rid in seen:
            if rid in path_ids:
                cycles.append((rid, path_ids))
            continue
        seen.add(rid)
        order.append(rid)
        origin[rid] = path_ids
        for nxt in refs_in(clause_body(ROOT, node)):
            if nxt in path_ids or nxt == rid:
                cycles.append((nxt, path_ids + [rid]))
                if nxt in seen:
                    continue
            queue.append((nxt, path_ids + [rid]))

    if missing:
        for rid in missing:
            print("resolve: target clause does not exist: %s [[%s]]" % (rel, rid))
        return 1

    for line in source:
        print(line)

    print("")
    print("---")
    print("")
    print("## Referenced clauses (expanded by `spec-graph.sh resolve`)")
    print("")
    if not order:
        print("No references.")
        return 0
    print("Reached %d clauses. Each clause appears only once (a cycle terminates)." % len(order))
    print("")
    reported = set()
    for rid in order:
        node = index[rid]
        print("### %s — %s" % (rid, node["title"] or "(untitled)"))
        print("")
        print("Source: `%s:%d` (%s)" % (node["file"], node["line"], node["layer"] or "-"))
        for cid, path_ids in cycles:
            key = (cid, tuple(path_ids))
            if cid == rid and key not in reported:
                reported.add(key)
                print("")
                print("<!-- resolve: cycle %s -> %s -->"
                      % (" -> ".join(p for p in path_ids if p != rel), cid))
        print("")
        for line in clause_body(ROOT, node):
            print(line)
        print("")
    return 0


USAGE = ("Usage: spec-graph.sh "
         "{verify|index|diff <git-ref>|reverse <ID>|deps <FILE>|files|layers|resolve <FILE>}")

if not ARGS:
    print(USAGE)
    sys.exit(2)

cmd, rest = ARGS[0], ARGS[1:]
if cmd == "verify":
    sys.exit(cmd_verify())
if cmd == "index":
    sys.exit(cmd_index())
if cmd == "reverse":
    if not rest:
        print(USAGE)
        sys.exit(2)
    sys.exit(cmd_reverse(rest[0]))
if cmd == "deps":
    if not rest:
        print(USAGE)
        sys.exit(2)
    sys.exit(cmd_deps(rest[0]))
if cmd == "diff":
    if not rest:
        print(USAGE)
        sys.exit(2)
    sys.exit(cmd_diff(rest[0]))
if cmd == "files":
    sys.exit(cmd_files())
if cmd == "layers":
    sys.exit(cmd_layers())
if cmd == "resolve":
    if not rest:
        print(USAGE)
        sys.exit(2)
    sys.exit(cmd_resolve(rest[0]))

print(USAGE)
sys.exit(2)
