# Changelog

All notable changes to this project are documented here.
Format loosely follows [Keep a Changelog](https://keepachangelog.com/); this project
uses [Semantic Versioning](https://semver.org/).

## [Unreleased]

_Nothing yet._

## [2.13.0] — 2026-07-16

Native requirement traceability — the spec and plan sides of the chain v2.12.0 started. Stable
`REQ/AC/OBJ` ids now flow `docs/SPEC.md` → roadmap `Requirements:` → plan tasks → the conditional
evaluator, validated deterministically for structure. Opt-in, inert by default, and never required for
tiny work; no external tool, no second spec/task/completion tree.

### Added — native id conventions on the spec and plan sides
- `docs/SPEC.md` gains an **optional** `## Requirements (optional — REQ/AC)` section: `REQ-###`
  (a requirement), `AC-###` (an acceptance criterion, unique across the whole spec), `OBJ-###`
  (a maintenance objective), each with a `Status:`. Tiny specs keep using only the measurable Success
  criterion. `[NEEDS CLARIFICATION]` keeps a requirement out of `Approved`.
- `to-spec` is the **sole owner** of native id assignment and preservation at spec close (no renumber on
  reorder, no silent recycle); `grill` only discovers requirement candidates during the interview.
- The `planner` maps each task to the `REQ/AC/OBJ` it advances — only when the phase declares a
  `Requirements:` block; tiny/mechanical phases skip it. An external id (`FR-001`, `JIRA-1234`,
  `REQ-AR-001`) is accepted when the source defines it; core hard-codes no external prefix.

### Added — deterministic id validation
- New shared lib `.claude/lib/_requirements.sh` owns id semantics; `scripts/lint-roadmap.sh` calls it
  only when a phase carries a `Requirements:` line. It validates **structure only**: well-formed and
  unique ids (`AC` globally), roadmap refs that resolve to `docs/SPEC.md` for spec-sourced phases, and
  no blocking `[NEEDS CLARIFICATION]` inside an `Approved` requirement. Advisory by default; `--strict`
  fails. It never claims a requirement is *satisfied* — that stays the evaluator's model-dependent job.

### Guarantees
- **Deterministic:** id well-formedness + uniqueness, reference resolution, and the Approved/clarification
  rule (`_requirements.sh` via `lint-roadmap.sh`). **Model-dependent:** whether a requirement is genuinely
  satisfied (the evaluator, only when a phase declares `Requirements:`). `docs/dev/AUTHORING.md` records
  the split; no model-dependent guarantee is described as enforced.
- **Unchanged:** `scripts/tick.sh` remains the sole completion gate; the evaluator's verdict contract,
  isolation, and the v2.12.0 conditional traceability behavior are byte-for-byte untouched (no cosmetic
  edit). Requirement metadata adds no open tasks and cannot bypass the gate.
- **Backward compatible & lean:** a spec with no ids, or a phase with no `Requirements:` block, behaves
  exactly as before. Always-loaded context is unchanged (5035 B) — the guidance rides skill/agent bodies,
  not their descriptions. Why native and not Spec Kit:
  `docs/decisions/ADR-001-native-requirement-traceability.md`.
- **Verified:** 21/21 guard suites green on macOS (Bash 3.2 / BSD) and non-root Linux (mawk 1.3.4),
  including the new requirement-id validation.

## [2.12.0] — 2026-07-16

Requirement traceability, as a core capability — grade a phase against the external requirement ids
it declares, from any source.

### Added — the evaluator traces declared requirement ids

When a project is planned from an external requirements source — a PRD, a ticket, an imported feature
specification — a roadmap phase MAY now carry two optional lines under its tasks:

```md
Sources:
- specs/account-recovery/spec.md
Requirements:
- REQ-AR-001 — the reset token expires after 15 minutes
```

The `evaluator` treats each declared id as an **additional Axis-A acceptance criterion**: it locates
the id in the named source and states, per id, whether the diff satisfies / partially satisfies /
does not touch it. An id it cannot trace to code or a test is an unmet criterion — it fails the phase
exactly as a missing "Done when:" would. It grades only the ids the phase claims, and treats an id
silently dropped since planning as the same integrity violation as an edited "Done when:".

The `roadmap` skill documents the producing side (the optional `Requirements:`/`Sources:` block and
how to attribute ids honestly). The `lint-roadmap` schema ignores both lines, so they are always safe
to add and never required.

**This names no tool and adopts no id format** — use `FR-001`, `REQ-AR-001`, `JIRA-1234`, whatever the
source already uses. It works for a PRD, a ticket, or any external spec. (It originated in the Release
2 Spec Kit experiment, which was rejected as a promoted integration precisely because this — the one
capability worth keeping — is separable from any single tool. Here it lands on its own merits.)

### Guarantees
- **Inert in a default project.** No shipped roadmap template carries a `Requirements:` line, so the
  branch never fires unless a project opts in. A clean install produces a byte-identical evaluator;
  `test-docs-invariants.sh` asserts both the conditional wording and that the shipped agent names no
  external tool. Always-loaded context is unchanged (5035 B).

## [2.11.2] — 2026-07-14

A roadmap is allowed to talk about its own notation. It wasn't.

### Fixed — one definition of an open task

`docs/ROADMAP.md` is prose as well as state. It can quote an example, carry a legend, or hold a
`Done when:` that says *"every `- [ ]` under this phase is checked"*. Core disagreed with itself
about whether such a line is a **task**:

- `lint-roadmap.sh` matched tasks **anchored** (`^[[:space:]]*- \[ \] `) — correct.
- `_roadmap.sh`'s open count, and `tick.sh`'s completion gate, its before/after counts **and its
  gsub**, matched them **unanchored** (`/- \[ \]/`) — any line merely *containing* the substring.

Eight sites, five files, drifted apart over time. `close-milestone.sh` had already hit this and
anchored itself, with a comment naming the exact hazard — and the fix never travelled.

Two real failures, both silent:

1. **A phase could tick with no work in it.** Prose mentioning `- [ ]` satisfied `tick.sh`'s "target
   phase still has an open item" gate. The before/after counts then dropped, so the transaction
   validated, and the phase was marked complete.
2. **`tick.sh` corrupted documentation in place.** The `gsub` rewrote *every* occurrence of `- [ ]`
   in the phase block — including inside prose — to `- [x]`.

There is now exactly one definition — `ROADMAP_OPEN_RE` / `ROADMAP_TASK_RE` in
`.claude/lib/_roadmap.sh` — with `roadmap_open_total`, `roadmap_first_open_task`,
`roadmap_next_open_heading` and `roadmap_tick_phase` (the mutation itself) built on it. `tick.sh`,
`autopilot.sh` and `close-milestone.sh` all go through the library; no core file hand-writes a task
regex any more. `lint-roadmap.sh` (dependency-free by design) and `session-start.sh` (a display-only
hook) remain the two documented exceptions.

Regexes reach awk via `ENVIRON`, never `-v` — awk processes escape sequences in a `-v` assignment
and mangles the `\[`. Verified on BSD awk (macOS) and mawk 1.3.4 (Linux CI).

### Changed
- `autopilot.sh` and `close-milestone.sh` now **fail closed** when `.claude/lib/_roadmap.sh` is
  unloadable, rather than degrading to a hand-copied regex. Both already required the library; they
  now say so before doing any work, not after. ("I couldn't read the roadmap" must never become
  "safe to close".)

### Added — the guard, which is the point
`test-roadmap-lib.sh` now asserts, at source level, that **no core file matches a task line
unanchored**, and that **no core file outside the three documented homes hand-writes a task regex at
all**. The bug was never one regex; it was eight copies free to drift. Anchoring them all again
without that guard would just restart the clock.

## [2.11.1] — 2026-07-14

Fixes a flaky guard test. Test-only: no shipped behaviour changes.

### Fixed
- **`test-autopilot-gates.sh` #23 (`spawn_hang`) was intermittently failing** — roughly 3 runs in 4
  inside a container, while passing on macOS and in CI. It was a **lying assertion, not a real bug**:
  the watchdog's tree-kill has been working correctly all along.

  `pid_dead()` decided liveness with `kill -0`, which **succeeds on a zombie**. When the watchdog
  reaps the subtree, the grandchild is orphaned to PID 1; a real init reaps it instantly (the pid
  vanishes, `kill -0` fails, the check passes), but a container's PID 1 is often a plain shell that
  never reaps — so the zombie lingers and `kill -0` kept reporting a process that had already been
  killed as *alive*. The intermittency was a race between the parent reaping its child and the parent
  itself being killed.

  `pid_dead()` now treats a **zombie as dead**, which is what it is: it holds no resources and
  executes nothing. This does not weaken the assertion — a subtree that genuinely survived the kill
  would be state `S`/`R`, never `Z`.

  Diagnosed by instrumenting the real failure rather than guessing (`state=[Z] cmd=[sleep<defunct>]`).
  Two earlier hypotheses — a missing `pgrep`, and a minimal isolated repro — were both **refuted** by
  evidence before the real cause was found.

- **Added a regression self-test (`#22b`)** that builds a zombie deterministically and asserts
  `pid_dead` reads it as dead. If anyone reverts the helper to a bare `kill -0`, that test fails
  loudly instead of #23 flaking silently. It fires (does not skip) on both macOS and Linux.

  A flaky guard test is worse than a missing one: this suite is the evidence the whole completion
  gate rests on, and a test that cries wolf teaches people to ignore it.

## [2.11.0] — 2026-07-13

Closes the architectural-drift gap at the milestone boundary — and corrects a mistake v2.10.0
shipped, caught by the independent review v2.10.0 owed but never performed.

**Always-loaded context DROPPED 296 B, back to the v2.9.0 baseline (5035 B).** All three skills
added in v2.10.0 now cost **zero**.

### Added — the architecture pass at the milestone boundary
Per-phase review is diff-bound. The evaluator grades one phase's changes, so ten individually-clean
phases can compose into a pass-through layer and **nothing is looking at the whole**. The milestone
boundary is the only place that view exists, and `close-milestone.sh` checked open items, findings
and roadmap shape — but never architecture.

- **`close-milestone.sh` now prints a non-fatal `NOTE`** when a whole milestone was built without
  refreshing `docs/ARCHITECTURE.md` (or when there is no map at all and code shipped). It names the
  `mapme` skill. It **never blocks the close** — same contract as the existing Ownership-gaps notice.
  "This milestone" is scoped to commits since the previous close, so the notice fires when it means
  something rather than on every close, which would be noise nobody reads.
- **`milestone` Mode B gains the pass itself** (step 1b): dispatch `mapme` **into a subagent** — it
  reads the whole codebase, and that belongs in its own context, not the one you are about to write
  the next roadmap in — then carry any **Strong** friction finding into the next roadmap as a real
  phase. A Strong finding nobody schedules is one that gets rediscovered, identically, next milestone.

This is deliberately *not* an agent. `agent-creator` audited exactly that proposal in v2.10.0 and
refused it: a 5th agent must join `GATE_CONTROL_FILES` and is then byte-compared on **every autopilot
tick in every downstream project, forever** — a permanent tax on the hot path to serve a
once-per-milestone human path. A skill dispatched into a subagent buys the separate context for free.

### Changed — `module-design` is now user-invoked (a v2.10.0 correction)
v2.10.0 shipped it **model-invoked**, reasoning that "five components must reach it". The independent
review found that all five — `design-twice`, `mapme`, planner, executor, evaluator — name it by
**explicit path**, and **none** relies on autonomous invocation. The 295 B/turn bought nothing,
forever. The defence offered ("a user might ask a bare question about seams") was circular: a user who
can phrase the question in the skill's own vocabulary has already read it.

The file is unchanged and still shipped; only its invocation mode moved. `prototype` was the
precedent that should have been followed — also adapted, also engineering, correctly user-invoked.

### Changed — `skill-creator` now prevents that mistake
Three gaps let it through, all closed:
- **A mandatory consumer enumeration.** Before choosing model-invocation you must `grep` the
  consumers and show that at least one relies on *autonomous* reach. The argument felt right; the grep
  would have settled it in ten seconds.
- **A stated default:** user-invoked. Model-invocation now carries the burden of proof.
- **An `Independent review:` field that may not name you.** A component's author cannot clear it —
  not "reviewed my own work carefully", not a subagent you briefed and then graded. If nobody
  independent looked, the honest value is `NONE — not cleared for release`.
- The context-cost check now demands the **new always-loaded total**, not the marginal cost. Every
  skill looks affordable alone; that is how a budget dies.

### Fixed
- **The deletion test had three homes** (`module-design`, `mapme`, `evaluator`) — a violation of
  `checks.md`'s own "one meaning, one home" rule, found by the same review. `mapme` now points at the
  canonical definition. The `evaluator` keeps its inline copy as a **documented** exception: a
  gate-checked grading contract must stand on its own and cannot depend on reading a skill file.

## [2.10.0] — 2026-07-13

Engineering-disciplines release. It strengthens how Jaimitos designs, tests, debugs, verifies and
reviews, and adds maintainer-only tooling for creating and linting components — while adding **no**
second orchestrator, planner, executor, evaluator, completion gate, roadmap, or agent swarm.
Adapted (not copied) from `obra/superpowers` @ `d884ae0` and `mattpocock/skills` @ `391a270`, both
MIT, both pinned in `integrations/upstreams.lock.json`. `VERSION` → `2.10.0`. Not tagged.

**Always-loaded context grew by 387 bytes (~96 tokens, +4.8%)** — one new model-invoked description
plus one CLAUDE.md clause. Everything else is on demand or maintainer-only.

### What this release does NOT claim

`docs/dev/AUTHORING.md` opens with a `Guarantee | Enforcement` table, and it is the point of the
release. The linters check **shape** — frontmatter, naming, catalog registration, install exclusion,
tool boundaries, context budget, provenance, and that a discipline is *stated*. They do **not** check
**judgement**: whether a test failed for the intended reason, whether a speculative-fix loop was
avoided, whether a component was justified, whether an architecture is proportionate. Those are
model-dependent and, for control-plane changes, human-reviewed. No check here proves otherwise.

### Added
- **`module-design`** (model-invoked, 295 B description) — the deep-module vocabulary: depth, seam,
  leverage, locality, the deletion test. A reference: it decides nothing, owns no artifact, never
  ticks. It pays for a description because the planner, executor, evaluator, `design-twice` and
  `mapme` all reach it. Long material behind `deepening.md`.
- **`prototype`** (user-invoked, **0 B** always-loaded) — throwaway code answering ONE stated
  question, isolated from production/runtime paths. Its output **may** serve an explicitly scoped
  prototype/research phase but **may never** satisfy production implementation or release criteria,
  and it can never tick. `disable-model-invocation: true` is deliberate: auto-firing "write
  throwaway code" inside a TDD-mandatory scaffold is actively harmful.
- **`review-feedback`** (user-invoked, **0 B** always-loaded) — nothing covered *receiving* review
  feedback. Classifies each comment (correct and actionable · out of scope · misunderstanding ·
  already addressed · conflicting · unsafe · architecturally harmful), verifies it against the code,
  implements what's right and pushes back with reasons on what isn't. Never complies on authority.
- **`skill-creator`** and **`agent-creator`** — maintainer-only, in the repo-root `.claude/skills/`.
  `install.sh` reads only `jaimitos-os/` and `skills/`, so they are **structurally** unshippable, not
  list-excluded. Both default to refusal; `NO NEW AGENT JUSTIFIED` is a success.
- **`docs/dev/AUTHORING.md`** — the authoritative maintainer guide. Maintainer-only.
- **`integrations/upstreams.lock.json`** — pinned upstream provenance, the files consulted, the files
  influenced, and every deliberate deviation, including what was **rejected** and why. No auto-updater.
- **`test-skills.sh` / `test-agents.sh`** — two new guard suites (21 total).

### Changed
- **`tdd`** — the red must fail *for the intended reason*; green must also be quiet; the wider suite
  runs after the targeted green; regression coverage precedes a behavior change; an explicit,
  **recorded** exception when production code must precede the test. Never claim TDD with no observed
  meaningful red.
- **`diagnose`** — an evidence taxonomy (symptom · root cause · contributing condition · unverified
  hypothesis · confirmed evidence · unresolved uncertainty), a ban on speculative fix loops, revert
  before retry, **three failed fixes = stop and question the architecture**, and bisect-first for
  regressions.
- **`evaluator`** — now grades two named axes, **Specification compliance** and **Engineering
  quality**, reported separately and never re-ranked. **A failure in either axis is `NEEDS_WORK`.**
  The verdict token is unchanged (`PASS` / `NEEDS_WORK:`) *on purpose*: `record-grade.sh` records a
  grade only when the last non-empty line is exactly `PASS`, so the `PASS|FAIL` the brief asked for
  would have silently broken the tick gate.
- **`/phase`, `/wrap`, `executor`** — verification must be **fresh, after the final edit**. The
  builder's report is a claim, not evidence. Exact commands, warnings disclosed, skipped checks
  disclosed; a unit suite never substitutes for a required integration check.
- **`glossary`** — the active domain-modeling discipline (challenge, sharpen, cross-reference against
  the code) plus a 3-condition ADR test. Still the sole `docs/GLOSSARY.md` authority.
- **`mapme`** — flags architectural friction in `module-design` vocabulary (shallow modules,
  pass-through layers, leaky seams, poor locality) and classifies findings Strong / Worth exploring /
  Speculative. Reports; never refactors. **This is why no `architecture-audit` skill was added.**
- **`doctor.sh` no longer hardcodes `REQUIRED_SKILLS`** — it derives the expected skill set from
  `.claude/.jaimitos-manifest`, which `install.sh` already writes. Strictly stronger: it detects a
  skill dropped or renamed relative to what *actually shipped*, and it cannot go stale. No manifest →
  it warns rather than claiming the set is complete.
- **`install-smoke.sh`** derives its expected set from `skills/`; the **negative** assertions stay
  explicit and now cover `skill-creator` / `agent-creator`.
- **Skill counts live in `skills/README.md` and nowhere else.** The unchecked counts in
  `CONTRIBUTING.md` / `GUIDE.md` / `SCAFFOLD.md` are gone. `test-docs.sh` now scans those files too,
  including English word forms — "Sixteen skills" sat in `README.md` for three releases because a
  digits-only regex never looked at it.

### Fixed
- **The shipped `CLAUDE.md` pointed every installed project at `toolkit-docs/GUIDE.md`** — a path
  `install.sh` deliberately excludes. Every user project carried a pointer to a document it could not
  open. Found by dogfooding the new `diagnose` skill; regression test in `test-docs-invariants.sh`.

### Rejected (documented, not silently dropped)
- **`architecture-audit`** — `mapme` + `design-twice` + `module-design` + the evaluator's Axis B
  already own that responsibility. Its upstream form is a Tailwind/Mermaid HTML report app.
- **Superpowers' `brainstorming`, `writing-plans`, `subagent-driven-development`, `executing-plans`,
  `finishing-a-development-branch`, `dispatching-parallel-agents`, and the SessionStart bootstrap** —
  each is a competing spine (router / planner / executor / completion gate / swarm), and importing one
  drags the cross-referenced chain with it.
- **`requesting-code-review` / Matt's `code-review` as skills** — v2.7.0 already delegated review to
  the native `/code-review` and `/security-review` plus `scope-guard` and the evaluator. Matt's
  two-axis *idea* was adopted: it is the two-axis evaluator.
- **No new production agent.** `agent-creator`'s own dogfood audited the architecture-review-agent
  proposal and refused it.

## [2.9.0] — 2026-07-11

Trust-hardening release acting on the 2026-07-11 re-audit (`docs/dev/audits/`). It closes the
reproduced trust gaps that remained after v2.8.x — all in manual mode, release tooling, and
edge-case loss-of-work paths — without adding a database, service, workflow engine, or crypto.
`VERSION` → `2.9.0`. Not tagged (tag at release with approval; run `scripts/release-check.sh
--prepare` before tagging and `--released` after).

### Fixed — security & correctness (from the 2026-07-11 re-audit)
- **F1 — headless autopilot no longer publishes an incomplete run.** The `--pr` push/PR path was
  reached on ANY non-high-stakes, non-aborted exit — including ordinary failures (builder crashed,
  empty/garbled verdict, thrash cap, tick REFUSED) and partial multi-phase runs — so a branch
  carrying ungraded per-task builder commits could be pushed. A single authoritative `RUN_RESULT`
  (default "failed"; "success" only after a fully-successful iteration or the roadmap-complete
  break) now gates publication; every other outcome keeps the branch local. Ordinary failures and
  watchdog aborts exit non-zero; intentional high-stakes/supervised stops exit 0.
- **F2 — the sandbox never discards produced work.** The exporter keyed only on `autopilot/*`
  branches, and forwarded args were unchecked; a forwarded `--no-worktree` made the loop commit on
  the clone's current branch, so the exporter found "nothing to import" and deleted the clone. Now
  `--no-worktree` (and other export-breaking options) are rejected before any container starts, and
  the wrapper inventories ALL produced work (new/advanced `autopilot/*` branches, commits on a
  non-autopilot branch or detached HEAD, dirty/untracked files) — deleting the clone only when
  everything was exported, otherwise preserving it with exact recovery.
- **F3 / audit I1 — the manual phase anchor is base- and test-command-bound.** A builder could
  advance the tracked `.claude/.phase-anchor` base to a later ancestor and commit it, narrowing the
  secret/high-stakes scan window; `tick.sh` still ticked. It now requires the anchor's `base=` to
  equal the parent of the commit that last set the anchor (the naive narrowing fails closed, exit
  3). The anchor also records the authorized test-command identity (`test_source` + `test_command`
  + `test_config_sha`), and manual `tick.sh` requires anchor == evidence == current command, so a
  mid-phase `.claude/test-command` swap is refused. `authorized_test_cmd` additionally rejects
  bounded wrapped/degenerate no-ops (`sh -c true`, bare `echo`/`printf`, …). Honest residual: a
  builder running arbitrary git can still `reset`+re-anchor — headless (orchestrator `TICK_BASE`)
  remains the trust-equivalent path.
- **F4 — ROADMAP/STATE completion is rollback-safe.** `tick.sh` mutated ROADMAP then STATE; a STATE
  failure left ROADMAP ticked with STATE stale. A minimal two-file transition now generates both
  updated files, validates them (open-count dropped, STATE markers, targets writable), backs up the
  originals, applies both, and rolls back on any failure — printing `✓ ticked` only after both
  succeed and cross-file verification passes. If rollback itself fails, the `*.tick-bak` backups are
  preserved with exact recovery. Leftover artifacts from an interrupted run are detected and refused.
  A read-only STATE is now caught before any mutation (no half-apply). (The full `doctor --state`
  cross-file repair engine stays deferred.)
- **F5 — the checkpoint hook restores the EXACT pre-hook index.** It saved only staged filenames and
  re-`git add`-ed them on a secret abort, losing partial (hunk-)staging, staged renames, mode
  changes, and intent-to-add. It now snapshots the raw `.git/index` (`git rev-parse --git-path
  index`, so linked worktrees resolve) and restores it byte-for-byte.
- **F6 — evaluator isolation covers configured fixture dirs.** The `--directory` collapse hid a new
  file created inside a pre-existing ignored dir. A project lists such dirs in project-owned
  `.claude/eval-fixture-paths` (empty by default; never dependency trees); files under them are
  hashed so a created/modified fixture is detected (interactive) or removed / STOP'd (headless).
- **F7 — release-check verifies tag IDENTITY, not just existence.** New `--prepare` (VERSION ↔
  newest CHANGELOG, `[Unreleased]` empty, clean tree) and `--released` (annotated `v$VERSION` tag
  pointing at a commit whose VERSION + newest CHANGELOG both equal `$VERSION`; reports master↔tag;
  verifies the remote tag when origin exists). A tag on the wrong commit now fails.

### Changed
- macOS CI leg now ASSERTS bash 3.2 (was informational) so the portability coverage can't silently
  move to a newer Homebrew bash. Permission-injection guard tests are root-guarded (root bypasses
  `chmod`). New `.claude/eval-fixture-paths` is project-owned (sync/install never overwrite it).

## [2.8.1] — 2026-07-11

Patch release. Corrects a dangling command reference introduced in 2.8.0. No safety-path behavior
changes — the N-2 fail-closed refusal on a failed STATE write is unchanged; only the recovery guidance
it prints is now accurate.

### Fixed
- **Dangling `doctor.sh --state` reference in `scripts/tick.sh`.** On a failed `docs/STATE.md` write
  (finding N-2) tick.sh refused correctly but told the user to run `bash scripts/doctor.sh --state` — a
  command that was deferred and never implemented (`doctor.sh` rejects it with exit 2). The recovery
  message and its code comment now name only supported actions: `docs/ROADMAP.md` is authoritative;
  restore or repair `docs/STATE.md` and re-run `bash scripts/tick.sh` on a clean tree. New regression
  test (`scripts/test-tick.sh`, case 16e) forces the STATE write to fail and asserts tick exits
  non-zero, never prints `✓ ticked`, never mentions `doctor.sh --state`, and that every command named
  in the recovery message actually exists.

### Deferred (unchanged, still tracked)
- Full transactional ROADMAP+STATE two-file update and a complete `doctor --state` cross-file
  invariant/repair path (audit N2/6.7) remain a separately tracked future improvement — deliberately
  NOT pulled into this patch.

## [2.8.0] — 2026-07-10

Hardening release acting on the repository-wide 2026-07-10 audit (`docs/dev/audits/`). It closes the
audit's Critical/High findings on the unattended-execution safety story without adding any database,
service, workflow engine, or crypto — every fix stays in the Git/file model and routes completion
through the single `tick.sh` gate. `VERSION` → `2.8.0`. Not tagged (tag at release with approval).

### Fixed — security & correctness (from the 2026-07-10 audit)
- **C1 — the sandbox no longer mounts ignored secrets.** `sandbox/run-autopilot-sandboxed.sh` mounted
  the live working dir, so a gitignored/untracked `.env`, `*.pem`, `.netrc`, `id_rsa`, `secrets/`, a
  cache tree, or a tracked *symlink* to one rode into the bypass-mode container. It now mounts a clean,
  tracked-only `git clone --local` staging copy — ignored/untracked content is physically absent; a
  self-contained `.git` lets `git worktree add` work inside; a *committed* secret still fails closed.
  The loop's `autopilot/*` branch is imported back out of the clone, failing closed + preserving the
  clone if the import can't complete (no work lost behind a warning). (finding N-3 folded in)
- **C2 — headless autopilot refuses to build a `Mode: supervised` phase.** It used to build a
  supervised phase to completion before `tick.sh` refused the checkbox. A pre-build gate now parses the
  next phase's Mode (via one shared, fail-closed parser) BEFORE spawning the builder and stops on
  supervised / missing / duplicate / invalid Mode. New `.claude/lib/_roadmap.sh` replaces the several
  hand-copied phase parsers (in `tick.sh`, `close-milestone.sh`, and the gap `autopilot.sh` had).
- **H1 — the manual phase scan floor is tamper-evident.** `tick.sh` read the floor from the gitignored,
  builder-writable `.claude/.phase-base`, which a builder could silently advance to hide commits. New
  `scripts/start-phase.sh` records the floor in a TRACKED, committed `.claude/.phase-anchor` (clean tree
  required; prints the judged range); `tick.sh` prefers it and prints the `BASE..HEAD` range. Advancing
  the floor is now a visible commit, not a silent rewrite. Honest scope: tamper-EVIDENT + human-reviewed,
  not builder-proof — headless (orchestrator-derived `TICK_BASE`) remains the trust-equivalent path.
- **H2 — the graded test command is integrity-bound.** The tick gate graded whatever the resolver read
  from mutable, builder-writable, un-gated sources (settings.json env block, package.json, Makefile…),
  so a builder could swap in a no-op. New `authorized_test_cmd()` grades ONLY the `LEAN_TEST_CMD` env
  (parent-shell, not builder-settable) or the project-owned, gate-controlled `.claude/test-command`
  (no-ops rejected; `none: <reason>` sentinel). Evidence records command + source + config hash.
  Migrated safely: `sync.sh` / `doctor --fix` seed `.claude/test-command` from PERSISTENT config only
  (never the transient env), never overwrite, and fail closed if nothing safe can be derived.
- **H3 — evaluator isolation now sees ignored files.** Snapshot/restore ignored the ignored set, so a
  grader could create/modify an ignored fixture/cache/`.env` undetected. `_eval-isolation.sh` now
  detects `[created-ignored]` paths (removing only those created during grading — never the builder's
  deps) and, for a bounded sensitive allowlist (`.env`/`.pem`/`.netrc`/…), detects tampering and fails
  closed. Documented residual: arbitrary edits to other pre-existing ignored files stay undetectable.
- **H4 — a malformed `HIGH_STAKES_RE` fails closed.** An invalid custom regex silently disabled the
  path gate. The matcher is now three-state (matched / clean / config-error) and EVERY caller in
  `tick.sh` treats a config error as a hard refuse (the audit's own `return 2` fix alone would still
  have failed open); `doctor.sh` reports a non-compiling regex as an error, not a green "customized".
- **H5 — manual tick refuses a dirty checkout.** Exact-HEAD evidence is only honest when the checkout
  equals HEAD; `tick.sh` now refuses a dirty tracked/untracked tree (gitignored runtime artifacts
  exempt) before mutating ROADMAP/STATE.
- **N-2 — a failed STATE write no longer reports success.** `tick.sh`'s `update_state` returned 0
  unconditionally; a read-only `docs/STATE.md` yielded "✓ ticked" + exit 0. It now returns the write
  status and tick refuses on failure, pointing at the repair path.
- **N3 — the checkpoint hook preserves a curated staging selection** on a secret-scan abort (was a
  whole-index `git reset`).
- **N-1 — the local `lint-shell.sh` gate is trustworthy.** `.shellcheckrc`'s `severity=` key is
  unsupported (CLI-only), so the local gate failed on a clean tree while CI passed; the warning floor now
  lives in `lint-shell.sh` explicitly.

### Changed / Added
- New shared `.claude/lib/_roadmap.sh` (fail-closed phase parser) and `scripts/start-phase.sh`;
  `.claude/test-command` is the one authorized graded command (project-owned, gate-controlled).
- Strict `lint-roadmap.sh` schema checks (unique headings, one valid Mode, ≥1 task); new
  `scripts/release-check.sh`; a macOS/bash-3.2 CI leg; honest three-state installer status; corrected
  SECURITY/GUIDE/README/CONTRIBUTING/CLAUDE/install claims to match the implementation.
- `/autopilot-parallel` was already removed in 2.7.0; confirmed clean.

### Deferred (tracked follow-ups, not blocking this release)
- **Full transactional ROADMAP+STATE replacement and a `doctor --state` cross-file repair path**
  (audit N2/6.7). The dangerous half — a failed STATE write silently reporting success — is fixed
  (N-2 above); the remaining two-file transactional rewrite + invariant repair is a larger, riskier
  change deferred to a follow-up.

## [2.7.0] — 2026-07-10

### Added
- **dbt test runner in the shared resolver.** `dbt_project.yml` + `dbt` on `PATH` → `dbt build`
  (models **and** their tests, in dependency order — `dbt test` alone would grade a warehouse the
  phase never rebuilt). Gated on manifest AND runner exactly like go/cargo/make/mvn/gradle, so an
  absent `dbt` falls through to the loud `LEAN_TEST_CMD` fallback rather than emitting a command that
  can't run. `tick.sh` is untouched. This was the audit's highest-value fix and its only *day-one,
  phase-one* blocker: a dbt project matched no detector, so the tick gate recorded `passed:null` and
  the first phase could never auto-tick. Sits after the pytest checks — `dbt init` scaffolds a
  `tests/` dir, so a dbt repo that *also* has pytest installed still resolves to pytest; set
  `LEAN_TEST_CMD="dbt build"` to override. (`_test-cmd.sh`, `scripts/test-test-cmd.sh`)
- **`doctor.sh` lists active `high-stakes-ok:` content suppressions** (audit F2). The path allowlist
  was already reported for auditability; the inline, **builder-forgeable** content marker was surfaced
  nowhere, so a suppression could hide in plain sight. A line is listed (`path:line — reason`) only
  when it both matches `HIGH_STAKES_CONTENT_RE` and carries a reasoned marker; both regexes are
  sourced from `_high-stakes.sh` so they can't drift from the gate. Report-only — no gate behavior
  changes, exit code untouched. (`doctor.sh`, `scripts/test-doctor.sh`)
- **Docs drift guard for the shared-lib count** — `test-docs.sh` now binds every
  "`<N>` shared/sourced lib(s)" mention in README/GUIDE to the real `.claude/lib/_*.sh` count,
  mirroring the existing skill-count binding. Accepts digits *and* English number words, because the
  mentions that rotted were spelled "three".

### Changed
- **Retired `explain-diff` and `ship-check`.** Claude Code's native `/code-review`,
  `/security-review` and `/verify` supersede them and are maintained upstream. `ship-check`'s
  scaffold-specific Step 3 ("check the paper trail" — STATE.md updated? ADR written?) is **preserved**,
  folded into `scope-guard`, which fires at the same pre-commit moment. The pre-commit chain is now
  `scope-guard → /code-review → /security-review` (or `/verify`). Skills: 18→16 total, 17→15 portable.
- **Removed `/autopilot-parallel`** — the audit's "minimum safe cut": 392 lines (command + test), no
  usage evidence, already labeled Advanced/experimental, and the only guardrail in the stack enforced
  by nothing but the operator's judgment (human-asserted phase independence). The tick gate, `/phase`,
  in-session `/autopilot` and headless `scripts/autopilot.sh` are untouched. `merge-conflicts` stays,
  retargeted at worktree phase-branch integration generally.
- **Dropped the stale `MultiEdit` tool name** from `disallowed-tools:` lists — it is not a current
  built-in tool, so it declared a contract that never existed. (`scope-guard`, `skills/README.md`,
  `CONTRIBUTING.md`. The `Write|Edit|MultiEdit` hook *matchers* in `settings.json` /
  `format-on-edit.sh` are a defensive superset and stay.)
- **Corrected "3 shared libs" → 4** and named `_eval-isolation.sh` (extracted in v2.5.0, never counted).
  README.md ×3, GUIDE.md ×3.

### Fixed — security & correctness (from the independent v2.6.0 multi-agent audit)
- **`/wrap` now grades under evaluator isolation, and a grade can't be recorded over a dirty tree**
  (audit G12). `record-grade.sh` stamped `run_id = HEAD` at *record* time, blind to the tree the
  evaluator actually graded; headless closed this via `_eval-isolation.sh`, the manual path had no
  isolation at all. `wrap.md` now mirrors `phase.md`: `eval_snapshot` before the evaluator
  (fail-closed) and `eval_changed_files` after — if the grader wrote to the live checkout, the files
  are named and the tick refuses. As the deterministic backstop (a markdown command can't enforce
  itself), `record-grade.sh` is **fail-closed on a dirty tracked tree**. Untracked files are ignored
  by design. Headless is unaffected: it already calls `record-grade` only after `eval_restore` proves
  the tree clean. Residual: a commit landing between grade and record still binds a stale verdict —
  closing that needs the evaluator to emit the HEAD it graded. **Tightens a gate; weakens none.**
- **Documented the transient-secret blind spot** (audit F1). `secret_scan_diff` scans the *net*
  `BASE..HEAD` diff, so a secret added in one commit and `git rm`'d in a later one *within the same
  phase* nets to zero and is reported clean — while `--pr` still pushes the intermediate commit that
  contains it. The opt-in backends already close it (`gitleaks`/`trufflehog` scan commit-by-commit,
  fail-closed when absent); only the documentation was missing. Now in `SECURITY.md` beside the
  prefix-matcher caveat and in `README.md`'s `--pr` notes, both recommending
  `LEAN_SECRET_SCANNER=gitleaks` for any run that pushes. No code change.
- **`auto` permission mode is a complement, not a replacement.** Stated in `SECURITY.md` and
  `rules/high-stakes.md`: `auto` adds a useful in-session *semantic* second opinion, but it is ignored
  for subagents and aborts under `-p`, so it can never be the headless mechanism. `HIGH_STAKES_RE` +
  `tick.sh` remain the enforced gate.

### Fixed — CI / cross-platform test portability
- **Master CI is green again.** The v2.6.0 guard suite had never actually run in CI: the shellcheck
  step failed first (a `lint-shell.sh` doc comment whose leading token `shellcheck` was misparsed as a
  directive → SC1073/1072; and `LEAN_CHECKPOINT= bash …` in `test-doctor.sh` → SC1007), which masked
  the guard tests entirely. Fixed both, plus the failures each newly-reached step then surfaced:
  - **actionlint** — once shellcheck passed, actionlint (it lints workflow `run:` blocks through
    shellcheck) flagged SC2155 in `ci.yml`'s shfmt step (`export PATH="$PATH:$(go env GOPATH)/bin"`
    masks `go env`'s exit status); split the declare and assign.
  - **`claude`-less runner** — `test-doctor.sh` and the `test-sandbox.sh` sandbox-gate tests run
    `doctor.sh`/`autopilot.sh`, which correctly treat a missing `claude` CLI as fatal; CI installs no
    `claude`. Both now stub a no-op `claude` on `PATH` so the tests assert scaffold/gate behavior, not
    the runner's tool availability (the same pattern the other harnesses already use).
  - **BSD-vs-GNU portability** — `session-start.sh` printed a ragged `truncated — … is       40 lines`
    on macOS because BSD `wc -l` left-pads its count (STATE.md + GLOSSARY.md messages); normalized with
    `tr -d`. `test-sandbox.sh`'s docker-mount assertion compared the logical repo path, which macOS
    resolves through the `/var → /private/var` symlink; it now compares the resolved (`pwd -P`) path.
  - **Runner-location assumption** — `test-test-cmd.sh`'s "go.mod present but go absent from PATH"
    case simulated "go absent" with `PATH=/usr/bin:/bin`, but GitHub's ubuntu runner ships `go` in
    `/usr/bin` (macOS keeps it in `/opt/homebrew`), so the resolver found it and emitted `go test`.
    Rebuilt it to run against a PATH with the coreutils the harness needs but no ecosystem runner.
  Verified: shellcheck + actionlint clean, all 17 guard suites + install-smoke pass with the real
  `claude` masked off PATH. Test-only + one hook-message whitespace fix; no scaffold behavior changed.

## [2.6.0] — 2026-07-10

Closing guarantees: make the evaluator's independence mechanical in both run modes, fail-closed the
sandbox brake, and let the secret scan be a real scanner. No new commands, skills, or agents.
`VERSION` → `2.6.0`. Not tagged.

### Fixed
- **The evaluator-isolation asymmetry — a broken guarantee, not an enhancement.** Headless
  `scripts/autopilot.sh` discarded any file change the evaluator wrote; interactive `/phase` did
  not — so the grader's independence was mechanical headless but merely a *convention* in the
  most-used mode, and undocumented. The evaluator has `Bash`, and `>` is a write; the realistic
  vector is a *complacent* grader whose test re-run lets a fixture get written that makes the grade
  pass. Extracted the mechanism to `.claude/lib/_eval-isolation.sh` (`eval_snapshot` +
  `eval_restore` (destructive, headless) + `eval_changed_files` (non-destructive detect,
  interactive)). `autopilot.sh` now sources the lib instead of duplicating it (behavior identical,
  proven by the existing gate tests). `/phase` snapshots before grading (fail-closed) and, after,
  **refuses to advance and names the exact files** if the grader wrote — it never `git reset
  --hard`s your live checkout (that would eat WIP); a human is present to clean up. The lib is
  gate-integrity-checked under headless and required by `doctor.sh`.

### Added
- **`LEAN_SECRET_SCANNER`** (`regex` default | `gitleaks` | `trufflehog`) — opt a real scanner in as
  the backend of `secret_scan_diff`, same 0/1/2 contract, so `tick.sh`/`commit-on-stop.sh` are
  untouched. Fail-closed: a selected-but-missing binary stops the scan (never a silent downgrade to
  regex). `doctor.sh` hard-fails when a selected scanner is absent.
- **`autopilot.sh --i-understand-no-sandbox`** — `--dangerously-skip-permissions` on a bare host
  (no `JAIMITOS_SANDBOXED` / `/.dockerenv` / container-cgroup signal) is now **refused** unless this
  flag is passed; with it, a loud banner is printed and recorded in the run log. The wrapper exports
  `JAIMITOS_SANDBOXED=1`. Signals are documented as reminders, not a boundary.
- **`/autopilot-parallel` requires the literal phrase `I assert these phases are independent`**
  before building (a sentence isn't typed reflexively like `--yes`), and can now reuse the Fase 1
  lib to isolate its integration-time grades.
- **`doctor.sh` subagent-frontmatter check** (warn): flags a subagent file that uses hyphenated
  skill-style keys (`disallowed-tools`/`permission-mode`) instead of camelCase
  (`disallowedTools`/`permissionMode`), or malformed frontmatter that loads with empty metadata —
  both silently drop the restriction you think you set. Warn, not error: the docs confirm the
  camelCase names but not whether the CLI rejects vs ignores a hyphenated key. Also a new `doctor`
  `info` level for non-problem notes.
- **Shell-lint hardening (minor):** repo-root `.shellcheckrc` (codifies CI's existing flags),
  `.github/scripts/lint-shell.sh` (local convenience: blocking shellcheck + advisory shfmt), CI now
  lints `sandbox/*.sh` (a gap since v2.5.0) and runs an **advisory** `shfmt -d` step. shfmt is
  advisory-only because the tree predates it; flip it to blocking once formatted.

### Changed
- **`/autopilot-parallel` is now labeled Advanced / experimental** in README and GUIDE, with its
  absent guarantees (no child watchdog, no auto-retry) listed alongside.

### Deferred (out of scope, with a reactivation trigger)
- **Run-ledger JSONL** — when the 3-strike thrash cap fails to stop a runaway even once.
- **Two-axis (Spec/Impl) evaluator** — when the evaluator passes something a Spec axis would catch.
- **context7 MCP for the researcher** — when the researcher hallucinates an API in practice.
- **Modern command frontmatter (`description`/`argument-hint`)** — a dead afternoon; verify each key
  against the live docs first (adding keys the CLI ignores is maintenance noise).
- **statusline / MCP profiles / monorepo / devcontainer / per-stack templates / `/audit-setup` /
  solo-vs-team install profiles / PR-level code-review** — when real use demands it, not before.

### Note
- **TODO 2026-09-09 (carried from v2.5.0): `autopilot.sh` usage review.** Unchanged.

## [2.5.0] — 2026-07-09

External-audit fixes + seven skills adapted from
[mattpocock/skills](https://github.com/mattpocock/skills) (MIT, © Matt Pocock — rewritten
docs-centric, never copied verbatim). `VERSION` → `2.5.0`.

### Breaking — sync moves to a checksum manifest (one-time migration required)
- **`scripts/sync.sh` is rewritten around `.claude/.jaimitos-manifest`** (written by
  `install.sh`: one `sha256  path` line per toolkit-owned file as shipped, `sha256sum -c`
  compatible). Unchanged files batch-update after ONE confirmation; locally modified files are
  **never** written (diff shown, "manual merge required"); project-owned files are never touched
  or reported; locally deleted files are never recreated (`--restore <path>` reinstalls one
  deliberately); new toolkit files join the batch and enter the manifest.
- **Required action for every pre-2.5.0 project:** run
  `bash scripts/sync.sh --toolkit <path> --adopt-manifest` once. It records the CURRENT local
  files as the baseline (writes only the manifest, no content). Review the first post-adoption
  sync with `--dry-run` — adoption cannot tell a pre-adoption customization from shipped bytes.

### Added
- **Seven adapted skills** (attribution: mattpocock/skills, MIT): `grill` (one-question-per-turn
  plan stress-test), `to-spec` (conversation → docs/SPEC.md with confirmed seams + measurable
  criterion), `diagnose` (feedback-loop-first bug discipline, ships `hitl-loop.template.sh`),
  `tdd` (+`tests.md`/`mocking.md`; the executor's TDD manual; anti-patterns mirrored in the
  evaluator), `merge-conflicts` (intent-preserving resolution incl. the `/autopilot-parallel`
  integration case), `design-twice` (two genuinely different designs → ADR with the rejected
  alternative; applied by the planner on non-trivial phases), `glossary` (docs/GLOSSARY.md only;
  injected capped by the session-start hook). 18 skills total, 17 per-project.
- **A spec lifecycle across `grill` → `to-spec` → `roadmap` → `milestone`** (composition, one new
  stored bit). `docs/SPEC.md` gains `status:` frontmatter plus `## Open questions` and
  `## Test seams` sections. `grill` now writes each closed decision straight into its real spec
  section as it lands (vocabulary → the `glossary` skill in place); `to-spec` closes the spec —
  empties Open questions, distills the *settled* architectural notes into ADRs at close (via the
  `adr` skill, so a decision reversed mid-interview never leaves a stale ADR), writes the confirmed
  seams, and flags a pivot when the success criterion changed vs `git show HEAD:docs/SPEC.md`.
  `roadmap` gains an entry gate and an **amend-don't-regenerate** mode; `milestone` inserts +
  renumbers only when no ticked phase sits below, else appends with `Depends on: … Blocks: …`
  (phase numbers are stable IDs). **Only `grilling` is a stored, load-bearing state** — `roadmap`
  derives "ready" from content (measurable criterion + empty Open questions), so a stale label
  can't gate a bad spec into planning. Ticked phases are immutable — and, corrected here, *not*
  because `tick.sh` byte-compares the roadmap (it stores no prior copy): the real reasons are audit-
  trail integrity, not regressing a `- [x]`, and keeping STATE.md's "last ticked" pointer resolvable.
  No new skill; `tick.sh`/hooks/agents untouched.
- **An executable sandbox for unattended runs**: `sandbox/Dockerfile.autopilot` +
  `sandbox/run-autopilot-sandboxed.sh` — mounts only the repo, passes only `ANTHROPIC_API_KEY`,
  runs the headless loop with `--dangerously-skip-permissions` inside; refuses fail-closed on
  missing docker/key/scan-lib or secret-shaped files in the repo. `test-sandbox.sh` covers it.
- **`sync.sh --adopt-manifest` and `--restore <path>`**; install-smoke verifies the manifest.
- **`doctor.sh` team-repo warn**: >1 contributor with `LEAN_CHECKPOINT` not off (env or
  settings.json `env`) → advisory pointer to the new GUIDE "Working in a team repo" section.
  Checkpoint commits keep their stable `checkpoint:` prefix for filtering/squashing.
- **Evaluator fakery list** gains `tautological tests` and `implementation-coupled tests`
  (teach/grade symmetry with the `tdd` skill).
- **Session-start hook** injects `docs/GLOSSARY.md` (capped at 30 lines) when present.

### Changed
- `CLAUDE.md` slimmed 67→51 lines (Autonomy = 10 lines of operational rules); the detailed
  security narrative (gate integrity, scan window, /wrap-is-weaker) consolidated into GUIDE.md
  Parts 4–5 as the single source; README carries a ≤15-line summary.
- Dev plans and audits moved out of the shipped tree: `docs/dev/plans/`, `docs/dev/audits/`.
- `planner.md` applies design-it-twice to non-trivial phases ("Alternative considered:" line);
  `executor.md` follows the `tdd` skill; `roadmap`→`grill` and `unstick`↔`diagnose`
  cross-references.

### Removed
- **`Bash(curl *)`/`Bash(wget *)` permission denies** — a bash glob is not an egress boundary
  (python/node/nc/git-push all reach the network) and it broke daily curl work; the exfiltration
  boundary is the no-credentials sandbox, now shipped (see Added).
- **sync's four-tier classifier and all value-preserving merge machinery** (HIGH_STAKES_RE /
  agent `model:` / `paths:`-block surgical merges, the `unknown` tier): 575→292 lines of sync,
  875→283 of tests. A modified file is yours; you merge the diff by hand.

### Review note (dated)
- **TODO 2026-09-09 — autopilot.sh usage review.** `scripts/autopilot.sh` (683 lines) was
  deliberately NOT simplified in this release: its bulk is guarantees (watchdogs,
  integrity-checks, worktrees), not fat. The lean decision is about USE, not code: if by
  ~2026-09-09 the headless mode has been used fewer than 3 times, the right simplification is
  deleting it entirely in favor of in-session `/autopilot`.

## [2.4.0] — 2026-07-08

Autopilot child containment + supervised-phase approval — from the SessionLens headless dogfood —
bundled with the post-`v2.3.1` review-skill follow-ups. Cut from `master`; `VERSION` → `2.4.0`. No
existing tag is altered (the v2.3.x tags stay immutable — the coherence lesson from v2.3.1).

### Changed — skills
- Review skills **`scope-guard`** and **`explain-diff`** now declare an `allowed-tools` surface of
  read-only git (`git diff`/`status`/`log`, plus `git show` for explain-diff) and carry an explicit
  "read-only by contract" guardrail. They keep `disallowed-tools: Edit, Write, MultiEdit, NotebookEdit`
  (the file-editing tools stay removed) and are instructed to use the shell for inspection only.
- Corrected the `skills/README.md` "cannot modify code" claim to match reality: the review skills remove
  the file-editing tools and are held to a report-only contract, but retain read-only shell access (for
  `git diff`, tests, lint) — a contract, not an OS sandbox. (`allowed-tools` is permission pre-approval,
  not a hard restriction; `disallowed-tools` is what actually removes a tool.)
- **`mapme`** now diffs its regenerated `docs/ARCHITECTURE.md` against an existing one and confirms
  before overwriting, instead of silently clobbering a hand-authored doc.

### Fixed — headless autopilot child containment
- **`scripts/autopilot.sh` now contains its builder/evaluator children** instead of running them
  foreground with no timeout. A real headless dogfood (the SessionLens round) found a wedged
  `--dangerously-skip-permissions` run spawning ~9–13 concurrent `claude` processes that `AGENT_STOP`
  and `SIGTERM` could not stop (only `kill -9`), with an empty `autopilot.log`. Each child now runs
  BACKGROUNDED as its own process-group leader under a Bash-3.2 watchdog (macOS has no
  `timeout(1)`): the parent polls every `AUTOPILOT_POLL_INTERVAL` (default 5s) for a wall-clock
  timeout (`AUTOPILOT_CHILD_TIMEOUT`, default 20m), for `AGENT_STOP` **during** the child run (not
  just between iterations), and for loss of the run lock; a breach tree-kills the child
  (`TERM`→2s→`KILL`, depth-first `pgrep -P` + process-group kill) and **fails closed** if it survives
  `SIGKILL`. `INT`/`TERM` to the parent kill the child tree first; any watchdog abort sets
  `RUN_ABORTED`, which blocks the tick and joins the no-push guard (an aborted branch stays local even
  with `--pr`). The child's stdout is captured to the log, fixing the empty-`autopilot.log` symptom,
  and the resolved log path is printed at loop start. `/autopilot-parallel` does **not** inherit this
  containment yet and now carries a caution to prefer `/autopilot` or the headless script.

### Added — supervised phase approval
- **`Mode: supervised` phases are no longer un-tickable.** They previously hit `tick.sh` `exit 3`
  unconditionally with no approval path, so a roadmap containing one could never close via
  `close-milestone.sh`. `tick.sh` gains `--supervised-approved [--note "<why>"]`, which records an
  auditable, HEAD-bound approval in `.claude/.supervised-approval` (valid iff `title` == the heading
  **and** `run_id` == HEAD; stale/mismatched/malformed all fail closed). The override replaces **only**
  the supervised block — grade, evidence, secret, gate-config and high-stakes checks all run above it,
  so approval clears the supervised refusal and nothing else. `close-milestone.sh` now classifies the
  first open phase (supervised-awaiting-approval / unresolved-finding / plain-unfinished) so a
  supervised block is actionable, and the `milestone` skill Mode B documents the flow.

## [2.3.1] — 2026-07-07

Release-coherence + follow-up hardening from the post-`v2.3.0` audit. `v2.3.0` was tagged and pushed;
several behavioral fixes then landed on `master` **after** that tag while `VERSION` still read `2.3.0`,
so a tag-pinned checkout silently got a slightly older, less-hardened tree under the same version
string. This release reconciles that: `VERSION` → `2.3.1`, cut from current `master`, with the post-tag
work recorded below. The existing `v2.3.0` tag is left untouched (immutable — already published).

### Fixed
- **Headless autopilot gate integrity now also protects the four staged agent prompts.** `autopilot.sh`
  byte-compares `.claude/agents/{researcher,planner,executor,evaluator}.md` against the trusted launch
  checkout alongside the gate-control scripts, so a builder that rewrote the evaluator's grading
  contract (or any stage prompt) mid-phase forces supervised review instead of silently steering its
  own grade. (Was: only scripts/libs/allowlist were integrity-checked.)
- **`tick.sh` evidence-JSON validation hardened** to `jq -e 'type'` (some bundled `jq` treat `jq empty`
  as a no-op), and **resolvable non-ancestor `.phase-base` values** are now covered by the strict-
  ancestor guard + a regression test — a forged base that resolves to a real but unrelated commit is
  fail-closed, not just an empty/`==HEAD` base.
- **`install.sh` answers `-h`/`--help`** like every other operational script (prints usage, exits 0).
- **`/resume` surfaces whether the next open phase is loopable or supervised** (reads its `Mode:` line)
  so the operator picks `/autopilot` vs a supervised `/phase` correctly.

### Added — coverage
- **Full shipped-skill manifest checks.** `install-smoke.sh` now asserts every project skill installs
  with its `SKILL.md` (was: only `roadmap`), and `doctor.sh` validates the same manifest against a real
  installed tree (`.claude/skills/<name>/SKILL.md`) so a dropped/renamed skill is caught loudly instead
  of shipping silently. `test-doctor.sh` gains a regression case proving a dropped skill is detected.

### Changed — docs
- Corrected release-state documentation and ignored local maintainer scratch-note patterns
  (`*-MISSION-PROMPT.md`, `HANDOFF-*.md`, `REDTEAM-*.md`, `CHANGES-LAST-*.md`).
- Removed the stale `OWNERSHIP` reference in `install.sh`'s skill-copy comment (only `skills/README.md`
  exists at that level).
- Added "archived / superseded by v2.3.1" banners to the v2.3-era audit reports under `docs/audits/`
  whose release-state statements (unreleased / unpushed / origin at v2.2.0) were true when written and
  are no longer current. Their findings are preserved verbatim.

## [2.3.0] — 2026-07-07

Trust-boundary & maintenance hardening milestone closing the P1/P2 backlog from the v2.2 adversarial
audit (`AUDIT-JAIMITOS-OS-V2.2.md`) plus the stronger `.phase-base` forgery bypass surfaced in the
v2.2.1 re-audit. No new features, no guardrail weakening — every fix makes a failure mode fail closed /
route to manual review / force supervised, and each ships a regression test that fails on pre-fix code
and passes after. Released at the explicit human checkpoint: `VERSION` bumped to `2.3.0`, tagged
`v2.3.0`, merged to `master`, and pushed to origin (branch + annotated tag).

### Fixed — trust boundary
- **`.phase-base` forgery / forgeable orchestrator state (the centerpiece).** Under headless
  `autopilot.sh` the untrusted builder wrote `.claude/.phase-base` (via `/phase`) and both the evaluator
  and `tick.sh` read it verbatim with no validation — a forged `BASE=HEAD` emptied the `BASE..HEAD` scan
  window, hiding a high-stakes/secret commit (and even the C1 gate-config guard) from every gate, then
  auto-ticked and auto-pushed. `autopilot.sh` now derives the phase base in its OWN trusted shell
  (set-once-per-phase, preserved across NEEDS_WORK retries), overwrites `.claude/.phase-base` before the
  evaluator, and passes it to `tick.sh` via `TICK_BASE`; `tick.sh` uses the env base in preference to the
  file and strict-ancestor-validates either source (real commit, `!= HEAD`, ancestor of HEAD) — a forged
  base can no longer narrow or misdirect the scan.
- **Gate-control self-neutering under autopilot.** `tick.sh`/`_high-stakes.sh` run from the builder's
  worktree, so a builder could rewrite them (even `tick.sh` itself, which the C1 guard cannot cover) and
  the neutered gate would run. `autopilot.sh` now byte-compares every gate-control file against its
  version in the trusted launch checkout before running the gate; any drift (committed OR uncommitted)
  forces supervised review — no auto-tick, no push. `executor.md` also forbids writing the orchestrator's
  state + gate-control code (advisory, atop the mechanical enforcement).
- **`models.sh reset` false-success + `.tmp` debris on a missing role file (H2)**, and its detection/
  update/removal now scoped to the `---`…`---` frontmatter block so a stray body `model:` line is never
  read or rewritten (M3).

### Fixed — reliability / DX
- **`doctor.sh` blind spots (H3/M4/M11):** a manifest-based presence check catches a deleted
  `tick.sh`/`sync.sh`/`_test-cmd.sh` (was "All good"); `jq -e 'type'` catches a corrupt `settings.json`
  (`jq empty` is a no-op on some bundled jq); the `install.sh --force` remediation hint prints on any
  problem run. `doctor.sh` and `install.sh` now also detect an off-git-root / monorepo (subdir) install
  and report/refuse it clearly instead of a wall of false "missing" (H4; `install.sh --allow-subdir`
  overrides).
- **Test-ecosystem deadlock (M2):** `_test-cmd.sh` now resolves go/cargo/make (+mvn/gradle), and a
  genuinely-unknown stack gets a loud "set `LEAN_TEST_CMD`" instruction on stderr instead of a silent
  empty that deadlocked the tick gate.
- **`sync.sh` UX/safety (M5/M6/M7):** refuses a never-scaffolded project (run `install.sh` first); the
  mixed-merge prompt names the exact value preserved and states ONLY it survives; an unknown-tier drift
  (e.g. `settings.json`) shows an informational diff; enumeration is deterministically sorted.
- **CLI `--help` (M12):** every operational script has a safe `-h|--help`; `run-guard-tests.sh --help`
  no longer runs the whole battery.
- **Install-smoke coverage (M13):** checks the full shipped manifest and runs `doctor.sh` on the
  installed tree. **CI supply-chain (H7):** the actionlint fetch is pinned to a tagged release instead of
  an unpinned `main` `curl|bash`.

### Changed — docs
- README documents `sync.sh` (layout tree + a "Keeping a project up to date" subsection). README
  Security and `SECURITY.md` document the high-stakes path allowlist (an auditable escape hatch, not a
  bypass), the gate-control-edits-force-supervised rule, and the orchestrator-trusted `.phase-base` /
  gate-integrity model under headless `--dangerously-skip-permissions` — honestly stating what it does
  and does not protect against.
- Corrected the `test-evidence.sh` retry comment (M8): the any-green vote absorbs a flake for an
  IDEMPOTENT suite, but can mask a real first-attempt failure for a non-idempotent one. `tick.sh` heading
  matching hardened with `grep -e` + awk `ENVIRON` (option/escape-safe on unusual headings).

### Fixed — pre-tag audit cleanup (`AUDIT-JAIMITOS-OS-V2.3.md`)
- **`install.sh` no longer ships the toolkit's own `PLAN-*.md` dev/audit milestone plans into a target
  project** (M-Ship1) — they were meaningless inside a user's repo and contradicted install.sh's own
  header; `install-smoke.sh` now asserts none ship.
- **Corrected the `scripts/tick.sh` self-edit docs** (M-Docs1): README + `SECURITY.md` had claimed editing
  `scripts/tick.sh` inside a phase forces `tick.sh` exit 3. It does not — `tick.sh`'s in-gate check covers
  only `_high-stakes.sh` and the allowlist (a neutered `tick.sh` would run its own neutered check);
  `tick.sh` self-edits are caught one level up by headless `autopilot.sh`'s gate-control byte-integrity
  check. The docs now also record the manual `/wrap` path as the weaker, human-supervised path (run from a
  clean working tree; headless `autopilot.sh` is the hardened path for unattended operation).

### Known limitations / deferred
- **Root scratch docs** (`HANDOFF-*`, `REDTEAM-*`, `SESSIONLENS-*`) remain untracked at the repo root.
  Relocating or gitignoring them is deferred — they are the maintainer's untracked working notes, so
  moving them is a call to confirm explicitly, not something this milestone does unprompted.
- **`test-evidence.sh` was NOT renamed** to `record-evidence.sh`: it has many references (autopilot, the
  test suites, install-smoke, `doctor.sh`'s manifest, and the guard-runner drift-guard carve-out), so the
  rename is not "trivially updatable" and is deferred. Its header already states it is a producer, not a
  test suite.
- **`v2.0.0` was never tagged**, and the `v0.2.0` tag's `VERSION` content reads an older value — a
  historical tagging discrepancy recorded here for the record. No git history is rewritten; future
  releases should tag at each checkpoint.

## [2.2.1] — 2026-07-07

Surgical patch closing the trust-boundary findings from the v2.2.0 adversarial audit
(`AUDIT-JAIMITOS-OS-V2.2.md`). No new features, no redesign — every fix makes a failure mode
**fail safe / route to manual review / force supervised**, and each ships with a regression test
that reproduces the bug and proves it closed. Each fix was re-verified by an independent adversarial
reviewer.

### Fixed
- **High-stakes gate self-exemption (Critical).** A phase could disable its own high-stakes gate by
  editing `.claude/high-stakes-path-allowlist` (self-exempt) or `.claude/lib/_high-stakes.sh`
  (self-narrow `HIGH_STAKES_RE`) in the *same* commit `scripts/tick.sh` then reads — neither path
  matches `HIGH_STAKES_RE` itself, so the change was invisible to the keyword scan, and under
  `autopilot --pr` the phase auto-committed and pushed. `tick.sh` now exact-line-matches those two
  gate-config files in the phase diff and forces supervised review (exit 3), regardless of contents.
- **`sync.sh` silently truncated a multi-line `HIGH_STAKES_RE` (Critical).** The `_high-stakes.sh`
  mixed-merge treated `HIGH_STAKES_RE=` as a single physical line; a backslash-continued or
  quote-split value was truncated while reporting `merged`, corrupting the safety regex. The merge
  now rejects a trailing-backslash / unbalanced-quote shape and validates the merged file with
  `bash -n` before writing — either failure routes to manual review with the project file untouched.
- **`sync.sh` agent `model:` merge could destroy a file (Critical).** A stray body `model:` line, a
  frontmatter-less file, or unclosed frontmatter could cause the whole project agent file to be
  replaced while reporting success. `model:` is now only merged inside a well-formed `---`…`---`
  frontmatter block; anything else routes to manual review, byte-identical.
- **`sync.sh` `paths:` block dropped paths after an unindented comment (High).** A column-0 `#`
  comment inside a `rules/high-stakes.md` `paths:` block silently ended the block, dropping later
  paths. Blank, indented, and bare-comment lines now stay in the block; only a real top-level key
  ends it; a garbage line routes to manual review.
- **`test-high-stakes.sh` could not fail (High).** A block of content-suppression assertions
  incremented its failure counter inside a `(…)` subshell, so a real regression in that
  security-gate logic printed `✗` yet the suite exited 0. The block now runs at top level.
- **`test-test-cmd.sh` could not fail.** The same swallowed-counter bug, worse: all 15 resolver
  scenarios ran the assertion inside a subshell, so the entire suite always exited 0. Assertions now
  `return` their status and each scenario propagates it. (No latent resolver failure was hiding — the
  resolver was correct; the suite simply couldn't report one.) A re-scan confirmed no other
  `scripts/test-*.sh` has this pattern.

### Changed
- `scripts/test-sync.sh`: corrected the test-13 fixture, which set an **unquoted** `HIGH_STAKES_RE`
  with bare `(` `)` `|` — invalid bash that could never source in a real project (the gate would be
  dead). The new `bash -n` guard correctly refused it; the fixture is now single-quoted like every
  real `_high-stakes.sh`. Added regression tests for all six fixes above.

### Known limitations (tracked, out of scope for this patch)
- **`.claude/.phase-base` is trusted, not verified.** The high-stakes/secret scan runs over
  `${phase-base}..HEAD`; a builder with write access to `.claude/` (i.e. headless
  `--dangerously-skip-permissions`) can forge `.phase-base` to exclude a malicious commit and evade
  *both* the new gate-config guard and the original matcher. This is the same forgeable-orchestrator-
  state class as the audit's M1 and is the top hardening target for the next milestone.
- `merge_hs_lib`'s quote-parity shape check is syntax-blind: a valid single-line value with an
  apostrophe inside double quotes (`HIGH_STAKES_RE="it's…"`) is over-conservatively routed to manual
  review. This fails *safe* (a needless prompt, never data loss) and is left as-is deliberately.

## [2.2.0] — 2026-07-06

### Added
- **`scripts/sync.sh`** — lets an already-scaffolded project pull in later `jaimitos-os` toolkit
  fixes from a local checkout without clobbering its own customizations. `install.sh` only handles
  brand-new projects (skip-if-exists); sync is the update path for one that's already scaffolded.
  It enumerates every toolkit-shipped file and classifies each into one of four tiers: **overwrite**
  (toolkit-owned logic, no project values inside — diffed, confirmed, copied over), **never**
  (project-owned — `docs/`, `CLAUDE.md`, `SCAFFOLD.md`, `.gitignore` — always skipped), **mixed**
  (a toolkit-owned file with exactly one project-customized value inside: `_high-stakes.sh`'s
  `HIGH_STAKES_RE=` line, an agent's `model:` frontmatter line, or `rules/high-stakes.md`'s
  `paths:` block — a narrow, value-preserving merge keeps the toolkit's updated body with the
  project's value substituted back in verbatim, byte-for-byte even when it contains regex
  metacharacters; always prompts, never bypassed by `--yes`), and **unknown/malformed**
  (unclassified, e.g. `.claude/settings.json`, or a known-mixed file whose shape doesn't match what
  sync expects — always left for manual review, never guessed at or clobbered). Fails safe: nothing
  is written without an explicit confirmation and a shown diff (or, for a mixed merge, a diff of
  the proposed merge result); `--dry-run` previews the whole plan; a `cp` failure is tallied as
  FAILED rather than silently reported as updated. Drift is detected by diffing against a LOCAL
  toolkit checkout passed via `--toolkit <path>` (no shipped manifest yet); `.github/workflows/*`
  is never synced, and `.github/scripts/*.sh` only into a project that already opted into CI.
  Wired into `doctor.sh` (a small advisory pointing at `sync.sh --dry-run` when
  `.claude/.jaimitos-os-version` is present) and
  `.github/scripts/install-smoke.sh`.

## [2.1.0] — 2026-07-06

Per-stage model configuration (the `researcher`/`planner`/`executor`/`evaluator` subagents and the
`/models` command) plus a hardening milestone of five edge fixes surfaced by dogfooding the toolkit
across real builds.

### Added
- **Auditable high-stakes path allowlist** (`.claude/high-stakes-path-allowlist`) — a git-tracked,
  per-line, reason-required escape for exact-path false positives in the high-stakes gate's path
  matcher (e.g. an ADR file whose name merely contains "money"). Purely subtractive: the enforced
  `HIGH_STAKES_RE` and the content scanner are unchanged; only an exact path with a non-empty
  reason is cleared, and a bare/reasonless entry suppresses nothing. `doctor.sh` reports active
  entries so a suppression is never hidden.
- **`close-milestone.sh` surfaces open ownership gaps** — a non-fatal notice when `docs/STATE.md`
  has unresolved `## Ownership gaps` entries, so a skipped `teach-back` is visible at milestone
  close instead of accumulating silently. It never blocks the close.

### Changed
- **Closing a milestone (`close-milestone.sh`) + bumping `VERSION`/tagging is now its own explicit
  checkpoint**, never inferred from an ambiguous "go ahead"/"resume"/"continue" reply to an
  unrelated question (documented in `CLAUDE.md`, `GUIDE.md`, and the `milestone` skill's Mode B,
  which now pauses for a clear yes and reads any ownership-gaps notice aloud). Motivated by a real
  dogfooding incident where an ambiguous "resume" chained a phase-tick into a milestone close.
- **Documented that headless `scripts/autopilot.sh` currently assumes
  `--dangerously-skip-permissions`** (sandbox-only), and why a narrower scoped `permissions.allow`
  profile is not currently possible: `.claude/` is a Claude Code protected path whose writes are
  denied in every mode except bypass, and `/phase` writes its state files there.

### Fixed
- **`resolve_test_cmd()` no longer depends on `.claude/settings.json`'s `env` block reaching the
  Bash subprocess.** When `$LEAN_TEST_CMD` is empty it reads the (string-typed) value directly from
  `settings.json` via `jq`, closing a gap where a raw Bash-tool invocation got an empty var and
  silently fell back to a system `pytest` lacking a `uv`/`poetry` project's deps.
- **A genuinely-green phase can no longer fail to tick on a flaky one-shot test sample under
  `--pr`.** `scripts/test-evidence.sh` now retries-with-backoff before recording a red result, and
  `scripts/autopilot.sh` re-measures test evidence after the evaluator PASS (the measurement
  closest to the grading decision). `scripts/tick.sh`'s fail-closed contract is unchanged — a
  genuinely red suite is still refused.
- **`scripts/models.sh` could silently corrupt an agent's `model:` frontmatter line instead of
  rejecting an unsafe value.** The raw value was spliced directly into a `sed` replacement string
  and into `awk -v` — both treat certain characters specially: `&`/`/`/`\` have meaning inside a
  sed replacement, and POSIX `awk -v` escape-processes assignments, so a literal `\n`/`\b` in the
  input became a real newline/backspace byte written straight into the YAML frontmatter block. In
  every case the script still printed `"Updated:"` and exited 0. Found via a dedicated adversarial
  red-team test campaign fuzzing `models.sh` with sed/awk metacharacters — the original TDD suite
  never tried a value containing one. Fixed by escaping the value before it becomes sed
  replacement text and passing it to awk via `ENVIRON` instead of `-v` (not escape-processed);
  values now round-trip byte-for-byte regardless of content.
- **Two more silent-false-success paths in the same function**, found by the same campaign: a
  missing closing `---` silently no-op'd instead of refusing, and mutating a deleted role file
  printed an error to stderr but still exited 0 (occasionally leaving a stray `.tmp` file behind).
  Both now fail loudly before any write is attempted, via an up-front file-existence +
  well-formed-frontmatter check.
- A `chmod 444` role file lost its original permissions after a `models.sh` update (the temp-file
  swap reset to the process umask). The original mode is now preserved on both the insert and
  replace code paths.
- `.claude/commands/models.md` didn't mention the `CLAUDE_CODE_SUBAGENT_MODEL` override warning,
  and `models.sh`'s own usage header didn't document that a repeated key in one invocation
  resolves last-occurrence-wins (already the behavior, just undocumented) — both now stated
  explicitly.
- `planner.md`'s Constraints section read "src/tests/" (a single nested path) instead of the
  comma-separated "src/, tests/" convention used identically in `CLAUDE.md` and `executor.md`.
- `.claude/commands/phase.md`'s heading-matching rule could read as one run-on clause, risking a
  spurious "ambiguous, which one?" stop even when one candidate is an unambiguous exact match —
  now states explicitly that an exact full-line match is checked first and wins outright.
- `.github/scripts/install-smoke.sh` didn't check for `scripts/test-models.sh` alongside the other
  four new per-stage-model files, so a future install regression dropping just that file would
  only be caught by manual inspection.

  (New regression coverage added to `scripts/test-models.sh` for metacharacter round-tripping on
  both code paths, malformed/missing frontmatter delimiters, a deleted role file, and permission
  preservation — all previously undertested. Found via an exhaustive multi-agent adversarial test
  campaign — 197 designed tests across 10 specialized red-team agents — run against the
  already-shipped per-stage-model feature below; every gate this toolkit depends on — `tick.sh`,
  `record-grade.sh`, `test-evidence.sh`, the evaluator's grading contract, and the secret-scan and
  high-stakes gates — was independently re-confirmed byte-identical to before the feature, i.e.
  none of this touched or weakened them.)

### Added
- **`/phase`'s four stages (research/plan/execute/verify) now delegate to their own subagents**
  (`.claude/agents/researcher.md`, `planner.md`, `executor.md`, joining the existing
  `evaluator.md`), each independently pinnable to a specific model. `scripts/models.sh` is the
  new deterministic script that owns all mutation of each role's `model:` frontmatter field
  (the same mechanism `evaluator.md`'s `model: sonnet` already used) — `/models` is a thin
  command wrapper around it, and `setup-jaimitos-os` calls it once at project setup.
  `scripts/doctor.sh` reports current model configuration by delegating to `scripts/models.sh`.
  New tests: `scripts/test-models.sh` (mutation contract), `scripts/test-doctor.sh` additions,
  `.github/scripts/install-smoke.sh` additions.

### Fixed
- **`scripts/autopilot.sh` can now actually complete a phase headless against a real
  (non-stubbed) `claude` binary.** Found via dogfooding a full project through the whole
  stack, not synthetic testing (which mocks the `claude` binary and so never exercised
  the real permission system): without a TTY, the hardcoded `--permission-mode acceptEdits`
  cannot approve writes to `.claude/` (treated as a sensitive path) or Bash commands like
  the test suite — both were silently denied, so the builder could never write
  `.claude/.phase-ready`, and `scripts/tick.sh`'s own fail-closed check ("missing
  `.claude/.phase-base`") meant no phase could ever tick in a truly unattended run.
  Added `--dangerously-skip-permissions` (same flag name as the `claude` CLI's own) to
  switch both the builder and evaluator invocations to `bypassPermissions`, opt-in only,
  with a loud warning (SECURITY.md and the GUIDE now say explicitly: sandboxed container,
  no production credentials — same bar as any other unattended run). Also added a
  deterministic post-builder check (`.claude/.phase-ready` must exist after the builder
  exits) so a blocked builder stops the loop immediately with a clear cause and fix,
  instead of silently wasting an evaluator grading pass on a phase never attempted.
  (`scripts/test-autopilot-gates.sh` — 5 new tests: default flags never leak
  `--dangerously-skip-permissions`, the flag correctly propagates to both invocations,
  the warning prints, and a blocked-builder run is caught before the evaluator ever runs.)
- **High-stakes content-matching now catches web-framework `DELETE` route registration**
  (`@app.delete(`/`@router.delete(` decorators, `methods=[...,"DELETE",...]`,
  `.delete("path", ...)`) — found via the same dogfood run: a real `DELETE /admin/...`
  endpoint tripped neither `HIGH_STAKES_RE` (the file lived in an existing `api.py`, no
  "delete" in its own path) nor, until now, the content matcher, leaving `Mode: supervised`
  as the only protection for that phase. Still a backstop, not exhaustive — deliberately
  does NOT match a plain `.delete(some_id)` call with no string literal (an object's own
  method, not route registration), so it stays a "cite the specific pattern" gate, not a
  blanket ban on the word "delete". (`scripts/test-high-stakes.sh` — regression tests for
  both the new matches and the false-positive-avoidance case.)
- **`/phase` (no argument) documented for the case where it re-selects an already-built
  `Mode: supervised` phase indefinitely** instead of advancing — a real consequence of
  checkbox-driven selection combined with `tick.sh` correctly never auto-ticking a
  supervised phase's checkboxes (also found via dogfooding; not destructive, but
  undocumented friction). `.claude/commands/phase.md` now tells the builder to verify
  rather than rebuild in this case, and the root README's troubleshooting table tells a
  human operator to target the next phase explicitly (`/phase "## Phase N — ..."`).

### Added
- **`evaluator` now checks for specific ways a diff can fake "done."** Beyond the
  existing criteria-integrity and scope checks (steps 4–5, which guard the
  acceptance-criteria docs and diff scope), it now has a dedicated checklist for
  implementation-level shortcuts that can hide inside an otherwise-passing diff:
  weakened/skipped tests, swallowed errors, stub returns, comment-as-fix,
  happy-path-only handling, invented APIs, and mocking the subject under test.
  No automated test accompanies this — it's a prompt-level change to an
  LLM-graded rubric, and there is no mechanical way to assert it improves grading
  judgment; the frontmatter and PASS/NEEDS_WORK verdict contract `record-grade.sh`
  depends on are unchanged.

### Fixed
- **`close-milestone.sh` and `autopilot.sh` no longer mistake the `roadmap` skill's own
  legend line for an open task.** Every roadmap the `roadmap` skill generates permanently
  carries the line `` > `- [ ]` = todo, `- [x]` = done. ... `` near the top. A plain substring
  grep for `- [ ]` (or `- [x]`) matched *inside* that instructional text too, since it wasn't
  anchored to real list-item lines. Concretely this meant: `close-milestone.sh` could **never**
  successfully close a milestone generated the documented way (`grep -q '\- \[ \]'` always found
  a "match," always refusing with "open items remain"); and `autopilot.sh`'s own "roadmap has no
  open items — nothing to do" preflight and its in-loop "roadmap complete" check were equally
  fooled, never correctly recognizing a fully-ticked roadmap as done. Found via real usage
  (`/milestone` on a live project), not synthetic testing — the existing test fixtures never
  included the legend line, which is why it slipped through. Anchored all four call sites to
  `^[[:space:]]*- \[ \] ` (matching the pattern `session-start.sh` already used correctly).
  New regression tests in `test-close-milestone.sh` and `test-autopilot-gates.sh` use the real
  legend-line format so this can't silently regress. (`tick.sh` was already safe — its own
  open-item count is a before/after *differential*, not an absolute check, so the legend line's
  constant match cancels out.)

### Added
- **`ownership-nudge.sh` now flags quick fixes that happened outside an active roadmap phase.**
  `docs/STATE.md`'s prose is normally only touched by `/wrap`, `/phase`, or `tick.sh`'s auto-block —
  a tiny, no-ceremony fix prompted directly touches none of those, so STATE.md could silently go
  stale while `session-start.sh` kept re-injecting outdated "where we are" context. The hook now
  checks for `.claude/.phase-ready`'s absence (no phase in flight) alongside a real change, and
  nudges you to add a one-line STATE.md note if it matters — advisory only, never blocks, same
  ceremony-to-stakes rule as everywhere else. (`scripts/test-hooks.sh`)

### Fixed
- **`ownership-nudge.sh` no longer silently skips a merge-commit turn.** Its last-resort
  "files in the most recent commit" fallback (`git show --name-only HEAD`) returns empty by
  default for a clean merge commit (e.g. right after `/autopilot-parallel` integrates a phase
  branch), even though real work landed — so with a clean tree and no breadcrumb, neither the
  ownership nudge nor the STATE.md-drift nudge fired at all. Added a first-parent-diff fallback
  (`git diff --name-only HEAD^1 HEAD`) for exactly that case. Found via 20 adversarial tests run
  in parallel against the hook; confirmed with a real merge-commit repro.
- The STATE.md-drift nudge no longer fires when `docs/STATE.md` is itself the only file that
  changed this turn — telling someone to update the exact file they just updated was redundant.

## [2.0.0] — 2026-07-02 — Jaimitos OS rename + automation hardening

### Changed — BREAKING: renamed "the Lean Stack" to "Jaimitos OS"
- The scaffold directory `lean-stack/` is now `jaimitos-os/`; the shipped CI workflow is now
  `jaimitos-os-ci.yml`; the installer meta-skill directory is `skills/setup-jaimitos-os/`
  (trigger phrase: "set up jaimitos-os here"); the generated version-stamp file is now
  `.claude/.jaimitos-os-version`; `install.sh`'s `.gitignore` merge marker is now
  `# --- jaimitos-os control/secret ignores ---`.
- **Clean break, no compatibility shims.** A project that already installed the old `lean-stack`
  layout keeps working exactly as it is — nothing forces a re-install — but re-running
  `install.sh` on it will NOT recognize the old marker/version-stamp filenames, so treat a
  re-install on an old layout as a fresh install, not an in-place upgrade.
- **`LEAN_TEST_GATE` / `LEAN_TEST_CMD` / `LEAN_CHECKPOINT` env vars are UNCHANGED, deliberately.**
  These are a quieter, more load-bearing API (someone may already have them set in a shell profile
  or CI config) than a folder name, so renaming them wasn't worth the silent-breakage risk for a
  branding win.

Also includes a third hardening pass from a skeptical multi-agent automation audit, turning
prompt-only joints into code-enforced, tested ones, with one shared completion gate.

### Added — targeted phase selection & parallel execution
- **`/phase <heading>`** — optional argument to target a specific roadmap phase instead of always
  picking the first open one (backward compatible; bare `/phase` is unchanged). Refuses clearly on
  an ambiguous or zero-match heading rather than silently falling through to another phase.
- **`/autopilot-parallel`** — new command: builds named, user-asserted-independent phases
  concurrently in isolated git worktrees, then integrates/grades/ticks them one at a time through
  the same shared `scripts/tick.sh` gate — never a second completion path. Conflicts stop for
  explicit human direction rather than auto-resolving; a high-stakes phase in the batch stays local
  without blocking the rest of the batch. (`scripts/test-autopilot-parallel.sh`)

### Fixed — supervised-tag over-broadening & doc accuracy
- `CLAUDE.md`, `.claude/rules/high-stakes.md`, and the `roadmap` skill no longer treat "makes an
  external API call" alone as grounds for `Mode: supervised` — only external effects that MUTATE
  something outside our control (payments, emails, webhooks, deploys) do; a read-only/idempotent
  call is judged on its actual blast radius instead.
- **`/autopilot` now checks the next phase's `Mode:` line BEFORE building it**, not just before
  ticking — previously an unattended run could carry out a supervised phase's real work (including
  any live external effect it required) and only be blocked from *ticking* it afterward.
- README no longer claims `/autopilot` doesn't apply the high-stakes gate programmatically — it
  does, via the same shared `tick.sh`; `/phase` alone genuinely doesn't, since it never ticks at all.
- `skills/milestone` now defers to `skills/roadmap`'s phase-shape rules instead of restating a
  looser duplicate (it was only checking a `Done when:` line exists, not that it's measurable).

### Added — one shared completion gate
- **`scripts/tick.sh` is now the ONLY path that ticks the roadmap.** `/wrap`, `/autopilot`, and
  `scripts/autopilot.sh` all route through it — nothing marks a phase done by prose. It requires a
  recorded evaluator PASS, fresh green test evidence bound to the exact commit, a clean secret scan,
  and no high-stakes (path **or** content) changes, then updates the STATE auto-block. Fails closed,
  leaving `docs/ROADMAP.md` byte-identical on any refusal. (`scripts/test-tick.sh`)
- **`scripts/test-evidence.sh`** — authoritative test-evidence producer, run after the builder exits
  so `run_id` binds to the final HEAD (the Stop-hook gate raced commit-on-stop and is now advisory).
- **`scripts/record-grade.sh`** — single writer of the evaluator grade file (HEAD-bound; refuses
  non-PASS); shared by autopilot and the in-session tick path.
- **Deterministic STATE on every tick** — `docs/STATE.md` gets a machine-managed block (last ticked
  phase, next open phase + task) so it can no longer lag the roadmap. Model narrative is untouched.
- **`scripts/close-milestone.sh`** — gated milestone closure: refuses while any open item or
  unresolved `NEXT_FINDINGS.md` remains; no "proceed anyway" bypass. (`scripts/test-close-milestone.sh`)
- **Failure history** — resolved findings are archived to `docs/FAILURES.md` instead of deleted.
- **`doctor.sh --fix`** — safe, idempotent local repair (chmod, dirs, FAILURES.md); never touches
  the high-stakes fingerprint. (`scripts/test-doctor.sh`)

### Changed — broader, enforced guards
- **Content-level high-stakes detection** — `high_stakes_content_match` catches destructive
  operations (DROP/DELETE/TRUNCATE, `rm -rf`, force-push, `--no-verify`, `os.system`, `shell=True`,
  `eval(`) in benignly-named files; forces supervised review.
- **`Mode: supervised` is now ENFORCED** — `tick.sh` parses it and refuses to auto-tick such a
  phase (was advisory/unparsed).
- **Autopilot crash-safety** — a single-run lock (`.claude/.autopilot.lock`) blocks concurrent runs
  and reclaims a stale lock; an EXIT/INT/TERM trap releases it and reports (never auto-removes) an
  orphaned worktree.
- **Honesty** — "auto-maintained docs" reworded to "an evidence-gated, auto-ticked roadmap with
  auto-written state" (now actually true). Kill-switch match-all wiring is asserted by doctor + test.
- **Docs** — the README is the primary entry point; the former `GUIDE.md` and `LOOP-ENGINEERING.md`
  were merged into one comprehensive `jaimitos-os/toolkit-docs/GUIDE.md` (manual + loop-engineering
  theory), refreshed to match the shared `scripts/tick.sh` gate. `docs/ROADMAP.md` now matches the
  enforced `Mode: supervised` behavior in `scripts/tick.sh`.
- **SessionStart context is capped and stricter** — `NEXT_FINDINGS.md` is injected as the last
  60 lines with a file pointer, and roadmap extraction ignores blockquoted/example `- [ ]` text.

### Added — tests
Behavioral coverage for commit-on-stop, steer, format-on-edit, test-gate modes, SessionStart
roadmap extraction, and capped findings; a docs-invariant guard against prose ticking;
lint/helper tests (`next-adr.sh`, `lint-roadmap.sh`). A single shared runner
(`scripts/run-guard-tests.sh`) is the one behavioral-test list both CI workflows call. All wired into CI.

## [1.0.0] — 2026-06-30 — initial hardened release

First public release: a lean, project-neutral Claude Code operating system — an evidence-gated,
auto-ticked roadmap with auto-written state, deterministic hooks, an independent evaluator, two
autonomous loops (watchable + headless), path-scoped rules, and a pack of portable skills.
(Consolidates the same-day 1.0.0–1.0.3 hardening passes, each driven by an independent multi-agent audit.)

### Scaffold (`jaimitos-os/`)
- `CLAUDE.md` lean constitution; `docs/` source-of-truth set (SPEC, ROADMAP, STATE, ARCHITECTURE,
  decisions/, plans/).
- Commands `/resume`, `/wrap`, `/phase` (research → plan → TDD → self-check; never self-ticks), and
  `/autopilot N` (watchable in-session loop).
- `evaluator` subagent: fresh context, no edit tools, default-FAIL contract, anchored PASS/FAIL
  parsing, `.phase-base` criteria-integrity check — the sole gate.
- Hooks: `session-start` (state re-injection incl. NEXT_FINDINGS), `steer` (mid-run redirect),
  `kill-switch` (AGENT_STOP, honored inside worktrees), `format-on-edit` (format-only — no
  semantic autofixes), `test-gate` (opt-in), `commit-on-stop` (honest checkpoint), `ownership-nudge`.
- `scripts/autopilot.sh`: fresh-process headless loop with preflight, per-phase thrash cap, flexible
  count (`N`, `N-M`, `all`), **worktree isolation ON by default** (`--no-worktree` opts out), and
  script-as-sole-roadmap-ticker (only on an independent PASS).
- `scripts/doctor.sh` health check; `.claude/rules/high-stakes.md` path-scoped extra care.

### Enforcement (docs-promise → code-backed)
- **Shared guard libraries** (`.claude/lib/_secret-scan.sh`, `_high-stakes.sh`) sourced by both
  `commit-on-stop.sh` and `scripts/autopilot.sh` so the same guards run everywhere.
- **Content-aware secret scan** (AWS `AKIA`, PEM blocks, `sk-`/`ghp_`/`xox*`, Stripe `sk_live_`,
  Google `AIza…`, URL-embedded `user:password`); commit paths **fail closed** on a hit or a missing lib.
- **High-stakes gate in `autopilot.sh`:** a graded phase touching auth/money/migrations/etc. is never
  auto-ticked/committed/pushed — the loop stops for supervised review, and **stays local even with `--pr`**.
- **Evaluator-change cleanup:** the tree is snapshotted before grading and any file change *or commit*
  the evaluator makes is discarded before ticking — a grader can't edit code into passing.
- **Root CI** (`.github/workflows/ci.yml`) + install smoke test: shell syntax, `settings.json`
  validation, `install.sh` lint, shellcheck + actionlint, and the behavioral guard tests.

### Install & skills
- `install.sh`: idempotent, deterministic installer (copies scaffold + skills, chmods, runs doctor;
  `--force`, `--global-skills`, `--with-ci`). Ships toolkit docs by directory; merges (not clobbers)
  an existing `.gitignore`; `setup-jaimitos-os` is global/installer-only, not copied per-project.
- Skills pack: workflow (`roadmap`, `milestone`, `adr`, `ship-check`, `scope-guard`, `explain-diff`,
  `unstick` — the three review skills are report-only via `disallowed-tools`), ownership (`teach-back`,
  `mapme`, `quizme`), and the `setup-jaimitos-os` meta-skill.

### Fixed
- Final-phase crash in `tick_phase` (`grep -c … || echo 0` produced `"0\n0"`).
- `.phase-base` overwrite on NEEDS_WORK retry, which corrupted the evaluator's whole-phase diff.

### Security & honesty
- Read-tool deny rules are a real boundary; Bash deny rules are documented as best-effort
  defense-in-depth (use sandboxing + `permission_mode: default` for the real shell boundary).
- Mode-scoped claims: the deterministic sole-ticker / eval-discard / secret-scan / high-stakes-no-push
  guarantees hold in the **headless** loop; the in-session `/autopilot` and `/wrap` have an independent
  grader but rely on the same shared tick gate. Single-sourced the skills catalog and hooks table.
