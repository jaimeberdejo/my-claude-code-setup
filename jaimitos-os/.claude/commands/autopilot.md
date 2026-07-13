Run roadmap phases autonomously IN THIS SESSION so I can watch every step. This is the
watchable in-context loop — distinct from `scripts/autopilot.sh` (headless, fresh process per
phase). Use this for a handful of phases I want to observe; use the script for long overnight runs.

**Argument = how many phases (interpret flexibly, default 3):** a number → up to that many, then
STOP; a range ("3-5") → at least the low end if context allows, at most the high end; "all"/"max"
→ until the roadmap is empty or a guardrail trips (don't burn context to hit a number).

Loop until the count target is met OR `docs/ROADMAP.md` has no `- [ ]` items:

1. **Check controls first, every iteration.** `AGENT_STOP` file → STOP and tell me. No unchecked
   items → STOP (roadmap complete). `NEXT_FINDINGS.md` exists → read and address it before anything
   else. (The steer.sh hook surfaces any `STEER.md` I write mid-run — act on it when it appears.)
   This in-session loop checks controls *between* iterations; the headless `scripts/autopilot.sh`
   additionally polls `AGENT_STOP` *during* each builder/evaluator child run and enforces a
   per-child wall-clock timeout (`AUTOPILOT_CHILD_TIMEOUT`), so a wedged child there can't ignore
   the stop signal or block the loop forever.

2. **Check the next phase's `Mode:` line BEFORE building it — do not wait for `tick.sh` to catch
   this at the end.** Identify the next phase exactly as `/phase` would (the first phase with
   unchecked items) and read its `Mode:` line. If it says `supervised`, STOP right here — do NOT
   run `/phase`, do not start research/plan/TDD, do not attempt anything. Report which phase it is
   and why (quote its `Mode:` line and any nearby high-stakes note), and say this phase must be
   built with plain `/phase` under direct human review, then ticked via `/wrap` — never through
   this loop. This check exists because `tick.sh`'s `Mode: supervised` refusal only protects the
   *checkbox* — it runs after a phase is fully built, so without this check an unattended loop
   could still carry out a supervised phase's actual work (including any live external effect it
   requires) before being blocked from ticking it.

3. **Build the phase: run the `/phase` procedure exactly** (research→plan→execute→verify, TDD,
   3-strike thrash cap, records `.claude/.phase-base`/`.phase-ready`). Do not restate it here.

4. **Grade + tick — ticking ONLY goes through the shared gate, never by editing checkboxes:**
   - **PASS:** produce evidence and tick with the SAME scripts the headless loop uses:
     - `bash scripts/test-evidence.sh --allow-no-tests`
     - `bash scripts/record-grade.sh "<the evaluator's full verdict text>"`
     - `bash scripts/tick.sh "<exact phase heading>"`
     `tick.sh` verifies the grade + fresh green tests + clean secret scan + no high-stakes changes,
     then flips the checkbox and updates the STATE auto-block. If it REFUSES, do NOT tick — report
     why and stop. Then commit and continue.
   - **NEEDS_WORK:** address the items, re-run the `evaluator` (max 2 rounds). If it still fails,
     write the findings to `NEXT_FINDINGS.md`, do NOT tick, and STOP — report the blocker.

5. **Between phases, manage context.** Report your running token/context budget. After 2-3 phases
   or when the window feels full, STOP and recommend I `/wrap` then `/clear` then re-run `/autopilot`
   — this in-session loop rots context the way the headless script does not.

At the end, summarize: phases completed, remaining, and the single next action. Do not push to a
remote. (The headless `scripts/autopilot.sh --pr` publishes only after the *whole* requested run
succeeds — a failed, aborted, or partial run keeps the branch local and exits non-zero; this
in-session loop never pushes at all.) What this loop LACKS versus `scripts/autopilot.sh` is
evaluator-change discard and throwaway-worktree isolation — you (the watcher) are those guardrails. High-stakes work is `supervised`; for
unattended high-stakes runs there is no safe mode — do it by hand.
