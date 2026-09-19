# [Module name]: [Title]

> How to use this template: put the frontmatter at the top of the file. Replace `PFX` with the prefix of this file (2 to 6 uppercase letters, unique in the corpus) and `n` with a sequence number from 1. Fill in the `[ ]` parts and delete this quote block.
> Order the sections as the "composition" section of the upper specification of your layer prescribes. The sections here are an example.
>
> ```yaml
> ---
> xref-prefix: PFX
> layer: [optional. The same value as the upper specification]
> impl: [optional. The main implementation path. If written, its existence is verified]
> ---
> ```

## 1. Responsibility and background

<a id="PFX-n"></a>
### [PFX-n] Responsibility of [module name]

The scope of what this file adds follows [the "what a lower specification adds" clause of the upper specification, as `[ID](<relative path>#ID)`].

This file is one of [name of the layer] ([the "composition" clause of the upper specification]). [Title of the shared norm] follows [the clause of the upper specification].

[Write the specific responsibility and boundaries. Do not restate upper norms. For each neighboring module, one line: its name and what is delegated to it.]

### Why it is needed

[One paragraph that references the requirement clauses as `[ID](<relative path>#ID)`. Reasons are not clauses.]

---

## 2. [Section for the specific norms. Domain rules, or whatever section name the upper specification prescribes]

<a id="PFX-n"></a>
### [PFX-n] [Title of the norm]

[Write in EARS. When adding a condition to an upper norm, reference the upper norm and write only the added condition.]

---

## 3. [API endpoints, or screen behavior. The section name the upper specification prescribes]

<a id="PFX-n"></a>
### [PFX-n] [Title of the endpoint or the operation]

[Path, request, and response, or the operation and the behavior after it. Follow the shared shapes by reference.]

---

## 4. Test viewpoints

<a id="PFX-n"></a>
### [PFX-n] [Title of the cases to verify]

[Only the specific viewpoints. Do not write the viewpoints of the shared patterns.]
