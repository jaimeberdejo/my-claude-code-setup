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

## Requirements (optional — REQ/AC)
<!-- OPTIONAL — skip for tiny/local work; the measurable Success criterion above is already the
     acceptance bar. Add REQ/AC ids only when phases will be graded against discrete, separately
     testable requirements, then reference them from a docs/ROADMAP.md phase's `Requirements:` line.
     `to-spec` is the sole id owner: it assigns and preserves these ids — an approved id is never
     renumbered when requirements are reordered, nor silently recycled after removal. Ids:
     REQ-### (requirement) · AC-### (acceptance criterion, unique across the whole spec) ·
     OBJ-### (maintenance objective). An external id (FR-001, JIRA-1234, …) is accepted only when
     defined here. A requirement whose text carries [NEEDS CLARIFICATION: …] is not Approved and
     cannot complete a phase. Delete this section if the spec needs no ids. -->
<!-- Example — replace with real requirements, or delete the whole section:
     ### REQ-001 — account data export
     Status: Approved      (Proposed | Clarifying | Approved | Deferred | Rejected | Superseded)
     Priority: Must        (optional: Must | Should | Could)
     Authenticated users can export their supported account data.
     - AC-001: the export contains all supported user-owned data.
     - AC-002: only the authenticated account owner can download the export.
     - AC-003: the export never deletes or modifies account data. -->

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
