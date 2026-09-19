# Sprint [major]-[minor]: [Feature Name]

> Created: YYYY-MM-DD
> Status: PLAN
> Requirement IDs: [FR-XX / REQD-n]

---

## 1. Background and purpose

### Problem to solve
- Why this sprint is necessary
- What changes when the sprint is complete

### Corresponding specification documents
| Domain | File | Section |
|---------|---------|----------|
{{spec_docs}}

---

## 2. Scope

**MUST**:
- [ ] T-1: …
- [ ] T-2: …

**OUT OF SCOPE**:
-

---

## 3. Tasks and progress

### Task list

| # | Task | Agent | State |
|---|--------|------------|------|
| 1 | — | backend | ⬜ |
| 2 | — | tester | ⬜ |
| 3 | — | frontend | ⬜ |

State: ⬜ Not started / 🔧 In progress / ✅ Done

### BUILD (fill in during implementation)

#### Changed files

| File | Change type | Summary |
|---------|---------|------|

---

## 4. REVIEW

- Date and time:
- Verdict: 🟢 / 🟡 / 🔴

| Check item | Result | Notes |
|-------------|------|------|
| The specification documents and the scope are consistent | — | — |
| TEST.md covers the EARS requirements in SPEC.md | — | — |

### Audit of referenced clauses (R10. qa fills this in)

For each row of the "0. Referenced common clauses" section of SPEC, read the target clause text with `bash harness/bin/sprint spec-graph resolve <SPEC.md>`.
Judge whether the handling is valid. **As the basis, write which part of the resolve output you read to make the verdict.**

| Clause | Handling | qa verdict | Basis (key points of the clause text you read) |
|------|------|---------|---------------------------|
| — | — | 🟢 / 🟡 / 🔴 | — |

---

## 5. TEST

- Date and time:
- Verdict: 🟢 / 🟡 / 🔴

| Item | Result |
|------|------|
| `bash harness/bin/sprint run lint` | — |
| `bash harness/bin/sprint run typecheck` | — |
| `bash harness/bin/sprint run build` | — |
| `bash harness/bin/sprint run test` | — |
| `bash harness/bin/sprint run e2e` | — |

---

## 6. RETRO

### What went well
-

### Problems
-

### Improvements

-

### Pattern extraction
Record reusable patterns in the specification, the implementation, or the process, if any.

| Pattern | Applies to | Notes |
|---------|-------|------|
| — | — | — |

---

## 7. DOCS

Feed the implementation results back into the specification documents.

| Layer | File | Diff |
|----|---------|------|
| — | — | — |

### Reconciliation of referenced clauses (D4. qa fills this in)

Measure the **clauses whose content changed** with `bash harness/bin/sprint spec-graph diff <sprint start commit>`.
Reconcile them with the declarations in the "0. Referenced common clauses" section of SPEC. Mark a row 🔴 when the declaration and the actual result differ (example: a clause declared `none` changed / a `new` Test ID is not green).

| Clause | Declared handling | Actual result (measured diff and tests) | Verdict |
|------|------------|---------------------------|------|
| — | — | No change / Changed (n referrers), TEST-x.x green | 🟢 / 🔴 |

### Work commit (do this at the end of DOCS)

After you finish reflecting the changes into the base specification, **commit the implementation and the documents in the DOCS stage.** Record the hash in §8.

- [ ] Work commit done (record the hash in §8)

---

## 8. SHIP

- [ ] All tasks ✅
- [ ] `bash harness/bin/sprint run all` green
- [ ] REVIEW 🔴 = 0
- [ ] TEST 🔴 = 0
- [ ] RETRO filled in
- [ ] DOCS reflected
- [ ] Commit hash: <!-- The work commit of DOCS. Do not record the SHIP commit -->
