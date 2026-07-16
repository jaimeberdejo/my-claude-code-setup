---
name: diagnose
description: Diagnosis discipline for hard bugs and performance regressions — build a tight red/green feedback loop BEFORE hypothesizing. Use when something is broken and needs a reproduction — "diagnose", "debug this", "hay un bug", "está roto", "va lento", "it's throwing", "it's failing sometimes".
---

# Diagnose

A discipline for hard bugs. Skip phases only when explicitly justified. When exploring, read
`docs/ARCHITECTURE.md` (if it exists) for the module map, and check `docs/decisions/` ADRs in
the area you're touching.

> **Boundary with `unstick`:** `diagnose` is for a bug/regression you need to *reproduce and
> isolate* (technique). `unstick` is for when you've made 3+ attempts that keep failing the same
> way (process — reset the approach). If you're mid-diagnose and going in circles, switch.

Scale the process to the bug. A one-line typo with an obvious stack trace does not need an
incident review; a wrong-answer-under-load bug does. Skipping phases is fine — saying which, and
why, is not optional.

## Name what you actually know
Most bad debugging is a confident sentence that mixes these up. Keep them separate, out loud:

| | |
|---|---|
| **Symptom** | What the user sees. Never the thing you fix. |
| **Root cause** | The thing that, changed, makes the symptom go away *and stay* away. |
| **Contributing condition** | Real, load-bearing, but not sufficient on its own (a timing window, a config value, a data shape). |
| **Unverified hypothesis** | A guess with a prediction attached. Say "I think", and say what would disprove it. |
| **Confirmed evidence** | You ran something and read the output. Nothing else counts. |
| **Unresolved uncertainty** | What you still don't know. **Report it — do not round it up to a conclusion.** |

**Never present a hypothesis as evidence.** If you did not run it and read the output, it is a
guess, and it must be labelled as one.

## No speculative fix loops
- **A fix without new evidence is a guess.** Don't stack guesses: change one thing, re-run the
  loop, read the result.
- **A speculative change that didn't work gets reverted** before the next attempt. Otherwise you
  are debugging a codebase nobody has ever run.
- **Three failed fixes = stop fixing.** You are no longer wrong about a detail, you are probably
  wrong about the shape of the problem. Re-read Phase 1, or question the architecture (each fix
  revealing new coupling *somewhere else* is the tell), and say so to the user. Do not attempt
  fix #4 on the same theory.
- **A regression?** Find the first bad commit — `git log` the area, `git bisect run` your Phase 1
  loop. A bisect that names the commit beats three hours of hypotheses.

## Phase 1 — Build a feedback loop
**This is the skill.** If you have a **tight** pass/fail signal that goes red on *this* bug, you
will find the cause; bisection, hypotheses, and instrumentation all just consume it. Spend
disproportionate effort here. Be aggressive. Refuse to give up.

Ways to construct one, in roughly this order:
1. **Failing test** at whatever seam reaches the bug — unit, integration, e2e.
2. **Curl / HTTP script** against a running dev server.
3. **CLI invocation** with a fixture input, diffing stdout against a known-good snapshot.
4. **Headless browser script** (Playwright/Puppeteer) asserting on DOM/console/network.
5. **Replay a captured trace** — save a real request/payload/event log, replay it in isolation.
6. **Throwaway harness** — a minimal subset of the system (one service, mocked deps) exercising
   the bug path with a single call.
7. **Property / fuzz loop** — "sometimes wrong output"? Run 1000 random inputs, find the mode.
8. **Bisection harness** — bug appeared between two known states? Automate "boot at X, check"
   so `git bisect run` can drive it.
9. **Differential loop** — same input through two variants, diff outputs: old vs new build, config A/B,
   dataset A/B, or query-plan A/B. The difference between the two runs localises the cause.
10. **HITL script** — last resort: a human must click, so drive *them* with
    `scripts/hitl-loop.template.sh` (in this skill's dir) and parse the captured answers.

**Tighten the loop** once you have one: faster (cache setup, narrow scope), sharper (assert the
exact symptom, not "didn't crash"), more deterministic (pin time, seed RNG, freeze network).
A 2-second deterministic loop is a debugging superpower.
**Non-deterministic bugs:** the goal is a *higher reproduction rate*, not elegance — loop the
trigger 100×, parallelize, add stress, narrow timing windows. 50% flake is debuggable; 1% is not.
**Record the measured rate** (e.g. 37/1000) — it is your baseline, and the only way to later prove the
fix worked: a flaky bug is never resolved by one green run.
**Genuinely can't build one?** Stop and say so, list what you tried, and ask for a reproducing
environment, a captured artifact (HAR, log dump, recording), or temporary instrumentation.
Do NOT hypothesize without a loop.

**Done when** you can name ONE command you have already run (paste invocation + output) that is
red-capable on the user's exact symptom, deterministic, fast, and agent-runnable. Reading code to
build a theory before that command exists is the exact failure this skill prevents.

## Phase 2 — Reproduce + minimise
Run the loop; watch it go red on the failure mode the USER described (wrong bug = wrong fix).
Then shrink to the smallest scenario that still goes red — cut inputs/config/steps one at a time,
re-running after each cut, until every remaining element is load-bearing.

## Phase 3 — Hypothesise
3–5 **ranked, falsifiable** hypotheses before testing any ("if X is the cause, changing Y makes
it disappear"). Can't state the prediction? It's a vibe — discard it. Show the ranked list to the
user (they often re-rank instantly); proceed with your ranking if they're away.

## Phase 4 — Instrument
Each probe maps to one prediction; change one variable at a time. Debugger/REPL over logs;
targeted logs over "log everything". Tag every debug log with a unique prefix (`[DEBUG-a4f2]`)
so cleanup is one grep. Performance regressions: measure a baseline first, then bisect — logs
are usually the wrong tool.

## Phase 5 — Fix + regression test
Regression test BEFORE the fix, at a **correct seam** — one that exercises the real bug pattern
at its call site. If no correct seam exists, that is itself the finding: document it, and if
fixing it is real work, suggest adding a phase to the roadmap via the `milestone` skill.
Then: failing test → fix → green → re-run the Phase 1 loop on the original scenario.

## Phase 6 — Cleanup + post-mortem
Original repro green · regression test in (or seam absence documented) · all `[DEBUG-…]` lines
removed · throwaway harnesses deleted · the winning hypothesis stated in the commit message.
**For a flaky/non-deterministic bug, one green run is NOT resolution** — re-run the Phase 1 loop many
times after the fix and record the new rate (target 0 over a count comparable to the pre-fix repro
baseline). A single pass proves nothing when the failure was intermittent to begin with.
If the fix rested on a real design decision (or revealed one), record it with the `adr` skill —
including the alternative rejected.

<!-- Adapted from mattpocock/skills (MIT) — https://github.com/mattpocock/skills -->
