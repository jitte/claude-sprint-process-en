---
xref-prefix: PROC
---

# Sprint process

> A lightweight process whose main purpose is to control agent launches.
> The base specification (docs/05_specifications) is final.
> The gate tool specification is in `docs/06_process/gate-tools.md`. The hooks and scripts are explained in `docs/90_deliverables/hooks-and-scripts.md`.

---

## 1. Stage definitions

```mermaid
flowchart LR
    PLAN --> REVIEW --> build-red --> BUILD --> TEST --> DOCS --> SHIP --> CLOSED
```

| Stage | Purpose | Agents that can launch | Role of main |
|---------|------|-------------------|------------|
| PLAN | Break down the tasks. Decide the implementation approach. Update the base specification in this stage too | none | Draft README / SPEC / TEST |
| REVIEW | Check the consistency of the specification and the approach | qa | Check the qa report. Decide whether to go to BUILD |
| build-red | Create test skeletons (RED) | tester | Seal. Confirm that `make test` FAILs |
| BUILD | Implementation + test writing (GREEN + VERIFY) | backend, frontend, tester | Launch agents. Manage progress |
| TEST | Run the tests. Evaluate quality | tester, qa | Check the test results |
| DOCS | Feed the results back into the specification documents | qa | Check the document updates. Make the work commit |
| SHIP | Verify implementation quality. Commit | qa | After the qa implementation check, git commit + branch push |
| CLOSED | Maintenance after SHIP | all | Bug fixes and small adjustments. main cannot edit src directly |

**Process compliance has priority over implementation.** Do not break the stage boundary rules, even in Auto Mode.

---

## 2. Human-in-the-Loop gates

**Do not pass the following stage transitions without an explicit instruction from the user.**

| Gate | Timing | Reason |
|-------|----------|------|
| **REVIEW → build-red** | After REVIEW is complete | The user judges whether the specification is valid |
| **TEST → DOCS** | After TEST is complete | The user evaluates the test results and the quality |

When `/sprint to <STAGE>` reaches the target stage, **report that the work of that stage is complete and stop**. Do not go to the next stages. This also applies in Auto Mode.

main can do the other stage transitions (the ones that are not gates) on its own.

---

## 3. Stage transitions

main transitions the stage with `bash harness/bin/sprint stage <STAGE>`. **`edit-scope-gate.sh` denies direct edits of flags.json.** This prevents stage skips and manual-edit mistakes.

`.sprint/flags.json` has `active` (the ID of the sprint in progress) and `sprints[id]` (`stage` / `status` / `kind` / `sprint_dir` / `updated_at`). `agent-gate.sh` reads the stage of `active`. To pause and resume a sprint, change `active`.

### Transition rules

Completion conditions (a human / main judges):

- **PLAN → REVIEW**: The task definition is complete
- **REVIEW → build-red**: qa reports 🔴 = 0. The specification is sealed with `bash harness/bin/sprint seal`
- **build-red → BUILD**: `make test` FAILs (RED confirmed)
- **BUILD → TEST**: All build sub-phases are complete. `make verify` is green
- **TEST → DOCS**: The tests pass. The qa quality evaluation is OK
- **DOCS → SHIP**: The specification documents are updated. The work commit is done
- **SHIP → CLOSED**: commit + push are complete

Order enforcement (`harness/bin/sprint` verifies it mechanically):

- **Advance only by the next allowed transition**: PLAN→REVIEW→build-red→BUILD→TEST→DOCS→SHIP→CLOSED
- **A backward move (rollback to an earlier stage) is always allowed**
- **A skip is rejected** (example: PLAN→BUILD, REVIEW→TEST). The script exits non-zero and shows the reason
- 🚧 gates (§2) need human approval. The script guarantees only the order. main decides whether to pass a 🚧 by following the user's instruction

### Stage gates

`harness/bin/sprint` runs the gates through `harness/tools/gate-check.sh` when it advances a stage. **The `gates` key of `sprint.config.json` is the source of truth for the stage → tool assignment** (per kind). The specification of each tool is in `docs/06_process/gate-tools.md`.

The runner classifies gate failures into 4 classes (spec / impl / test / infra) and shows the recommended stage. It does not execute the transition. A human decides the rollback target. The classes are defined in [GATE-1](gate-tools.md#GATE-1).

### Rollback

When a problem is found, main returns to the earlier stage with `bash harness/bin/sprint stage <earlier stage>`.

- Defect in TEST → return to BUILD
- Specification contradiction in DOCS → return to REVIEW
- **A specification gap is found → return to PLAN.** main fixes SPEC.md / TEST.md → REVIEW again → reseal with `bash harness/bin/sprint seal` just before build-red. A rollback after sealing changes the seal hash, so REVIEW and all later stages must be done again

### State aggregation and transition log

`bash harness/bin/sprint status` shows the scattered state with 1 command. The sources are `flags.json` (stage / status / kind / dir), `spec-hashes.json` (seal), `test-fails.json` (the number of test failures. Its form is `{ "total": n, "tasks": { "<component>.<task>": n }, "recorded_at": "..." }`. `harness/hooks/record-test-fails.sh` writes it from the evidence just after `sprint run`), the fresh check of the `results` gate (evidence freshness), and `.sprint/logs/stage-transitions.jsonl` (the latest transitions). **Do not create new state files.** The task table in the "3. Tasks and progress" section of README stays the only source of information. Do not copy it here.

`bash harness/bin/sprint status --json` returns the same content as JSON (`/sprint resume` uses it). `bash harness/bin/sprint list` lists all sprints.

`sprint stage` appends each transition to `stage-transitions.jsonl` (sprint / from / to / direction / gate). `bash harness/bin/sprint log` counts "how many rollbacks occurred in each stage" and "how many times each gate failed". A recording failure never stops `sprint`.

### BUILD sub-phases

| Phase | Allowed agents | Purpose | Completion condition |
|---------|---------------|------|---------|
| `build-red` | tester | Create test skeletons | `make test` FAILs |
| `BUILD` | backend, frontend, tester | Implementation. Test maintenance. Remove skips | `make verify` is GREEN. No `test.skip()` remains |

`make verify` = the fail-fast chain `lint` → `typecheck` → `test` → `test-frontend` → `build` (e2e is heavy, so it is not included. Run `make test-e2e` in the TEST stage).

**Procedure:**

1. main: `bash harness/bin/sprint seal` → `bash harness/bin/sprint stage build-red`
2. main: launch tester → create test skeletons from TEST.md → confirm FAIL with `make test`
3. main: `bash harness/bin/sprint stage BUILD`
4. main: launch agents as SPEC.md "Implementation units and dependencies" specifies. Run the units without dependencies in parallel. A unit with dependencies waits until its dependencies are complete (example: the frontend screen implementation depends on the backend unit that has the type definitions)
5. main: join point. After all units are complete, confirm GREEN with `make verify` → transition to TEST

**Do not run units that use the same test runner in parallel.** Runs of the same `(component, task)` write to the same execution evidence (`<evidence.dir>/<component>.<task>.json`). If 2 agents that use the same runner run at the same time, the later write overwrites the earlier evidence, and the content that `results` / `tdd-audit` read breaks.

| Combination | Parallel |
|-----------|------|
| backend × frontend | Yes (the evidence is separate) |
| backend × backend / frontend × frontend | **No**. Run them in series, even when their files do not overlap |
| tester × any | Decide from the runners that tester runs for verification |

**Self-repair loop:** Each agent repairs the failures caused by the code that it wrote or changed in that sprint, until `make verify` is green (**maximum 3 times**). If it is not green after 3 attempts, the agent stops and reports the cause analysis and the attempted fixes to main. **When an agent finds a bug in an existing feature, it does not repair it itself.** It reports and waits for an instruction. Do not make tests green by deleting them, skipping them, or relaxing their conditions (`tdd-audit` detects this from the execution evidence). In build-red, FAIL is the correct state, so tester does not self-repair.

### REVIEW work

The REVIEW stage does an independent audit of SPEC / TEST / README. The evaluation items (R1 to R10) are in `.claude/agents/qa.md`. qa only reads the unsealed drafts and does not edit them (the findings go in the "4. REVIEW" section of README).

**In each round, qa counts the following 3 numbers and records them in the "4. REVIEW" section of README.** In a round where the 3 numbers do not match, qa reports the mismatch as 🟡 or higher.

| What to count | How to count |
|-----------|-------|
| MUST count | The total number of MUST requirements (task IDs) in SPEC |
| Count covered by task rows | The sum of the task IDs that each row of the task list in the "3. Tasks and progress" section of README lists |
| EARS count | The total number of EARS requirements in SPEC |

Each time you apply REVIEW findings, run `bash harness/bin/sprint spec-check`. Make it OK before sealing (§4).

### DOCS work

The DOCS stage applies the implementation results to the base specification documents. The evaluation items (D1 to D4) are in `.claude/agents/qa.md`. When you apply the results, obey these rules.

- Check the values used in figures and examples (domain identifiers, for example `command` / scenario ID / view ID) against the real values in the catalog with grep. Do not write values that you did not check
- Align the vocabulary of EARS requirements with the field names in Interface Contracts

**Reconcile the declared clauses and the actual clauses by count.** qa runs `bash harness/bin/sprint spec-graph diff <sprint start commit>`. qa compares, by count, the list of changed clauses with the clauses that the "0. Referenced common clauses" section and the base specification reference table of SPEC declare. The difference is undeclared changes. Record the clause IDs and the changes in "Reconciliation of referenced clauses" of the "7. DOCS" section of README.

**A sprint that adds a new check does a trial run of the check against the production documents in PLAN. It declares the detected count in "Base specification references" of SPEC.** If a trial run is not possible (the check is not implemented yet), declare "Correct the detected errors and record the clauses in the '7. DOCS' section of README". If the new check detects errors in the production documents during BUILD, their correction is an undeclared clause change.

**Make the work commit at the end of DOCS.** Put the implementation, the tests, the base specification, and SPEC/TEST/README (up to the "7. DOCS" section) into 1 commit. Record the commit hash in "Commit hash" of the "8. SHIP" section of README.

- **Do not make the work commit in SHIP.** Do not record the SHIP commit (the §6 RETRO and §8 records) in README. If you record it, the record needs another commit, and this never ends
- **Do not merge into 1 commit with `git commit --amend`.** amend creates a new commit object, and the hash changes. The recorded value then points to a different commit

### SHIP work

1. main: launch qa → verify the quality of the implementation code (the evaluation items S1 to S6 are in `qa.md`)
2. qa: compare the observations that REVIEW marked "file as a separate issue" with `gh issue list`. Report the observations that are not filed to the user
3. main: fill in the "6. RETRO" section of README. For rules to make permanent, follow "Procedure to make rules permanent" in §6
4. main: check the checklist in the "8. SHIP" section of README. "Commit hash" already has the work commit of DOCS (do not add to it in SHIP)
5. main: git commit (RETRO and the fixes in SHIP) → branch push. Do not record the hash of this commit in README

**SHIP verdict rules:**

| Result | Action of main |
|------|-----------|
| 🟢 all green + qa 🟢 | commit + push |
| 🟡 qa findings | main fixes them and continues |
| 🔴 any fail / qa 🔴 | **Stop immediately.** Analyze the cause and report it to the user. Make the fixes only after the user instructs, by returning to BUILD. Do not get through with a workaround |

### Evaluation scope of qa

qa is launched in 4 stages. The evaluation scope is different in each stage. Do not go into the scope of other stages.

| Stage | Inspect | Do not inspect |
|---------|------|--------|
| REVIEW | The content of SPEC / TEST / the "1. Background and purpose" to "3. Tasks and progress" sections of README | Implementation code |
| TEST | Test results + test code + deliverables | Quality of the implementation code |
| DOCS | Differences between the implementation results and the base specification documents | — |
| SHIP | Implementation code | Test code (done in TEST), specification documents (done in DOCS) |

**The evaluation scope of qa is the SPEC contract and the deliverables. The "4. REVIEW" to "8. SHIP" sections of README are records. qa does not evaluate them.** If the audit included the text of the records, each correction record would become a finding in the next round, and the rounds would not converge. main is responsible for the accuracy of the records.

**Keep the launch prompt for qa within 40 lines.** The evaluation items are in `qa.md`. Write only the target files, the stage, and the sprint-specific aspects in the prompt.

**Common verdict rules:**

| Severity | Meaning | Action of main |
|-------|------|-----------|
| 🟢 | No problem | Continue |
| 🟡 | Minor gap | main fixes it and continues (no user confirmation needed) |
| 🔴 | Serious contradiction, or a policy decision is necessary | Stop and ask the user for confirmation |

Condition for a stage transition: 🔴 = 0 (every 🟡 must be fixed). 🔴 can stop SHIP. A human makes the decision to allow SHIP.

---

## 4. Agent launch control

### agent-gate.sh hook

A `PreToolUse` hook watches Agent tool calls. It allows or denies agent launches for the current stage.

| Agent | PLAN | REVIEW | build-red | BUILD | TEST | DOCS | SHIP | CLOSED |
|------------|------|--------|-----------|-------|------|------|------|--------|
| frontend   | -    | -      | -         | ✓     | -    | -    | -    | ✓      |
| backend    | -    | -      | -         | ✓     | -    | -    | -    | ✓      |
| tester     | -    | -      | ✓         | ✓     | ✓    | -    | -    | ✓      |
| qa         | -    | ✓      | -         | -     | ✓    | ✓    | ✓    | ✓      |

Information-gathering agents (for example Explore, Plan, general-purpose) are always allowed, in every stage.

**The hook mechanically prevents a second run of a 🚧 gate.** When `stage=REVIEW` and `status=closed`, and when `stage=TEST` and `status=closed`, even the agents marked ✓ in the table above cannot launch. In both states, "the work is complete, and the correct state is to wait for the user's instruction". Without this enforcement, `/sprint resume` after `/clear` runs a completed REVIEW / TEST again. When you must apply findings, first roll back with `bash harness/bin/sprint stage PLAN` (for TEST, `stage BUILD`). Then do the work.

### spec-check — structural check before sealing

`bash harness/bin/sprint spec-check [sprint_dir]` (the default is the active sprint). It checks the structure of SPEC.md / TEST.md by machine.

| # | Check | Accident that it detects |
|---|------|------------|
| 1 | Two-way difference between EARS ↔ coverage matrix | You add a requirement and forget to write it in the matrix |
| 2 | Assignment of every EARS to an implementation unit (ranges are expanded). Double assignment | A new EARS has no owner / a range includes the next unit |
| 3 | Difference between definitions ↔ references of Test IDs. Missing numbers | You add a test and forget to put it in the matrix |
| 4 | Markdown tables split by blank lines | Rows fall outside the table and do not render |
| 5 | Referenced test files exist | You specify a path that does not exist |

For a TEST.md without Test IDs (kind=docs. Static verification items only), checks 3 and 4 are skipped, and check 5 runs next.

**Put an "Assigned EARS" column in the implementation unit table.** Check 2 reads this column.

---

<a id="PROC-1"></a>
## [PROC-1] 5. File write constraints

### Write scope matrix (source of truth)

The judgment uses the combination of the caller (`agent_type`. main when it is missing or an information-gathering agent) and the type of the write target. The type comes from the layout in `sprint.config.json` (`docs.sprintRoot`, `components[*].src`, `components[*].tests`). The matrix code is in 1 place: `harness/hooks/scope-lib.sh`. `harness/hooks/edit-scope-gate.sh` judges Write / Edit in advance. It does not judge Bash writes. Write src / tests with Edit / Write (CLAUDE.md "Choosing tools").

Order of the type judgment: `state` → `spec` / `testmd` → other (`docs/**`) → `test` (matches `tests` of any component) → src of a component (matches any `src`. The component name) → other.

| Caller | src of a component | Tests (`components[*].tests`) | SPEC.md | TEST.md | `flags.json` / `spec-hashes.json` | Other (docs, scripts, settings) |
|---|---|---|---|---|---|---|
| main | deny | deny | allow | allow | deny | allow |
| `role` of a component (backend / frontend) | **allow only for the caller whose `role` matches** | deny | deny | deny | deny | allow |
| tester | deny | allow | deny | deny | deny | allow |
| qa | deny | deny | deny | **UNSEAL only** | deny | allow |

- The src of a component is "allow only for the caller whose `role` matches". Only the backend agent can write the src of the backend component (`role: backend`). Only the frontend agent can write the src of the frontend component. A caller whose role does not match (main included) is denied
- SPEC.md / TEST.md are the sprint specifications under `<docs.sprintRoot>/**/`. Other files under `docs/` are "other", even when they match a test glob
- **UNSEAL only** = only inside a `<!-- UNSEAL:BEGIN/END -->` block. `edit-scope-gate.sh` judges the region from the Edit arguments
- Only `harness/bin/sprint` writes `flags.json`. Only `bash harness/bin/sprint seal` writes `spec-hashes.json`
- When `sprint.config.json` does not exist, the hooks do not judge and let the call through (no output, exit 0)

<a id="PROC-2"></a>
### [PROC-2] 5.1 Specification seal (spec seal)

`SPEC.md` / `TEST.md` are specification artifacts. They are hash-sealed to **separate the drafter (main) from the evaluator (qa)**. The goal is to guarantee this state: "the side that measures (qa) cannot rewrite the measurement criteria" (prevention of self-evaluation).

- **Sealed region** = the whole file − the `<!-- UNSEAL:BEGIN -->` … `<!-- UNSEAL:END -->` block. In a file without markers, the whole file is the sealed region
- In **TEST.md**, only the UNSEAL block ("Results (filled in by qa)") is the unsealed region for qa. The test specification and the coverage matrix are in the sealed region
- **SPEC.md** is sealed as a whole. qa has read-only access. Only main can rewrite it
- The seal hashes are collected in `.sprint/spec-hashes.json`. Only `bash harness/bin/sprint seal` updates them (an approval act by main)
- `edit-scope-gate.sh` denies changes to the sealed region at edit time (prevention). `bash harness/bin/sprint seal-verify` detects mismatches with the manifest (guarantee, SHIP gate)

**Seal after REVIEW is complete, just before build-red.** PLAN to REVIEW fix the specification, and the seal closes it. The main purpose of the seal is to freeze the specification from BUILD onward, so any time before build-red is enough. In REVIEW, qa only reads SPEC/TEST and does not edit them. So self-evaluation prevention holds even when the specification is unsealed during REVIEW. When REVIEW finds a specification gap, no "rollback → reseal" loop is necessary. The `spec-seal` check of the `build-red` gate enforces the seal.

**Operation flow:**

1. main drafts SPEC.md / TEST.md in PLAN (no seal)
2. REVIEW: qa audits SPEC/TEST independently, as input (read only. The findings go in the "4. REVIEW" section of README)
3. main applies the REVIEW findings → after REVIEW is complete, just before build-red, seal with `bash harness/bin/sprint seal`
4. For a specification change after sealing: roll back to PLAN → edit → REVIEW again → run `bash harness/bin/sprint seal` again before build-red
5. In SHIP, run `bash harness/bin/sprint seal-verify`. A mismatch (an unauthorized change of the sealed region, an unsealed file) is 🔴

**No changes to past sprints (freeze after CLOSED):** Do not change the SPEC.md / TEST.md of a sprint after CLOSED. When a design change is necessary, express it with the base specification (for example docs/03_design) + the SPEC of the current sprint + an ADR (docs/08_decisions). `bash harness/bin/sprint seal` rehashes all SPEC/TEST files under docs/07_plans at once, so changes to past files are not detected mechanically. This operation rule keeps the freeze.

---

## 6. Sprint documents

### Structure

Put 3 files, README.md / SPEC.md / TEST.md, in `docs/07_plans/<major>_<slug>/<minor>_<slug>/`. How to write them: `docs/07_plans/README.md`. Templates: `docs/06_process/templates/`.

| File | Main readers | Content |
|---------|---------|------|
| README.md | main, qa | Background, scope, progress, REVIEW, TEST, RETRO, DOCS, SHIP |
| SPEC.md | backend, frontend | EARS requirements, Interface Contracts, state transitions |
| TEST.md | tester, qa | Test specification, coverage matrix, run commands |

### How to write SPEC.md — write requirements as results

**Do not write the means of implementation in requirements.** Write a requirement as "what holds true". The implementation chooses "how to achieve it".

| Bad wording | What happens | Corrected wording |
|-----------|------------|------------|
| Put the card being entered at the top as **an element without a time** | The reader cannot tell if "without a time" is a property of the data or of the display. The reference point of "the top" is also undefined | Among the submitted cards, **the newest is at the top** |
| The search card uses **the time when it was opened** as the sort key | When a time becomes a requirement, the implementation takes on problems that are not in the requirements: time zones, clock differences, and collisions in the same millisecond | Express the submission order with **a monotonically increasing value** |

An ambiguous requirement misses the user's expectations, even when the implementation follows the specification. When you choose the words for a verdict, obey these rules.

- Write observable results (the order on the screen, the fields of a response, counts)
- Do not make internal implementation state a requirement (variable names, data types, algorithms)
- Put the constraints that a requirement must keep into separate requirements

**Write the completion verdict of a correction sprint as a measurement at the exit.** In a sprint that fixes violations in the existing implementation, make the completion verdict independent of the list of correction targets. Write the verdict as a full scan at the exit (scan the actual responses and run results by machine, and confirm 0 violations).

- You can write the list as a work guide. Do not use it as the basis of the verdict
- Do not try to make the list correct through repeated REVIEW rounds. The scan is what stops omissions
- Even with a policy of fixing at the source, the correction does not apply to paths that do not go through the source. Only the scan at the exit covers both
- Do not count the target set of the scan by hand either. Derive it from machine output

### RETRO and the procedure to make rules permanent

The "6. RETRO" section of README.md is the most important section. Record the following in each sprint.

- **What went well**: judgments and methods to repeat
- **Problems**: unexpected obstacles, rework, ambiguity in the specification
- **Improvements**: the text of the rules to make permanent, and candidate locations for them
- **Pattern extraction**: reusable patterns in the specification, the implementation, and the process

**Procedure to make rules permanent:**

1. Write the **text** of the rule in RETRO. Do not write "consider X". Write a sentence that can go into a permanent document as is
2. Write the rule into a permanent document (base specification, standard, process) during this sprint. In RETRO, record where you applied it (the "6. RETRO" section of the template README)
3. Do not put a **sprint ID tag** ("made permanent in 18-N") in permanent documents. Place rules by their content, not by their origin

Register the items that cannot be made permanent (unsolved problems, deferred work) **as issues**. The user instructs when to register an issue. There is no mechanism to write these items in sprint documents and pass them to the next sprint. The reason: `.sprint/` is outside git control and disappears when the environment is rebuilt.

---

## 7. Documentation sprint (kind=docs)

A sprint that writes no code and creates only documents, for example an accounting principles reference or design documents. The gates for code sprints (tdd-exists, *-audit, results-*) do not fit documents, so this sprint uses a gate set per kind (`gates.docs` in `sprint.config.json`).

### 7.1 kind field

- `sprints[id].kind` in `flags.json` (`code` | `docs`. `code` when not set)
- Setting: `sprint new <id> <dir> docs` (new sprint) or `sprint set-kind docs` (existing sprint)

### 7.2 Meaning of the stages (docs version)

| Stage | Work | Owner |
|---------|------|------|
| PLAN | Decide the chapter structure, the adopted approach, and the reference materials (draft README/SPEC/TEST) | main |
| REVIEW | Independent audit of the chapter structure, the correctness of the approach, and the coverage plan | qa |
| 🚧 | Approve the approach (serious policy decisions) | the user |
| build-red | Seal (spec-seal). Confirm that the verification checklist (TEST.md DOC-x) is not yet satisfied | main |
| BUILD | Write the deliverable documents | **main** |
| TEST | Document consistency checks (for example grep and debit/credit cross-checks). Fill in the TEST.md UNSEAL and the "5. TEST" section of README | **qa** |
| 🚧 | Read through and approve the finished documents | the user |
| DOCS | Apply the resulting changes to the referenced documents. Make the work commit | main |
| SHIP | Link verification, commit, branch push | main |

**When TEST finds problems and you correct them, measure 1 more round after the correction and update UNSEAL.** A correction is new text, and it becomes a verification target at the moment you write it. Do not go to the next stage while the last entry in UNSEAL still points to a verdict from before the correction.

### 7.3 Separation of writing and verification

qa has no Write permission (it cannot create new documents). To prevent self-evaluation, **writing = main, verification = qa**. The TEST verdict is based on mechanical verification (grep, debit/credit cross-checks). qa records it in the TEST.md UNSEAL and the "5. TEST" section of README. In docs, test IDs use the `DOC-x.x` form (to tell them apart from `TEST-x.x` for code).

### 7.4 When you confirm that a reference exists, also check its shape, line numbers, and counts

**Do not mark 🟢 based only on an existence check.** The most frequent cause of rejection in REVIEW is this type: "confirmed that it exists, but did not check its content".

| What you write | What to confirm |
|---------|------------|
| Schema names, type names | Does the type match the shape of the actual response? Even with the same name, the shape is different when the use is different |
| `file:line` | Is the element that the text mentions inside the quoted range? Line numbers move with the implementation |
| Counts ("N items", "N files", "is the first") | Count with a full scan. Do not only add up an enumerated list |

For a verification item based on a count, write the scan procedure and the exclusions in TEST.md. The existence check of identifiers is in [TSTD-2](../04_standards/02_testing.md#TSTD-2).
