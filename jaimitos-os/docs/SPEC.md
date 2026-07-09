---
# status: the ONE stored spec-lifecycle bit. Only `grilling` is load-bearing (an open interview →
# the roadmap skill stops and sends you to to-spec). "ready" is NOT gated on this label — the
# roadmap skill DERIVES readiness from content (a measurable Success criterion present AND no
# unresolved Open questions), so a stale label can never trick the gate. No frontmatter = draft.
status: draft   # draft = not yet closed · grilling = interview open · ready = closed (informational)
---
# Spec: <NAME>

## What & why
<One paragraph: what this is, who it's for, the problem it solves.>

## Success criterion (measurable)
<One observable thing that proves it works. e.g. "Given a sample item, returns a
price within ±15% of the median of comparable sold listings.">

## In scope
-

## Non-goals (explicitly NOT building)
-

## Constraints
<tech stack, data sources, compliance, performance budgets. Cite ADRs by path
(docs/decisions/NNNN-*.md) for architectural decisions — don't repeat their content here.>

## Open questions
<Legitimate decisions not made yet. A permanent section, not scratch: an unanswered
question is valid spec information. to-spec must empty this before a spec is ready — each
entry either gets answered (moves to the section it belongs to) or degrades to a Non-goal
with its reason.>
-

## Test seams
<Written by to-spec after confirming them with you: the public interfaces behavior is
verified through — the fewer the better, ideal 1. The tdd skill reads these instead of
re-asking.>
-
