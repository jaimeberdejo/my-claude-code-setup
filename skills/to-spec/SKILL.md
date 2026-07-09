---
name: to-spec
description: Synthesizes the current design conversation into docs/SPEC.md — no interview, just capture what was already discussed, plus the test seams. Use when a design discussion has converged and should be frozen — "to spec", "congela esto en la spec", "vuelca la conversación en docs/SPEC.md", "write the spec from this".
---

# To spec

Turn what THIS conversation already decided into `docs/SPEC.md`. This is synthesis, not an
interview: do NOT re-ask things the discussion already answered. (Want the plan stress-tested
first? That's the `grill` skill — run it before this one.)

## Steps
1. **Gather.** Re-read the conversation and, if the repo already has code, skim what the spec
   touches (real files, not assumptions). Use the project's own vocabulary — check
   `docs/GLOSSARY.md` if it exists — and respect existing ADRs in `docs/decisions/`.
2. **Propose the test seams BEFORE writing.** A seam is the public interface behavior will be
   verified through. Propose the fewest that cover the feature — the ideal number is one; prefer
   seams that already exist over inventing new ones. State them ("I'd test this through X")
   and get the user's confirmation before writing the spec. Seams agreed here are binding
   downstream: the `roadmap` skill's phases and the `tdd` skill's tests use them without re-asking.
3. **Write/update `docs/SPEC.md`** following the existing template shape — do not invent new
   sections:
   - **What & why** — one paragraph, the user's problem in the user's terms.
   - **Success criterion (measurable)** — MANDATORY, one observable check that proves it works.
     If the conversation never produced a measurable one, ask for it now — this is the single
     question this skill is allowed. "Feels fast" is not a criterion; "p95 under 200ms on the
     sample set" is.
   - **In scope** — the concrete capabilities discussed.
   - **Non-goals** — what was explicitly deferred or rejected (as valuable as the yes-list).
   - **Constraints** — stack, data sources, compliance, performance budgets, and the confirmed
     test seams.
4. **Confirm and hand off.** Show a 5-line summary of what was frozen, then suggest the next
   step: "run the `roadmap` skill to break this into phases."

## Guardrails
- Synthesis only: if the conversation is too thin to fill a section, say which decision is
  missing rather than inventing one (the measurable criterion is the only allowed question).
- No file paths or code snippets in the spec — they go stale; decisions and interfaces don't.
  Exception: a snippet that IS the decision (a schema, a type shape) may be inlined, trimmed to
  the decision-rich part.
- An updated spec must not silently delete existing content — show what changed if
  `docs/SPEC.md` already had substance.

<!-- Adapted from mattpocock/skills (MIT) — https://github.com/mattpocock/skills -->
