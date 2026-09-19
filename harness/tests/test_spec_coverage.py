"""Tests for harness/tools/spec-coverage.sh (spec-coverage.py): clause reference
coverage of the base specification — cov / rcov / tcov / solo — computed from
spec-graph.py's index.

Python 3 standard library only (unittest + tempfile + subprocess). Every
fixture corpus is built from scratch in a temporary directory and the tool is
pointed at it with CLAUDE_PROJECT_DIR (env.sh's sprint_root) so nothing here
depends on the project the harness was copied out of.

The fixture writes sprint.config.json because spec-coverage.py reads all of
its paths from there (docs.sprintRoot / docs.specDir, and optionally
docs.normativeDirs / docs.commonFiles for the solo rate).
"""
import json
import os
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
SPEC_COVERAGE_SH = REPO_ROOT / "harness" / "tools" / "spec-coverage.sh"


def write_file(root: Path, rel_path: str, lines) -> Path:
    file_path = root / rel_path
    file_path.parent.mkdir(parents=True, exist_ok=True)
    file_path.write_text("\n".join(lines), encoding="utf-8")
    return file_path


def write_config(root: Path, normative=False) -> None:
    docs = {
        "templates": "docs/06_process/templates",
        "livingDirs": [
            "docs/03_design",
            "docs/05_specifications",
        ],
        "sprintRoot": "docs/07_plans",
        "specDir": "docs/05_specifications",
    }
    if normative:
        docs["normativeDirs"] = ["docs/03_design"]
        docs["commonFiles"] = ["docs/05_specifications/README.md"]
    cfg = {
        "schemaVersion": 1,
        "project": {"name": "fixture"},
        "docs": docs,
        "tasks": [],
        "components": {"app": {"tests": ["app/src/**/*.test.ts"]}},
        "evidence": {"dir": ".sprint/test-result"},
        "sets": {},
        "gateToolsDirs": [],
        "gates": {},
    }
    write_file(root, "sprint.config.json", [json.dumps(cfg, indent=2)])
    write_file(root, ".gitignore", ["node_modules/"])


def write_fixture(root: Path, normative=False) -> None:
    """05 x.md (XX-1, XX-2), 05 README.md (RULE-1, refers to XX-2),
    03 d.md (DD-1), and a test file whose name refers to XX-1.
    XX-1 is test-referenced only; XX-2 is doc-referenced only; DD-1 is
    outside specDir."""
    write_config(root, normative=normative)
    write_file(root, "docs/05_specifications/x.md", [
        "---", "xref-prefix: XX", "---", "# X", "",
        "## [XX-1] Clause 1", "", "Body 1.", "",
        "## [XX-2] Clause 2", "", "Body 2.", "",
    ])
    write_file(root, "docs/05_specifications/README.md", [
        "---", "xref-prefix: RULE", "---", "# README", "",
        "## [RULE-1] References", "", "A clause reference takes [[XX-2]] as an example.", "",
    ])
    write_file(root, "docs/03_design/d.md", [
        "---", "xref-prefix: DD", "---", "# D", "",
        "## [DD-1] Design clause", "", "Body.", "",
    ])
    write_file(root, "app/src/a.test.ts", [
        "import { describe, it, expect } from 'vitest'", "",
        "describe('[[XX-1]] test of a', () => {",
        "  it('check', () => {",
        "    expect(1).toBe(1)",
        "  })",
        "})", "",
    ])


def run_coverage(root: Path, *args):
    env = dict(os.environ)
    env["CLAUDE_PROJECT_DIR"] = str(root)
    for key in ("SPRINT_CONFIG", "SPEC_GRAPH_ROOT", "SPRINT_GATE"):
        env.pop(key, None)
    return subprocess.run(
        ["bash", str(SPEC_COVERAGE_SH), *args],
        cwd=str(root), env=env, capture_output=True, text=True,
    )


def row_cols(stdout: str, needle: str):
    line = next(l for l in stdout.split("\n") if needle in l)
    return [c.strip() for c in line.split("|")]


class SpecCoverageTest(unittest.TestCase):
    def setUp(self):
        self.root = Path(tempfile.mkdtemp(prefix="csp-spec-coverage-")).resolve()

    def tearDown(self):
        shutil.rmtree(self.root, ignore_errors=True)

    def test_tcov_column_and_rcov_ignore_test_references(self):
        write_fixture(self.root)
        result = run_coverage(self.root, "--no-sprint")
        self.assertEqual(result.returncode, 0, result.stderr)

        header = row_cols(result.stdout, "| File")
        tcov = header.index("tcov")
        rcov = header.index("rcov(lines)")
        solo = header.index("solo")

        x = row_cols(result.stdout, "docs/05_specifications/x.md")
        self.assertEqual(x[tcov], "1/2 (50%)")
        # rcov counts only .md edges: README refers to XX-2, the test refers to XX-1.
        self.assertEqual(x[rcov], "2/5 (40%)")
        # No normativeDirs / commonFiles in the config: solo is not computed.
        self.assertEqual(x[solo], "—")

        readme = row_cols(result.stdout, "docs/05_specifications/README.md")
        self.assertEqual(readme[tcov], "0/1 (0%)")

        d = row_cols(result.stdout, "docs/03_design/d.md")
        self.assertEqual(d[tcov], "—")

        total = row_cols(result.stdout, "**Total**")
        self.assertEqual(total[solo], "—")
        self.assertIn("The solo rate is not counted: docs.normativeDirs / docs.commonFiles is not set.", result.stdout)

    def test_untested_lists_specdir_clauses_by_file(self):
        write_fixture(self.root)
        result = run_coverage(self.root, "--no-sprint", "--untested")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("docs/05_specifications/x.md: XX-2", result.stdout)
        self.assertNotIn("XX-1", result.stdout.split("that no test references")[1].split("Unreferenced")[0])
        self.assertNotIn("DD-1", result.stdout.split("that no test references")[1].split("Unreferenced")[0])

    def test_json_has_tcov_and_untested(self):
        write_fixture(self.root)
        result = run_coverage(self.root, "--no-sprint", "--json")
        self.assertEqual(result.returncode, 0, result.stderr)
        data = json.loads(result.stdout)
        files = {f["file"]: f for f in data["files"]}
        self.assertEqual(files["docs/05_specifications/x.md"]["tcov"], 1)
        self.assertEqual(files["docs/05_specifications/x.md"]["untested"], ["XX-2"])
        self.assertIsNone(files["docs/03_design/d.md"]["tcov"])
        self.assertEqual(data["total"]["clauses"], 4)

    def test_solo_rate_uses_normative_config(self):
        write_fixture(self.root, normative=True)
        result = run_coverage(self.root, "--no-sprint")
        self.assertEqual(result.returncode, 0, result.stderr)
        header = row_cols(result.stdout, "| File")
        solo = header.index("solo")
        # x.md is a leaf under specDir. Neither XX-1 nor XX-2 refers to the
        # normative layer (03_design, 05 README), so both are solo.
        x = row_cols(result.stdout, "docs/05_specifications/x.md")
        self.assertEqual(x[solo], "2/2 (100%)")
        # README.md is a commonFiles entry, d.md is under normativeDirs: not leaves.
        self.assertEqual(row_cols(result.stdout, "docs/05_specifications/README.md")[solo], "—")
        self.assertEqual(row_cols(result.stdout, "docs/03_design/d.md")[solo], "—")
        self.assertNotIn("The solo rate is not counted", result.stdout)

    def test_sprint_spec_adds_rcov_plus(self):
        write_fixture(self.root)
        write_file(self.root, "docs/07_plans/01_a/SPEC.md", [
            "# SPEC", "", "This sprint implements [[XX-1]] and [[DD-1]].", "",
        ])
        result = run_coverage(self.root, "--spec", "docs/07_plans/01_a/SPEC.md")
        self.assertEqual(result.returncode, 0, result.stderr)
        header = row_cols(result.stdout, "| File")
        self.assertIn("rcov+(lines)", header)
        rp = header.index("rcov+(lines)")
        x = row_cols(result.stdout, "docs/05_specifications/x.md")
        self.assertEqual(x[rp], "4/5 (80%)")
        self.assertIn("Clauses that become referenced only through the sprint references: DD-1, XX-1", result.stdout)


if __name__ == "__main__":
    unittest.main()
