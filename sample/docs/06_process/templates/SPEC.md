# SPEC — Sprint [major]-[minor]

> Implementation contract. The main reference for the backend / frontend agents.
> For the review, see `README.md`. For the test design, see `TEST.md`.
> **Seal**: `bash harness/bin/sprint seal` seals this whole file with a hash. Only main can
> rewrite and reseal it. backend / frontend / tester / qa have read-only access.

---

## 0. Referenced common clauses

List the common clauses that this sprint follows in the form `[ID](<relative path>#ID)`. **Do not restate their content.**
Write the relative path from this SPEC.md (`<docs.sprintRoot>/<major>_<slug>/<minor>_<slug>/SPEC.md`).
To list the clauses, run `bash harness/bin/sprint spec-graph files`. To verify, run `bash harness/bin/sprint spec-graph`.

**For each referenced clause, declare how to handle the tests.** Write one of the 4 handling values (`new` / `modify` / `reuse` / `none`).
An empty cell makes the REVIEW gate (refs of `spec-lint.sh`) fail. The purpose is to record the decision.
The gate does not force a test to exist.

| Referenced clause | Reason | Test handling | Test ID / reason |
|---|---|---|---|
| [HELLO-1](../../../05_specifications/hello.md#HELLO-1) | Verifies the output | new | TEST-1-1-1.1 |

- **new**: Write a new test in this sprint. The Test ID belongs to this sprint
- **modify**: Change an existing test. A deletion is also `modify`. **If an existing test goes red, the handling is `modify`.** For a change that makes a verdict condition stricter (limiting the allowed values, making a value required), scan the fixtures of the existing tests in PLAN (use `rg` to see how the input values are built). Declare each fixture that does not meet the condition as `modify`
- **reuse**: An existing test guarantees the behavior without change. Do not touch it in this sprint
- **none**: The behavior under test does not change. Context references and term references are in this category. A change that "makes the implementation follow the clause" changes the behavior. Its handling is `new`, not `none`
- Test IDs of old sprints are not unique. Quote them in the form `<sprint_id> TEST-x.x` (example `12-1 TEST-3.2`)
- If one clause has more than one handling, write the same clause on more than one row
- For a sprint with no references, write the single row `| (no references) | — | none | Does not depend on common clauses |`


---

## Base specification references

| Domain | File | Section | Diff type |
|---------|---------|----------|---------|
| — | `<docs.specDir>/*.md` | — | Add / Change / None |

---

## Implementation units and dependencies

Declare the **units that can proceed in parallel** in BUILD. In BUILD, `agent-gate.sh`
allows backend / frontend / tester to run at the same time. You can start units with no dependencies at the same time.

| Unit | Owner | Depends on units | Notes |
|------|------|------------|------|
| — | backend / frontend / tester | None | — |

- **Start in parallel** the units whose "Depends on units" is None
- The API types and schemas (shared schemas) must be fixed before the FE implementation.
  Thus an FE unit depends on the BE unit that defines the schema
- If there is a **merge point** (for example, integration tests and E2E tests that run after all units are complete), write it in Notes

---

## EARS requirements

### N-x.x — Normal Cases

- **N-1.1**: WHEN `<actor>` `<trigger>` THE system SHALL `<response>`

### E-x.x — Error Cases

- **E-1.1**: IF `<invalid condition>` THEN the system SHALL `<rejection behavior>`

---

## State transitions (optional)

| Start state | Trigger | End state | Corresponding EARS |
|---------|---------|---------|----------|
| — | — | — | N-x.x |

> Delete this section in a sprint with no state transitions.

---

## APIs used and type check

List all APIs that the sprint uses. Check that the shared schemas have a type for each API. If a type is missing, write the schema definition in this SPEC. The backend agent creates it in build-green.

<!-- UNSEAL:BEGIN -->

| API | Purpose | Shared schema type | State |
|-----|------|-------------------|------|
| `GET /api/v1/xxx` | — | `XxxResponse` | ✅ Existing / ⬜ To create |

<!-- UNSEAL:END -->

> If a type is "To create", write all of its fields in the "Schema definition" section below.

### Schema definition (if a type is missing)

```typescript
// Add to the shared schema xxx
export const xxxSchema = z.object({
  // Write all fields
})
export type Xxx = z.infer<typeof xxxSchema>
```

> Delete this section if the types of all APIs already exist.

---

## Interface Contracts (only when you create a new API)

### `METHOD /api/v1/xxx`

**Request**:
```typescript
export const xxxSchema = z.object({
  // ...
})
```

**Response** (200):
```typescript
export type XxxResponse = {
  // ...
}
```

> Delete this section in a sprint that creates no new API.
