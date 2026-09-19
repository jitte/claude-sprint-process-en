# Specification metrics

Measure how well specifications are structured, referenced, and tested.

## 1. Metrics

| Value | Meaning | Work when low |
|---|---|---|
| cov (clause rate) | The share of lines outside clauses. Judge whether they are unstructured norms or explanatory text | docs sprint. Turn them into clauses or delete them |
| rcov (referenced rate) | The share of unreferenced clauses | docs sprint. Delete the clauses or write referrers (`--unreferenced` prints the IDs) |
| tcov (test-referenced rate) | The share of clauses that test names do not reference | code sprint. Add `[[ID]]` to test names or write tests (`--untested` prints the IDs) |

- **Do not set thresholds on the values.** The values are material for choosing targets, not pass/fail criteria
- **Do not measure in the middle of a sprint.** No action exists for values in the middle

## 2. Commands

```bash
bash harness/bin/sprint spec-coverage               # All metrics
bash harness/bin/sprint spec-coverage --no-sprint    # Measure excluding the active sprint
bash harness/bin/sprint spec-coverage --unreferenced # List clauses with zero references
bash harness/bin/sprint spec-coverage --untested     # List clauses not referenced by tests
```

## 3. Recording the values

Measurement is done on user instruction. The user decides where to record the values and what to do with them.
