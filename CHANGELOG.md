# Changelog

All notable changes to this project are documented here.
Format loosely follows [Keep a Changelog](https://keepachangelog.com/); this project
uses [Semantic Versioning](https://semver.org/).

## [Unreleased]

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
