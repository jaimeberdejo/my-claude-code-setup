# Changelog

All notable changes to this project are documented here.
Format loosely follows [Keep a Changelog](https://keepachangelog.com/); this project
uses [Semantic Versioning](https://semver.org/).

## [Unreleased] — automation hardening

Third hardening pass from a skeptical multi-agent automation audit. Turns prompt-only joints
into code-enforced, tested ones, with one shared completion gate. No breaking changes.

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
- **Lean-docs prune** — `GUIDE.md` and `LOOP-ENGINEERING.md` were merged into the README and
  deleted to remove parallel manuals. `docs/ROADMAP.md` now matches the enforced `Mode:
  supervised` behavior in `scripts/tick.sh`.
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

### Scaffold (`lean-stack/`)
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
  an existing `.gitignore`; `setup-lean-stack` is global/installer-only, not copied per-project.
- Skills pack: workflow (`roadmap`, `milestone`, `adr`, `ship-check`, `scope-guard`, `explain-diff`,
  `unstick` — the three review skills are report-only via `disallowed-tools`), ownership (`teach-back`,
  `mapme`, `quizme`), and the `setup-lean-stack` meta-skill.

### Fixed
- Final-phase crash in `tick_phase` (`grep -c … || echo 0` produced `"0\n0"`).
- `.phase-base` overwrite on NEEDS_WORK retry, which corrupted the evaluator's whole-phase diff.

### Security & honesty
- Read-tool deny rules are a real boundary; Bash deny rules are documented as best-effort
  defense-in-depth (use sandboxing + `permission_mode: default` for the real shell boundary).
- Mode-scoped claims: the deterministic sole-ticker / eval-discard / secret-scan / high-stakes-no-push
  guarantees hold in the **headless** loop; the in-session `/autopilot` and `/wrap` have an independent
  grader but rely on the same shared tick gate. Single-sourced the skills catalog and hooks table.
