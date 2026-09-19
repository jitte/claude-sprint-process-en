# [Name of the layer] (upper specification)

> How to use this template: put the frontmatter at the top of the file. Replace `PFX` with the prefix of the layer (2 to 6 uppercase letters, unique in the corpus) and `n` with a sequence number from 1. Fill in the `[ ]` parts and delete this quote block.
> `bash harness/tools/clause-anchors.sh` places the anchor lines, so you do not write them by hand.
>
> ```yaml
> ---
> xref-prefix: PFX
> layer: [optional. One of common / core / supporting / generic / operation / frontend / design]
> ---
> ```

> **[What this layer does, in 1 or 2 sentences.]**
>
> The [N] lower specifications are specializations of this one. They do not restate the norms written here. They reference them as `[ID](<relative path>#ID)` and write only their own differences.

---

## 1. Norms shared by [name of the layer]

<a id="PFX-n"></a>
### [PFX-n] [Title of the norm. Include the layer name to keep it unique]

[Write in EARS. Where this follows a norm of the layer above, reference it as `[ID](<relative path>#ID)` and write only the condition this layer adds.]

<a id="PFX-n"></a>
### [PFX-n] [Title of the norm]

[Same. Repeat for each shared norm.]

---

## 2. Composition of [name of the layer]

<a id="PFX-n"></a>
### [PFX-n] [N] modules

| # | Module | File | Responsibility |
|---|---|---|---|
| 1 | [name] | `[path relative to this directory]` | [one line] |
| 2 | [name] | `[path]` | [one line] |

- Mutually exclusive, covering the whole. If a matter fits no lower specification, add a row here or write it in the shared norms

---

## 3. What the lower specifications add

<a id="PFX-n"></a>
### [PFX-n] What a lower specification adds

| Write | Do not write |
|---|---|
| [The responsibilities and boundaries specific to the module] | Restatements of norms written above (reference them as `[ID](<relative path>#ID)`) |
| [Specific norms] | [Norms shared by all modules] |
| [Specific API or screen behavior] | [Shared shapes (pagination, error shape)] |
| [Specific test viewpoints] | [Test viewpoints of the shared patterns] |

- When adding a condition to an upper norm, reference the upper norm and write only the added condition
- When a lower specification would contradict an upper norm, do not write it below. Fix the upper norm
