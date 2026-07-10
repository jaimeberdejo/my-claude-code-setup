# Changelog

All notable changes to this project are documented here.
Format loosely follows [Keep a Changelog](https://keepachangelog.com/); this project
uses [Semantic Versioning](https://semver.org/).

## [Unreleased]

_Nothing yet._

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
