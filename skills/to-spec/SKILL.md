---
name: to-spec
description: Closes a spec that grill has been building — resolves the open questions, distills the settled ADRs, writes the test seams, and detects pivots. Use to freeze a design — "to spec", "close the spec", "congela esto en la spec", "vuelca la conversación en docs/SPEC.md".
---

# To spec

`grill` builds `docs/SPEC.md` live during the interview, so there are no raw notes to distill.
`to-spec` does the five things only the close can do. Work from the document itself — a fresh
session with no interview in context must be able to close a spec by reading only the file.

## Steps
1. **Empty `## Open questions`.** One at a time, each with your recommendation. Every entry ends
   either **answered** (moved into the section it belongs to — In scope / Constraints / Success
   criterion) or **degraded to a Non-goal with its reason.** A spec is not ready while this
   section has unresolved entries.
2. **Assign and preserve requirement ids — you are the sole id owner.** *Only if the spec's
   `## Requirements` section is in use — a `tier: TINY` spec skips this and keeps just the measurable
   Success criterion; STANDARD and DEEP specs use it.* Give each settled requirement a stable `REQ-###` and each acceptance
   criterion an `AC-###` (globally unique across the whole spec); use `OBJ-###` for a maintenance
   objective. **Preserve every already-approved id** — never renumber on reorder, never silently
   recycle a removed id (mark it `Superseded`/`Rejected` and reference its replacement). An external
   id (`FR-001`, `JIRA-1234`) is accepted only when this spec defines it. A requirement whose text
   still carries `[NEEDS CLARIFICATION: …]` stays `Proposed`/`Clarifying`, never `Approved`. `grill`
   only surfaces candidates; minting and preserving the canonical ids is this skill's job. Roadmap
   phases then reference these ids via a `Requirements:` line — the definition stays here, never
   copied into the roadmap.
3. **Distill the settled ADRs.** The architectural decisions `grill` noted under Constraints are
   now settled — record each with the **`adr`** skill (its 4-line format already requires the
   rejected alternative). Then in `Constraints`, replace the inline note with a citation of the
   ADR path (`see docs/decisions/NNNN-*.md`) — never repeat its content. Vocabulary and the ADR
   format are not yours to write; the `glossary` and `adr` skills own them.
4. **Propose and write the test seams.** The public interfaces behavior will be verified through —
   the fewer the better, ideal 1; prefer seams that already exist. Confirm them with the user,
   then write them into `## Test seams`. The `tdd` skill reads these instead of re-asking.
5. **Detect a pivot.** Compare the current `Success criterion` against the last committed spec:
   `git show HEAD:docs/SPEC.md` (skip this check if there's no prior HEAD version). If the
   criterion *changed*, this is **not an amendment — it's a different product.** Do NOT edit in
   place: say so, and offer to archive the old spec (`git mv docs/SPEC.md docs/spec-v1.md`) and
   record the pivot with the `adr` skill, before writing the new one.

Fill any still-empty `What & why`. A **measurable** success criterion is mandatory — if the
document doesn't have one, ask for it (that, the Open questions, and the seams are the only
questions this skill may ask; it does not re-interview).

**Match depth to the spec's `tier:`** (set from `scripts/classify-work.sh`; override it if the work
warrants). A `TINY` spec closes on the compact core — What & why, Success criterion, In scope, Non-goals —
and REQ/AC ids stay optional. A `DEEP` spec must also have its `## Deep design` section filled
(architecture alternatives, data model, migration/rollback, failure modes, threat model, observability)
or that section deleted because the work genuinely isn't DEEP — never left as an empty template. A tier
is a recommendation, not a gate: readiness is still content-derived (measurable criterion + no unresolved
*blocking* clarification), so a stale tier can never close or block a spec on its own.

## Close
When Open questions is empty, the seams are written, and a measurable criterion exists, set
`status: ready` in the frontmatter (an informational label — the `roadmap` skill re-derives
readiness from content, so it doesn't trust the label blindly) and suggest: "run the `roadmap`
skill to break this into phases."

<!-- Adapted from mattpocock/skills (MIT) — https://github.com/mattpocock/skills -->
