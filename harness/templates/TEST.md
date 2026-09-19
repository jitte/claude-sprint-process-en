# TEST — Sprint [major]-[minor]

> Test specification. The main reference for the tester / qa agents.
> For the implementation contract, see `SPEC.md`. For the business view, see `README.md`.

---

## Test writing criteria

- **Write tests for all screens and all components.** A visual check is an aid. It does not replace a test
- Create a matching `.test.ts[x]` for each new file. Production code without a test is 🔴 in REVIEW
- Test all UI elements whose behavior changes (buttons, filters, forms, dialogs, disabled control)
- Coexistence with seed data: in a test of an API with pagination, do not `find()` over all records. Narrow the records with a filter ([TSTD-4](../../../04_standards/02_testing.md#TSTD-4))
- **Test ID rules (tdd-audit matches them against the execution evidence)**:
  - **Write the ID in the form `TEST-<sprint_id>-<major>.<minor>`** (example: `TEST-17-11-1.1`). `<sprint_id>` is
    the `active` value in `.sprint/flags.json`. You can number `<major>` / `<minor>` from 1 in each sprint.
    The prefix makes the ID unique across all sprints. Thus IDs do not collide in long-lived test files.
    The `spec-lint` gate (test-id) enforces the format ([GATE-4](../../../06_process/gate-tools.md#GATE-4))
  - A test definition row (a table row whose first cell is a Test ID) **must have the Test file column**
  - Do not write `ditto` in the Test file column. Write the path on each row. `tdd-audit` reads the path from the row itself. Thus `ditto` counts as an empty cell and causes a FORMAT fail
  - Include the Test ID in the **run name** of the test (the concatenated name of `describe` and `it`/`test`). The standard form writes the ID in the `it()` name (a `describe('TEST-<sprint_id>-x.y ...')` wrapper is also accepted). **The audit does not match IDs in comments**
  - In the name of the test, write the ID of the clause that defines the behavior the test verifies, in the form `[[ID]]`, next to the Test ID ([TSTD-6](../../../04_standards/02_testing.md#TSTD-6))
  - **Do not assign a Test ID** to a verification item that has no real test (for example, a line count check, a set check, a manual check). Write its type and method in the "Static verification items" table. qa measures it in the TEST stage ([TSTD-1](../../../04_standards/02_testing.md#TSTD-1))

## Completion criteria

- `bash harness/bin/sprint run all` is **all green**
- **Zero** `test.skip()` **remain**
- For every Test ID in TEST.md, the matching real test **runs and passes** (tdd-audit matches it against the result JSON)

---

## Test specification

### Unit tests (backend)

| Test ID | Corresponding SPEC | Test file | Test name | What it checks |
|---------|----------|---------------|----------|----------|
| TEST-1.1 | N-1.1 | — | — | — |

### Unit tests (frontend)

| Test ID | Corresponding SPEC | Test file | Test name | What it checks |
|---------|----------|---------------|----------|----------|
| TEST-2.1 | — | — | — | — |

### E2E

| Test ID | Corresponding SPEC | Test file | What it checks |
|---------|----------|---------------|----------|
| TEST-3.1 | — | — | — |

> If E2E is not needed, write "E2E not needed (reason: …)".

---

## Coverage matrix

| EARS ID | Test ID | Test file | Notes |
|---------|----------|---------------|------|
| N-1.1 | TEST-1.1 | <component>/…test.ts | — |
| E-1.1 | TEST-1.2 | <component>/…test.ts | — |

If a requirement is not covered, write the reason. A requirement that is not covered and has no reason is 🔴.

---

## Static verification items

Verifications that have no test. **Declare the type. Write the method that matches the type** ([TSTD-1](../../../04_standards/02_testing.md#TSTD-1)). An item with no type or no method is 🟡 in REVIEW.

| ID | Type | Target | Method | Expected value / verdict condition |
|----|------|------|------|------|
{{static_check_example}}

- Machine scan: write the expression, the expected value, the unit to count (lines / files), and the exclusions. Run the expression with `command grep` or a script
- Structural scan: write the tool command and the expected value
- Reading: write the range to read and the text that fails the check. "No line states the same norm" alone is not a condition you can judge

---

## Run commands

```bash
{{run_commands}}
```

---

## Results (filled in by qa)

> About the seal: `bash harness/bin/sprint seal` seals this file with a hash.
> **qa can edit only the `<!-- UNSEAL -->` block below.** Only main can rewrite and reseal everything else (the sealed region),
> including the test specification and the coverage matrix (this prevents self-evaluation).

<!-- UNSEAL:BEGIN -->

| Round | Date | Verdict | Result |
|---|---|---|---|
| — | — | 🔴🟡🟢 | — |

### Static verification measurements

Fill in the Recorder column. qa does not update the `main` rows. main writes the main rows (the rows share one UNSEAL block, so an instruction alone does not protect them).

| ID | Recorder | Measured | Verdict |
|----|--------|------|------|
| S-1 | qa | — | — |
| S-2 | main | — | — |

### Aspects not inspected

- —

<!-- UNSEAL:END -->
