---
name: spec-coverage
description: Reports the clause reference coverage of the base specification (the md files with clauses in docs.livingDirs) per file. cov (clause rate, in 2 forms, lines and headings), rcov (referenced rate = the share of lines of referenced clauses), tcov (test-referenced rate = the share of docs.specDir clauses that test names reference), rcov+ that includes the SPEC.md of a given sprint (the active sprint by default), and the solo rate (the share of leaf specifications that reference nothing in the normative and common layer; only when docs.normativeDirs / docs.commonFiles exist). Use this skill when the user says "spec coverage", "cov", "rcov", "referenced rate", "unreferenced clauses", "orphan clauses", "which clauses are not used", "which parts of the base specification does this sprint reference", "which clauses have no tests", or "tcov". Code coverage of tests (lcov) is not this skill.
---

# Specification coverage (cov / rcov / tcov)

Run `bash harness/bin/sprint spec-coverage` **only once**. Select the arguments from the table below. Do not try more than one set of arguments.

```bash
bash harness/bin/sprint spec-coverage [arguments]
```

| What the user says | Arguments to add |
|---|---|
| "spec coverage", "cov and rcov", "what about the current sprint", with no sprint given | None (reflect the active sprint in rcov+) |
| "for 1-3", "taking sprint 1-3 into account" | `--sprint 1-3` |
| The user gives the path of a SPEC.md | `--spec <path>` |
| "base specification only", "regardless of the sprint" | `--no-sprint` |
| "which clauses are not referenced", "list of orphan clauses" | `--unreferenced` (you can combine it with a sprint argument) |
| "which clauses have no tests", "clauses that tests do not reference" | `--untested` (prints, per document, the IDs of the docs.specDir clauses that no test name references) |
| "in JSON", "I want to process it by machine" | `--json` |

Show the output (the per-file table, the total, and the notes at the end) on screen as is. Do not round numbers. Do not omit rows.

| Metric | Definition |
|---|---|
| cov(lines) | The share of lines that are in clause ranges (non-empty lines, frontmatter excluded). The more explanatory text outside the clauses, the lower the value |
| cov(headings) | The share of headings that have a clause ID (`##` to `####`, outside code fences) |
| rcov(lines) | The share of lines of the clauses that living documents (outside docs.sprintRoot) reference |
| rcov+(lines) | rcov with all references of the sprint SPEC.md added as incoming edges |
| tcov | For each document in docs.specDir: the number of clauses that test files (`[[ID]]` in test names) reference / the number of clauses. A document outside specDir shows `—`. rcov / rcov+ / solo do not count test references |
| solo | The share of clauses that reference no part of the normative and common layer (docs.normativeDirs and docs.commonFiles). The targets are only the leaf specifications in specDir. With no setting, every row shows `—` |

This is an evaluation metric. It does not fail. The definitions of metrics and commands are in `docs/06_process/spec-metrics.md`. How to choose refactoring targets from the values is in `docs/04_standards/03_spec-structure.md`.
