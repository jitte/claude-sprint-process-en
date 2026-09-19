---
xref-prefix: TSTD
---

# Testing policy

Normative rules for tests. 3 clauses (how to write static verification, coexistence with seed data, clause IDs in test names).

---

<a id="TSTD-1"></a>
### [TSTD-1] 1.3 How to write static verification

Static verification items are the place in TEST.md for verifications that have no tests (0 remaining occurrences, matching sets, correctness of clause bodies). **Declare a type for each item. Write the method for that type.** There are exactly 3 types.

| Type | Target | Can a machine get it? | What to write in TEST.md |
|------|------|------|------|
| Machine scan | Identifiers, IDs, English keys, paths, notations | Yes | Scan expression, expected value, unit of counting, exclusions |
| Structural scan | Clause references, anchors, table columns, route sets | Yes (tools) | Tool command (`spec-graph.sh reverse <ID>` / `deps` / `clause-anchors.sh --check` / `impl-sync.sh`) and expected value |
| Reading | Natural-language normative text, diagrams, JSDoc, existence of clause values | No | Range to read (`sed -n '<start>,<end>p' <file>` or the whole file), verdict condition (what text makes the item fail), who read it |

**"Scan" means only machine scan and structural scan.** Work on natural-language normative text is called "reading". Natural language has spelling variants, different word orders, and synonyms, so patterns cannot catch it. If you write "scanned the lines that state the same norm", ranges that nobody actually read are recorded as "scanned". For reading, cut out the range with a machine (`sed -n`), and leave only the verdict to a human.

**Run scan expressions with a bash script or with `command grep`.** In the interactive shell, `grep` is a shell function that Claude Code replaced with ugrep. It silently excludes `.gitignore` targets, hidden files, and binaries. The same expression can give a different result from a script (`/usr/bin/grep`). Write expressions in TEST.md that give the same value when qa reruns them as a script.

Write a machine scan with `grep` that claims "0 occurrences of the old name" by the following rules.

#### Separate the scan targets and the words

1. **Do not include generated artifacts in the targets.** `**/migrations/**` holds applied migrations and snapshots. You do not rewrite them, so their count does not go down. Always exclude them from the scan
2. **When a word has the same spelling across layers, do not use a source grep for the verdict.** `total_amount` can be correct as a DB column name and wrong as an API key name. Base the verdict on a scan of responses (call the API and look at the keys). Use the source grep to show the breakdown

```bash
# Correct: exclude generated artifacts
grep -rn 'old_field_name' src | grep -v '/migrations/' | grep -v '\.test\.'

# Forbidden: applied migrations are counted
grep -rn 'old_field_name' src | grep -v '\.test\.'
```

- **Limit the scan expression to the shape of the deletion target.** The same identifier can have 2 roles in the same file. Write the shape of the line to delete, such as `grep 'oldKey: source'`, not `grep 'oldKey'`
- **Build the scan words mechanically from "the set of spellings before the rename".** List all spellings before the rename, and use all of them as scan words. Take the list from the definition of the rename targets (for example, the list of configuration keys, or `SELECT DISTINCT key` in the DB)
- **Assign expected-0 scans and classification scans to every layer, with no gaps.** When the same spelling exists in both frontend and backend, make a table of "which scan checks which layer", and leave no empty cells
- **Include the specification document directories (requirements to detailed specifications) in the scan range.** Do not include process documents, plan documents, or decision records. They keep records of past measurements and retractions as evidence, so they never reach expected 0. As an exception, include a directory that the sprint changes. Write in TEST.md that this is a deviation, and write the reason
- **Count the old spellings that remain in existing tests first.** Tests of past sprints still contain the literals of absence assertions. Before you add an expected-0 scan that includes tests, check whether you can reduce the existing remainders to 0. If you cannot, use a classification scan for that word
- **Show remainders together with their classification.** Write "what the remaining lines point to", not "how many lines remain". A line can be right or wrong, depending on whether the same word points to a DB table name, a column name, a stored value, or a variable name

#### Use only static scans to verify deletions

For a change that removes an old name, put the deletion check in a static scan (grep expected 0), not in an absence assertion in a test. An absence assertion needs a literal of the old spelling in the test. Then, in the same sprint, "text that the test requires" and "text that the scan forbids" conflict.

- **A scan that claims a deletion with expected 0 includes test files in its targets.** A scan that classifies and shows a breakdown can exclude test files. If you exclude them, state in the verification item that the scan is for classification
- **Do not write old spellings in tests.** If you need to write one, drop that absence assertion
- **Do not split strings to avoid scans.** A form such as `['total','cost'].join('_')` is forbidden
- Tests cover that the new spelling works. Scans cover that the old spelling is gone

The exception is **API input values**. When an external caller can pass an old value, as in `?sort=created_at` returning 400, assert in a test that the old value is rejected. In this case the old spelling is test input data, and the scan words are limited to the identifiers in the implementation. Also in this exception, write the old spelling only inside a URL or a query string. Do not write it as a key-value pair such as `{ sort: '<old name>' }`.

#### When you rewrite the normative words of a clause, read 3 kinds of range

When you change the normative words of a clause, do not fix only the line that was pointed out. Other places that state the same norm remain. Fix the range to the following 3 kinds, and put every place that you find into the tasks. Only the ID references in b are a structural scan. The rest is reading.

| # | Type | Range | What to look for |
|---|------|------|---------|
| a | Reading | The whole text of the file that contains the clause | Lines that state the same norm in other words (tables, notes, lists of constraints) |
| b | Structural scan + reading | The referrers that `bash harness/tools/spec-graph.sh reverse <ID>` returns, and the whole text of the design documents | Text that cites the clause, and text that writes the same norm without citing the ID |
| c | Reading | The prohibitions in SPEC, OUT OF SCOPE in README, the completion criteria | Scope text that assumes the old norm |

For a reading item, write the range to read and "the text that makes the item fail". "No line states the same norm" alone is not a condition that you can judge.

#### Scans do not catch diagrams and JSDoc

grep cannot catch norms inside mermaid fences, ASCII layout diagrams, or JSDoc. **A sprint that corrects a document with many diagrams, such as a UI screen specification, has at least 1 static verification item of the reading type.** In the item, write the range to read (`sed -n '<start>,<end>p' <file>`) and the condition that the diagrams do not contradict the corrected clauses.

#### When a scan catches its own explanations, decide how to write the examples

In a sprint that changes a notation or a vocabulary itself, the scan expression counts the examples written for explanation. **Do not add exclusions to the scan expression as a symptomatic fix.** Decide that examples of the notation go in code fences ([RULE-1](../05_specifications/README.md#RULE-1)). Give the scan expression only one exclusion: "exclude the contents of fences".

#### Write dependencies on external renderers in SPEC

A specification that assumes the behavior of a renderer that you do not control (for example, GitHub or Obsidian) writes that assumption in SPEC. When the assumption is written, the range of rework is known if the assumption fails. Example: the anchor form assumes that "GitHub keeps `<a id>` and resolves fragments".

<a id="TSTD-2"></a>
### [TSTD-2] 1.4 Reconcile the identifiers in a clause up to their existence

When a clause writes **names that are outside it** (table names, column names, function names, type names, environment variable names), do not end the static verification at "whether the value **is written**". Include in the check items **whether that name exists in the implementation**. The type is reading (a human extracts the values from the clause) + machine scan (look up the extracted values in the implementation).

| Kind of check | Example that passes | What it misses |
|---|---|---|
| Existence check | "All clauses write the input type and the service in charge" | The written value itself differs from the implementation |
| Content reconciliation | "The identifiers that the clause writes exist in the implementation" | — |

A format check finds only format errors. Identifiers that do not exist and missing branches appear only when you reconcile the clause with the implementation.

---

## 8. Test data

<a id="TSTD-4"></a>
### [TSTD-4] 8.1 Coexistence with seed data

Tests run on a DB that contains seed data. Follow these rules:

- **In tests of paginated APIs, do not use `find()` to search all records for a specific record.** The number of seed records changes the page boundaries, and the test becomes flaky. Instead, narrow the target with a filter parameter of the API (for example, `id`). Actual damage: there are cases where `find()` on an unfiltered response fails because data growth pushes the record out of the page
- **Separate order checks from the retrieval of specific records.** You can keep order checks (tie-breakers included) with an unfiltered request. But do not use `find()` on that response to search for a specific record
- **Use count assertions (`toHaveLength(N)`) only after a filter limits the targets.** A total count without a filter depends on the amount of seed data
- **Give the codes and names of test records a unique prefix (for example, `TEST-`).** This avoids collisions with seed data

---

## 3. Test placement

Put a test file in the same directory as its target file, with the name `{name}.test.ts`. Do not create `__tests__/` directories.

<a id="TSTD-6"></a>
### [TSTD-6] 3.1 Write clause IDs in test names

In a test name (the first argument of `describe` / `it` / `test`), write the ID of the clause that defines the behavior that the test verifies, in the form `[[ID]]`. A test name is the record that connects the specification and the test. `bash harness/tools/spec-graph.sh reverse <ID>` returns that test as `path:line`.

- **Do not write it in comments.** Comments do not appear in the execution evidence, and `spec-graph` does not read them
- **Do not write it in implementation code.** Leave the link between the implementation and the specification to name matching (`impl-sync`, `impl` in frontmatter)
- **Write it next to the Test ID (`TEST-<sprint>-x.y`).** `tdd-audit` matches the Test ID, and `spec-graph` matches the clause ID. Their roles differ
- Where to put it: if all tests in the file verify the same clause, put 1 ID in the name of the top-level `describe`. If the clauses differ, put the IDs in the names of the `describe` or `it` where they split. You can write several `[[ID]]` in one name
- Find the clause to write in this order. (1) The clauses of the specification document that has the target file of the test in the `impl` of its frontmatter. (2) For a test that has no such document (gate tools, hooks, scripts), the clauses in `docs/06_process` / `docs/04_standards`. Use general clauses for common screen behavior or UI parts only for behavior that has no matching clause in the document of (1). To decide, read the current clause body. Do not read sprint documents
- The ID points to a clause that exists in the nodes of `bash harness/tools/spec-graph.sh index`. `bash harness/bin/sprint spec-graph` (V3) verifies it. The gate specification (the graph section of `docs/06_process/gate-tools.md`) defines the scan range of test files and the lines that count as test names
