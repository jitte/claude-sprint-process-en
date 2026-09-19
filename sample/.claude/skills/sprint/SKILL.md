---
name: sprint
description: Sprint management. /sprint resume restores the context, /sprint handover prepares the handover before a clear, /sprint to <stage> runs everything up to a target stage, /sprint status shows the state, /sprint new creates a sprint, /sprint stage makes a single transition. Trigger on "sprint", "resume", "pick up where we left off", "status", "flag". **When the user mentions discarding the conversation, trigger with handover** — "can I clear?", "I'll reset", "wipe the context", "I'll /clear", "session clear", "let's cut it here for now", "let's stop here".
---

# Sprint Manager

This skill manages the sprint lifecycle. It reads and writes `.sprint/flags.json`.
It is the main way to restore the context after `/clear`.

`docs/06_process/sprint-process.md` is the authoritative source for the stage definitions, the transition rules, the work of each stage, and the 🚧 gates. This skill holds only the command syntax and the procedures of `resume` / `handover`.

## Commands

Select the behavior by the argument. No argument is the same as `status`.

### Short forms

**Accept a command name by prefix match.** The shortest unique forms are these.

| Short form | Command |
|---|---|
| `r` | `resume` |
| `ho` | `handover` |
| `he` | `help` |
| `n` | `new` |
| `sw` | `switch` |
| `t` | `to` |
| `stat` | `status` |
| `stag` | `stage` |

Treat a prefix longer than the one in the table above as the same command (`res` → `resume`, `hand` → `handover`).

**Do not run an ambiguous short form.** For `h` (handover / help), `s`, `st`, `sta` (status / stage / switch), show the candidates and ask back. Do not pick one on your own.

You can omit `to` (`/sprint REVIEW` = `/sprint to REVIEW`). Accept stage names by prefix match too (`/sprint b` does not identify one of build-red / BUILD, so ask back).

### `resume` — restore the context

Use this to restart after `/clear`. Do these steps in order:

1. **Run `bash harness/bin/sprint status --json`** to get the full state of the active sprint in one call
2. Read README.md / SPEC.md / TEST.md from `sprint_dir` (read all of SPEC.md. It is the base of the instructions to agents)
3. Read CLAUDE.md
4. Show the user the next action based on the current stage **and status**

Output format:
```
## Sprint: {sprint_id}
- Stage: {stage} ({status})
- Dir: {sprint_dir}
- Sealed: SPEC {✓/✗} / TEST {✓/✗}  Test failures: {n}  Evidence: {fresh/stale}

### Scope
(list the MUST tasks from README.md §2)

### Current state
(show the task progress from README.md §3)

### Next action
```

**Decide the recommended action from `status` as well as from `stage`.**

| status | Meaning | Next action |
|---|---|---|
| `open` / `doing` | The work of the stage is not complete | Do or continue the work of the stage (the work is in `sprint-process.md` §3) |
| `closed` (REVIEW / TEST) | 🚧 gate. The work is complete | **Stop and wait for the user's instruction.** Do not run the same stage again (`agent-gate.sh` rejects it mechanically) |
| `closed` (other stages) | The work is complete | Transition to the next stage |
| `CLOSED` + `closed` | The sprint is complete | Go to the next sprint (`switch` / `new`) |

### `handover` — prepare the handover before a clear

This is the pair of `resume`. **Actually create a state in which the work continues after the session is discarded**, then report.

Run this command when the user mentions discarding the conversation ("can I clear?", "I'll reset", "let's cut it here for now", "let's stop here").

The failure pattern is known. It is **stating "you can resume" when the preparation is not done**. Real case: the agent checked only that the documents were on disk and answered "you can resume". But the work branch did not exist, and the session was on `main`.

Obey 3 rules.

1. **Do not write "you can resume" until all checks pass**
2. **Fix what you can fix without asking.** Create the branch. Make status match the actual state. For reversible operations within scope, do not stop at a report
3. **Reply with the fixed table.** Do not write prose

#### Check items

| # | Item | Decision |
|------|------|------|
| 1 | Running processes | If background commands or agents remain, **clear is not allowed**. You can no longer receive their results |
| 2 | Work branch | If you are on a shared branch such as `main` during a sprint, **create a branch** |
| 3 | **Information that exists only in the conversation** | **Most important.** A clear deletes the conversation, not the disk |
| 4 | State file | Check with `bash harness/bin/sprint status` that stage / status match the actual state |
| 5 | Uncommitted diff | **Report** its content. **Do not commit** (the user decides after checking the content) |
| 6 | Resume method | Show it in 1 line. If you cannot show it, the preparation is not complete |

**Item 3 is the center.** The information that is really lost: facts found in investigations (line counts, counts, results of cause isolation), design decisions agreed verbally with the user, and items promised "for later". If an item is not yet in a destination (SPEC / README / issue / commit message), write it there, then clear.

#### Output

Return only this table. Do not write an introduction or closing words.

```
| Item | State |
|------|------|
| Running processes | None |
| Branch | sprint/17-6 |
| Information only in the conversation | None |
| State file | 17-6 / REVIEW / doing |
| Uncommitted diff | 3 files (sprint documents) |

Safe to clear. Resume: `/sprint resume`
```

If you fixed items, write them in 1 line below the table. If some items do not allow a clear, write only those items.

### `status` — show the state

**Run `bash harness/bin/sprint status`.** It shows a summary of the active sprint state (stage / status / kind / dir / seal / test failure count / evidence freshness / recent transitions).

- List of all sprints: `bash harness/bin/sprint list`
- Summary of stage transitions: `bash harness/bin/sprint log`
- JSON format: `bash harness/bin/sprint status --json`

### `stage <STAGE>` — stage transition (single)

**Run `bash harness/bin/sprint stage <STAGE>`.** It only updates flags.json. It does not do the work of the stage. edit-scope-gate denies a manual edit of flags.json.

Valid stages: `PLAN` / `REVIEW` / `build-red` / `BUILD` / `TEST` / `DOCS` / `SHIP` / `CLOSED`

The transition rules (advance only to the next allowed stage, rollback always allowed, skip rejected) and the gates are in `sprint-process.md` §3. An attempt to skip exits with a non-zero code. Report this to the user.

#### `stage <STAGE> to <STAGE>` — roll back, then run

**Transition to the stage of the 1st argument, then run everything up to the stage of the 2nd argument.** The use is rollback (a specification defect after the seal, an error in the SPEC text after SHIP).

```
/sprint stage PLAN to TEST     Roll back to PLAN, then run from there to TEST
/sprint stage DOCS to SHIP     Roll back to DOCS, then run DOCS → SHIP
```

**The 🚧 gates (after REVIEW, after TEST) apply as usual.** An instruction to roll back is not an instruction to pass a gate. Even if the 2nd argument is past a gate, stop at the gate and wait for an instruction.

### `[to] <STAGE>` — run everything up to the target stage

From the current stage to the target stage, **run the stages that are not done yet, in order**. main does the work of each stage autonomously and makes the stage transitions automatically. Follow `sprint-process.md` §3 for the work (the work of REVIEW / the BUILD sub-phases / DOCS / SHIP).

**When you reach the target stage, report the result and stop. Never advance to a later stage.**

Stage order: `PLAN → REVIEW → 🚧 → build-red → BUILD → TEST → 🚧 → DOCS → SHIP → CLOSED`

- 🚧 is a Human-in-the-Loop gate. You cannot pass it without the user's instruction. If `/sprint to BUILD` passes REVIEW, report the result of REVIEW and stop
- Seal (`bash harness/bin/sprint seal`) after REVIEW is complete, just before build-red
- If a 🔴 occurs, or if you cannot resolve a test failure, stop and ask the user

### `new <sprint_id> <name | sprint_dir>` — new sprint

**The 2nd argument does not have to be a formal path.** If the user gives a name or a description, main converts it to a `sprint_dir` that follows the conventions.

- If the 2nd argument is a formal path in the form `docs/07_plans/...`, use it as is
- If not, treat it as a name and derive the path with these steps:
  1. Find the **major directory** for the major of `sprint_id` (example `10-2`) (`ls docs/07_plans/10_*`). If none exists, decide the slug of the new major
  2. Find the **next sequence number** in the major directory (the maximum of the existing `NN_*` + 1, zero-padded to 2 digits)
  3. Convert the name to a **lowercase kebab-case slug** (example `sankey/mosaic part 2` → `sankey-mosaic-2`)
  4. Use `docs/07_plans/<major>_<slug>/<NN>_<slug>` as `sprint_dir`
- Show the derived `sprint_dir`, then run the command. Do not ask whether the path is acceptable. Agree on the content and the scope of the sprint in a separate dialog
- **`sprint.sh new` rejects an existing ID.** In that case, ask the user how to handle the existing ID (redefine it / create a new sprint with a different number)

**Run `bash harness/bin/sprint new <sprint_id> <sprint_dir> [docs]`.** It creates README/SPEC/TEST from the templates, adds the sprint to flags.json, and switches active. It does not seal SPEC.md / TEST.md at this point.

### `switch <sprint_id>` — switch active

**Run `bash harness/bin/sprint switch <sprint_id>`.**

### `help` — help

Show the command list of this skill.

## Implementation notes

- **Read flags.json with the Read tool. Write it through `harness/bin/sprint`**
  - Stage transition: `bash harness/bin/sprint stage <STAGE>`
  - Status update: `bash harness/bin/sprint set-status <open|doing|closed>`
  - New / switch: `bash harness/bin/sprint new|switch ...`
  - Get a value: `bash harness/bin/sprint get [field]`
  - State summary: `bash harness/bin/sprint status [--json]`
- sprint_dir is a path relative to the project root
- The script updates `updated_at` (ISO 8601 JST) automatically

### status lifecycle

| status | Meaning | Transition timing |
|--------|------|-------------|
| `open` | Before the stage work starts | When `stage` transitions to a new stage |
| `doing` | Stage work in progress | When `to` starts the work of the stage (`set-status doing`) |
| `closed` | Stage complete | When the work is complete (`set-status closed`). The next `stage` returns it to `open` |
