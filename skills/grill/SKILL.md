---
name: grill
description: Relentless one-question-at-a-time interview to stress-test a plan, spec, or idea, writing each closed decision straight into the real document. Use before freezing a design — "grill me", "grill this plan", "estréssame este plan", "grill milestone 3", "stress-test this idea", "poke holes in this".
---

# Grill

Interview the user relentlessly until you share an understanding solid enough to build on.
Walk down each branch of the design tree, resolving dependencies between decisions one at a time,
and **write each decision into its real home the moment it closes** — the document is built in
front of the user, not synthesized at the end.

## What you're grilling (one skill, one parameter — do NOT make new skills)
| Invocation | Target | Decisions land in |
|---|---|---|
| `grill` (bare) | the spec | `docs/SPEC.md` |
| `grill milestone <N>` | one not-yet-started phase | `docs/ROADMAP.md` (that phase only) |
| `grill this plan` | the current phase's plan | `docs/plans/<phase>.md` |

Grilling a phase only ever touches a **not-yet-started** phase — never a ticked one (see the
`milestone`/`roadmap` immutability rules).

## Rules of the interview
1. **One question per turn.** Ask it, WAIT for the answer, then the next. Several at once hides the
   weak one behind the easy ones.
2. **Every question carries your recommendation** ("what DB? I'd pick SQLite here — single writer,
   no ops — unless you expect concurrent writers"). The user should be able to answer "your call".
3. **Facts are yours to find; decisions are the user's.** If the codebase or a quick command
   answers it, look it up. Only genuine choices go to the user.
4. **Dependency order.** Ask the questions that unblock others first (data model before endpoints,
   success criterion before phasing).

## Where each closed decision goes (compose — don't reimplement)
Write only when a decision **closes**, never when a question is merely asked:
- **Product / scope** → straight into the real spec section: `In scope`, `Non-goals` (with its
  reason in half a line), `Constraints`, or `Success criterion`.
- **Domain vocabulary** ("we call this X, not Y") → invoke the `glossary` skill. It owns the
  format and updates `docs/GLOSSARY.md` in place (no churn — it overwrites a renamed term).
- **Architectural** (structure, dependency, technical trade-off) → note it briefly under
  `Constraints` (one line: the decision + the alternative rejected). **Do not write the ADR now** —
  a choice made mid-interview may be reversed three questions later, and an ADR file can't be
  cleanly un-written or retconned. `to-spec` distills the *settled* architectural notes
  into ADRs at close, via the `adr` skill. (If you catch yourself writing ADR format inside this
  skill, stop — you're duplicating `adr`.)
- **No answer yet** → `## Open questions`. An honest gap beats a plausible placeholder. Don't force
  it into a section it doesn't belong to.

## Writing rules
- At start: if the spec doesn't exist, create it from the template. Either way set `status: grilling`.
- **Anti-churn: one write per closed decision, never per turn.** Three questions in a row that
  close nothing → zero writes.
- A later decision that invalidates an earlier one → **overwrite it in place.** No strike-through,
  no tombstone marker — the earlier version lives in git history.
- Mid-interview the document must read as an **incomplete but coherent** spec, not a shell with a list.
- At the end don't synthesize on your own: offer "close it with `to-spec`?". If the user leaves,
  `status: grilling` stays and everything is persisted.

<!-- Adapted from mattpocock/skills (MIT) — https://github.com/mattpocock/skills -->
