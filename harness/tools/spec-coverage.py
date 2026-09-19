#!/usr/bin/env python3
"""spec-coverage.py — count the clause reference coverage of the base specification (cov / rcov / tcov).

The unit is 1 clause. Count by whether an edge exists in the reference graph (spec-graph.py index in the same directory).

  cov   clause rate : the ratio of lines in a clause range (non-empty lines. frontmatter excluded)
  hcov  heading rate : the ratio of headings that have a clause ID (## to ####. Outside code fences)
  rcov  referenced rate : the ratio of lines of clauses that are referenced from elsewhere (that have an incoming edge). The referrers are living documents
                   (outside docs.sprintRoot. References from consumer files that have no clauses also count)
  rcov+ referenced rate with the sprint : rcov with all references in the SPEC.md of the given sprint added as incoming edges
  tcov  test-referenced rate : for each document in docs.specDir, the number of clauses that test files (the [[ID]] in test names)
                   reference / the clause count. — for a document outside specDir. rcov / rcov+ / solo
                   do not count test references (only edges whose referrer is a .md)
  solo  solo rate   : the ratio of clauses that reference nothing in the normative and common layer (docs.normativeDirs and docs.commonFiles).
                   Only the leaf specifications in specDir are in scope. — when the normative and common layer is not configured

It is a metric and does not fail. The layers and the direction of references are metrics, not constraints.

Read the layout from sprint.config.json (docs.sprintRoot, docs.specDir, docs.normativeDirs,
docs.commonFiles). The harness core holds no paths.

Usage (through spec-coverage.sh. ROOT is the scan root):
  python3 spec-coverage.py <ROOT>                 # include the SPEC.md of the active sprint
  python3 spec-coverage.py <ROOT> --sprint 1-2    # select by sprint ID
  python3 spec-coverage.py <ROOT> --spec <sprintRoot>/.../SPEC.md
  python3 spec-coverage.py <ROOT> --no-sprint     # base specification only
  python3 spec-coverage.py <ROOT> --json          # machine-readable
  python3 spec-coverage.py <ROOT> --unreferenced  # list the unreferenced clause IDs at the end
  python3 spec-coverage.py <ROOT> --untested      # list, per document, the specDir clause IDs that no test references
"""
import argparse
import json
import os
import re
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.normpath(os.path.join(HERE, "..", "lib")))
import config  # noqa: E402

if len(sys.argv) < 2:
    print("usage: spec-coverage.py <ROOT> [options]")
    sys.exit(2)
ROOT = sys.argv[1]
CFG = config.load(ROOT)
DOCS = CFG.get("docs", {})


def _dir(key):
    v = DOCS.get(key, "")
    return v.rstrip("/") + "/" if v else ""


SPRINT_DIR = _dir("sprintRoot")
SPEC_DIR = _dir("specDir")
NORM_PREFIXES = tuple(p.rstrip("/") + "/" for p in DOCS.get("normativeDirs", []))
NORM_FILES = tuple(DOCS.get("commonFiles", []))
NORM_ENABLED = bool(NORM_PREFIXES or NORM_FILES)

# The same 2 notations as spec-graph.py. Pick up only what matches the ID shape.
REF_RE = re.compile(r"\[\[([A-Z]{2,6}-[0-9]+)\]\]")
REF_LINK_RE = re.compile(r"\[([A-Z]{2,6}-[0-9]+)\]\(([^)#]*)#([A-Z]{2,6}-[0-9]+)\)")
FENCE_RE = re.compile(r"^\s*(```|~~~)")
SPEC_GRAPH_PY = os.path.join(HERE, "spec-graph.py")


def load_index():
    out = subprocess.run(
        [sys.executable, SPEC_GRAPH_PY, ROOT, "index"],
        capture_output=True, text=True, cwd=ROOT,
    )
    if out.returncode != 0:
        sys.stderr.write(out.stderr or out.stdout)
        sys.exit(2)
    return json.loads(out.stdout)


def refs_in_file(path):
    """Return the set of reference IDs in the file (outside code fences and outside inline code)."""
    ids = set()
    in_fence = False
    with open(path, encoding="utf-8") as f:
        for ln in f:
            if FENCE_RE.match(ln):
                in_fence = not in_fence
                continue
            if in_fence:
                continue
            bare = re.sub(r"`[^`]*`", "", ln)
            ids.update(REF_RE.findall(bare))
            ids.update(m[2] for m in REF_LINK_RE.findall(bare))
    return ids


def resolve_spec(args):
    """Return the path (relative to ROOT) of the SPEC.md to include, and the sprint ID. (None, None) if there is none."""
    if args.no_sprint:
        return None, None
    if args.spec:
        return args.spec, None
    flags_path = os.path.join(ROOT, ".sprint", "flags.json")
    if not os.path.isfile(flags_path):
        return None, None
    flags = json.load(open(flags_path, encoding="utf-8"))
    sid = args.sprint or flags.get("active")
    entry = (flags.get("sprints") or {}).get(sid)
    if not entry:
        sys.stderr.write("sprint %s is not in .sprint/flags.json\n" % sid)
        sys.exit(2)
    return os.path.join(entry["sprint_dir"], "SPEC.md"), sid


def _body_start(raw):
    if raw and raw[0] == "---" and "---" in raw[1:]:
        return raw.index("---", 1) + 1
    return 0


def line_coverage(rel, spans):
    """(number of non-empty lines, number of those in a clause range). frontmatter is not counted."""
    raw = open(os.path.join(ROOT, rel), encoding="utf-8").read().split("\n")
    start = _body_start(raw)
    inside = set()
    for lo, hi in spans:          # 1-based, both ends included
        inside.update(range(lo - 1, hi))
    body = [i for i in range(start, len(raw)) if raw[i].strip()]
    return len(body), sum(1 for i in body if i in inside)


HEAD_RE = re.compile(r"^(#{2,4})\s+(.*)$")
DECL_ID_RE = re.compile(r"\[[A-Z]{2,6}-[0-9]+\](?!\()")


def is_norm_file(rel):
    return rel.startswith(NORM_PREFIXES) or rel in NORM_FILES


def heading_coverage(rel):
    """(number of headings, number of those with a clause ID). Code fences and frontmatter are excluded."""
    raw = open(os.path.join(ROOT, rel), encoding="utf-8").read().split("\n")
    total = with_id = 0
    fence = False
    for ln in raw[_body_start(raw):]:
        if FENCE_RE.match(ln):
            fence = not fence
            continue
        if fence:
            continue
        m = HEAD_RE.match(ln)
        if m:
            total += 1
            if DECL_ID_RE.search(m.group(2)):
                with_id += 1
    return total, with_id


def pct(n, d):
    return "%d/%d (%d%%)" % (n, d, round(100.0 * n / d)) if d else "0/0 (-)"


def main():
    ap = argparse.ArgumentParser(prog="spec-coverage")
    ap.add_argument("--sprint", help="sprint ID (default: active in .sprint/flags.json)")
    ap.add_argument("--spec", help="path of SPEC.md (takes precedence over --sprint)")
    ap.add_argument("--no-sprint", action="store_true", help="count only the base specification")
    ap.add_argument("--unreferenced", action="store_true",
                    help="list the unreferenced clause IDs at the end (default: the count only)")
    ap.add_argument("--untested", action="store_true",
                    help="list, per document, the specDir clause IDs that no test references")
    ap.add_argument("--json", action="store_true", help="output JSON")
    args = ap.parse_args(sys.argv[2:])

    idx = load_index()
    nodes = {n["id"]: n for n in idx["nodes"]}
    has_in = set()
    to_norm = set()
    tested = set()          # clauses referenced from test files (not .md)
    for e in idx["edges"]:
        if SPRINT_DIR and e["fromFile"].startswith(SPRINT_DIR):
            continue
        if not e["fromFile"].endswith(".md"):
            if e["to"] in nodes:
                tested.add(e["to"])
            continue
        if e["to"] in nodes:
            has_in.add(e["to"])
            if e["from"] in nodes and is_norm_file(nodes[e["to"]]["file"]):
                to_norm.add(e["from"])

    spec_rel, sid = resolve_spec(args)
    spec_refs = set()
    if spec_rel:
        spec_abs = os.path.join(ROOT, spec_rel)
        if not os.path.isfile(spec_abs):
            sys.stderr.write("SPEC.md not found: %s\n" % spec_rel)
            sys.exit(2)
        spec_refs = {r for r in refs_in_file(spec_abs) if r in nodes}
    has_in_plus = has_in | spec_refs

    files = {}
    for n in sorted(nodes.values(), key=lambda n: (n["file"], n["line"])):
        f = files.setdefault(n["file"], {"prefix": n["prefix"], "ids": [], "spans": []})
        f["ids"].append(n["id"])
        f["spans"].append((n["line"], n["endLine"]))

    rows = []
    for rel in sorted(files):
        ids = files[rel]["ids"]
        spans = dict(zip(ids, files[rel]["spans"]))
        body, covered = line_coverage(rel, files[rel]["spans"])
        _, rcov_l = line_coverage(rel, [spans[i] for i in ids if i in has_in])
        _, rcovp_l = line_coverage(rel, [spans[i] for i in ids if i in has_in_plus])
        heads, heads_id = heading_coverage(rel)
        is_spec = bool(SPEC_DIR) and rel.startswith(SPEC_DIR)
        # The solo rate covers only the leaf specifications in specDir. Do not count it when the normative and common layer is not configured.
        is_leaf = NORM_ENABLED and is_spec and not is_norm_file(rel)
        leaf = ids if is_leaf else []
        rows.append({
            "file": rel,
            "prefix": files[rel]["prefix"],
            "clauses": len(ids),
            "lines": body,
            "cov": covered,
            "headings": heads,
            "hcov": heads_id,
            "rcov": rcov_l,
            "rcov_plus": rcovp_l,
            "rcov_clauses": sum(1 for i in ids if i in has_in),
            "leaf_clauses": len(leaf),
            "solo": sum(1 for i in leaf if i not in to_norm),
            "unreferenced": [i for i in ids if i not in has_in],
            "covered_by_sprint": [i for i in ids if i in spec_refs and i not in has_in],
            # tcov is only for the documents in specDir. None for the others (— in the table)
            "tcov": sum(1 for i in ids if i in tested) if is_spec else None,
            "untested": [i for i in ids if i not in tested] if is_spec else [],
        })
    total = {
        "clauses": len(nodes),
        "lines": sum(r["lines"] for r in rows),
        "cov": sum(r["cov"] for r in rows),
        "headings": sum(r["headings"] for r in rows),
        "hcov": sum(r["hcov"] for r in rows),
        "rcov": sum(r["rcov"] for r in rows),
        "rcov_plus": sum(r["rcov_plus"] for r in rows),
        "rcov_clauses": len(has_in),
        "leaf_clauses": sum(r["leaf_clauses"] for r in rows),
        "solo": sum(r["solo"] for r in rows),
        "clauses_spec": sum(r["clauses"] for r in rows if r["tcov"] is not None),
        "tcov": sum(r["tcov"] for r in rows if r["tcov"] is not None),
    }

    if args.json:
        json.dump({"sprint": sid, "spec": spec_rel, "total": total, "files": rows},
                  sys.stdout, ensure_ascii=False, indent=1)
        print()
        return 0

    head = "| File | prefix | Clauses | cov(lines) | cov(headings) | rcov(lines) |"
    sep = "|---|---|---:|---:|---:|---:|"
    if spec_rel:
        head += " rcov+(lines) |"
        sep += "---:|"
    head += " tcov | solo |"
    sep += "---:|---:|"
    print(head)
    print(sep)
    for r in rows:
        line = "| %s | %s | %d | %s | %s | %s |" % (
            r["file"], r["prefix"], r["clauses"],
            pct(r["cov"], r["lines"]), pct(r["hcov"], r["headings"]),
            pct(r["rcov"], r["lines"]))
        if spec_rel:
            line += " %s |" % pct(r["rcov_plus"], r["lines"])
        line += " %s |" % (pct(r["tcov"], r["clauses"]) if r["tcov"] is not None else "—")
        line += " %s |" % (pct(r["solo"], r["leaf_clauses"]) if r["leaf_clauses"] else "—")
        print(line)
    line = "| **Total** | | %d | %s | %s | %s |" % (
        total["clauses"], pct(total["cov"], total["lines"]),
        pct(total["hcov"], total["headings"]), pct(total["rcov"], total["lines"]))
    if spec_rel:
        line += " %s |" % pct(total["rcov_plus"], total["lines"])
    line += " %s |" % pct(total["tcov"], total["clauses_spec"])
    line += " %s |" % (pct(total["solo"], total["leaf_clauses"]) if NORM_ENABLED else "—")
    print(line)
    print()
    if spec_rel:
        print("rcov+ = rcov with the references in %s (%s) added as incoming edges: %d references." % (
            spec_rel, sid or "given path", len(spec_refs)))
        newly = sorted(i for r in rows for i in r["covered_by_sprint"])
        print("Clauses that become referenced only through the sprint references: %s" % (
            ", ".join(newly) if newly else "none"))
        print()
    if not NORM_ENABLED:
        print("The solo rate is not counted: docs.normativeDirs / docs.commonFiles is not set.")
    if args.untested:
        n_untested = total["clauses_spec"] - total["tcov"]
        print("Clauses in %s that no test references (%d):" % (SPEC_DIR.rstrip("/"), n_untested))
        for r in rows:
            if r["untested"]:
                print("- %s: %s" % (r["file"], " ".join(r["untested"])))
        print()
    n_unref = total["clauses"] - total["rcov_clauses"]
    if not args.unreferenced:
        print("Unreferenced clauses: %d. Add --unreferenced to see the IDs." % n_unref)
        return 0
    print("Unreferenced clauses (no reference from anywhere in the base specification. %d):" % n_unref)
    for r in rows:
        if r["unreferenced"]:
            print("- %s: %s" % (r["file"], " ".join(
                "%s (%s)" % (i, nodes[i]["title"]) for i in r["unreferenced"])))
    return 0


if __name__ == "__main__":
    sys.exit(main())
