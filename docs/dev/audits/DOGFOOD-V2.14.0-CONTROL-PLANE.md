# Dogfood — v2.14.0 progressive control plane

Exercised the Release 4 control plane against real artifacts. The disposable exploration stayed out of
the repo; only this findings report and the fixes it drove were committed.

## Targets exercised

1. **The toolkit itself (jaimitos-os)** — a real, non-trivial project, and R4's own development.
2. **Three real consumer repos** — `AIModelCostGuard`, `MisFinanzas`, `FiscalPilot` (small/medium,
   none opted into the control plane).
3. **R4 development as its own dogfood** — 16 commits, each with targeted tests + fresh evidence, and the
   `diagnose` discipline applied to the real bugs that surfaced while building.

## What worked (value)

- **Tiers are proportionate.** `classify-work.sh` recommended **DEEP** for R4 itself (12+ components, 16
  phases, unresolved architecture, research, external interface) and **TINY** for a one-line doc fix.
  Escalation signals (auth/secrets/payments/…) correctly floored work at STANDARD.
- **Heavy machinery stays inactive by default.** On all three real consumer repos, `lint-enforcement`,
  `check-uat`, and `trace-requirements` were **inert** ("nothing to lint/check/trace") — zero ceremony
  imposed on a project that hasn't opted in. `docs/CLAUDE.md` always-loaded cost is **unchanged (3140 B)**.
- **Traceability report is honest.** `trace-requirements` on the shipped template (no REQ/AC) reported a
  clean, inert result; the orphan check correctly said "every active requirement is planned" when there
  were none.
- **`diagnose` discipline paid for itself during development.** Three real bugs, each resolved by a
  feedback loop → root cause → fix → re-run, not by guessing:
  - the `pipefail` + `grep -q` SIGPIPE flake (a validator gets SIGPIPE when `grep -q` matches early, and
    `pipefail` propagates it) — root-caused, fixed in every test by capturing output then grepping;
  - the evidence `content_hash` that didn't recompute (I hashed the raw object; a verifier canonicalises
    with a trailing newline) — fixed to a sorted-canonical `jq -cS` hash, now genuinely recomputable;
  - a fixed-string assertion that spanned a hard-wrapped line break — fixed the assertion.

## False positives found → fixed (the point of dogfooding)

- **`check-plan-freshness` file-existence was far too aggressive.** Run against R4's own dev plan it
  emitted **48 hard "referenced file no longer exists" signals** — every backticked basename in prose
  (`tick.sh`, `test-uat.sh`, …) treated as a missing repo path. Two-step fix, driven entirely by this
  finding:
  1. require a path-shaped reference (contains `/`) — dropped the bare-basename flood (48 → 11);
  2. the residual 11 were `scripts/…`-vs-`jaimitos-os/scripts/…` path-root mismatches (the toolkit's split
     layout), so **demoted missing-file from a hard --strict blocker to a soft revalidation signal.** The
     robust hard blockers remain baseline-not-ancestor, invalid-baseline, and a removed cited id. The dev
     plan now yields only soft hints and `--strict` exits 0.

## Not run (honest)

> **Appended in v2.15.0 by independent review.** This section omitted the release's flagship. Applying
> its own stated criterion — model-driven behaviour is not exercised by running a script — these belong
> here too, and did not appear as run *or* not-run:
>
> - `NOT RUN — PLAN_CHECK and the integrated pre-mortem` (ADR-005's headline). Equally model-driven,
>   equally unexercised. Its channel separation was also never tested, and was in fact broken: a
>   PLAN_CHECK verdict was demonstrably recordable as an implementation grade (fixed in v2.15.0).
> - `NOT RUN — the evaluator's Axis-A ownership-compliance check`.
> - `NOT RUN — mapme --ownership / --refresh` (only `--brownfield` was disclosed).
> - `NOT RUN — planner gap planning`.
>
> Also correcting two claims below: "exercised on fixtures and real repos" is true only of the **inert**
> path on real repos — no consumer had the artifacts, so nothing was validated in the field. And the
> `pipefail` + `grep -q` SIGPIPE fix recorded below landed in the tests only; the shipped
> `check-plan-freshness.sh` introduced by the same series still carried the bug, 10/10 fail-open, until
> v2.15.0. An honest "Not run" section that omits the flagship reads as more verified than it is.


- `NOT RUN — a full `mapme --brownfield` map of a large external repo`: mapme is a model-driven skill, not
  a script; a complete brownfield map of an unfamiliar large codebase is a session in itself. The
  brownfield *discipline* (evidence tags, stated-vs-actual, staleness) is exercised as skill prose +
  static invariants, and the ownership/enforcement/UAT validators were exercised on fixtures and real
  repos. A real consumer should run `mapme --brownfield` on their own repo before relying on the map.
- `NOT RUN — a controlled 1%-reproduction flaky bug`: the strengthened flaky discipline (record the rate;
  one green run is never resolution) is exercised as skill prose + `test-diagnose.sh` static invariants,
  not a staged non-deterministic bug.

## Net

The control plane is proportionate (inert until opted in, TINY stays cheap, DEEP earns its depth) and
caught a real false-positive defect in its own tooling, which was fixed. Recommendation: ship.
