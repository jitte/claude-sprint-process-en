# Sprint plans and records

## 1. Units and names

The only unit of progress is the sprint. Do not use the words phase, wave, step, or milestone.

- The ID is `<major>-<minor>`. major is a group of consecutive sprints. minor is the order in that group. Both start from 1
- Records go in `<docs.sprintRoot>/<major, 2 digits>_<slug>/<minor, 2 digits>_<slug>/`. Put README.md, SPEC.md, and TEST.md there. Create them with `bash harness/bin/sprint new <major>-<minor> <dir>`
- Write the plan for each major in `<docs.sprintRoot>/<major, 2 digits>_<slug>/README.md`

## 2. How to write a plan

Write a plan as a list of sprints. The initial development plan is sprint 1-1 to 1-N. Write the ID, kind, and purpose on 1 line.

| sprint | kind | purpose |
|---|---|---|
| 1-1 | docs | Write 01_overview and 02_requirements |
| 1-2 | docs | Write 03_design and 04_standards |
| 1-3 | code | The first component, and evidence of lint / typecheck / build / test |

kind is docs or code. A docs sprint does not pass through the code gates (results, tdd-*, impl-sync, size-audit). The definition is in `docs/06_process/sprint-process.md`.

## 3. Adoption situations

The state of the project at the time of import decides the first sprint and when to define `sets`.

| Situation | First sprint | `sets` in `sprint.config.json` |
|---|---|---|
| No code | kind=docs from 1-1. Write 01 to 04 | Write `components` in the first code sprint. Define `sets` after code exists |
| Much existing code and no clauses | kind=docs from 1-1. Write 05 from the implementation | Define them after the clauses cover the implementation sets. When you define them, impl-sync reports all mismatches. Until then, impl-sync compares nothing |
| Both specifications and implementation exist | kind=code from 1-1 | Define them at import |

## 4. Specification metrics

The definitions of metrics and commands are in `docs/06_process/spec-metrics.md`.
