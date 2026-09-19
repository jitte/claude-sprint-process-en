"""harness/lib/config.py — reading sprint.config.json (the source of truth for python).

spec-graph.py / clause-anchors.py import this. For bash, see config.sh. The glob rules are the same in both.

    import config
    cfg = config.load(root)            # dict. Missing file or wrong schemaVersion → SystemExit(4)
    config.glob_match(glob, path)      # bool
    config.glob_files(root, globs)     # list of files relative to root (excludes the trees under the `name/` directories of .gitignore)

CLI (entry point for the tests):
    python3 config.py glob-match <glob> <path>   0 on match / 1 on no match
"""
import json
import os
import re
import sys

SCHEMA_VERSION = 1


def config_path(root):
    return os.environ.get("SPRINT_CONFIG") or os.path.join(root, "sprint.config.json")


def load(root):
    p = config_path(root)
    if not os.path.isfile(p):
        print("sprint.config.json not found: %s" % p)
        sys.exit(4)
    with open(p, encoding="utf-8") as f:
        cfg = json.load(f)
    v = cfg.get("schemaVersion")
    if v != SCHEMA_VERSION:
        print("sprint.config.json schemaVersion %s is not supported (supported: %d)" % (v, SCHEMA_VERSION))
        sys.exit(4)
    return cfg


def abs_path(root, p):
    return p if os.path.isabs(p) else os.path.join(root, p)


def glob_regex(glob):
    """glob → regex. **/ → (.*/)? / ** → .* / * → [^/]* / ? → [^/]. Other characters are literal."""
    out = []
    i = 0
    n = len(glob)
    while i < n:
        c = glob[i]
        if c == "*" and i + 1 < n and glob[i + 1] == "*":
            if i + 2 < n and glob[i + 2] == "/":
                out.append("(.*/)?")
                i += 3
            else:
                out.append(".*")
                i += 2
            continue
        if c == "*":
            out.append("[^/]*")
        elif c == "?":
            out.append("[^/]")
        else:
            out.append(re.escape(c))
        i += 1
    return "^" + "".join(out) + "$"


def glob_match(glob, path):
    return re.match(glob_regex(glob), path) is not None


def _glob_prefix(glob):
    parts = []
    for seg in glob.split("/"):
        if any(ch in seg for ch in "*?["):
            break
        parts.append(seg)
    return "/".join(parts)


def ignored_dirs(root):
    """Directory names excluded from the scan. The `name/` lines of <root>/.gitignore (no wildcards and no / in the middle).
    Do not scan directories excluded from version control (where dependencies and generated files go). The tool holds no names."""
    p = os.path.join(root, ".gitignore")
    out = set()
    if not os.path.isfile(p):
        return out
    with open(p, encoding="utf-8") as f:
        for ln in f:
            ln = ln.split("#", 1)[0].strip()
            if not ln or ln.startswith("!") or ln.startswith("/") or any(ch in ln for ch in "*?["):
                continue
            if not ln.endswith("/"):
                continue
            ln = ln[:-1]
            if "/" in ln:
                continue
            out.add(ln)
    return out


def glob_files(root, globs):
    out = set()
    skip = ignored_dirs(root)
    for g in globs:
        prefix = _glob_prefix(g)
        base = os.path.join(root, prefix) if prefix else root
        if not os.path.isdir(base):
            continue
        rx = re.compile(glob_regex(g))
        for dirpath, dirnames, filenames in os.walk(base):
            dirnames[:] = sorted(d for d in dirnames if d not in skip)
            for fn in sorted(filenames):
                rel = os.path.relpath(os.path.join(dirpath, fn), root)
                if rx.match(rel):
                    out.add(rel)
    return sorted(out)


def component_globs(cfg, kind):
    globs = []
    for comp in cfg.get("components", {}).values():
        globs.extend(comp.get(kind, []))
    return globs


if __name__ == "__main__":
    args = sys.argv[1:]
    if len(args) == 3 and args[0] == "glob-match":
        sys.exit(0 if glob_match(args[1], args[2]) else 1)
    print("usage: config.py glob-match <glob> <path>")
    sys.exit(2)
