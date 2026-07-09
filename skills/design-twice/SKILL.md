---
name: design-twice
description: Before implementing a non-trivial design, sketch TWO genuinely different designs, compare trade-offs, choose, and record why as an ADR. Use when structuring new code — "design this", "diseña el módulo", "cómo estructuro esto", "what shape should this take". The planner applies this to non-trivial phases.
---

# Design it twice

Your first idea is unlikely to be the best one. For any non-trivial design — a new module, a new
public interface, a phase with more than ~3 tasks — sketch **two genuinely different** designs
before writing the plan or the code.

## Steps
1. **Frame the problem**: the constraints any design must satisfy, the dependencies it rests on,
   and one rough illustrative sketch to make the constraints concrete (not a proposal).
2. **Sketch design A and design B — genuinely different, not a strawman and a favorite.** Force
   difference by giving each a different bias, e.g.: minimize the interface (1–3 entry points,
   maximum behavior behind each) vs optimize for the most common caller (the default case is
   trivial); or sync-pipeline vs event-driven; or deep single module vs two thin composed ones.
   For each: the public interface (including invariants and error modes), a usage example, what
   it hides, and where its leverage is thin.
3. **Compare on trade-offs that matter here**: how much a caller must learn per unit of behavior,
   where change concentrates when requirements move, how it's tested through its own interface,
   and blast radius of being wrong. A table of two columns beats prose.
4. **Choose, and say why the loser lost.** If elements combine well, a hybrid is a legitimate
   third answer — but name it as one.
5. **Record it with the `adr` skill** — the 4-line format already demands the alternative
   rejected, which is exactly design B (or A). A design decision without its rejected alternative
   is half-recorded.

## In the phase pipeline
The `planner` agent applies this skill to non-trivial phases (> ~3 tasks, or any new
module/interface) before writing `docs/plans/<phase>.md`, and the plan carries one line —
`Alternative considered: <the losing design, one sentence>` — which later feeds the ADR.

## Guardrails
- Two designs means two you'd actually defend. If you can't argue for the second one, you
  haven't explored the space — pick a different axis of difference.
- Don't gold-plate: for a trivial change ("add a field"), skip this skill entirely — ceremony
  must match stakes.
- The comparison is about interfaces and change-concentration, not lines of code.

<!-- Adapted from mattpocock/skills (MIT) — https://github.com/mattpocock/skills -->
