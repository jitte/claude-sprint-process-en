# Document structure

| Directory | Contents |
|---|---|
| `01_overview` | Project definition, purpose, scope |
| `02_requirements` | Requirements. Write them in EARS |
| `03_design` | Design. Data, architecture, API conventions |
| `04_standards` | Normative rules for coding, testing, and refactoring |
| `05_specifications` | Module specifications. The main location of clauses |
| `06_process` | Sprint process, gates, `templates` |
| `07_plans` | Sprint plans and records. `<major>_<slug>/<minor>_<slug>/{README,SPEC,TEST}.md`. For how to write them, see `07_plans/README.md` |
| `08_decisions` | Records of design decisions. Specification text uses only the present tense. Put the reasons for decisions here |

A document that has clauses is an md that declares `xref-prefix` in its frontmatter. The folder does not matter. Do not put `07_plans` in `livingDirs`. It is a record, and it is not a referrer for verification.

Mapping to the items of `sprint.config.json`:

- `docs.livingDirs` — the list of document directories that can have clauses. The base is `01_overview` to `06_process`. Add `08_decisions` if the project gives it clauses
- `docs.sprintRoot` — `07_plans`
- `docs.specDir` — `05_specifications`
- `docs.templates` — `06_process/templates` (or the location that the target repository chooses)
- `docs.normativeDirs`, `docs.commonFiles` — optional. The directories and files that the solo rate of spec-coverage treats as the "normative and common layer". Without them, the solo rate is not counted

Each directory has at least 1 file. Git does not keep empty directories.
