Close out this session:

1. Update the prose parts of docs/STATE.md: what we completed, any open questions, and the
   "## Now" / "## Next action" narrative. Do NOT edit between the `<!-- lean:auto:begin -->`
   and `<!-- lean:auto:end -->` markers — that block is machine-managed by scripts/tick.sh.

2. **Roadmap ticking is gated — you may NOT flip `- [ ]` → `- [x]` by hand.** The ONLY way to
   mark a phase done is the shared gate, scripts/tick.sh, exactly as the headless loop uses it.
   If (and only if) a phase is genuinely complete and you want to tick it:
   a. **Grade under isolation** — the same discard net `/phase` and headless `autopilot.sh` use, so
      the grader cannot contaminate the tree it is grading. (The evaluator has no Edit/Write tools,
      but it does have `Bash`, and `>` is a write: a complacent grader that re-runs the suite and
      lets a test write a fixture that makes the grade pass is the real risk.) Steps:
      - **Snapshot first (fail-closed):** `source .claude/lib/_eval-isolation.sh && eval_snapshot`.
        If it returns non-zero, do NOT grade — report and STOP.
      - Invoke the `evaluator` subagent (Task tool) to grade the phase independently. Capture its
        full verdict. If the last line is not `PASS`, STOP — do not tick; report what's missing.
      - **After grading, detect (non-destructive):** run `eval_changed_files`. Unlike headless —
        which runs in a throwaway worktree and can safely `git reset --hard` — this is the user's
        LIVE checkout, so we NEVER auto-revert it. If `eval_changed_files` prints anything, the
        evaluator wrote to the tree: treat the grade as **untrustworthy**, do NOT record it and do
        NOT tick, print the exact list it emitted (`[modified] …` / `[created] …` / `[committed] …`)
        so the human can clean up without guessing, note the attempt (it is a signal about the
        grader, not a non-event), and STOP. Only when it prints nothing (returns 0) is the grade
        trustworthy.
   b. Produce fresh test evidence bound to the current commit:
      `bash scripts/test-evidence.sh --allow-no-tests`
   c. Record the grade: `bash scripts/record-grade.sh "<paste the evaluator's full verdict>"`
      (it refuses unless the verdict's last line is exactly `PASS`, and refuses outright if the
      tracked tree is dirty — the grade must describe a clean, committed tree).
   d. Run the gate: `bash scripts/tick.sh "<exact phase heading>"`. It verifies the grade +
      fresh green tests + a clean secret scan + no high-stakes changes, then ticks the roadmap
      and updates the STATE auto-block. If it REFUSES, surface the reason — do not tick by hand.
      If the phase is `Mode: supervised`, `tick.sh` refuses until you add `--supervised-approved`
      (and optionally `--note "<why it's safe>"`) to explicitly, auditably approve THIS phase at
      THIS commit — that flag clears only the supervised refusal; every other gate still applies.
   If a phase is "built, awaiting grade," leave it unchecked and say so.

3. If any real architectural decision was made, append a 4-line ADR to a new file
   in docs/decisions/ (format: id, date, decision, why).

4. If EVERY phase in docs/ROADMAP.md is now `- [x]`, tell me the roadmap is complete and offer the
   `milestone` skill (it runs scripts/close-milestone.sh to archive + start the next batch) — but
   do NOT archive or write a new roadmap yourself unless I say so; that's a deliberate step.

Keep all of it terse. Then tell me it's safe to /clear.
