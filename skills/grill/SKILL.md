---
name: grill
description: Relentless one-question-at-a-time interview to stress-test a plan, spec, or idea before building. Use before freezing a design — "grill me", "grill this plan", "estréssame este plan", "stress-test this idea", "poke holes in this".
---

# Grill

Interview the user relentlessly about the plan/spec/idea until you share an understanding solid
enough to build on. Walk down each branch of the design tree, resolving dependencies between
decisions one by one — the goal is to surface the decisions the plan is silently assuming.

## Rules
1. **One question per turn.** Ask it, then WAIT for the answer before the next one. Several
   questions at once is bewildering and lets the weak one hide behind the easy ones.
2. **Every question carries your recommendation.** Not "what database?" but "what database?
   I'd pick SQLite here — single writer, no ops burden — unless you expect concurrent writers."
   The user should be able to answer "yes, your call" to any question.
3. **Facts are yours to find; decisions are the user's to make.** If the codebase, the docs, or
   a quick command can answer it, look it up instead of asking. Only genuine choices — trade-offs,
   scope, risk appetite — go to the user.
4. **Follow the dependency order.** Ask the questions whose answers unblock other questions
   first (data model before endpoints, success criterion before phasing).
5. **Know when to stop.** When the remaining questions are cosmetic, say so: summarize the
   decisions made, list anything still open, and offer the hand-off — "want me to freeze this
   into docs/SPEC.md? (the `to-spec` skill)".

## Guardrails
- Do not start building, and do not write the spec yourself mid-grill — this skill only
  interrogates; `to-spec` captures.
- If an answer contradicts an earlier one, point at the contradiction immediately rather than
  writing both down.
- If the user says "just decide", record YOUR recommendation as the decision and move on —
  but say that's what happened.

<!-- Adapted from mattpocock/skills (MIT) — https://github.com/mattpocock/skills -->
