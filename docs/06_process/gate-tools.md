---
xref-prefix: GATE
---

# Gate tools

> The specification of the tools that verify the completion conditions by machine at stage transitions.
> The meaning of the stages and the transition rules are in `docs/06_process/sprint-process.md`.

---

<a id="GATE-1"></a>
## [GATE-1] 1. Mechanism

| Part | Location | Role |
|------|------|------|
| Runner | `harness/tools/gate-check.sh` | Reads the tool list of the stage and runs the tools in order. If any one tool fails, the whole run fails |
| Definition (source of truth) | `gates` in `sprint.config.json` | `{ "code": {...}, "docs": {...} }`. For each kind, it holds an array of tool names for each stage |
| Tool location | `gateToolsDirs` in `sprint.config.json` | An array of directories. The runner looks for `<dir>/<tool>.sh` in this order and uses the first one that it finds. If it finds none, "script not found" and infra (4) |
| Tools (generic) | `harness/gate-tools/<tool>.sh` (the first entry of `gateToolsDirs`) | The runner starts them without arguments. They return the result as an exit code. In a manual run, arguments narrow the checks. They do not depend on the domain, the technology names, or the layout of the project (they read these from the settings) |
| Tools (project-specific) | The second and later entries of `gateToolsDirs` | Same launch convention. Put the checks that depend on the project domain here |

`harness/bin/sprint stage <STAGE>` calls the runner automatically when it advances. For a manual run, use `bash harness/bin/sprint gate <STAGE>`.

- kind is `sprints[id].kind` in `.sprint/flags.json` (`code` when not set). `gate-check.sh` selects the gate set by kind
- The runner exports `SPRINT_GATE=1` before the loop. A tool reads this with `sprint_via_gate` in `harness/lib/env.sh` to tell a manual run from a run through the gate (example: `size-audit` treats 🟡 as a failure in a manual run and as a pass through the gate)
- When `sprint.config.json` does not exist, the runner and the tools print 1 line "sprint.config.json not found: <path>" and return infra (4)
- Tools do not know the stage. A check whose strictness changes by stage is a separate tool (`tdd-exists` / `tdd-audit`, `spec-lint` / `spec-seal`)

### Failure classes and recommended stages

The runner classifies gate failures into 4 classes and shows the recommended stage. It does not execute the transition. A human decides the rollback target.

| Exit code | Class | Meaning | Recommended stage |
|---|------|------|----------|
| 1 | spec | SPEC/TEST missing, seal mismatch, format errors, broken clause references | PLAN |
| 2 | impl | lint / typecheck / build failures, deliverable documents not written (docs) | BUILD |
| 3 | test | test failures, skips, missing execution evidence | BUILD |
| 4 | infra | tests not run, stale result files, missing entries | stay (repair in the current stage) |

The tools whose class changes with the failure content (`results` / `impl-sync` / `tdd-audit` / `size-audit`) return 2 to 4 themselves. Other non-zero codes follow `default_class()` in `gate-check.sh`. When several classes occur at the same time, the most upstream class (the smallest number) is the basis of the recommendation.

## 2. Tool list (12 generic tools)

The stage assignment is read from `gates` in `sprint.config.json`. It is not copied here.

| Tool | Purpose | Arguments (to narrow a manual run) | Specification |
|--------|------|------|------|
| `spec-files-exist` | Checks that SPEC.md / TEST.md exist | — | — |
| `spec-seal` | The seal hashes match (`bash harness/bin/sprint seal-verify`) | — | [PROC-2](sprint-process.md#PROC-2) |
| `spec-lint` | Clause references V1 to V3 / V5 / V6 / V8 to V11, the test handling in the "0. Referenced common clauses" section of SPEC, the Test ID format | `graph` / `refs` / `test-id` | §3.1 |
| `impl-sync` | Two-way comparison of the implementation set and the specification set (public routes) | `routes` | §3.2 |
| `verify` | The tasks in the settings (lint / typecheck / build / test / e2e) pass. Not assigned to a gate (`results` judges from the evidence). For manual runs | task name | §3.3 |
| `results` | Freshness and green state of the execution evidence. Reads only the JSON of the evidence contract (§6) | `fresh` / `green` | §3.4 |
| `tdd-exists` | The Test IDs of TEST.md exist in the test sources (skips are allowed. For BUILD) | — | §3.5 |
| `tdd-audit` | The Test IDs pass in the execution evidence | — | §3.5 |
| `size-audit` | 801 to 1200 lines: passes and reports. 1201 lines or more: rejects (change the limits with `SIZE_WARN` / `SIZE_LIMIT`) | — | — |
| `doc-exists` | The deliverable documents that README lists exist (docs) | — | §3.6 |
| `doc-verified` | In the verdict table of the UNSEAL of TEST.md, the verdict of the latest round is 🟢 (docs) | — | §3.6 |
| `ship-closed` | The commit hash is filled in in the "8. SHIP" section of README | — | — |

## 3. Tool specifications

### 3.1 spec-lint — machine check of the specification

The tool runs all 4 checks and then aggregates the results. The failure class is 1 (spec). Roll back to PLAN and fix the problem.

<a id="GATE-2"></a>
#### [GATE-2] 3.1.1 graph — verification of clause references

**Do not restate the common items of the base specification. Reference them with `[ID](<relative path>#ID)`.** When the same norm is written in several specification documents, the places where it is written are kept, and the places where it is missing break. Define a common norm only once, as 1 clause. The notation is in [RULE-1](../05_specifications/README.md#RULE-1).

`harness/tools/spec-graph.sh verify` (the implementation is `harness/tools/spec-graph.py`) verifies the following.

| # | Verification | Fail condition |
|---|------|----------|
| V1 | Uniqueness of prefixes | 2 files declare the same `xref-prefix` |
| V2 | Uniqueness of clause IDs | The same ID is declared 2 times / the prefix of an ID is different from the file declaration |
| V3 | The targets of references exist | The clause that a reference points to does not exist |
| V5 | impl paths exist | `impl` in the frontmatter is a path that does not exist |
| V6 | frontmatter | `xref-prefix` is not 2 to 6 uppercase ASCII letters / `layer` exists and its value is not one of the 7 values / an md that has clause headings `[ID]` has no `xref-prefix` |
| V8 | The relative paths of links exist | The file that the relative path of a reference link points to does not exist |
| V9 | Anchors exist | The target file has no matching `<a id>` |
| V10 | Reference cycles | The clause reference graph (node = clause, edge = reference in the clause text → clause) has a strongly connected component. A self-reference is also a cycle. 1 line per component: `A -> B -> A` |
| V11 | Section number references | In a line outside code fences, § comes within 8 characters after a file name (`.md`) (pattern 1). Or § and a number come right after an identifier-shaped word (joined with `_` or `-`, 2 or more uppercase letters, or 2 or more digits) or an alias in the `docs.docAliases` setting (pattern 2. A reference by abbreviation). Section numbers after an ordinary word, and section numbers in the same file, are out of scope. The output form is `file:line` |

- Verification scope: the files that have clauses = the md files (README.md included) among the living documents that declare `xref-prefix` in the frontmatter. The `docs.livingDirs` key of `sprint.config.json` is the source of truth for the directory list, and `xref.sh` and `clause-anchors.py` read the same list. Folders and `layer` do not matter. The md files in the directories that hold procedure documents do not declare `xref-prefix` (they are still scanned as referrers). V1/V2/V5/V6/V10 look at this set. V3/V8/V9/V11 verify these referrers: the living documents (templates included) + the unsealed sprint SPECs + the md files at the repository root. V8/V9 exclude the files under `docs.templates` (templates write relative paths for the depth of the copy destination, so the paths do not resolve at the location of the template itself). An md that does not declare `xref-prefix` is treated as a consumer. It can reference all clauses (it is not an edge of V10)
- **V3 also uses test names ([TSTD-6](../04_standards/02_testing.md#TSTD-6)) as referrers. V8 / V9 / V11 do not apply to tests.** The test files are the files that match the globs of `components[*].tests` in `sprint.config.json` (except the files under directories that `.gitignore` lists as directory names). The tool reads only the `[[ID]]` in lines that start, after leading whitespace, with `describe(` / `it(` / `test(` (the form followed by 0 or more `.identifier` parts, for example `test.describe(` / `it.each(`). When such a line ends with `(`, the tool joins the next line and reads it. It does not read comments, fixture strings, or test bodies. `index` / `reverse` / `diff` / `files` / `deps` output the test references in the same form as the document references (in the edges of `index`, `from` is null). `layers` counts only the references between files that have clauses
- **Sealed sprint SPECs are not verified as referrers** (they are historical records and are not rewritten)
- A sprint SPEC declares the clauses that it follows in the "0. Referenced common clauses" section of SPEC.md (template)
- `SPEC_GRAPH_ROOT` replaces the scan root. The settings are read from `SPRINT_CONFIG` (the default is `<scan root>/sprint.config.json`) (fixture test `harness/tests/test_runner.py`)

Helper commands (not part of the gate):

| Command | Output |
|---------|------|
| `spec-graph.sh files` | 1 line for each file that has clauses: relative path, prefix, layer (`-` when there is none), number of clauses, number of references to it |
| `spec-graph.sh layers` | A table of reference edge counts: referrer layer × target layer. The direction is an indicator. It does not cause a fail |
| `spec-graph.sh reverse <ID>` | Reverse lookup of the referrers (impact range) |
| `spec-graph.sh deps <FILE>` | The clauses that the file references |
| `spec-graph.sh resolve <FILE>` | Outputs the source text and the text of each clause reachable from it, 1 time for each clause. qa uses it to judge whether the "handling" in §0 is valid. A cycle terminates and gets a note (`<!-- resolve: cycle ... -->`) |
| `spec-graph.sh diff <git-ref>` | The clauses whose content changed, and their referrers (stale detection. A notice that does not cause a fail). The range of a clause starts at its declaration line and ends before the declaration line of the next clause (or before a heading line at the same or a higher level). The trailing anchor line (`<a id=…>`) and blank lines are not included. When you add a new clause, the clause before it does not appear in changed |

**Limits of machine checks**: The graph stops gaps in the reference structure. It does not stop errors in the meaning of the clause text (identifiers that do not exist, reversed directions). qa reads the text and reconciles it ([TSTD-2](../04_standards/02_testing.md#TSTD-2)).

<a id="GATE-3"></a>
#### [GATE-3] 3.1.2 refs — test handling of referenced clauses

**For each referenced clause, declare how tests handle it.** If each reference required 1 test, tests would become a quota, and branches that always pass and trivial checks would appear. It would also create a motive to copy text instead of referencing it. Copying is the problem that clause references try to solve. So the check enforces a record of the judgment, not a test.

The tool checks the "0. Referenced common clauses" section (`## 0. Referenced common clauses`) of SPEC.md of the active sprint.

| # | Fail condition |
|---|----------|
| 1 | There is no §0 heading (you cannot bypass the check by omitting the whole section) |
| 2 | §0 has neither a clause-reference table row nor a `(no references)` row (only the new notation is accepted. Rows in the old double-bracket notation are not counted as table rows) |
| 3 | The "Test handling" column or the "Test ID / reason" column is empty (empty = empty string, whitespace only, `—`, `-`, `TBD`) |
| 4 | The value of the "Test handling" column is not one of the 4 values (new / modify / reuse / none) |

- **The machine checks only the form.** qa judges whether the handling is valid in REVIEW with `resolve`, and records the result in "Audit of referenced clauses" of the "4. REVIEW" section of README. In DOCS, qa reconciles the declarations with the actual changes by `diff` (R10 / D4 of qa.md)
- **Do not relax the fail conditions later**
- A sprint with no references writes 1 row: `| (no references) | — | none | Does not depend on common clauses |`. Its first column is not in clause-reference form, so conditions 3 and 4 do not apply, and only the record of the judgment remains
- The tool reads only 1 file, the `SPEC.md` of the active sprint. It does not read sealed past SPECs. When you roll back a past sprint and unseal it, change its §0 to the new notation
- Check 3 of `spec-check.sh` (definitions ↔ references of Test IDs) excludes the §0 table. §0 always contains Test IDs of other sprints, so if the check included §0, the comparison would break
- The Test IDs of old sprints are not unique (sealed sprints use the old form `TEST-x.x`). Quote them in the form `<sprint_id> TEST-x.x`
- `SPEC_REFS_TARGET` replaces the target (fixture test `harness/tests/test_spec_graph.py`)

<a id="GATE-4"></a>
#### [GATE-4] 3.1.3 test-id — Test ID format

**Write Test IDs in the form `TEST-<sprint_id>-<major>.<minor>`.** Example: `TEST-3-1.1`.

`<sprint_id>` is the active value in `.sprint/flags.json`. You can number `<major>` / `<minor>` from 1 in each sprint. The prefix makes IDs unique across all sprints, so no collisions occur in long-lived test files.

The tool checks that every ID in the test definition rows (the rows whose first cell is a Test ID) of TEST.md of the active sprint has this form.

- **Do not rewrite IDs in the old form (without the prefix).** Their form is different, so they do not collide with the new form
- `TDD_ID_PATTERN` matches both the new and the old form (`TEST-[0-9]+(-[0-9]+)*\.[0-9]+[a-z]?`)
- `DOC-x.x` of kind=docs is out of scope (it passes as a file with no test definition rows)
- `TID_TEST_MD` / `TID_SPRINT_ID` replace the target

### 3.2 impl-sync — two-way comparison of the implementation set and the specification set

**Detect by machine when the specification becomes stale in the implementation → specification direction.** `spec-lint` looks only at changes on the clause side, and V5 looks only at whether paths exist. When public routes are added or removed, the specification becomes old without a warning.

The check is `routes` (§3.2.1). The check returns the failure class (1 = spec / 2 = impl / 4 = infra). Put project-specific checks that compare implementation ↔ specification sets in the same framework in the second and later entries of `gateToolsDirs`. `gates` in `sprint.config.json` calls them as separate tools.

- It runs only at the TEST gate. At REVIEW there is no implementation, so the implementation set cannot be obtained. Do not also put it at DOCS / SHIP (if you put it in 2 places, only 1 of them gets updated)
- **Do not read the implementation set with regular expressions.** Import the implementation and make it output the set. TypeScript object keys can be written in 3 ways, `'x':` / `"x":` / `x:`, and braces also appear in comments, strings, and regular expression literals. Regular expressions cannot list all the variants, and the elements that they miss disappear from the set without a warning. **Do not silently pass failures that shrink the set.** If you do, the gate itself hides the state that it must detect: "the implementation grew, but the specification did not follow"
- If you reimplement in another language or framework, you replace only the fetch command

<a id="GATE-5"></a>
#### [GATE-5] 3.2.1 routes — public route set

`bash harness/bin/sprint api-routes` (= `harness/tools/api-routes.sh verify`) compares, in both directions, the public route set of the implementation with the route set that `docs.specDir` describes. The notation is in [RULE-1](../05_specifications/README.md#RULE-1) "How to write API routes and the `api-routes` declaration".

| Side | How to get it |
|----|-------|
| Implementation | The default fetch command is `sets.routes.implCmd` in `sprint.config.json` (it runs with `bash -c` at the project root). Set a command that imports the routing definitions of the implementation and outputs the route list. Regular expressions cannot follow nested route registrations or factory functions |
| Specification | Extract `<METHOD> <path>` from the Markdown files under `docs.specDir`. `README.md` is out of scope |

Express the exclusion and expansion rules only with ` ```api-routes ` fence declarations in the specification (`expand` / `alias`) and normalization rules that do not depend on route names. **The script contains no route names at all.**

| # | Normalization / exclusion | Reason |
|---|------------|------|
| 1 | Allow 1 or more spaces between the method and the path | Column alignment in code blocks |
| 2 | Cut the path token at the longest match of `A-Z a-z 0-9 / : { } _ . - *` | The specification writes paths inside prose that contains fullwidth parentheses, middle dots, and square brackets. If the tool reads up to a space, false positives occur |
| 3 | Extract paths with or without `/api/v1`, and normalize them to the form without it | The "APIs used" table of the screen specifications uses the short form |
| 4 | Collapse path parameters to `/:p` | Treat `:id` in the specification and `:transactionId` in the implementation as the same |
| 5 | Exclude the paths that contain `*` from the specification side | `GET /masters/*` is a generic notation and does not point to a single route |
| 6 | Exclude the inside of ` ```mermaid ` fences | The participant names in diagrams are not API definitions |
| 7 | Exclude the inside of ` ```api-routes ` fences | They are declarations, not definitions |

- Failure classes: **1 = In the implementation but not in the spec** → roll back to PLAN and write the clause. **2 = In the spec but not in the implementation** → return to BUILD and implement. When there are differences in both directions, 1 has priority (the specification is upstream)
- Each line of `In the spec but not in the implementation` includes the source file name and line number
- **Do not add vocabulary to the declarations that allows unimplemented or undescribed routes.** Also fail declarations that match nothing (placeholders that are not used, implementation paths that do not exist)
- **Do not put declarations on the implementation side (code, comments, settings).** The reading scope is limited to the files under `docs.specDir`
- `API_ROUTES_IMPL_CMD` (the command that fetches the implementation routes. `sets.routes.implCmd` when not set) and `API_ROUTES_ROOT` (the start point of the specification scan. The project root when not set. `docs.specDir` is relative to this start point) replace the fetch procedure. Environment variables have priority over the settings (fixture tests `harness/tests/test_api_routes.py`, `harness/tests/test_runner.py`)

### 3.3 verify — the implementation and the tests pass

The tool runs `bash harness/bin/sprint run <task>` in the order of `tasks` in the settings (lint → typecheck → build → test → e2e). It judges with the JSON of the evidence contract (§6) and stops at the first task that fails. The failure class is 2 (impl).

| task | errors / failed | warnings / skipped | Result |
|---|---|---|---|
| lint / typecheck / build | errors > 0 | — | fail (you must fix it. No override) |
| lint / typecheck / build | 0 | warnings > 0 | fail. Passes only with `GATE_ALLOW_WARN=1` (the user decides go) |
| test / e2e | failed > 0 | — | fail |
| test / e2e | 0 | skipped > 0 | fail |
| All 0 and status = pass | | | pass |

- `bash harness/bin/sprint run all` is the completion condition of BUILD. It runs all the tasks in the order of tasks (fail-fast per verb)
- This tool is not assigned to a gate. A full rerun takes 3 to 5 minutes per transition, and `results` right after it checks the same evidence, so the work is duplicated. At the TEST gate, `results` judges from the execution evidence (freshness, green, skip)

### 3.4 results — execution evidence

The tool runs both checks and then aggregates the results. The check returns the failure class (if there are several, the most upstream one).

| Check | What it looks at | Failure class |
|------|---------|---------|
| `fresh` | For every `(component, task)` in the settings, the evidence file `<evidence.dir>/<component>.<task>.json` exists, and its `finished_at` is equal to or later than the last modification of the files that match `src` ∪ `tests` of all components | 4 (infra. A rerun fixes it) |
| `green` | The evidence `status` is `pass`. For test / e2e, `counts.failed` = 0 and `counts.skipped` = 0. For lint / typecheck / build, `errors` = 0 and `warnings` = 0 (with `GATE_ALLOW_WARN=1`, warnings are not checked). The check does not read `.sprint/test-fails.json` (the hook writes it only just after a Bash call of main, and it becomes old after a rerun inside the gate. It is used only for the `bash harness/bin/sprint status` display) | 2 (lint / typecheck / build) / 3 (test / e2e failures, skips) / 4 (no evidence) |

The tool does not read `.partial.json` (the evidence of a partial run. §5). The "evidence freshness" of `bash harness/bin/sprint status` uses the same judgment as `fresh`.

The code that reads the evidence is only in `harness/lib/evidence.sh`. It reads only the JSON of the evidence contract (§6). It does not read the output strings of the runner. `results` / `verify` / `tdd-audit` / `record-test-fails.sh` / `sprint status` call it.

<a id="GATE-7"></a>
### [GATE-7] 3.5 tdd-exists / tdd-audit — test execution evidence

These tools guarantee that the planned tests (the Test IDs of TEST.md) are not ignored, always run, and pass. The only basis of the verdict is "what happened when the tests ran" (`tests[]` of the evidence contract JSON. §6), not "how the test code is written" (static matching with grep).

Static matching becomes an endless chase against the variants of writing: changes in skip syntax, commenting out, implicit disabling with `.only`, IDs written in comments, and piggybacking on a same-named Test ID of a past sprint. With grep, all of these cause missed detections or false detections. With execution evidence, all of them fail with a single verdict: "the run results have no record that satisfies the requirement".

**Mechanism:**

1. Continuous output of execution evidence: `bash harness/bin/sprint run test` / `run e2e` write the evidence contract JSON (`<evidence.dir>/<component>.<task>.json`. `tests[]` has the file, the name, and the status of every test) through `convert-evidence` of the adapter (§5 / §6)
2. Matching (`tdd-audit.sh`): the tool collects `tests[]` of the evidence of every `(component, test|e2e)` in the settings. For each test definition row of TEST.md (a table row whose first cell is a Test ID), it requires a record "the test name contains the ID and status=passed" in the test file listed in the row (matched by basename). It does not read `.partial.json`. If there is no evidence at all, infra (4)
3. Fail conditions: no record (MISSING) / skipped, todo, failed, flaky (NOT-PASS) / no test file listed in the row (FORMAT)

`tdd-exists.sh` is the lenient version for BUILD. It only checks that the Test ID exists in the test sources (the files that match the globs of `components[*].tests`) (skips are allowed). The strictness is different, so it is a separate tool.

**TEST.md conventions** (already in the template):

- A test definition row must have a test file column. The ID is matched only inside that file (it does not collide with a same-named ID of a past sprint)
- Put the Test ID in the run name of the test (the joined name of `describe` and `it`/`test` = the fullName of the reporter). The basic form is to write the ID directly in the `it()` name. A wrapper `describe('TEST-x.y ...')` also matches. **IDs in comments are not matched**
- Do not assign Test IDs to verification items without real tests (line count checks, set checks, manual checks). Write them outside the table. qa measures them in the TEST stage

**Use in other projects**: `tdd-audit.sh` / `tdd-exists.sh` do not know the output format of the runner. `convert-evidence` of the adapter (§5) converts the runner-specific JSON into the evidence contract. Environment variables: `TDD_TEST_MD` (the path of TEST.md. The default is resolved from the active sprint in `.sprint/flags.json`) / `TDD_ID_PATTERN` (the regular expression of Test IDs. The default is the form in §3.1.3).

### 3.6 doc-exists / doc-verified — for documentation sprints

- `doc-exists.sh`: checks that all `docs/…\.md` paths in README (except the sprint's own 07_plans) exist. Failure class 2 (in docs, writing is the equivalent of implementation)
- `doc-verified.sh`: reads the verdict table in the UNSEAL block of TEST.md (the first table that has a "Verdict" column in its header row). It checks that the last row with a verdict (the latest round) is 🟢. Failure class 3. It looks only at table cells. It does not use 🔴 / 🟢 in prose for the verdict. It skips the template rows before entry (🔴🟡🟢) as not filled in

---

## 4. Implementation rules

- **Tools do not know the stage.** Split a check whose strictness changes by stage into separate tools
- **Do not get the implementation set with regular expressions.** Import the implementation and make it output the set (§3.2)
- **Do not weaken a check to make it pass.** Changes that relax fail conditions are prohibited. Additions of declaration vocabulary that allows differences are prohibited
- **Do not put the same check in several stages.** If you put it in 2 places, only 1 of them gets updated
- **Do not write Python inside bash.** Put the implementation in a `.py` file and make the bash script a thin wrapper (`spec-graph.py` / `clause-anchors.py`). Then the script can start alone, and you can write fixture tests for it
- A tool returns the class as an exit code (§1). When the output is empty, the runner adds the exit code
- **Under `set -o pipefail`, do not write "generator `| grep -q`".** `grep -q` stops reading at the first match. When the writer continues to write, the pipeline fails with SIGPIPE (141). For a set membership check, read with a here-string: `grep -qx "$x" <<<"$(generator)"`
- **The harness core (lib, tools, gate-tools, hooks, bin of `harness/`) contains no technology names (runners, package managers) and no project layout.** It reads the layout, components, tasks, evidence, sets, and gates from `sprint.config.json`. Only `harness/adapters/` contains technology names

---

## 5. Task contract and adapters

There are 5 **verbs**: `lint` `typecheck` `build` `test` `e2e`. The order of `tasks` in `sprint.config.json` is the run order of the gates and of `sprint run all`. A component runs only the verbs that it has in `adapters`. A verb that it does not have is "not applicable", not a failure.

An **adapter** is a directory `harness/adapters/<name>/` that has the following executables. Only adapters know technology names (how to start the runner, the output format).

| File | Arguments | Role |
|---|---|---|
| `run-lint` / `run-typecheck` / `run-build` / `run-test` | `[<extra arguments for the runner>...]` | Uses the component directory (`SPRINT_COMPONENT_DIR`) as cwd and starts the runner. Passes stdout and stderr through as is. The exit code is the exit code of the runner. Writes the runner-specific results (for example JSON) to `SPRINT_RAW_DIR` |
| `convert-evidence` | `<verb>` | Reads the runner-specific output in `SPRINT_RAW_DIR` (the text `stdout.txt` and the JSON). Writes the evidence contract JSON (§6) to stdout |

- The verb `e2e` maps to `run-test` of the adapter (the E2E runner is a test runner. The distinction exists for the gates, not for the runner)
- Environment variables that the adapter receives: `SPRINT_ROOT` (project root), `SPRINT_COMPONENT`, `SPRINT_COMPONENT_DIR` (absolute), `SPRINT_TASK` (verb. `e2e` included), `SPRINT_RAW_DIR` (the destination of the runner-specific output. `<evidence.dir>/raw/<component>.<task>/`), `SPRINT_RUN_EXIT` (passed only to `convert-evidence`. The exit code of `run-<verb>`)
- The adapter does not go through `scripts` in `package.json`. It starts the runner binary directly. It does not depend on which package manager is used
- The adapter gives the reporter setting on the CLI. The runner settings of the project need no reporter setting. Before you write an adapter, do 1 trial run to confirm that, for that runner, the CLI setting has priority over the options of the same-named reporter in the configuration file (some runners do not work this way)
- Bundled adapters: `node-vitest` (test), `eslint-tsc` (lint / typecheck), `vite-build` (build), `playwright` (test). `SPRINT_ADAPTERS_DIR` replaces their location (the default is `harness/adapters`) (the entry point for fixture tests)

**Runner** `bash harness/bin/sprint run <task>|all [<component>] [-- <extra arguments>...]`:

1. In the order of `tasks`, the runner processes the components that have `<task>` in `adapters`, in the order of the settings. When `<component>` is given, it processes only that component
2. For each component: if `pre.<task>` exists, the runner runs it with `bash -c` at the project root. If the result is non-zero, it prints "`<component>.<task>`: pre failed (exit n)" and stops with 4. Next, it starts `run-<verb>` of the adapter. It writes stdout and stderr to `<raw>/stdout.txt` and also streams them to the terminal. Next, it writes the output of `convert-evidence <verb>` to `<evidence.dir>/<component>.<task>.json`
3. A run with extra arguments is a partial run. The runner writes its evidence to `<component>.<task>.partial.json`. The gates and `sprint status` do not read it
4. Exit code: 0 when `run-<verb>` of every component returns 0. When any one returns non-zero, the runner runs to the end and then returns 2. `run all` is fail-fast per verb (when a verb returns 2, it does not go to the next verb). When an adapter is missing (`harness/adapters/<name>/` does not exist), the runner prints 1 line "adapter not found: <name> (<component>.<task>)", stops with 4, and does not process the other components
5. Just after `sprint run`, `harness/hooks/record-test-fails.sh` writes `.sprint/test-fails.json` from the evidence

### 5.1 Adapter development

To use a runner that the bundled 4 do not cover, **write the adapter in the target repository.** Do not add it to the harness core. The core has no technology name.

1. **Run the runner CLI once.** Check that the CLI can set the reporter and the path of the result file. Some runners let the reporter in the settings file win over the CLI
2. Write `harness/adapters/<name>/run-<verb>`. Take the cwd at `SPRINT_COMPONENT_DIR` and start the runner directly. Pass standard output and standard error through. Return the exit code of the runner. Write the runner-specific result into `SPRINT_RAW_DIR`
3. Write `harness/adapters/<name>/convert-evidence`. Read the result in `SPRINT_RAW_DIR` and `SPRINT_RUN_EXIT`, and write the JSON of the evidence contract (§6) to standard output. For `test` and `e2e`, put the `file`, `name` and `status` of every test into `tests[]` (`tdd-audit` matches the Test IDs with them)
4. Write `<name>` in `components[].adapters.<verb>` of `sprint.config.json`
5. Run it with `bash harness/bin/sprint run <task> <component>`. Read `<evidence.dir>/<component>.<task>.json` with `jq` and check that it matches the shape of the evidence contract
6. Pass `bash harness/bin/sprint gate TEST`. `results` judges the freshness and green

- The location is `harness/adapters/`. A re-import (the "2.6 Re-import (update)" section of README) copies `harness/` over the top. Put the adapter you wrote under version control and check that it is still there after a re-import
- `SPRINT_ADAPTERS_DIR` replaces the location itself. The bundled 4 become invisible. It is the entry point of the fixture tests, not a second location for the project
- Only `convert-evidence` reads the output strings of the runner. The gates and `bash harness/bin/sprint status` read only the JSON of the evidence contract

## 6. Evidence contract

`<evidence.dir>/<component>.<task>.json`. 1 file per run. Only `harness/lib/evidence.sh` reads it. No function reads the output strings of the runner.

```json
{
  "schemaVersion": 1,
  "component": "backend", "task": "test", "adapter": "node-vitest",
  "status": "pass",
  "counts": { "passed": 412, "failed": 0, "skipped": 0 },
  "errors": 0, "warnings": 0,
  "tests": [ { "file": "src/x.test.ts", "name": "TEST-3-1.1 [[GATE-1]] ...", "status": "passed" } ],
  "started_at": 1788948000, "finished_at": 1788948120
}
```

| Field | Meaning | Verb |
|---|---|---|
| `status` | `pass` / `fail`. `pass` when the exit code of `run-<verb>` is 0 and `counts.failed` = 0 and `errors` = 0 | all |
| `counts` | The number of tests (`passed` / `failed` / `skipped`). E2E counts `flaky` separately | test / e2e |
| `errors` / `warnings` | lint: the total of errors / warnings. typecheck: the number of error lines. build: errors = 1 on failure | lint / typecheck / build |
| `tests[]` | 1 element per test. `file` is relative to the component directory. `name` is the run name (describe and it joined). `status` is `passed` / `failed` / `skipped` / `flaky` / `todo` | test / e2e |
| `started_at` / `finished_at` | epoch seconds. The freshness judgment uses `finished_at` | all |

- `pending` of the unit test runner maps to `skipped`. `todo` maps to `todo` as is. `counts.skipped` counts only `skipped` (`todo` stays in `tests[]`, and `tdd-audit` marks it NOT-PASS)
- E2E is aggregated per spec. If a spec contains `unexpected`, `failed`. If it contains `flaky`, `flaky`. If it contains `skipped`, `skipped`. Otherwise `passed`. A flaky test that passed on retry is not `pass` (`status` becomes `fail`)
- `.sprint/test-fails.json` is `{ "total": n, "tasks": { "<component>.<task>": n, ... }, "recorded_at": "..." }`. n is `counts.failed` for test / e2e, `errors` for lint / typecheck, and 1 for build when status is fail

## 7. Headings of the bundled unit

The templates (`harness/templates/`. They are copied to `docs.templates` at import) and the checks are fixed as a bundled unit. The heading strings that the checks read are not settings. At import, only the placeholders (`{{spec_docs}}` / `{{common_clauses}}` / `{{static_check_example}}` / `{{run_commands}}`) are filled in. The headings do not change.

| String | Location | Check that reads it |
|---|---|---|
| `## 0. Referenced common clauses` | SPEC.md | `spec-lint refs` ([GATE-3](#GATE-3)) |
| `## Implementation units and dependencies` | SPEC.md | `spec-check` (check 2) |
| `## EARS requirements` | SPEC.md | `spec-check` (checks 1 and 2) |
| `## Test specification` | TEST.md | `spec-check` (check 3. The start of the test definition row range) |
| `## Existing tests to modify` | TEST.md (optional) | `spec-check` (check 3. The end of the test definition row range) |
| `## Coverage matrix` | TEST.md | `spec-check` (checks 1 and 3) |
| `## Run commands` | TEST.md | `spec-check` (checks 1 and 3. The end of the coverage matrix range). The location of `{{run_commands}}` |
| `Commit hash:` | README.md "8. SHIP" | `ship-closed` |
| `<!-- UNSEAL:BEGIN -->` / `<!-- UNSEAL:END -->` | SPEC.md / TEST.md | `spec-seal` ([PROC-2](sprint-process.md#PROC-2)), `edit-scope-gate.sh`, `doc-verified` |
| The verdict cells 🟢 / 🟡 / 🔴 of the verdict table (a table that has a `Verdict` column in its header) | UNSEAL of TEST.md | `doc-verified` |
