# Practice Project — learn jaimitos-os hands-on (then delete this)

> **This file is a standalone, throwaway tutorial — safe to delete completely once you've
> test-driven the setup.** Nothing in the scaffold depends on it, and `install.sh` does NOT
> copy it into real projects (it lives at the repo root, outside `jaimitos-os/`).

A small, self-contained project to learn the whole stack on — not tied to anything real.
A CLI + API that suggests a secondhand-marketplace listing price from an item description,
~4 phases you can build in an evening. Low stakes (no money moves, fully reversible) so you
can safely try the autopilots, steering, and the kill-switch.

## How to use it
1. Make a throwaway repo and install the scaffold into it:
   ```bash
   mkdir /tmp/prendapricer && cd /tmp/prendapricer && git init
   bash ~/jaimitos-claude-setup/install.sh .
   ```
2. Follow the four sessions below.
3. When you're done learning, `rm -rf /tmp/prendapricer` (and delete this file). Done.

---

## The spec (drop into `docs/SPEC.md`)
```md
# Spec: PrendaPricer

## What & why
A CLI + FastAPI service that suggests a listing price for a secondhand clothing item,
given a structured description (category, brand tier, condition, era/style tags).

## Success criterion (measurable)
Given the 20-item fixture set in tests/fixtures/items.json, the suggested price is within
±20% of the labelled "good_price" for at least 15 of 20 items.

## In scope
- Pure pricing function: features in → price + confidence out.
- A rules+heuristics baseline (no ML in v1).
- CLI (`prendapricer "item desc"`) and POST /price endpoint.

## Non-goals
- No scraping of live marketplace data in v1 (use the fixture set).
- No image input, no persistence in v1.

## Constraints
- Python 3.12, FastAPI, pytest. Money as Decimal, never float.
- Pricing logic must be a pure, unit-tested function.
```

## The roadmap
Run the **`roadmap`** skill on that spec. It will recommend a granularity — for this scope,
~4 fine phases — and write them with `Done when:` lines and loopable/supervised tags, e.g.:
```md
## Phase 1 — Pricing core
- [ ] ItemFeatures + PriceSuggestion dataclasses
- [ ] suggest_price() with base-by-category + brand/condition/era multipliers
- [ ] Unit tests for each multiplier + an end-to-end example
Done when: pytest passes and suggest_price() returns a Decimal + confidence for a sample item.
Mode: loopable

## Phase 2 — Evaluation harness
- [ ] tests/fixtures/items.json (20 labelled items)
- [ ] eval test asserting ≥15/20 within ±20% of good_price
Done when: the eval test runs and reports the hit rate.
Mode: loopable

## Phase 3 — Interfaces
- [ ] CLI entrypoint + POST /price endpoint + TestClient test
Done when: curl to /price returns a valid suggestion and the CLI works.
Mode: supervised   # touches I/O

## Phase 4 — Hardening
- [ ] input validation + 422; README with the eval hit rate; tune multipliers to pass the eval
Done when: full suite green, eval criterion met, README written.
Mode: loopable
```

## Build it across four sessions
```
Session 1 — scaffold + Phase 1 (manual, learn the rhythm)
  /resume → plan → "implement phase 1, TDD" → @evaluator grade → teach-back → /wrap → /clear

Session 2 — Phase 2 watchable
  /resume → /autopilot 1   (watch it build fixtures + the eval test) → /wrap → /clear

Session 3 — Phase 3 supervised
  /resume → /phase → curl the endpoint + run the CLI yourself → /wrap → /clear
  # Phase 3 is Mode: supervised, so the tick gate REFUSES to auto-tick it —
  # that's why it's a manual session, not an autopilot one.
  # Under the hood, /phase itself delegates research/plan/execute to their own subagents
  # (verify already did) — each independently pinnable to a model via /models, if you want.

Session 4 — Phase 4 headless
  bash scripts/autopilot.sh 2
  # if it overfits: echo "Keep multipliers interpretable; don't overfit the fixtures." > STEER.md
```
At the end you have a working, tested, documented tool with a full git checkpoint history,
ADRs, and a STATE.md you could hand to a stranger.

> **What actually ticks the roadmap.** In every session, `/wrap` and the autopilots don't flip
> `- [ ]` → `- [x]` by hand — they route through **`scripts/tick.sh`**, the one gate that requires
> an independent evaluator PASS, fresh green tests, and a clean secret scan before a phase counts as
> done. Watch it refuse in Session 1 if you try to `/wrap` before the evaluator passes — that refusal
> is the whole point.
>
> **Ownership matters as much as output.** The `teach-back` skill (Session 1) has Claude explain what
> it built, then quizzes *you* — code you can't explain is code you don't own. The `ownership-nudge`
> hook reminds you after each change.

## What you'll have learned
Measurable success criteria · phase boundaries that each leave a working program · TDD as the
loop's truth source · the evaluator catching premature "done" · the `tick.sh` completion gate that
won't mark a phase done without evidence · owning the code via `teach-back` · running a phase
watchable and headless · steering and stopping a loop.

## Graduating to high-stakes work
Apply the same stack to real work with one change for anything consequential: **drop autopilot
for high-stakes/irreversible code** (auth, migrations, money, deletes, external effects). Use
`/phase` supervised, keep `permission_mode: default`, require review before merge, and let git
history + ADRs be your audit trail. Point the **enforced** high-stakes list — `HIGH_STAKES_RE` in
`.claude/lib/_high-stakes.sh` — at your sensitive dirs (then mirror it in `.claude/rules/high-stakes.md`
for humans); the tick gate refuses to auto-tick anything that touches those paths.
