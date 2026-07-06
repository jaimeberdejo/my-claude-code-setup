# Changelog

All notable changes to this project are documented here.
Format loosely follows [Keep a Changelog](https://keepachangelog.com/); this project
uses [Semantic Versioning](https://semver.org/).

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
