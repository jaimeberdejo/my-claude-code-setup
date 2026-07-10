Run the next unchecked phase of docs/ROADMAP.md, autonomously:

**Optional argument = a specific phase heading to target** (e.g. `/phase "## Phase 4 —
Hardening"`, or enough of the heading to be unambiguous, e.g. `/phase "Phase 4"`). If given, skip
"pick the first phase with unchecked items" below and instead find the roadmap phase whose
heading matches the argument. Check for an exact full-line match FIRST: if a heading equals the
argument verbatim, use it immediately, even if the same string is also a partial match inside
some other heading's line. Only when there is NO exact full-line match does the argument get
treated as a partial string — match the unique `## ` heading that contains it — if more than one
heading matches, STOP and ask which one; if ZERO headings match at all, STOP and report that no
such phase exists in docs/ROADMAP.md — never fall through to picking the first open phase
instead. That phase must
still have at least one unchecked `- [ ]` item, or STOP and report it's already done — do not
silently fall through to another phase. This is for targeted work — building a specific phase out
of roadmap order; bare `/phase` (no argument) is unchanged.

0. If NEXT_FINDINGS.md exists, READ IT FIRST. It contains the previous evaluator's
   reasons a phase was not done. Address those findings before selecting any new
   work — do not skip past them.
1. Read docs/STATE.md and docs/ROADMAP.md. If a phase argument was given (see above), select
   that phase. Otherwise, pick the first phase with unchecked items.

   **Known consequence of checkbox-driven selection: a `Mode: supervised` phase whose code is
   already built and evaluator-passed still has unchecked `- [ ]` items** (only a human running
   `/wrap` — or `scripts/tick.sh` directly — flips them, and it correctly refuses to auto-tick a
   supervised phase). So bare `/phase` will keep re-selecting that SAME phase on every future
   invocation instead of advancing, until a human ticks it or you're pointed at the next phase
   explicitly. If the selected phase's tasks are already implemented and committed, do NOT redo
   the work — verify it (re-read the code, re-run its tests/evaluator check) and report that it's
   done and awaiting a manual `/wrap`, exactly as if you'd just finished building it. To actually
   advance past it, use the heading argument on the NEXT phase (e.g. `/phase "## Phase 6 — ..."`).
2. Record the phase base (so the grader can diff the whole phase) and the phase
   heading (so the orchestrator knows which items to tick on PASS). Create .claude/
   if needed, then:
   - Determine THIS phase's exact roadmap heading line (e.g. `## Phase 2 — Eval harness`).
   - **Phase base — set it ONLY when starting a NEW phase, preserve it on a retry.**
     If `.claude/.phase-base` already exists AND `.claude/.phase-ready` contains this
     exact same heading, you are RE-RUNNING the same phase after a NEEDS_WORK — leave
     `.claude/.phase-base` untouched (it must keep pointing at the phase's true start, so
     the grader diffs the whole phase and the criteria-integrity check still sees any
     weakening). Only when there is no `.phase-base`, or `.phase-ready` names a DIFFERENT
     heading (a genuinely new phase), run `git rev-parse HEAD > .claude/.phase-base`.
     (Under headless `scripts/autopilot.sh` this write is advisory only: the orchestrator re-derives
     the phase base in its OWN trusted shell and OVERWRITES this file before the evaluator and
     `scripts/tick.sh` read it, so a builder can't forge it to narrow the safety scan. In-session
     `/phase` + `/wrap` still rely on this write.)
   - Write the EXACT heading line to `.claude/.phase-ready`, verbatim, no extra text
     (do this in both cases — it is cheap and idempotent for the same phase).
   - If this phase's `Mode:` line says `supervised`, say so plainly before continuing — you are
     about to build it under direct human review (that's what plain `/phase`, unlike `/autopilot`,
     is for). Its tick needs an EXPLICIT human approval afterward: a human runs
     `bash scripts/tick.sh --supervised-approved "<exact heading>" --note "<why it's safe>"`, which
     records an auditable, HEAD-bound approval; `scripts/tick.sh` refuses to auto-tick a supervised
     phase without it (and that approval clears only the supervised refusal — grade, evidence,
     secret and high-stakes gates all still apply). This is informational, not a stop — building
     supervised phases interactively is the sanctioned path for them.
3. **Research (only if the phase needs it) — delegated to the `researcher` subagent.** If the
   phase uses an unfamiliar API, library, or pattern, or touches code you haven't read, invoke
   the `researcher` subagent (Task tool) with a prompt containing: the phase's exact heading, its
   "Done when:" line(s), and why you judged research needed. Capture its full returned text
   verbatim — you'll pass it to the planner in step 4 unchanged, since each Task-tool call gets a
   fresh context with no memory of this one. Skip this step entirely when the path is obvious —
   research is conditional, not ceremony. This is the R in research → plan → execute → verify.
4. **Plan — delegated to the `planner` subagent.** Invoke the `planner` subagent (Task tool)
   with a prompt containing: the phase's exact heading, its "Done when:" line(s), and — only if
   step 3 ran — the researcher's findings verbatim from step 3 (omit this entirely if step 3 was
   skipped; do not invent findings). The planner writes a plan file under docs/plans/ (research
   notes + tasks + "Done when") and reports back the exact path it wrote. Confirm that file
   exists before continuing.
5. **Execute — delegated to the `executor` subagent.** Invoke the `executor` subagent (Task
   tool) with a prompt containing: the phase's exact heading and the plan file path from step 4.
   The executor runs the TDD loop per task (failing test, minimal code, run test, commit) and
   reports back what it completed. If it reports a task still red after 3 attempts, STOP and
   report the blocker exactly as it described it — do not retry the task yourself or proceed to
   step 6.
6. When all tasks pass, run the evaluator under isolation — the SAME discard net headless
   `autopilot.sh` uses, so the grader can't contaminate the tree it grades (a complacent grader
   that re-runs the suite and lets a test write a fixture that makes the grade pass is the real
   risk — the evaluator has `Bash`, and `>` is a write). Steps:
   - **Snapshot first (fail-closed):** `source .claude/lib/_eval-isolation.sh && eval_snapshot`.
     If it returns non-zero, do NOT grade — report and STOP.
   - Invoke the `evaluator` subagent as a SELF-CHECK. If it returns NEEDS_WORK, address the items
     and re-run it (max 2 rounds; re-snapshot before each run). If still NEEDS_WORK, STOP and report.
   - **After grading, detect (non-destructive):** run `eval_changed_files`. Unlike headless — which
     runs in a throwaway worktree and can safely `git reset --hard` — this is your LIVE checkout, so
     we NEVER auto-revert it. If `eval_changed_files` prints anything, the evaluator wrote to the
     tree: treat the grade as **untrustworthy**, do NOT report the phase clean or advance to `/wrap`,
     print the exact file list it emitted (`[modified] …` / `[created] …` / `[committed] …`) so the
     human can remove them without guessing, note the attempt (it is a signal about the grader, not a
     non-event), and STOP. Only when it prints nothing (returns 0) is the grade trustworthy.

DO NOT tick docs/ROADMAP.md yourself. Ticking is the orchestrator's job, gated on an
INDEPENDENT grade: under `autopilot.sh` the script ticks the phase only after a fresh
`claude --agent evaluator` process returns PASS; in manual mode you tick via `/wrap`
after you've seen the evaluator pass. The builder never marks its own work done.

When the phase is built and self-checked, update docs/STATE.md to:
"Phase <N> built, awaiting independent grade." Then STOP.

Constraints: touch src/, tests/, and docs/ freely. You MAY also touch project config and
manifests when the task genuinely needs it (package.json, pyproject.toml, lockfiles,
migrations, *.example env files) — but call out any such change explicitly. Never touch
unrelated files. Commit after each green task. Do not ask for confirmation between tasks.
These constraints apply to whichever subagent is doing the work in steps 3–5, not only to
you directly — they're restated in each subagent's own file, but you (the orchestrating
session) remain responsible for relaying them via the prompts you construct in steps 3–5.

HARD RULE — do not move your own goalposts. While building the current phase you (and any
subagent you delegate to) MUST NOT edit that phase's heading or its `Done when:` line in
docs/ROADMAP.md, and must not weaken, reword, or delete any of its acceptance criteria. You are
graded against that exact standard; altering it is a false PASS. You MAY append NEW phases or
add notes elsewhere in the roadmap, but never alter the criteria you are being graded on.
