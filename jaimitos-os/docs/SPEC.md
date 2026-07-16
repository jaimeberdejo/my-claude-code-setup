---
# status: the ONE stored spec-lifecycle bit. Only `grilling` is load-bearing (an open interview →
# the roadmap skill stops and sends you to to-spec). "ready" is NOT gated on this label — the
# roadmap skill DERIVES readiness from content (a measurable Success criterion present AND no
# unresolved Open questions), so a stale label can never trick the gate. No frontmatter = draft.
status: draft   # draft = not yet closed · grilling = interview open · ready = closed (informational)
tier:           # TINY | STANDARD | DEEP — recommended by scripts/classify-work.sh, informational + overridable.
                # Governs how much of this template to fill (see "Depth by tier" below). NOT gated on:
                # readiness is still derived from content, so a stale tier can never trick the gate. Empty = STANDARD.
---
# Spec: <NAME>

<!-- DEPTH BY TIER — fill only what the tier needs (scripts/classify-work.sh recommends the tier; you may override):
     · TINY     — What & why (objective + current vs expected) · Success criterion (the verification) ·
                  In scope (+ likely files) · Non-goals. Native REQ/AC ids are OPTIONAL. No Constraints depth,
                  no Deep design, no formal ownership / UAT / PLAN_CHECK unless a risk signal appears.
     · STANDARD — everything TINY has, PLUS the ## Requirements REQ/AC section, ## Constraints, and
                  scenarios / edge cases / dependencies as they matter.
     · DEEP     — everything STANDARD has, PLUS the ## Deep design section below (architecture alternatives,
                  data model, interface contracts, migration / rollback, failure modes, threat model,
                  observability, performance, compatibility). Reference ADRs by path; never duplicate them.
     A higher tier NEVER deletes a lower tier's sections — it only adds. A spec with no tier: line behaves
     exactly as a STANDARD/legacy spec: nothing here is mandatory beyond a measurable Success criterion. -->

## What & why
<One paragraph: what this is, who it's for, the problem it solves. TINY: state the current behavior and
the expected behavior plainly.>

## Success criterion (measurable)
<One observable thing that proves it works. e.g. "Given a sample item, returns a
price within ±15% of the median of comparable sold listings.">

## In scope
- <TINY: also note the likely affected files here.>

## Non-goals (explicitly NOT building)
-

## Requirements (optional — REQ/AC · STANDARD & DEEP)
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

## Deep design (DEEP tier only — delete this whole section for TINY / STANDARD)
<!-- Fill for DEEP / high-stakes / large or brownfield work. Reference ADRs (docs/decisions/NNNN-*.md)
     rather than duplicating them; drop any line that is genuinely not applicable.
     - Sourced research: <external evidence, with sources>
     - Architecture alternatives + chosen approach: <see docs/decisions/NNNN-*.md>
     - Data model / interface contracts: <...>
     - Dependency graph / integration order: <...>
     - Migration + rollback: <...>
     - Failure modes + observability: <...>
     - Threat model / security + privacy: <...>
     - Performance + compatibility: <...>
     - Deferred decisions + risks/mitigations: <...> -->

## Open questions
<Legitimate decisions not made yet. A permanent section, not scratch: an unanswered
question is valid spec information. to-spec must empty the BLOCKING ones before a spec is ready — each
blocking entry either gets answered (moves to the section it belongs to) or degrades to a Non-goal
with its reason.
  · BLOCKING clarification → written as [NEEDS CLARIFICATION: …] inline in the requirement/section it
    affects. It keeps that requirement out of Approved and blocks the phase. Progression is prevented.
  · NON-BLOCKING deferred question → stays here and MUST record: reason · owner · expected resolution
    point · impact if still open at build time. It does not block, but it is never silent.>
-

## Test seams
<Written by to-spec after confirming them with you: the public interfaces behavior is
verified through — the fewer the better, ideal 1. The tdd skill reads these instead of
re-asking.>
-
