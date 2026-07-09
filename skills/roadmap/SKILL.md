---
name: roadmap
description: Turns a spec into docs/ROADMAP.md — an ordered set of phases, each with a checklist and a measurable "Done when:" line, and each marked loopable or supervised. Use after a spec exists and before building — "write the roadmap", "break this into phases", "plan the milestones", "turn the spec into a roadmap". Produces the work queue the /phase and autopilot loops read.
---

# Roadmap

The roadmap is the work queue every loop in this stack reads. A good one makes
autonomy safe; a vague one makes it dangerous. This skill turns docs/SPEC.md into
phases that are each verifiable, bounded, and demoable.

## Entry gate (before anything else)
Read the spec's `status:` frontmatter and its content:
- `status: grilling` → an interview is open. STOP: "The spec is in grilling — run `to-spec` to close it first."
- Otherwise derive readiness from **content, not the label** (a stored `ready` can lie): proceed
  only if there's a measurable Success criterion AND `## Open questions` is empty/absent. If not,
  it's still a draft — offer the `grill` skill. (This is advisory, inside the skill: no hooks, and
  `tick.sh` is never touched.)

## If docs/ROADMAP.md already exists → amend, don't regenerate
Never overwrite an existing roadmap wholesale — that would destroy live state. See
[Amending a roadmap](#amending-a-roadmap-immutability) below, then stop; the write-from-scratch
flow in the rest of this file is only for a roadmap that doesn't exist yet.

## Before writing

1. Read `docs/SPEC.md` (and `docs/STATE.md` if present). If there is no SPEC or no
   **measurable** success criterion in it, STOP and say so — a roadmap without a
   measurable target produces unverifiable phases. Offer to stress-test it first with the
   `grill` skill (then freeze the answers with `to-spec`).
2. Note the constraints (stack, data sources, compliance, performance budgets) — they
   shape phase boundaries.
3. **Fill CLAUDE.md from the SPEC, if it's still templated.** Check `CLAUDE.md` for
   un-substituted `<...>` placeholders (the `<NAME>` header and the Test/Typecheck/Lint/Run
   command lines — the same check `doctor.sh` runs). If any remain, this is a greenfield
   project whose stack wasn't known at install time — it's known now, from the SPEC's
   Constraints section you just read. Fill them in before writing the roadmap:
   - `<NAME>` → the project name (from the SPEC's title/what-and-why).
   - Test/Typecheck/Lint/Run commands → derived from the Constraints section (language,
     package manager, tooling named there) and any manifests that already exist
     (`package.json` scripts, `pyproject.toml`, etc.).
   - If the Constraints section doesn't pin down real commands (ambiguous or missing
     tooling choices), ask rather than guess — don't invent a command that doesn't exist.
   - If CLAUDE.md has no placeholders left (already customized — the common brownfield
     case, filled by `setup-jaimitos-os`/install), skip this silently; it's a no-op.

## Decide how many phases (don't hardcode a number)

Phase count should fit the project, not a template. First estimate the natural number
from the spec's scope, then recommend a granularity and let the user choose:

1. **Estimate** the natural count from scope: count the distinct vertical slices the spec
   implies (data model, each interface, eval harness, hardening, each integration…).
2. **Recommend a tier**, with a one-line reason:
   - **Few / coarse (~3–4 phases):** large chunks. Fastest setup, least overhead. Best for
     small or throwaway projects you'll supervise closely. Trade-off: bigger phases are
     harder to verify atomically and riskier to autopilot.
   - **Medium (~5–7 phases):** balanced. The default recommendation for most projects.
   - **Many / fine (~8–12+ phases):** small vertical slices. Best for autonomy (smaller =
     safer to loop), high-stakes code, and ownership/learning (teach-back per small phase).
     Trade-off: more ceremony.
3. **Ask the user** which they want — "Few, Medium, or Many phases? (or give me a number)" —
   and **state your recommendation up front** with the reason (e.g. "I'd recommend Medium,
   ~6 phases: the spec has one data model, two interfaces, an eval harness, and a hardening
   pass — that splits cleanly into 6"). If the user gives an explicit number, use it. If
   they don't answer, default to your recommendation.

Then produce that many phases, ordered so each one builds on the last. Every phase MUST:

- **Leave the app in a working, demoable state.** No phase ends with a half-wired feature.
- **Be one vertical slice / bounded scope.** If a phase would touch ~30 files, split it.
- Have a **checklist of concrete tasks** (unchecked list items), each small enough to TDD.
- End with a **`Done when:` line that names an observable, machine-checkable condition** —
  a passing command, an eval threshold, a curl that returns the right thing.
  Good: "pytest passes AND the eval test asserts ≥15/20 within ±20%."
  Bad: "the pricing feels reasonable."

Order heuristic: pure logic / data model first → evaluation harness early (it's the
truth source) → interfaces → hardening last.

## Mark each phase loopable or supervised

After each phase, add one line: **`Mode:`** `loopable` or `supervised`.
A phase is **loopable** only if it has ALL four: a machine-checkable done condition,
bounded scope, independent verifiability (the evaluator can confirm from diff + a
command), and a low/reversible blast radius. If it fails any — especially anything
touching money, auth, prod migrations, or compliance judgment — mark it **supervised**.

Don't over-tag: "the phase makes an external API call" is not by itself a reason to mark it
supervised. Judge the actual blast radius — a read-only, idempotent, unauthenticated GET against
public data is a different risk than a call that mutates something outside your control (a
payment, an email send, a webhook, a deploy). The latter is supervised; the former can be
loopable if the other three criteria hold.

> **The `Mode:` tag is ENFORCED.** `scripts/tick.sh` parses the phase's `Mode:` line, and a
> phase marked `supervised` REFUSES to auto-tick (it exits "supervised", same as a high-stakes
> hit) in every mode — headless and in-session. It is backed up by the high-stakes **path** and
> **content** gates (`.claude/lib/_high-stakes.sh`), matched against the phase diff. Still keep
> genuinely sensitive work under a sensibly-named path, but a `supervised` tag alone now blocks
> the auto-tick.

## Output format (write to docs/ROADMAP.md)

```md
# Roadmap

> Each phase must leave the app in a working, demoable state.
> Each task line starts as an unchecked list item; the /phase command and hooks check it off when done.

## Phase 1 — <goal>
- [ ] <task>
- [ ] <task>
Done when: <observable, checkable condition>
Mode: loopable | supervised

## Phase 2 — <goal>
...
```

## After writing

- Tell the user how many phases, and which are `supervised` (and why).
- If you filled CLAUDE.md's placeholders in step 3, say so and list what you set (commands +
  name) — otherwise note it was already customized.
- Remind the user to point `HIGH_STAKES_RE` in `.claude/lib/_high-stakes.sh` (and the mirrored
  `paths:` in `.claude/rules/high-stakes.md`) at this project's real sensitive dirs if it has
  any (auth, migrations, payments, deletes, external effects) — that's a judgment call from the
  scope, not something this skill infers automatically.
- Update `docs/STATE.md` "Next action" to point at the first phase.
- Do NOT start building. The roadmap is a plan; building is `/phase` or `/autopilot`.

## Amending a roadmap (immutability)
When `docs/ROADMAP.md` already exists, edit it in place — the classification is by phase state:
- **Ticked / completed phases (checked items): immutable.** Do not reword, renumber, delete, or
  touch their `Done when:`. Reproduce them byte-for-byte.
- **Not-yet-started phases: freely rewritable** — content, tasks, `Done when:`, order.
- **New phases: added via the `milestone` skill** (it chooses insert-and-renumber vs append-with-
  `Depends on:`, so a ticked phase's number never shifts).
- Finish by summarizing what you amended: which phases you changed, which you left untouched, why.

Why ticked phases are immutable — and it is **not** because `tick.sh` diffs the roadmap against a
stored copy (it does not; its "left byte-identical" only means it doesn't half-write on refusal).
The real reasons: (1) nothing mechanical guards a between-phases edit, so a silently reworded
ticked phase just becomes the new baseline and corrupts the audit trail — the one thing that
*would* catch it, the evaluator's `git diff phase-base..HEAD -- docs/ROADMAP.md` criteria-integrity
check, only sees the *active* phase's window; (2) rewriting a ticked line can flip a checked item
back to unchecked, regressing recorded state; (3) `docs/STATE.md`'s "last ticked" pointer must keep
resolving to a heading that still exists verbatim. (Fuller writeup: `skills/README.md`.)

## Guardrails
- Phases come from the spec, not from imagination — every phase should trace to an
  in-scope item. Flag anything you're adding that the spec doesn't cover.
- Keep "Done when:" measurable. If you can't make it measurable, the phase is too vague
  to automate — say so and propose how to make it checkable.
- One milestone's worth of phases. Don't roadmap the entire product; roadmap the next
  shippable increment.
