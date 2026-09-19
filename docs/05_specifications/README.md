---
xref-prefix: RULE
---

# 05 Detailed specifications

Normative rules for writing module specifications in EARS format. This document defines clause IDs, reference notation, and `api-routes` declarations.

---

### frontmatter

```yaml
---
xref-prefix: FOO
layer: core
impl: src/domain/foo/
---
```

| Item | Required | Meaning |
|------|------|------|
| `xref-prefix` | Required | Prefix of clause IDs. 2 to 6 uppercase ASCII letters. Unique in the whole corpus. **An md that declares it has clauses.** The folder does not matter |
| `layer` | Optional | An indicator. If you write it, use one of `common` / `core` / `supporting` / `generic` / `operation` / `frontend` / `design`. `bash harness/tools/spec-graph.sh layers` uses it for its counts. It does not decide whether a reference is allowed |
| `impl` | Optional | Main implementation path (relative to the repository). If you write it, its existence is verified |

---

<a id="RULE-1"></a>
## [RULE-1] 3. Clause IDs and references

### Declaring a clause

Embed the ID in the form `[CORE-4]` in a heading or in the first cell of a table row. **Put an explicit anchor on the line just before the heading.**

```markdown
<a id="CORE-4"></a>
### [CORE-4] 3.1 Debit-credit balance check
```

- Only an `[ID]` in a **heading line or the first cell of a table row** counts as a declaration. `[CORE-4]` in prose is neither a declaration nor a reference
- **Put the anchor alone on the line just before the heading. Do not change the heading line itself.** The id that GitHub generates from a heading includes the heading text, so each change of wording breaks the references
- `bash harness/tools/clause-anchors.sh` places the anchors (idempotent. Do not write them by hand)
- IDs do not repeat in the whole corpus. **Serial numbers are append-only. Do not reuse a missing number**
- The range of a clause extends to the next clause declaration or to the next heading of the same or a higher level (lower-level headings are in the range)

### What to make a clause

**A clause is "a unit of normative text that can be referenced".** Do not decide by heading level mechanically.

| Make it a clause (normative) | Do not make it a clause (non-normative) |
|---|---|
| Behavior and constraints (`the system shall` / `If ... then`) | Reasons and background (`Why it is needed`) |
| Structure definitions (tables, types, request/response shapes) | Traceability lists (`Mapping`) |
| Boundary declarations (responsibilities, scope, boundaries with other modules) | Grouping headings that only bundle lower sections |
| Definitions of classifications and mappings (lists of allowed values, systems) | Sections with only diagrams (mermaid / ASCII diagrams only) |
| Verification aspects (each section of `Test aspects`) | Rewording of a concept |

- **Judge each section by reading its body.** Do not sort by heading name only. Two sections with the same name can differ: one has normative text, and the other does not
- **Do not mass-produce clauses with the same name.** If you turn a heading that appears in every module, such as `Responsibilities`, into a clause everywhere, unreferenced clauses increase and the graph loses meaning. Put the module name in the clause name to make it unique
- **When you promote a table to a clause, reconcile the cell contents with the implementation before you copy them.** Table text is a loose note, but a clause becomes normative. A promotion is not a move. It is the writing of a new norm. This accident happens: a value loses its "etc.", becomes `the system shall`, and does not exist in the implementation

### References

```markdown
Clause in another file:  Time handling follows [COM-20](10_common.md#COM-20).
Clause in the same file: Debit-credit balance follows [CORE-4](#CORE-4).

Double-bracket notation (remains in sealed SPECs in docs/07_plans. Reading still accepts it. Do not write it in new documents):
                    Time handling follows [[COM-20]].

Do not put the title in the display text:
                    [CORE-4 Debit-credit balance check](#CORE-4)

Do not point to a section of another file by an abbreviation and a section number:
                    design document §2 / specification document §4.9
```

- **When reading**, only `[<ID>](<relative path>#<ID>)` / `[<ID>](#<ID>)` and strings that match the double-bracket notation count as references. `<ID>` is 2 to 6 uppercase ASCII letters + `-` + digits
- **Write the relative path relative to the referrer file. Do not write a relative path for a clause in the same file**
- **Make the display text the clause ID only.** If you include the clause title, each title change requires updates to all references
- The target heading has `<a id="<ID>"></a>` on the line just before it. GitHub and Obsidian use it to jump to the target
- **New specifications and SPECs use only the link notation (`[<ID>](<relative path>#<ID>)`).** The REVIEW gate (refs in `harness/gate-tools/spec-lint.sh`) **accepts only the link notation** in a sprint SPEC's §0
- **Reading continues to accept the double-bracket notation.** Sealed SPECs in `docs/07_plans` use it, and they are not rewritten. `spec-graph.sh` parses both as references
- **Test names (the first argument of `describe` / `it` / `test`) are referrers.** `spec-graph.sh` reads a clause ID written in a test name as a reference ([TSTD-6](../04_standards/02_testing.md#TSTD-6))
- **Use the double-bracket notation in test names.** The link notation has no meaning in code
- `bash harness/tools/clause-anchors.sh` does the conversion (idempotent)
- Code fences and inline code are not scanned. **To show a notation itself as an example, put it in a code fence**
- **Do not point to a section of another file by an abbreviation and a section number** (the "design document §x" form in the fence above. V11 detects it). Add a clause ID to the target section and write `[ID](<relative path>#ID)`. You can write section numbers within the same file
- **A reference means "follow this norm".** Do not use a reference to explain how something looks downstream
- **Do not restate the content of the target.** The exception is an excerpt that is clearly marked as a quotation. When you add a reference, delete the restated body text. If you keep the body text, write in the clause that it is a summary and that the norm is in the target
- **When you write a clause in a new layer, first cite the existing clauses that define the same subject.** Scan `docs/05_specifications/**` for the subject words, and read the clauses that match. If they overlap, reference them and follow them. If you write something different, record why it is different in the "Decisions" table of an ADR / SPEC. `spec-graph` checks that references exist and that there are no cycles. It does not check whether the same subject is defined in another place
- **When you add a reference, read the target.** Confirm that the clause has `the system shall` and that it defines that subject. `spec-graph` checks that the target exists, but not what it defines

### Layers (indicator)

The direction of references is an **evaluation indicator** of the dependency structure, not a constraint. The machine does not check the direction.
`bash harness/tools/spec-graph.sh layers` counts the references between files that declare `layer`, as "referrer layer × target layer", and prints a table.
Files without `layer` count as `-`.

```bash
bash harness/tools/spec-graph.sh layers        # table of reference counts, layer × layer
bash harness/tools/spec-graph.sh deps <FILE>   # breakdown of the clauses that the file references
```

Write the expected dependency direction (for example, supporting → core → generic, and generic only reads) in the design documents of the project. If the counts show the opposite direction, suspect the location of the norm, not the reference.
Move norms shared across layers to the common layer (`common`). Move norms shared within a layer to the higher-level specification.

- A file that does not declare `xref-prefix` (a consumer) can reference all clauses. Its references do not count as edges
- V10 detects cycles in any direction (principle: the reference graph is a DAG)

### Verification

```bash
bash harness/bin/sprint spec-graph                          # verify (V1 to V3 / V5 / V6 / V8 to V11)
bash harness/tools/spec-graph.sh files         # list of files that have clauses
bash harness/tools/spec-graph.sh layers        # reference counts, layer × layer
bash harness/tools/spec-graph.sh reverse <ID>  # reverse lookup of referrers (impact scope)
bash harness/tools/spec-graph.sh deps <FILE>   # clauses that the file references
bash harness/tools/spec-graph.sh resolve <FILE># source text + body text of the reachable clauses
bash harness/tools/spec-graph.sh diff <ref>    # clauses whose content changed, and their referrers
bash harness/tools/clause-anchors.sh --check   # list missing anchors and missing reference links (no writes)
bash harness/tools/clause-anchors.sh           # place anchors and convert references to links (idempotent)
```

`clause-anchors.sh` is a repair tool, not a verification tool. Run it after you add clauses.

| # | Verification |
|---|------|
| V1 | Uniqueness of prefixes |
| V2 | Uniqueness of clause IDs |
| V3 | Existence of references |
| V5 | Existence of `impl` paths |
| V6 | frontmatter (existence and format of `xref-prefix`, values of `layer`, files that have clause headings but no `xref-prefix`) |
| V8 | Existence of relative paths in links |
| V9 | Existence of target anchors |
| V10 | No cycles in the clause reference graph (self-references included. References from consumers are not edges) |
| V11 | No references by section-number strings. Pattern 1: a line where § appears within 8 characters after a file name. Pattern 2: a line where § and a digit come right after an identifier-shaped word (joined with `_` or `-`, 2 or more uppercase letters, or 2 or more digits) or an alias in the `docs.docAliases` setting (a reference by abbreviation). Code fences are out of scope |

V8 / V9 exclude `docs/06_process/templates/**`. Relative paths in templates are written for the depth of the copy destination, so they do not resolve at the location of the template itself.

V11 covers living documents (templates included), unsealed sprint SPECs, and md files at the repository root.
Section numbers after an ordinary word, and section numbers within the same file (the form with neither a file name nor an abbreviation: "(§3)", "in §8"), are out of scope. To point to a section of another file, add a clause ID to the heading of that section and reference it. Register an abbreviation that the file name does not give in `docs.docAliases`.
Template sections have no clauses, so refer to them by title (for example, the "6. RETRO" section of the template README).

The REVIEW gate runs it. The specification is in the graph section of `docs/06_process/gate-tools.md`.

### How to write API routes and the `api-routes` declaration

`bash harness/bin/sprint api-routes` compares the set of public routes in the implementation and the set of routes written in this directory, in both directions. If they differ, the TEST gate fails. The specification is in the routes section of `docs/06_process/gate-tools.md`.

**Write a route in the form `<METHOD> <path>`.** You can include or omit `/api/v1`. You can write it anywhere: in a code block, a heading, an EARS sentence, or a table of used APIs. Extraction excludes the following.

| Exclusion | Reason |
|------|------|
| Inside a ` ```mermaid ` fence | Participant names and transition labels in diagrams are not API definitions |
| Inside a ` ```api-routes ` fence | It is a declaration, not a definition |
| Paths that contain `*` | A generic form such as `GET /items/*` does not point to a single route |

**Do not abbreviate paths.** A form with only the tail, such as `PATCH /deactivate`, is detected as a route that does not exist. Write the full form: `PATCH /api/v1/{resource}/:id/deactivate`. When an explanation mentions a route that is not in the implementation, do not use the `<METHOD> <path>` form.

Write the declarations for the comparison in an ` ```api-routes ` fence. **Put the fence inside the clause that is the source of the rule.** If the declaration and its basis are apart, only one of them gets updated. Write 1 declaration per line. The vocabulary has only 2 words.

```
expand <placeholder> = <value>, <value>, ...
alias  <METHOD> <implementation path> -> <specification path>
```

- `expand` instantiates a generic form
- `alias` maps a compatibility route to the canonical path
- A declaration that matches nothing fails (an unused placeholder, an implementation path that does not exist)
- **The vocabulary has no word that allows unimplemented or undocumented routes.** Do not let a mismatch pass through a declaration. Fix either the specification or the implementation

**Do not put declarations in the implementation (code, comments, configuration).** There are 2 reasons.

1. **The implementation could exempt itself from its own check.** The target of the check would write the conditions of the check, and the check would lose its meaning
2. **The implementation language stays open.** This directory is a contract that is independent of the implementation. If you reimplement in another language or another framework, the declarations still work as they are. Only the procedure that extracts the public routes depends on the implementation, and you can replace it

The reading scope is limited to this directory and below. Declarations written in the implementation are not read, and they do not affect the check.
