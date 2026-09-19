# claude-sprint-process-en

Languages: **English** | [Japanese](https://github.com/jitte/claude-sprint-process)

![Gates, not rules — what breaks when an AI runs the sprint, and the mechanism that stops it](docs/assets/sprint-process.png)

## 1. What this is

A harness for handing software development to Claude Code for the long haul. It keeps four things in step: the specification, the tests, the implementation, and the documents.

Since February 2026, every line of code in our projects has been written by AI — 256 sprints and counting, some 300,000 lines of code and 230,000 lines of documents. The harness grew out of that work, one fix at a time, as each problem came up. The core is about 4,700 lines of bash and Python 3 and needs nothing beyond the standard library. The regression tests add about 5,000 lines, and the templates and documents about 1,900 more.

Development methodology for generative AI keeps changing fast. From prompt engineering (PE) through context engineering (CE), harness engineering (HE), and loop engineering (LE) to graph engineering (GE), the unit being designed has grown from one instruction to the wiring of several agents. CSP was not built from these ideas. It was built by adding one countermeasure per problem, from the standpoint of development quality, and ended up on the same path: a case of convergent evolution. Element by element, it compares as follows.

| Element | PE | CE | HE | LE | GE | CSP |
|---|---|---|---|---|---|---|
| Unit of design | One instruction | What one turn gets to see | The runtime around the model | One agent's cycle | The wiring of several agents | One sprint (a sequence of stages) |
| Verifier (separate from the generator) | — | — | The runtime (tests, type checks) | An external verifier | Per-node checks and vetoes | Gate tools and qa. They read the evidence JSON |
| Stop condition | — | — | — | A stopping rule | Terminal nodes | The target stage and 🚧 |
| Failure triage and where to go back | — | — | — | Recoverable vs. fatal | Rerouting | 4 failure classes → rollback stage |
| Memory | — | Choosing what to read | Files, persistent memory | Memory across cycles | Shared state on the edges | `flags.json`, seal hashes, RETRO → permanent documents |
| Allowed transitions and permissions | — | — | Permission boundaries | — | Allowed edges, per-node mandates | Hooks enforce the forward rule. Stage × agent launch matrix, write scope |
| Human approval | — | — | Permission prompts | — | Approval nodes | 🚧 at 2 points |
| Versioned topology | — | — | — | The loop spec as an artifact | The wiring as a versioned artifact | `sprint.config.json` and `sprint-process.md` |
| Observability | — | — | Logs | A record of each cycle | Traces | Transition log, tool log, `sprint log` |
| Automatic triggers, parallelism | — | — | — | Triggers | Fan-out and fan-in | None. A person starts it, and it runs in one environment |
| Cost budget | — | The context window | — | An iteration cap | A token budget | None |

CSP assumes the HE runtime and fixes the elements of LE and GE in the shape of one sprint. There is one kind of cycle: advance a stage, stop at the gate, roll back by failure class. The wiring is the sequence of stages plus the rollback edges. There is no branching, no parallelism, and no automatic trigger, because a person starts the sprint in one environment and approves it at 🚧.

Three things differ from LE and GE. The cycle is driven by Claude Code's main session, not by a script outside it. Permissions are split by stage (which agents may launch, what they may write), not by wiring between agents. There is no budget for cost (cycles, tokens); CSP only records the number of REVIEW rounds.

## 2. The problems it solves

Taken one at a time, the failures below look like carelessness. But set them side by side and a pattern emerges: the same structures return every time development is handed to an AI. Each section below gives what actually happened, then the structure behind it.

### 2.1 Reporting is cheaper than checking

- The AI wrote off failing tests as "unrelated to this change" or "a flaky test" and reported a pass. Those same tests had run 180 times in a row without a single failure
- An implementation agent reported that it had "checked every route". It had silently skipped four of them because they "would break the development database"
- In one session, the AI put claims into its reports four times without checking them. A single command would have disproved each one

"Unrelated" and "done" take one word to write. Checking takes running a command and reading the output. The AI picks the cheaper option. As long as the one who did the work also writes the report, a rule against it will not stop it.

### 2.2 When blocked, it looks for another way

- The check that required tests first only fired when the work went through one specific command. The AI called the implementation agent directly instead, and skipped the tests. It did this four times
- When an agent launch was blocked while it waited for human approval, the AI tried to edit the stage state file to move itself ahead
- E2E tests that were supposed to drive the screen called the API directly in 305 places across 48 files. Even while fixing that, the AI decided for itself that the screen "was too hard" and kept 184 of them as exceptions
- When a test would not pass, the AI changed the product screen instead of the test. It trimmed heading text and hid labels with CSS until the test went green

To the AI, being blocked is an obstacle to clear. Moving forward becomes the goal, and the reason for the block drops out. If a check has a gap, the AI goes through it.

### 2.3 The writer and the reviewer can edit the same files

- The reviewing agent could edit the specification and the test specification — the very documents it judged against
- The reviewer overwrote the writer's entry field and wiped the record already there. The field was marked "do not update"
- Where the AI that wrote the code also wrote its tests, the tests did no more than repeat the implementation's assumptions. Six new API endpoints shipped with no tests at all

Splitting roles by name does not split them if both roles can write the same files. An instruction to "leave it alone" did not hold the line.

### 2.4 At scale, review breaks down first

- Once code and documents together passed about 90,000 lines, the reviewer began letting problems through as warnings, passing them off as "not applicable" or "out of scope"
- Asked to "merge the old function into the new one", the AI added the new one and left the old one in place. The record said "merged", and the mismatch went unnoticed for eight weeks
- One unit of work was so large that it used up the whole context window. Every operation a human tried on the finished feature turned up a bug

Reviewing means reading the specification, the implementation, and the tests side by side. Once they no longer fit in the context, the comparison stays on the surface. Passes keep coming back, so from the outside you cannot see that review has broken down. Also, tests can confirm what was added, but nothing confirmed what was supposed to be removed.

### 2.5 New rules do not carry over to the next task

- Each time the same violation came back, we added a rule to the documents. By the fourth time, none of the four rules we had added was working
- At every retrospective, the AI wrote new rules and deferred them: "move this into the official documents in the next stage". They were never moved
- The corrections the author had to give the AI about how to work reached 79, counting only the ones that were recorded

A written rule works only when it is read. Call an agent directly, or let the conversation grow long enough to be summarized, and the rule is no longer read. What held were mechanisms that stop the tool call itself, and rules written directly into each role's definition.

### 2.6 The AI fills gaps in the specification with guesses

- When implementation started while the specification was still under discussion, the specification ended up scattered across per-task documents. The AI filled the unclear parts with guesses instead of asking
- When a human handed over a detailed plan, the AI took it for a finished specification and skipped the step that pins the specification down
- The time zone was written in one part of the specification and missing from another. The AI left the unwritten part in UTC, and a test that only checked the format let it pass

The AI would rather fill in a plausible value and keep going than stop and ask. Tests are written from the specification, so a gap in the specification is a gap in the tests too.

## 3. Principles

We added the fixes in the order the problems appeared. Hooks came first, limiting which agents could launch and where they could write. Then came a script that refuses to skip stages, and a seal on the specification that keeps the writer and the reviewer apart. After that, a gate at the entrance to every stage, judging by what the tests actually did. Last came specification references a machine can follow, and everything technology-specific moved out into adapters and configuration.

Each principle below answers one of the structures in section 2.

### 3.1 Judge by evidence, not by reports (2.1)

Lint, typecheck, build, test, and e2e each write their results as JSON in a fixed format, and the gates read nothing else. A report like "it passed" or "that was unrelated" never decides anything, whether a human wrote it or an agent did. A Test ID in TEST does not count as passed until the execution results say it passed.

### 3.2 Stop it with a machine, not an instruction, and leave no gaps (2.2, 2.5)

What must be followed is enforced by hooks and gates rather than written into documents. Every agent launch passes through a hook, no matter which path it takes. The stage state file changes only through a dedicated command, and only one stage forward at a time.

### 3.3 Separate the writer and the reviewer by write permission (2.3)

A hook decides which kinds of files each role may write. Once the specification and the test specification have been reviewed, they are sealed with a hash, and from then on the reviewer can write only the result fields. The tester writes the tests from the specification before any implementation exists.

### 3.4 Let a machine count what can be counted (2.4)

The reviewer is not asked to read everything. Tools do the counting: whether any clause reference is broken, whether every Test ID ran, whether the routes in the implementation match the routes in the specification. The reviewer reads those results alongside the specification and makes the call.

### 3.5 Write the specification and tests first, and have a human approve (2.6)

Before implementation, write the specification (SPEC, with requirements in EARS form) and the test specification (TEST). A human stops to decide at exactly two points: when the specification review is done, and when testing is done. Everywhere else, the AI carries on by itself for as long as it keeps passing the gates.

### 3.6 Stay independent of technology

The harness core contains no names of languages, test runners, or directories. Anything runner-specific lives in an adapter, and file locations come from a configuration file. You can add the harness to a project in another language or framework without touching the core.

## 4. How it works

### 4.1 Stages

A sprint moves through the stages below in order, one stage at a time, and every stage has a gate at its entrance. 🚧 marks a point where a human approves.

```mermaid
flowchart LR
    PLAN --> REVIEW --> G1{{🚧}} --> BR[build-red] --> BUILD --> TEST --> G2{{🚧}} --> DOCS --> SHIP --> CLOSED
```

| Stage | What happens | Agents that can launch | Entrance gate |
|---|---|---|---|
| PLAN | Write README / SPEC / TEST | none | — |
| REVIEW | Review the specification independently | qa | SPEC / TEST exist, clause references are valid |
| 🚧 | A human approves the specification | | |
| build-red | Write the tests first and confirm they fail | tester | Seal, clause references |
| BUILD | Implement | backend / frontend / tester | The Test IDs in TEST exist in the test code |
| TEST | Run the tests and evaluate quality | tester / qa | Evidence is newer than the sources and green, file size |
| 🚧 | A human approves the test results | | |
| DOCS | Update the specification documents, commit the implementation and documents | qa | Evidence, Test IDs were executed and passed |
| SHIP | Check implementation quality, push the branch | qa | Evidence, Test ID execution, seal |
| CLOSED | Maintenance | all | The commit hash is filled in |

### 4.2 Commands

You drive the harness in two ways. `bash harness/bin/sprint` does the work; the `/sprint` skill calls it.

#### `bash harness/bin/sprint <subcommand>`

This command is the only way to change `.sprint/flags.json`. Edit the file directly and `edit-scope-gate.sh` refuses the write.

State:

| Subcommand | What it does |
|---|---|
| `stage <STAGE>` | Moves the active sprint to a stage. It advances one stage only and refuses skips. Rollback is always allowed. Advancing runs the gate |
| `set-status <open\|doing\|closed>` | Updates progress within the stage |
| `new <id> <dir> [kind]` | Creates a sprint. Expands README / SPEC / TEST from the templates and makes it active |
| `switch <id>` | Switches the active sprint |
| `get [<field>]` | Prints a value of the active sprint (stage if omitted) |
| `status [--json]` | Shows stage, seal, test failure count, evidence freshness, and recent transitions on one screen |
| `list` | Lists all sprints |
| `log` | Summarizes the stage transition log (rollbacks and gate failures) |
| `set-kind` / `set-dir` / `rename` | Changes the kind, directory, or ID |

Running tasks:

| Subcommand | What it does |
|---|---|
| `run <task>\|all [<component>] [-- <extra args>...]` | Starts the adapters in the order of `tasks` in the configuration and writes the JSON of the evidence contract. A run with extra arguments is a partial run, and its evidence goes to `.partial.json` |

Checks:

| Subcommand | What it does |
|---|---|
| `gate <STAGE>` | Runs a stage gate by hand (no transition) |
| `seal` / `seal-verify` | Seals SPEC.md / TEST.md, and verifies the seal |
| `spec-lint [<check>...]` | Machine checks of the specification (`graph` / `refs` / `test-id`) |
| `spec-graph [<args>...]` | Clause reference graph. No arguments means `verify` |
| `spec-coverage [<args>...]` | Clause reference coverage (cov / rcov / tcov). An indicator that never fails |
| `api-routes` | Compares the public route sets both ways |
| `size-audit` | Lists files over the size limit |
| `spec-check [<dir>]` | Structure check of SPEC.md / TEST.md |

#### `/sprint` (a Claude Code skill)

Copy `harness/skills/sprint/SKILL.md` to `.claude/skills/sprint/SKILL.md` to use it. The main session runs the sprint; the skill holds the procedures it follows.

| Command | Short | What it does |
|---|---|---|
| `/sprint status` | `stat` | Runs `sprint status` and shows the state |
| `/sprint resume` | `r` | Restores context after `/clear`. Reads the state, README / SPEC / TEST, and CLAUDE.md, and shows the next task |
| `/sprint handover` | `ho` | Prepares for `/clear`. Checks 6 items, fixes what it can, and returns a table |
| `/sprint new <id> <name>` | `n` | Derives `sprint_dir` from the name and runs `sprint new` |
| `/sprint switch <id>` | `sw` | Switches the active sprint |
| `/sprint stage <STAGE>` | `stag` | Moves one stage (does no work) |
| `/sprint [to] <STAGE>` | `t` | Does the work of each stage up to the target stage, then stops |
| `/sprint help` | `he` | Lists the commands |

- `/sprint to <STAGE>` never passes a 🚧 gate (after REVIEW, after TEST). It stops there and waits for the user
- Coverage indicators live in the `/spec-coverage` skill (`harness/skills/spec-coverage/SKILL.md`)

### 4.3 Hooks and gates

Hooks are registered in `.claude/settings.json`. The hooks that block run before a tool call; the hooks that record run after it.

| Hook | When it runs | What it does |
|---|---|---|
| `agent-gate.sh` | Before an agent launches | Allows or refuses the launch based on the stage and the role |
| `edit-scope-gate.sh` | Before Write / Edit | Refuses writes based on the role and the file type. Also refuses writes to sealed regions and to `.sprint/flags.json` |
| `block-cd.sh` | Before Bash | Refuses `cd` and keeps the working directory at the project root |
| `record-test-fails.sh` | After Bash | Records the test failure count from the evidence |
| `log-tool.sh` / `log-agent-event.sh` | Before and after tools, agent start and end | Records operations |

Gates are listed stage by stage under `gates` in `sprint.config.json`. Here is the configuration in `sample/`.

| Stage | Gate tools | What they check |
|---|---|---|
| REVIEW | `spec-files-exist` / `spec-lint` | SPEC and TEST exist. Clause references, test handling of referenced clauses, and Test ID format are valid |
| build-red | `spec-seal` / `spec-lint` | The seal matches |
| BUILD | `tdd-exists` | The Test IDs in TEST exist in the test code |
| TEST | `results` / `size-audit` | Evidence is newer than the sources and green. No file is over the line limit |
| DOCS | `results` / `tdd-audit` | Every Test ID in TEST was executed and passed |
| SHIP | `results` / `tdd-audit` / `spec-seal` | The DOCS checks, plus a matching seal |
| CLOSED | `ship-closed` | The commit hash is filled in in README |

When a gate fails, it sorts the cause into one of four classes (spec, impl, test, infra) and names the stage to go back to. It does not move the stage itself; a human decides where to roll back.

Three checks keep the specification, the implementation, and the documents in line.

- Clause references: each section of the specification gets a clause ID, and references are links to that ID. `spec-graph` checks that every target exists, no ID is duplicated, no references form a cycle, no link is broken, and no section of another document is cited by its number
- Implementation and specification sets: the API routes are pulled out of the implementation and compared, in both directions, with the routes the specification lists (only when configured)
- Clause changes: in DOCS, the clauses whose content changed are pulled from the diff and checked against the test handling declared in SPEC

### 4.4 Contracts

The harness asks a project for four agreements and nothing more. Only `harness/adapters/` holds technology names; the core deals with a project through these four alone.

| Contract | Content |
|---|---|
| Task contract | The verbs are fixed to five: `lint`, `typecheck`, `build`, `test`, `e2e` |
| Evidence contract | Results go to `<evidence.dir>/<component>.<task>.json` as JSON in a fixed format |
| Layout contract | Component and docs locations come from `sprint.config.json`. The core holds no paths |
| Set contract | Implementation sets (API routes) come from running or importing the implementation, not from regular expressions |

### 4.5 Structure

```
.
├── README.md
├── docs/                         Specifications of the sprint process and the gate tools (copy README.md and 6 documents to the target repository)
│   ├── README.md                 Structure of docs/ (01_overview to 08_decisions)
│   ├── 07_plans/README.md        How to write sprint plans and records. Adoption situations and measurement
│   ├── 04_standards/02_testing.md          Normative rules for testing
│   ├── 04_standards/03_spec-structure.md    Normative rules for the structure of specifications (apply upstream, refactor afterwards)
│   ├── 05_specifications/README.md         How to write clause IDs
│   └── 06_process/
│       ├── sprint-process.md               Stage definitions, agent launch control
│       └── gate-tools.md                   Gate tool specification, contracts
├── harness/                      The harness core (copy it as is to the root of the target repository)
│   ├── bin/sprint                Runner (new / stage / run / gate)
│   ├── lib/                      Reading of configuration and evidence. Root resolution
│   ├── tools/                    Verification tools (for example, spec-graph, spec-coverage, xref)
│   ├── gate-tools/               Stage gates
│   ├── hooks/                    Claude Code PreToolUse / PostToolUse hooks
│   ├── adapters/                 Execution and evidence conversion for each runner (eslint-tsc / node-vitest / playwright / vite-build)
│   ├── templates/                Templates for SPEC / TEST / README, and for upper and leaf specifications
│   ├── agents/                   Templates for agent definitions (backend / frontend / tester / qa)
│   ├── skills/                   /sprint and /spec-coverage skills
│   └── tests/                    Regression tests of the harness core (python3 unittest. 85 tests)
└── sample/                       Sample of the form after import (1 component, TypeScript + vitest)
    ├── sprint.config.json
    ├── harness -> ../harness
    ├── .claude/                  settings.json (hooks), agents/, skills/
    ├── app/                      Minimal project
    ├── docs/                     01_overview to 08_decisions. 07_plans/01_hello/01_hello has a record that passed all gates
    └── .sprint/                  Record of the work state (flags.json, logs/). Committed as a sample
```

### 4.6 Notes

- `harness/bin/sprint` looks for the project root in this order: `CLAUDE_PROJECT_DIR` → the first directory containing `sprint.config.json`, walking up from the cwd → the git top level → pwd. One git repository can hold several projects (like `sample/` here); run the command inside the project's directory and the runner finds it
- Stage and gate definitions are in `docs/06_process/sprint-process.md`. Gate tools, contracts, and adapters are covered in detail in `docs/06_process/gate-tools.md`

## 5. Usage

### 5.1 Before you start (disclaimer)

This section is for anyone who wants to add the harness to their own project. The code blocks in §5.4 and §5.6 are **prompts**: you paste them into your own Claude Code, and Claude Code carries them out. They are not instructions for you to follow by hand.

- The prompts write files into your repository and run commands (tests and gates). Read them and understand what they do before you paste them. If a step is unclear to you, do not use it
- The prompts tell the AI not to change anything outside the target repository. Whether it complies depends on the AI that runs them and on your Claude Code permission settings, so run them with settings that do not allow writes outside the repository
- Install the dependency commands (§5.3) yourself before you start. Do not let the AI install them
- The harness is provided as is. The author accepts no responsibility for the results of using it

### 5.2 Prerequisites

#### Environment

Ubuntu 24.04 LTS or later.

#### Required commands and features

| Command | Features used | Verified implementation |
|---|---|---|
| bash | 4 or later. `declare -A`, `mapfile` | GNU bash 5.2 |
| jq | — | 1.6 |
| python3 | Standard library only. No pip | 3.11 |
| git | — | 2.54 |
| coreutils | `readlink -f`, `stat -c`, `sha256sum`, `date +%s%3N`, `realpath --relative-to`, `comm`, `sort -t / -n / -u`, `head -c`, `tail -F`, `mktemp -d` | GNU 9.1, uutils 0.11.0 |
| findutils | `find -name / -type / -o / -newer / -maxdepth`, `xargs -r -d` | GNU 4.9, uutils 0.10.0 |
| sed | `-E`, `-n`, `-i` (only `harness/tools/hook-replay.sh` uses `-i`) | GNU 4.9 |
| grep | `-E`, `-o`, `-q`, `-x`, `-n`, `-r`. No `-P` | GNU 3.8 |
| awk | `-F`, `-v` (within POSIX) | mawk 1.3 |

Test runners such as vitest or pytest belong to your project, so they are not listed here. `sample/` uses Node and npm.

### 5.3 Installation

Install the dependency commands yourself before you hand over the import prompt (§5.1).

1. Install the packages:

   ```bash
   sudo apt-get install python3 jq git
   ```

2. Check them. Each line should print what its comment says:

   ```bash
   bash -c 'echo $BASH_VERSION'   # 4.0 or later
   jq --version
   python3 --version
   sed --version | head -1        # GNU sed
   date +%s%3N                    # 13-digit number
   readlink -f .                  # absolute path
   ```

### 5.4 Import (first time)

Give the following prompt to Claude Code as is.

```
Import claude-sprint-process-en (https://github.com/jitte/claude-sprint-process-en) with the following steps.

0. Do not change anything outside the target repository (system directories, shell
   settings, packages).
   If a dependency command (the table in the "5.2 Prerequisites" section of README) is missing, do not install it
   yourself. Ask the user to install it.

1. Run `git clone https://github.com/jitte/claude-sprint-process-en`. Copy `harness/`
   as is to the root of the target repository. Copy `harness/skills/<name>/SKILL.md`
   to `.claude/skills/<name>/SKILL.md` (2 skills: sprint and spec-coverage).

2. Copy `sample/sprint.config.json` to the root of the target repository. Ask the user
   about the following items and rewrite them. Do not choose the values yourself.
   - `project.name`, `project.timezone`
   - `components`: the component name, directory, role (for example, backend or
     frontend), the src and tests globs, the adapter for each verb (lint / typecheck /
     build / test / e2e), and the pre commands (omit them if there are none)
   - `docs`: `templates`, `livingDirs`, `sprintRoot`, `specDir`, `docAliases`
   - `evidence.dir`: the default is `.sprint/test-result`. Ask about it only if the
     value changes
   - `sets`: the commands that get project-specific sets (for example, the command
     that gets the routes)
   - `gateToolsDirs`: if the project has its own gate tools, add a second
     directory
   - `gateToolClasses`: only if the project has its own gate tools, write their
     default failure classes
   - `gates`: the list of tools to run at each stage. You can start from `gates.code` /
     `gates.docs` in `sample/sprint.config.json`
   Do not rewrite `tasks`. Keep it fixed to the 5 verbs
   `["lint", "typecheck", "build", "test", "e2e"]`.
   There are 4 bundled adapters: `node-vitest`, `eslint-tsc`, `vite-build`, `playwright`.
   If a runner that you use is not one of these 4, write new `run-<verb>` and
   `convert-evidence` files in `harness/adapters/<name>/`.

3. Copy `docs/README.md`, and create `docs/01_overview` to `docs/08_decisions` with that
   structure. Copy the 6 documents of 04 / 05 / 06 / 07 (`docs/04_standards/02_testing.md`,
   `docs/04_standards/03_spec-structure.md`,
   `docs/05_specifications/README.md`, `docs/06_process/sprint-process.md`,
   `docs/06_process/gate-tools.md`, `docs/07_plans/README.md`) to the target repository,
   at the same relative paths as in this repository. `harness/templates/` and `harness/agents/` have links to these paths.
   Do not change the paths. For 01 / 02 / 03 / 08, ask the user and write 1 file each
   (1 paragraph of overview, 1 or more requirements, 1 paragraph of design, 1 design
   decision). If the user has nothing for one of them, create a file that contains only
   "Not filled in".

4. Copy `harness/templates/README.md`, `SPEC.md`, and `TEST.md` to `docs.templates` in
   `sprint.config.json`. Fill in the 4 placeholders `{{spec_docs}}`, `{{common_clauses}}`,
   `{{static_check_example}}`, and `{{run_commands}}`.
   Copy `spec-upper.md` and `spec-leaf.md` (the templates for upper and leaf
   specifications, `docs/04_standards/03_spec-structure.md`) to the same place. They have
   no placeholders.

   Copy `harness/agents/` to `.claude/agents/`. Always copy `tester` and `qa`.
   Copy `backend` and `frontend` only if `sprint.config.json` of the target repository
   has a component with the same `role` (do not copy an agent for a role that does not exist).

   The placeholders in each file (measured with `grep -o '{{[a-z_]*}}' harness/agents/*.md | sort -u`):

   | File | Placeholders |
   |---|---|
   | backend.md | `{{project_name}}`, `{{tech_stack}}`, `{{implementation_rules}}`, `{{files_to_read}}`, `{{contract_spec_paths}}`, `{{extra_tools}}` |
   | frontend.md | `{{project_name}}`, `{{tech_stack}}`, `{{implementation_rules}}`, `{{files_to_read}}`, `{{contract_spec_paths}}`, `{{extra_tools}}` |
   | tester.md | `{{project_name}}`, `{{tech_stack}}`, `{{implementation_rules}}`, `{{files_to_read}}`, `{{extra_tools}}` |
   | qa.md | `{{project_name}}`, `{{extra_tools}}`, `{{project_review_items}}`, `{{project_docs_items}}`, `{{project_ship_items}}` |

   There are 9 kinds in total (`project_name`, `tech_stack`, `implementation_rules`,
   `files_to_read`, `contract_spec_paths`, `extra_tools`, `project_review_items`,
   `project_docs_items`, `project_ship_items`). Ask the user for the values. Do not
   choose them yourself. Leave no placeholders.

   The format of `{{extra_tools}}`: if there are no extra tools, use an empty string.
   To add tools, append them to the existing tool list with a leading comma and space,
   like `, mcp__xxx__yyy`.

5. Copy `sample/.claude/settings.json` as is to `.claude/settings.json` of the target
   repository. The hooks point to `harness/hooks/*.sh`.

6. In `.gitignore`, write the directories of the dependencies that this import creates,
   in the form `name/` (for example, `node_modules/`). Also write `.sprint/*` and
   `!.sprint/spec-hashes.json`. `.sprint/` holds the work state (`flags.json`, `logs/`,
   evidence). Track only the seal hashes (`spec-hashes.json`). `sample/` commits
   `flags.json` and `logs/` to show the record, but a real project does not track them.

7. Check the following. Finish only after you confirm that all of them pass.
   - `bash harness/tests/run.sh`
   - `bash harness/bin/sprint new <id> <dir>`
   - `bash harness/bin/sprint run all`
   - `bash harness/bin/sprint gate TEST`

8. Write the commit hash of this repository that you imported to `harness.version` in
   `sprint.config.json`. Write the URL of this repository to `harness.source`
   (for example, `https://github.com/jitte/claude-sprint-process-en`).
   These 2 items are records only. The tools do not read them. How to get them:
   - `harness.version`: `git -C <clone of this repository> rev-parse HEAD`
   - `harness.source`: `git -C <clone of this repository> remote get-url origin`

Always ask the user about points that need a decision. Use `sample/` as the sample of the form after import.
```

### 5.5 Checks after import

The AI runs step 7 of the prompt and reports that the checks passed. Run the commands below at the root of the target repository and compare the results with the report. Check the exit code with `echo $?` right after each command.

| Check | Result when it passes |
|---|---|
| `bash harness/tests/run.sh` | The output ends with `Ran 85 tests in ...` and `OK`. Exit code 0 |
| `ls .sprint/flags.json <dir>/README.md <dir>/SPEC.md <dir>/TEST.md` | The 4 files are listed. `<dir>` is the directory that the AI gave to `sprint new` in step 7 |
| `bash harness/bin/sprint run all` | `<component>.<task>.json` appears in `evidence.dir` of `sprint.config.json` (default `.sprint/test-result`) for each verb set in `components`. Exit code 0 |
| `bash harness/bin/sprint gate TEST` | Under `=== Gate Check: TEST (kind=code) ===`, there is one `✓ <tool>` line for each gate tool, and the last line is `=== GATE PASSED ===`. Exit code 0 |

`sprint new` cannot run twice with the same id (it prints `sprint already exists` and exits with code 1), so check it by looking for the files it created.

`harness/tests/run.sh` runs `harness/tests/test_*.py` with `unittest` from the python3 standard library. The tests check the behavior of lib, gate-tools, hooks, adapters, spec-graph, spec-lint, and spec-coverage against fixtures. They do not read the target repository's docs, so all 85 pass whatever state the target repository is in.

### 5.6 Re-import (update)

Give the following prompt to Claude Code as is.

```
Import the latest version of claude-sprint-process-en (https://github.com/jitte/claude-sprint-process-en) with the following steps.

1. Read the difference between `harness.version` in `sprint.config.json` and the latest
   commit of https://github.com/jitte/claude-sprint-process-en,
   and identify the changes.

2. Copy `harness/` (including `tests/` and `skills/`) and overwrite the existing files.
   Do not copy over the files already copied to `docs.templates`, and do not copy
   `.claude/agents/`. The project filled in those files.

3. If `schemaVersion` in `sprint.config.json` increased, read the difference and fix the settings.

4. Check the following. Finish only after you confirm that all of them pass. Do not run
   `sprint new` (it creates an extra sprint in a project that is in progress).
   - `bash harness/tests/run.sh`
   - `bash harness/bin/sprint status` (the first line is `Sprint:   <id>  [<stage> / ...]`)
   - `bash harness/bin/sprint run all`

5. Update `harness.version` to the commit hash that you imported.
```

Run rows 1 and 3 of the table in §5.5, plus `bash harness/bin/sprint status`, and compare the results with the report. Gate results depend on the current stage, so they are no use for checking an update.

### 5.7 sample

A minimal project with one component, in TypeScript with vitest. It has the eight directories `docs/01_overview` to `docs/08_decisions`, and a single clause, HELLO-1, in `docs/05_specifications/hello.md`. `docs/07_plans/01_hello/01_hello` holds the record of a sprint that passed every gate from PLAN to CLOSED.

```bash
cd sample
npm --prefix app install
bash harness/bin/sprint run all
bash harness/bin/sprint gate TEST
```

Read `docs/07_plans/01_hello/01_hello` as an example of how to write a sprint record.
