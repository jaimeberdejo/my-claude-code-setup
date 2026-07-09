Build MULTIPLE roadmap phases IN PARALLEL, each in an isolated git worktree, then integrate them
one at a time back into this checkout. This is for phases the ROADMAP lists in order "so each one
builds on the last" — there is NO automatic check that any two phases don't interfere. YOU must
assert independence (no shared files, no logical dependency) before running this. A merge conflict
during integration is the closest thing to an after-the-fact safety check, not a guarantee. If you
are not confident two phases are independent, use `/autopilot N` or `/phase` one at a time instead.

> **⚠ Caution — prefer `/autopilot N` or headless `scripts/autopilot.sh` until this command inherits
> child containment.** The v2.4.0 per-child watchdog (a wall-clock timeout plus a parent-polled
> `AGENT_STOP` that kills the whole child tree) lives in `scripts/autopilot.sh`. This command's
> parallel builds run as in-session worktree **Agent** calls, which do **not** inherit that
> containment: a spawned build has no `AGENT_STOP` check of its own and can't be killed mid-build
> cleanly (see **Controls** below). Until parallel builds gain the same watchdog, treat this command
> as experimental — use it only for small, closely-watched batches, and reach for `/autopilot` or
> the headless script whenever you need the kill-switch/timeout guarantees.

**Expect a `docs/STATE.md` conflict even between genuinely independent phases — this is normal,
not a sign the phases actually interfere.** Every `/phase` run rewrites STATE.md's free-text
narrative line (outside the `<!-- lean:auto:begin -->` markers) to say "Phase N built, awaiting
independent grade." Two phases built in parallel both write to that same line, so it is very
likely your first (and most harmless) conflict during Step C — resolve it by keeping whichever
sentence is still accurate (or noting both), never by reverting a real code change. The
machine-managed block between the markers is always correct regardless, since `tick.sh` rewrites
it fresh on every successful tick.

**Input — REQUIRED, no auto-detection:** the user must name the exact ROADMAP headings to build in
parallel, e.g.: `/autopilot-parallel "## Phase 3 — X" "## Phase 5 — Y" "## Phase 6 — Z"`. At least
one heading is required (a single heading is a valid dry run of this command's mechanics before
trusting it on a real multi-phase batch). If any named heading doesn't exist verbatim in
docs/ROADMAP.md, or any named phase is tagged `Mode: supervised`, STOP before doing anything and
say why (supervised phases are never run unattended — build them with plain `/phase` and review by
hand).

**Preflight (before spawning anything):**
1. `AGENT_STOP` present → STOP, report, do nothing else.
2. Working tree must be clean (uncommitted changes make each phase's merge-base ambiguous) — if
   dirty, STOP and ask the user to commit/stash first.
3. Record `PARALLEL_BASE=$(git rev-parse HEAD)` — the commit every phase worktree branches from,
   and the ref used later to compute each phase's `.claude/.phase-base`.

**Step A — parallel build.** For EACH named phase heading, in a SINGLE message, launch one Agent
tool call with `isolation: "worktree"`. Each agent's prompt is exactly:
> "Run the /phase command targeting this exact heading: `<heading>`. Follow
> `.claude/commands/phase.md` in full, including its evaluator self-check. Stop after STATE.md
> says 'Phase `<N>` built, awaiting independent grade.' Do not attempt to merge, tick, or push
> anything."

Launch all of them together so they build concurrently — do not stagger them. Note the
branch/worktree identifier each Agent call returns; it's needed in Step C. A build that errors out
does not block the others — record it as "build failed" for that phase and continue.

**Step B — barrier.** Wait for every Agent call from Step A to finish before continuing.

**Step C — serial integration, in ROADMAP heading order (not completion order).** For each
successfully-built phase, in the order its heading appears in docs/ROADMAP.md top to bottom — NOT
whatever order the builds finished in:

1. Re-check `AGENT_STOP` and read `STEER.md` if present before each phase's integration — a batch
   of N integrations is itself a loop and gets the same checks `/autopilot` gets between phases.
2. In THIS checkout (not the worktree), attempt: `git merge --no-ff <phase-branch>`.
   - **Conflict:** `git merge --abort`. Do NOT silently punt to raw git, and do NOT auto-resolve.
     Use the `merge-conflicts` skill to understand both sides' intent (it also documents the
     expected-and-harmless STATE.md conflict case), inspect the conflicting hunks, explain to the
     user *why* they conflict, and present 1–3
     concrete resolution options. **Stop here and wait for the user's explicit direction** — apply
     exactly what they choose, never a resolution you pick yourself — then redo the merge and
     continue. Do not abort the whole batch over one conflict; phases already integrated keep
     their tick, and you may continue integrating the remaining named phases once this one is
     resolved (or, if the user says to skip it, move on and leave this phase's branch/worktree in
     place).
   - **Clean merge:** continue to step 3.
3. Reconstruct the bookkeeping `tick.sh` needs, bound to the NEW post-merge HEAD, since the
   worktree's own `.claude/.phase-base`/`.phase-ready` do not carry over (they're gitignored,
   worktree-local files):
   - `echo "<exact heading>" > .claude/.phase-ready`
   - `git rev-parse <PARALLEL_BASE> > .claude/.phase-base` — this phase's diff is scoped from the
     BATCH start. If you have any doubt about scope after prior merges in this same loop, recompute
     as `git merge-base <PARALLEL_BASE> <phase-branch>` explicitly rather than assuming.
4. Invoke the `evaluator` subagent (Task tool) FRESH — this is a NEW grading pass against the
   merged tree at the new HEAD, not a reuse of whatever grade happened inside the worktree (that
   grade was bound to a different, now-discarded commit and `tick.sh` would reject it as stale).
5. **NEEDS_WORK:** do NOT tick. Leave the merge commit in place (it already happened — do not
   revert it), record the phase as "merged but failed independent grade — needs manual `/phase` +
   `/wrap` follow-up," and continue to the next phase.
6. **PASS:** run the exact same sequence `/wrap` uses —
   `bash scripts/test-evidence.sh --allow-no-tests`
   `bash scripts/record-grade.sh "<the evaluator's full verdict text>"`
   `bash scripts/tick.sh "<exact phase heading>"`
   - **Exit 0 (ticked):** commit the resulting ROADMAP/STATE change, then remove that phase's
     worktree (`git worktree remove <path>`) and delete its branch — it's fully integrated. Record
     it as "ticked" for the summary.
   - **Exit 3 (high-stakes, or `Mode: supervised` caught late):** do NOT tick, do NOT push. Leave
     the merge commit in this checkout (already merged) and remove that phase's now-empty
     worktree, but keep the branch for traceability. Note in the summary that this phase's roadmap
     item is UNCHECKED and needs supervised `/wrap` by a human. Unlike `scripts/autopilot.sh`
     (which aborts the ENTIRE run on a high-stakes trip), CONTINUE integrating the remaining named
     phases: each phase was independently asserted by the user to not interfere with the others,
     so one phase's high-stakes status says nothing about whether the next phase's grade or tick
     should be trusted.
   - **Any other non-zero exit (generic refusal):** do NOT tick, leave the merge commit, record
     "merged but tick REFUSED: `<reason>`" and continue to the next phase.

**Controls, mapped onto the parallel flow:**
- `AGENT_STOP`: checked once in preflight (before spawning any builds) and again before EACH
  phase's integration step in the Step C loop. It is NOT checked mid-build inside a spawned
  worktree agent — that agent is running its own `/phase`, which has no `AGENT_STOP` check of its
  own either (same as today), and it does **not** inherit the headless script's per-child watchdog
  (wall-clock timeout + parent-polled `AGENT_STOP` that kills the child tree): that containment
  landed in `scripts/autopilot.sh` only, which is why the caution at the top steers you there when
  you need those guarantees. If `AGENT_STOP` appears while builds are in flight, let the in-flight
  builds finish (you cannot half-kill a running Agent call cleanly), then stop before Step C's
  integration begins, and report which phases finished building but were never integrated (their
  branches/worktrees are left in place).
- `STEER.md`: read once before Step C begins (integration is the part a human is likely to want to
  redirect — e.g. "skip Phase 5, its API changed upstream"). It is NOT distributed into the N
  parallel build worktrees automatically; to steer an in-flight build, write `STEER.md` directly in
  that build's worktree.
- There is no evaluator-change discard here (unlike `scripts/autopilot.sh`): this is the
  in-session, watchable model — the human running this command is that guardrail, same as plain
  `/autopilot`.

**Worktree cleanup:**
- Ticked phases: worktree removed, branch deleted, nothing left behind.
- Conflicted phases (unresolved): worktree AND branch left untouched.
- High-stakes / NEEDS_WORK / tick-refused phases: worktree removed (the build is done and merged;
  nothing left to build there) but the branch is kept for provenance, and the ROADMAP item stays
  unchecked.
- Never push anything, ever, regardless of outcome — same rule as `/autopilot`.

**End-of-run summary — report exactly these four buckets:**
1. Ticked (heading + one-line what changed).
2. Needs manual merge (heading + branch/worktree path + which files conflicted).
3. High-stakes / supervised — merged but left unticked, local only (heading + why).
4. Failed to build or failed independent grade after merging (heading + reason).
Then state the single next action for each non-ticked phase, plainly (e.g. "resolve the conflict
in `<path>`, then `/wrap`").

**What this command does NOT do:** it never runs the equivalent of `scripts/autopilot.sh`'s
fresh-process-per-phase execution or its evaluator-change discard (there is no separate process
here to discard changes from — the evaluator subagent runs in-session via the Task tool, same
trust model as `/autopilot`). It is not a replacement for `scripts/autopilot.sh`; it is
`/autopilot`'s sibling for the specific case of user-asserted-independent phases. It also does not
retry a NEEDS_WORK phase automatically — one build attempt per phase, then a manual follow-up.
