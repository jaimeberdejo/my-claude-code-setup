---
name: milestone
description: Manage the roadmap lifecycle — add phases mid-project, or archive a finished roadmap and start the next batch/milestone. Use when the user says "add a phase", "add more phases", "expand the scope", "the roadmap is done", "start the next milestone", or "new set of phases". Mechanical roadmap edits, kept consistent with the loop's checkbox-driven model.
---

# Roadmap lifecycle (add phases / new milestone)

The loop is **checkbox-driven, not index-driven**: `autopilot.sh` greps for any `- [ ]`, `/phase`
picks the first phase with unchecked items, and `tick_phase` flips `- [ ]`→`- [x]` under the
exact heading. So this is mechanical and low-risk. Pick the matching mode.

## SAFETY FIRST (always)
- If `autopilot.sh` is currently looping, STOP it before editing the roadmap (`touch AGENT_STOP`,
  edit, `rm AGENT_STOP`) — it rewrites `docs/ROADMAP.md` every tick, so live edits are racy.
- Never weaken or delete existing phases' `Done when:` lines without the user's explicit say-so.

## Mode A — Add phase(s) to the current roadmap
1. **Check whether this is in-scope or scope creep.** Read `docs/SPEC.md`'s In scope / Non-goals
   against what's being requested. Two cases:
   - **Fits the existing SPEC** (a missed detail of already-described scope) → skip to step 2, no
     SPEC edit needed.
   - **Genuinely beyond it** (a new capability, a reversed non-goal, a direction the original SPEC
     didn't cover) → **don't silently add the phase.** Say so, then:
     a. Update `docs/SPEC.md`'s In scope / Non-goals to reflect the new scope (grill first if the
        addition itself needs sharpening — same bar as the original SPEC: it should stay
        measurable).
     b. Log it with the **`adr`** skill — one line Decision (what scope was added), one line Why
        (including that it started as a mid-project addition, not the original plan). This is
        what makes the scope change visible later instead of an unexplained SPEC diff.
     c. Only then continue to step 2.
2. Read `docs/ROADMAP.md`. Find the highest existing `## Phase N` number (default 0 if none).
3. For each new phase the user wants, append (or insert above remaining open phases if they want it
   to run next — **position = execution order**) a block in the EXACT shape:
   ```md
   ## Phase <N+1> — <goal>
   - [ ] <task>
   - [ ] <task>
   Done when: <observable, machine-checkable condition>
   Mode: <loopable | supervised>
   ```
4. **Phase shape is defined once, in the `roadmap` skill — don't restate a looser copy here.**
   Apply `roadmap/SKILL.md`'s "Every phase MUST" rules verbatim: a `Done when:` line naming an
   *observable, machine-checkable* condition (a passing command, an eval threshold, a curl that
   returns the right thing) — not just a line that happens to exist. "The pricing feels
   reasonable" is not a `Done when:`; if a requested phase can't be made measurable, say so and
   propose how to make it checkable, exactly as `roadmap` would, rather than inserting a vague
   one. Also enforce: each `## ` heading must be **unique and verbatim**. Renumbering on insert
   is optional (numbers are cosmetic) — uniqueness of heading text is what matters, since
   `tick.sh` matches against it exactly later.
5. Mark `supervised` (not `loopable`) for anything touching auth / money / migrations / deletes /
   external effects, or anything not independently verifiable — same bar as `roadmap`'s
   loopable/supervised rule (all four of: machine-checkable done condition, bounded scope,
   independent verifiability, low/reversible blast radius).
6. Commit the roadmap change (`docs/ROADMAP.md`, and `docs/SPEC.md` + the ADR file if step 1
   amended scope). Tell the user which phases you added, whether they run next or after current
   work, and whether the SPEC was amended.

## Mode B — Finish a roadmap → start the next batch / new milestone
Use when every phase is `- [x]` (or the user wants to close the current scope and expand).
Closure is **gated by a script** — you do NOT archive by hand, and there is no "proceed anyway":
0. **Confirm this is its own checkpoint.** Before running anything, state plainly that you're
   about to archive the roadmap and (optionally) bump `VERSION`/tag, and wait for a clear,
   unambiguous yes. Never infer that authorization from an earlier reply that was really about
   something else (e.g. a "go ahead"/"resume"/"continue" that only authorized ticking a phase) —
   even if that phase happened to be the roadmap's last open item.
1. Run the gate:
   ```bash
   bash scripts/close-milestone.sh        # or: --name <label> to set the archive suffix
   ```
   It REFUSES (exit 1, with the reason) if any `- [ ]` item is still open, if `NEXT_FINDINGS.md`
   exists (an unresolved evaluator finding), or if the roadmap has no phases. If it refuses,
   resolve the listed items first — do not work around it. It may also print a non-fatal
   `NOTE — ... Ownership gaps ...` line — that never blocks the close, but read the listed
   `## Ownership gaps` entries from `docs/STATE.md` aloud to the user before continuing. On
   success it `git mv`s `docs/ROADMAP.md` → `docs/archive/ROADMAP-<label>.md` (label = `--name`,
   else a `VERSION` file, else the latest git tag, else the date), writes a fresh empty
   `docs/ROADMAP.md`, and resets the `docs/STATE.md` auto-block.
2. Author the next scope into the fresh `docs/ROADMAP.md` — either re-run the **`roadmap`** skill
   on an updated `docs/SPEC.md` (preferred when scope changed), or hand-write phases as in Mode A.
3. Update the prose "## Now / ## Next action" in `docs/STATE.md` to point at the first new phase.
4. Optional: bump `VERSION` and `git tag` to mark the milestone.
5. Commit. Summarize: what was archived, what the next batch contains, the single next action.

## Guardrails
- Mechanical edits only — you are not redesigning the project, just maintaining the work queue.
- Keep the roadmap the single source of "what's left"; don't duplicate it into STATE.md.
- This is a convention skill: it edits `docs/`, it does not run loops or touch enforcement code.
