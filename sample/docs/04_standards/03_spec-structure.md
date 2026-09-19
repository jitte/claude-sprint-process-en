---
xref-prefix: SSTD
---

# Structure of specifications

Normative rules for applying a structure to a body of specifications upstream, and for refactoring them afterwards. 4 clauses (the structure, applying it through templates, the refactoring types and their completion conditions, the procedure).

---

## 1. Why structure matters

Specifications are written one file at a time, reference each other, and keep growing. Without structure, the same norm is written in several places, nobody can tell which copy is canonical, and a moved section number goes unnoticed. With structure, each norm has one home, a machine follows the references, and a change reaches the referrers.

Apply the structure when the first specification is written. Applying it to specifications that are already written takes a lot of work: repointing references and deciding which text is canonical. The means is a template. What is written in the template is written in a form that can be verified.

The deliverable of a sprint is correct by the standard of its time. When the standard is raised later, the gap that appears between it and the existing specifications is not damage; the standard changed. Refactoring starts from the specifications as they are, and raises their structural and content evaluation without changing the norms. It aims at the same structure, so it is not a separate set of rules.

Neither applying nor refactoring changes the content of the norms (the number and the meaning of `the system shall` / `If ... then`). Do not mix adding, deleting, or changing the meaning of a normative sentence into the same sprint as this work.

<a id="SSTD-1"></a>
### [SSTD-1] 1.1 The structure

The layered structure of the specifications is derived from the design.

| What the design decides | How it appears in the specifications |
|---|---|
| The partition of the domain (which business area owns which aggregate) | A layer of business modules. One upper specification and N leaf specifications |
| Shared behavior (the write entry point, the error shape, time, pagination) | A cross-cutting common specification. Every layer references it |
| The common UX of the screens (skeleton, parts, entry points) | The screen layer. One upper specification and N screen specifications |
| The API conventions (the shape of paths and responses) | The clauses that the API section of each module follows |

Each layer has one upper specification, and the leaf specifications are its specializations. A leaf writes only its difference from the upper specification. It does not restate the norms written above it. It references them as `[ID](<relative path>#ID)` and follows them.

The structure is held by the following 4 principles.

| # | Principle | Enforced by |
|---|---|---|
| 1 | Write each norm in exactly one place. Everywhere else, reference it | Nothing. A person finds violations by reading |
| 2 | Write references in a form a machine can follow. Detect broken ones | V3 / V8 / V9 / V11 |
| 3 | When a referenced clause changes, tell the referrers | `spec-graph.sh diff` (content hash of each clause) |
| 4 | The reference graph is a DAG. Detect cycles | V10 |

What follows from the 4 principles. The notation is in [RULE-1](../05_specifications/README.md#RULE-1).

- **The direction of a reference is an indicator, not a constraint.** Do not use layers, hierarchy, or folders to decide whether a reference is allowed. `spec-graph.sh layers` prints the counts per direction
- **There is not necessarily one root.** A specification is normally derived from several viewpoints. The references themselves express the derivation. Do not declare a parent
- **A file has clauses when it declares `xref-prefix`.** A folder is only a place to keep files
- **A reference means "this text follows that norm".** Do not link a pointer to where something lives, an explanation of downstream effects, or an introduction to background reading. Write the title in plain text
- **Do not write anything in a leaf that contradicts its upper specification.** Fix the upper specification. A contradiction placed in a leaf gives the same matter two homes

---

<a id="SSTD-2"></a>
## [SSTD-2] 2. Applying the structure through templates

Create every new specification file from a template. There are 2 templates in `harness/templates/`. Copy them to `docs.templates` when you adopt the harness.

| Template | When to use it | Its form |
|---|---|---|
| `spec-upper.md` | Starting a new layer | 3 sections. (1) the norms shared by the layer, (2) the composition of the layer, (3) what the lower specifications add |
| `spec-leaf.md` | Adding a module or a screen inside a layer | One opening line, "the scope of what this file adds follows the upper clause". Then its own responsibilities, norms, API or screen behavior, and test viewpoints |

**An upper specification is a summary, not an index.** If any of the 3 sections is missing, "read the upper specification and you know the whole layer" no longer holds.

1. **Shared norms** — the contract that applies to every lower specification. Lower specifications reference it instead of restating it
2. **Composition** — what sits below, and what each part is responsible for. One line each. Mutually exclusive, covering the whole
3. **What the lower specifications add** — what a lower specification writes on top of the upper one, and what it does not write. Written as a table

**A leaf specification writes only its difference.** Its opening line declares that it follows the "what the lower specifications add" clause of its layer. When it adds a condition to an upper norm, it references the upper norm and writes only the added condition.

What is written in the template form is covered by the following checks.

| Line in the template | What is checked |
|---|---|
| A `[ID](<relative path>#ID)` reference | Existence (V3 / V8 / V9), cycles (V10), content change (`diff`) |
| The opening line "the scope ... follows ..." | The solo rate (`spec-coverage`. When the upper specifications are listed in `docs.normativeDirs` / `docs.commonFiles`, it counts the leaves that reference none of them) |
| `xref-prefix` in the frontmatter | V1 / V6 |
| Clause headings `[ID]` and their anchors | V2 / V9. `clause-anchors.sh` places the anchors |

---

## 3. Choosing the targets

When to measure, and which sprint to run when cov / rcov / tcov are low, is in the "4. Measurement and the next scope" section of `docs/07_plans/README.md`. The definitions of the indicators are in the `/spec-coverage` skill. This section covers only how to read the output when looking for places where the structural or content evaluation is low.

| What to look at | Command | How to read it | Refactoring type |
|---|---|---|---|
| References by section number or abbreviation | `bash harness/bin/sprint spec-graph` (V11) | References that nothing detects when the target section number moves | A |
| Cycles | Same (V10) | Normative edges and guidance edges are mixed | F |
| Clauses with 0 referrers | `bash harness/bin/sprint spec-coverage --unreferenced` | Norms that nothing follows. Includes text that is a clause but not a norm | E |
| Many lines outside clauses (low cov) | `bash harness/bin/sprint spec-coverage` | Either norms that are not yet clauses, or explanation. Read the text to decide | G |
| High solo rate | Same (when `docs.normativeDirs` is set) | Leaves do not reference their upper specification and write the norms themselves | C / H |
| Direction between layers opposite to what the design expects | `bash harness/tools/spec-graph.sh layers` | Suspect the location of the norm, not the reference | D |
| One file with a lopsided share of referrers, or many lines | `bash harness/tools/spec-graph.sh files` | Sections with different readers share one file | B |
| Large `resolve` output | `bash harness/tools/spec-graph.sh resolve <FILE>` | Background reading is among the reachable clauses. Guidance is written as links | F |
| Duplicate titles | A scan. Take each heading, strip the clause ID, section number, and parentheses, and count titles that appear in 2 or more files. Exclude code fences | Sort into 4 groups: template section names, same title with different content, already referenced, duplicated content. Only duplicated content is a target | C / H |

- **Do not put thresholds on the values.** A value is material for choosing targets, not a pass/fail verdict
- **A duplicate title is not evidence of duplicated content.** A table definition and an API contract, or a design decision and a behavior, share a title while playing different roles. Read the bodies to sort them

---

<a id="SSTD-3"></a>
## [SSTD-3] 4. Refactoring types and their completion conditions

There are 8 refactoring types. Write each completion condition as a value a machine produces. Get the expected values by a trial run in PLAN against the baseline (`<base>` = the commit at the start of the work).

| Type | Operation | Unchanged | Completion condition |
|---|---|---|---|
| A Turn section-number references into clause references | Give the referenced section a clause ID and rewrite the reference as `[ID](<relative path>#ID)`. Keep the words around it | Clause bodies | `spec-graph verify` OK. `diff <base>` shows 0 changed, and added equals the sections that received IDs |
| B Split by reader | Split one file by reader (the set that one agent reads for one task). Only move the clause bodies. Choose an `xref-prefix` per resulting file | Clause bodies | `diff <base>` shows 0 changed and 0 removed. 0 references to the old path in living documents |
| C Replace a copy with a reference | Decide which text is canonical. Reduce the copy to one sentence, "follows X". Keep anything that exists only in the copy. Give the canonical text an ID first if it has none | The norms each referrer reaches | `verify` OK. `diff <base>` changed equals the clauses in the decision table. `resolve <file of the copy>` prints the canonical body exactly once |
| D Move a norm | Move the clause to the document whose subject matches its content. Keep the ID. If the prefix changes, assign a new ID and repoint every referrer that `reverse <old ID>` lists | Clause bodies | `verify` OK. 0 occurrences of the old ID in living documents and tests |
| E Inventory | For each clause with 0 referrers, do one of: delete it, write a referrer, or remove the clause declaration (when the text is not a norm) | Referenced clauses | The `--unreferenced` list equals the decision table |
| F Break a cycle | Among the edges of the cycle, rewrite the guidance edges as plain-text titles. Keep the normative edges | Normative edges | `verify` OK (V10 reports 0). Record the removed references in the README |
| G Promote | Turn a table or explanatory text into a clause. Check the values against the implementation before copying them ([RULE-1](../05_specifications/README.md#RULE-1)) | — | `verify` OK. `diff <base>` added equals the decision table |
| H Factor out | Extract what 2 or more clauses say in common into an upper clause, and reference it from each. Keep what is specific to each clause | The norms each referrer reaches | `verify` OK. Before and after the work, the set of normative sentences that `resolve` reaches from each referrer is the same |

C and H may change the number of normative sentences (in H, 2 sentences become 1 shared sentence and 2 references). The invariant is not the count but the set of norms each referrer reaches. Deciding to erase a difference and make two clauses identical is not factoring out; it is a change of norms, recorded as a specification change in an ADR and in the "decisions" of the SPEC.

How to decide the canonical text (types C / H). Decide in this order.

1. The document that holds the normative sentence (EARS)
2. The document with more referrers
3. The role of the document (design = decisions and structure, specification = behavior, reference = principles and adopted policies)

The test question is: "If this sentence were deleted, would the norm that the referrers depend on still hold?" A sentence without which it does not hold is the norm, and the norm has one canonical place.

Rules.

- **No bulk replacement.** Extract candidates, then read and fix each one. The same spelling has two meanings (a DB column name and an API key name). Bulk replacement produces errors in proportion to its size
- **Do not rewrite sealed sprint documents.** Accept the broken links that remain in past SPECs
- **Where adding a reference would create a cycle, write the "follows" declaration as a plain-text title.** Do not link it
- **Adding a new clause does not put the previous clause into `diff` changed.** If it appears, its body was changed

---

<a id="SSTD-4"></a>
## [SSTD-4] 5. Procedure

1. Record the baseline. `<base>` = the commit at the start of the work
2. Produce the full target set with a scan. "About N items" in an issue is an estimate, not the target set. Put the scan expression in TEST.md
3. Build the decision table. Columns: target / type / canonical text / treatment / reason. Write a reason for what you leave unchanged too
4. Decide how to run the work
   - With judgment (choosing the canonical text, promoting, deleting, factoring out): a sprint (kind=docs). Keep the decision table in SPEC.md, and qa checks every row against the actual text in REVIEW
   - Without judgment, and with no change to norms or tools (the mechanical part of types A / B / D): no sprint. Do it while the active sprint is CLOSED, and open a PR
5. Trial-run the completion checks against the tree before the work. Take the expected values from that output
6. Execute one item at a time
7. At the exit, measure the following
   - `bash harness/bin/sprint spec-graph` is OK
   - changed / added / removed of `bash harness/tools/spec-graph.sh diff <base>` equal the decision table
   - For each referrer, the set of normative sentences that `bash harness/tools/spec-graph.sh resolve <FILE>` reaches is the same as before the work (as a set for C / H; for the other types the count is also the same)
   - Rerun the scan of step 2. The target set is 0, or equals the decision table
   - `bash harness/tools/clause-anchors.sh --check` reports 0
8. Keep the decision table and the measured values in SPEC.md / TEST.md. For rules to make permanent, follow the "RETRO and the procedure to make rules permanent" section of `docs/06_process/sprint-process.md`
