# Adversarial Quality Audit — jaimitos-os v2.2.0

**Date:** 2026-07-06
**Scope:** structure, agents, scripts, commands, sync mechanism, per-stage model config, v2.1.0 hardening, automation workflow, docs, lean-ness, DX, safety boundaries.
**Method:** 16 parallel subagents, each working in disposable scratch git repos, running the *real* scripts (not paraphrasing them), plus first-hand verification by the lead auditor of the safety-critical core (`tick.sh`, `_high-stakes.sh`, `models.sh`, `sync.sh`). Every claim below is backed by command output, a byte-diff, a git fact, or a quoted line. Findings that were reproduced end-to-end are marked **[reproduced]**.

> **Layout note (verified):** the toolkit is dogfooded as a subdirectory `jaimitos-os/` of the wrapper git repo `Claude_SETUP`. Paths like `scripts/sync.sh` are relative to `jaimitos-os/`. Root docs (`README.md`, `CHANGELOG.md`, `SECURITY.md`, `install.sh`, `VERSION`) and `skills/` live at the repo root. This nesting matters for one finding (H4).

---

## 1. Executive summary

jaimitos-os v2.2.0 is a genuinely well-engineered lean automation scaffold whose **safety-critical core is strong and, in most places, provably correct**: the roadmap-completion gate (`tick.sh`) binds evidence to an exact commit and fails closed on every path; `models.sh` and `sync.sh` go out of their way to avoid the shell-metacharacter injection class that broke an earlier version; the secret scanner does exactly what its docs claim and no more; the shell is genuinely Bash-3.2-clean; and the engineering discipline is visible in the data (10 of 11 `fix:` commits ship their regression test in the *same commit*).

**But the two flagship features of this release cycle each contain a way to silently defeat their own core promise**, and both were confirmed by running the real code:

1. **The high-stakes gate — the one safety control standing between headless autopilot and auth/payments/migration code — can be self-exempted.** A phase that touches a genuine high-stakes path *and* adds a matching line to `.claude/high-stakes-path-allowlist` (or narrows `HIGH_STAKES_RE` itself) in the same commit ticks green (`tick: ✓ ticked, exit 0`) and, under `autopilot --pr`, auto-commits + `git push` + opens a PR — directly contradicting the documented guarantee that high-stakes work is *never* auto-pushed. **[reproduced end-to-end]**

2. **The v2.2.0 sync mechanism — whose entire value proposition is "safely preserve your customization" — silently corrupts or destroys files on realistic customized inputs**, while printing `merged: success`: a multi-line `HIGH_STAKES_RE` is truncated (breaking the safety regex); a frontmatter-less agent file has 100% of its content replaced with the toolkit's default; an unindented comment inside a `paths:` block silently drops later paths. **[reproduced with byte-diffs]**

Neither defect touches the *common happy path* — a fresh install at the git root is complete and doctor-clean, the shipped single-line `HIGH_STAKES_RE` and `models.sh`-set frontmatter merge correctly, and a real v2.0-era→current upgrade was verified to preserve custom values byte-for-byte. The problems live in exactly the adversarial / realistic-edge inputs a serious dogfooding audit is supposed to find.

**Net:** v2.2.0 is a real improvement over v2.0.0, the lean philosophy largely survived, and most of the hardening is excellent. It is **not yet safe to lean on unattended for high-stakes work, or to run `sync.sh` against a heavily-customized real project**, until the three Critical items are fixed. All three have small, well-scoped fixes.

---

## 2. Overall rating

### **7.0 / 10**

Excellent engineering foundations and honesty, dragged down by three high-severity edge-case failures located — unfortunately — in precisely the two features this release added (autopilot high-stakes gating, sync mixed-merge). Fix the three Criticals and the top Highs and this is a legitimate 8.5–9.

---

## 3. Ratings by area

| Area | Score | One-line justification |
|---|---:|---|
| Structure | 8/10 | Clean "prose orchestrates, script executes" everywhere; no logic duplicated across commands/skills/scripts/agents; two `.claude` dirs & two CI workflows are intentional, not drift. Loses points for root scratch-file clutter. |
| Lean-ness | 7/10 | Shipped scaffold is genuinely small (59 files / ~7.5k LOC; agents avg 52 lines). Loses points for shipping the 15-file self-test suite into every project and repo-root cruft. |
| Clarity | 8/10 | Layered docs (README → PRACTICE → SCAFFOLD → GUIDE), extensively commented scripts explaining *why*. |
| Automation reliability | 6/10 | tick/evidence/autopilot core is robust **[reproduced]**; but the high-stakes gate is bypassable (C1) and a non-pytest/npm ecosystem deadlocks the gate (H-tier). |
| Claude Code usability | 8/10 | Commands/agents are clean prompt-contracts; exact-match phase selection is correctly specified. |
| Agent design | 8/10 | 4 stages, non-overlapping, evaluator has a real tool restriction (no Write/Edit) + a script-level backstop that discards its edits. Not over-architected. |
| Script quality | 8/10 | Bash-3.2-clean, metachar-safe, fail-closed, shellcheck-clean at `-S warning`; a few missing `--` end-of-option guards. |
| Test coverage | 7.5/10 | Genuinely adversarial suites running the real scripts; strong fix→test discipline. Gaps: doctor's core diagnostics, sync mixed-merge adversarial values, one silent-pass bug. |
| Sync mechanism | 5/10 | Solves drift and is metachar-safe for single-line values, but two Critical data-loss/gate-corruption bugs and one High path-narrowing bug on realistic inputs. |
| Security / permissions | 7/10 | No command injection found; secret scanner honest; deny-list solid; `--dangerously-skip-permissions` documented candidly. Undercut by the self-exemptable gate and forgeable evidence in bypass mode. |
| Documentation accuracy | 8/10 | Unusually accurate — no "doc says X, code does Y" found; all counts match. Two real completeness gaps (sync & allowlist absent from top-level/security docs). |
| Developer experience | 7/10 | Good error text and fail-safe recovery; hurt by `--help` inconsistency, a doctor remediation-hint gap, and undocumented sync bootstrapping. |
| Maintainability | 8/10 | Single-source guard runner with a self-enforcing drift guard; fix-with-test discipline; clear module boundaries. |
| Scalability | 7/10 | Fine for its intended one-repo-per-project scope; off-git-root/monorepo installs break silently (H-tier). |

---

## 4. What works well (verified, not assumed)

- **`tick.sh` is a genuinely strong gate.** Both evidence files (`.phase-grade`, `.tick-evidence.json`) must carry `run_id == HEAD` (stale evidence rejected); `.phase-base` is required or it fails closed (no scan-window narrowing); high-stakes path/content and `Mode: supervised` all force exit 3; ROADMAP is left byte-identical on every refuse path (structural, not just tested). **[reproduced: stale/missing/malformed/red evidence and moved-HEAD all fail closed]**
- **Evidence retry + re-measure work.** A flaky red→green result is absorbed; a genuinely-red suite exhausts retries and records `passed:false`; evaluator-PASS-then-re-measure-FAIL correctly blocks the tick. `cleanup_eval_changes()` discards any file the evaluator edits and hard-resets any commit it sneaks in — **all four scenarios reproduced via full `autopilot.sh` runs.**
- **Concurrency is real.** Two truly-concurrent `autopilot.sh` processes → the atomic `noclobber` lock let exactly one proceed; stale-pid reclaim confirmed. **[reproduced]**
- **`models.sh` injection hardening holds.** Values with `&`, `/`, `\`, quotes, `$(...)`, backticks, `.*`, `|` round-trip byte-for-byte with no execution; real embedded newlines/CR are rejected; path traversal is structurally impossible (fixed `case` → 4 hardcoded paths); duplicate-key files are refused. **[reproduced with `od -c`]**
- **`sync.sh` is metachar-safe and fail-safe for single-line values.** Merges build into a temp file, show a diff, require confirmation (mixed is never bypassed by `--yes`), and use awk-`ENVIRON` / `sed -n 'N,Mp'` rather than `sed s///`. Single-physical-line values (incl. `& \ ' " (a|b) $ \1\2`, 5000 chars) round-trip byte-identical; `cp` failures are counted and the version stamp is withheld on failure; `--dry-run` is fully truthful; **zero `jq` dependency** (verified by hiding `jq`). **[reproduced]**
- **Secret scanner is honest.** 9/9 real secret shapes caught; the three false-negative classes it misses are exactly the ones `SECURITY.md` admits to. No overclaiming.
- **Shell quality is high.** Bash-3.2-clean across all 37 scripts (zero `declare -A`/`mapfile`/`${var^^}`/`&>>`/`${arr[-1]}`); BSD/GNU tool fallbacks throughout; `set -uo pipefail` used deliberately (with a documented reason for avoiding `set -e`); spaced paths handled; shellcheck-clean at `-S warning`.
- **Checkpoint discipline is strong on the doc layer.** Milestone-close is mechanically **unreachable** from any autopilot/headless path (`tick.sh` only prints a suggestion; `autopilot.sh` never references `close-milestone`), and the "own checkpoint, never inferred from resume/continue/go-ahead" rule is stated near-verbatim across CLAUDE.md, the milestone skill, GUIDE, and wrap.md, explicitly covering the hardest edge case.
- **Documentation is unusually accurate.** No "doc claims X, code does Y" was found; all cited counts (11 skill dirs, 6 commands, 4 agents, 7 hooks, 3 libs, 14 guard suites) match the filesystem; `--dangerously-skip-permissions` is described candidly and consistently across five surfaces.
- **Fix-with-test discipline.** 10 of 11 `fix:` commits bundle a regression test in the same commit (the 11th is a doc typo).

---

## 5. What does not work

- **The high-stakes gate can be defeated in the same phase it's supposed to guard** (C1) — the headline failure.
- **`sync.sh` mixed-merge corrupts/destroys realistically-customized files while reporting success** (C2, C3, H1).
- **`models.sh reset` falsely reports success and leaves debris** when an agent file is missing (H2).
- **`doctor.sh` reports full health with `tick.sh` and `sync.sh` deleted** (H3) — the health check has blind spots for the tool's own load-bearing files.
- **A non-pytest/npm project (Go/Rust/Ruby/Java) deadlocks the tick gate** unless `LEAN_TEST_CMD` is set (M-tier, but a hard wall). **[reproduced with a passing Go repo]**
- **`run-guard-tests.sh --help` silently runs the entire 14-suite battery** instead of showing help.
- **Off-git-root / monorepo installs silently break every script** with misleading errors (H4).

---

## 6. What is fragile

- **The evidence-file trust boundary in headless mode.** `.phase-grade` is two lines of plaintext with no cryptographic binding to a real evaluator run; in `--dangerously-skip-permissions` mode (which headless *requires*) the builder session could write a forged `verdict=PASS` + fake green evidence and skip the evaluator. `executor.md` never explicitly forbids writing these files. Every *non-adversarial* path is solid; the fragility is specifically the "builder is compromised/prompt-injected in bypass mode" case.
- **`sync.sh`'s mixed-merge shape assumptions.** It assumes each preserved value is exactly one physical line with well-formed surroundings; realistic deviations (wrapped regex, stray body `model:`, unindented comment) break it.
- **`tick.sh` awk `-v` and `grep` without `--`.** `awk -v ph="$heading"` (POSIX escape-processing) and `grep -qxF "$heading"` (flag-like heading) both misbehave on unusual headings — they fail *closed* (no mis-tick), but produce misleading output and are inconsistent with the project's own documented fixes elsewhere.
- **Retry-then-accept for non-idempotent test suites** can manufacture a false green — the code comment overclaims that it "never" does. **[reproduced]**

---

## 7. What is over-engineered

Very little — this is a lean codebase. Minor notes:

- **Four autopilot surfaces** (`/phase`, `/autopilot N`, `scripts/autopilot.sh`, `/autopilot-parallel`) is more concept-surface than a newcomer needs, though it's already well-tamed by a "least→most robust" table in GUIDE and is *not* duplicated logic (all route through one procedure + one tick gate).
- **The 4-stage `/phase` pipeline is unconditional** (plan→execute→verify always run, even for a 5-line change); the escape hatch ("skip the phase system for tiny work") lives only in GUIDE, not cross-referenced from `phase.md`. Not over-engineered per se, but the ceremony floor is higher than the "match ceremony to stakes" philosophy implies.
- **`test-docs-invariants.sh`** guards prose by literal substring match — brittle, and not really a behavioral test.

---

## 8. What is under-tested

- **`test-doctor.sh` is the weakest suite relative to its subject.** It covers only the `--fix` mechanics and *discards doctor's report text* (`>/dev/null`), so doctor's core "detect broken config / missing files" function is essentially unverified — which is exactly why H3 (false clean bill of health) exists with no test to catch it.
- **`test-sync.sh` mixed-merge cases aren't adversarial enough** — zero coverage for multi-line `HIGH_STAKES_RE`, agent-`model:` frontmatter-boundedness, or unindented-comment path narrowing (i.e. no test for C2/C3/H1).
- **The high-stakes self-exemption (C1) has zero test coverage** — no test in `test-tick.sh`/`test-autopilot-gates.sh` plants an allowlist/lib change alongside a sensitive-path change.
- **`test-high-stakes.sh` has a silent-pass bug** (H5) — a whole block of security-gate assertions can't actually fail CI.
- **The re-measure-after-PASS feature has no dedicated regression test** (both suites pin `LEAN_TEST_CMD=true`).
- **`test-test-cmd.sh`** doesn't cover uv+poetry-both, jq-missing, or non-string `LEAN_TEST_CMD` (the behavior is correct — just untested).

---

## 9. What is missing

- **README coverage of `sync.sh`** — the entire v2.2.0 feature is absent from the project's own "master map" (triple-confirmed).
- **Security-doc coverage of the high-stakes path allowlist** — a gate-narrowing mechanism absent from README Security / SECURITY.md / GUIDE Part 4.
- **A `--help` convention** across `scripts/*.sh` (only `doctor.sh` has one).
- **A documented sync-bootstrap path** for pre-2.2 projects (sync.sh doesn't exist there yet).
- **A `v2.0.0` git tag** (documented breaking release, never tagged; `v0.2.0`'s own VERSION content is `1.0.3`).
- **Orphan detection in sync** (renamed/removed toolkit files linger in projects forever).
- **A test that asserts doctor actually reports the things it's supposed to catch.**

---

## 10. Specific bugs / regressions found

Grouped; severities per the audit scale. "Blocks release?" = blocks *confident* reliance on the named feature.

### Critical

**C1 — High-stakes gate self-exemption (autopilot supervision bypass). [reproduced end-to-end]**
- Files: `.claude/lib/_high-stakes.sh` (`_high_stakes_allowlisted` L43-62, `high_stakes_match` L68-82); `scripts/tick.sh` L120 (sources the lib from the live worktree), L133-138 (path gate); `scripts/autopilot.sh` L409, L428-449.
- Evidence: a disposable repo committing one phase that modifies `payments/charge.py` **and** appends `payments/charge.py: reviewed and safe` to `.claude/high-stakes-path-allowlist` in the *same commit*, with a valid PASS grade + fresh green evidence, run through the real `tick.sh`:
  ```
  tick: ✓ ticked '## Phase 1 — Ship payments refactor' (1 item(s))   # exit 0
  ```
  Expected exit 3 (supervised, not ticked). A second PoC narrowing `HIGH_STAKES_RE` in `_high-stakes.sh` in the same commit produces the same tick. The lead auditor independently confirmed at the library level that an allowlist self-entry suppresses the gate, that exact-match still holds (`src/pay` does **not** suppress `src/payments.py`), and that the reason requirement holds. Critically, `.claude/high-stakes-path-allowlist` and `.claude/lib/_high-stakes.sh` **do not themselves match `HIGH_STAKES_RE`**, so editing them is invisible to the gate.
- Why it matters: in `autopilot.sh --pr` headless mode, `HS_BLOCKED` stays 0 → auto-commit + `git push` + `gh pr create`, contradicting the in-code guarantee (`autopilot.sh:427-429`) that high-stakes work is *never* auto-pushed. There is no human reading the diff at tick time in the documented overnight-loop use case.
- Fix: in `tick.sh`, if `.claude/high-stakes-path-allowlist` **or** `.claude/lib/_high-stakes.sh` appears in the phase's `$CHANGED` range, force exit 3 unconditionally. Add regression tests for both PoCs. (Simple, and consistent with the existing "fail toward supervised" philosophy.)
- Blocks release: **Yes**, for any reliance on unattended autopilot with high-stakes-eligible code.

**C2 — sync mixed-merge silently truncates a multi-line `HIGH_STAKES_RE`, corrupting the safety gate. [reproduced by sourcing the result]**
- Files: `scripts/sync.sh` `hs_line_count` (196-200), `merge_hs_lib` (202-220).
- Evidence: both treat `HIGH_STAKES_RE=` as one physical line (`grep -cE '^HIGH_STAKES_RE='`). A backslash-continued or a single-quoted-multi-line value → merge reports `merged: success` but drops the continuation. Sourcing before/after: intended `[foobar]` → actual `[foo]`; the single-quote variant leaves the quote open, swallows following comment lines, and ends with `HIGH_STAKES_RE` **empty** (plus `_high-stakes.sh: line 27: ride: command not found`). The shipped default value is a 150+ char single-quoted string — a natural thing for a user to wrap.
- Fix: `bash -n "$outfile"` before writing (`_high-stakes.sh` is bash); or detect a trailing unescaped `\` / odd quote count on the captured line → route to manual review.
- Blocks release: **Yes**, for `sync.sh` on any project that wrapped its regex.

**C3 — sync agent-`model:` merge destroys the entire project file on a malformed/frontmatter-less shape, reports success. [reproduced with `cmp`]**
- Files: `scripts/sync.sh` `model_line_count` (223-227), `merge_agent_model` (235-271); `has_wellformed_frontmatter` (229-233) is only consulted in the `pn==1 && tn==0` branch.
- Evidence, all reported `merged: success`: (a) a stray `model:` line in the markdown *body* is misread as the customization and spliced into the toolkit frontmatter, project body discarded; (b) a **frontmatter-less** project file with a coincidental `model:` line → **100% of the project's content replaced** with the toolkit's canned agent — total silent data loss on a shape that is unambiguously not the toolkit's, violating the documented fail-safe ("unrecognized/malformed shape in either copy → manual review, untouched"); (c) unclosed frontmatter is accepted and merged.
- Fix: bound `model:` detection to the `---`…`---` delimiters (as the `paths:` shape already does), for **all** branches; route to manual review if either copy lacks a well-formed delimiter pair.
- Blocks release: **Yes**, for `sync.sh` on hand-edited agent files.

### High

**H1 — Unindented comment inside a `paths:` block silently narrows the high-stakes path list. [reproduced, `grep late-path → 0`]**
- File: `scripts/sync.sh` `paths_block_bounds` (281-303) — `break`s on any unindented non-blank line, including a column-0 `# comment` between path items → later paths dropped. This is the *same bug class* already fixed for blank lines (commit `446150c` / test 25), left open for comments.
- Fix: only `break` on a real top-level key (`^[A-Za-z_][A-Za-z0-9_-]*:`); treat blank/indented/bare-comment lines as continuation.
- Blocks release: borderline Critical (silently weakens a guardrail); **Yes** for sync on customized `high-stakes.md`.

**H2 — `models.sh reset` false-success + debris on a missing agent file. [reproduced]**
- Files: `scripts/models.sh` `remove_model` (116-119), `reset` call sites (144-146).
- Evidence: `rm .claude/agents/researcher.md; bash scripts/models.sh reset` → prints `Reset to shipped defaults` + **exit 0**, with a raw `grep: No such file` error and a stray `researcher.md.tmp` left behind. `remove_model` lacks the existence check + error propagation its sibling `set_model` gained in commit `14572dc` ("Fix silent frontmatter corruption and false-success") — the same bug class recurring in the path the fix didn't touch.
- Fix: give `remove_model` the same existence check + error propagation; add `|| exit 1` to the three reset call sites; regression-test through `reset`.
- Blocks release: Yes for a "no false-success" claim.

**H3 — `doctor.sh` reports full health with `tick.sh` + `sync.sh` deleted. [reproduced]**
- File: `scripts/doctor.sh:45` (hardcoded scaffold-file list) and `:124` (hardcoded lib list).
- Evidence: `rm scripts/sync.sh scripts/tick.sh .claude/lib/_test-cmd.sh docs/ARCHITECTURE.md; bash scripts/doctor.sh` → **exit 0, "All good."** The single ticking gate and the headline sync feature absent = clean bill of health. Also silently misses close-milestone/lint-roadmap/next-adr/record-grade/run-guard-tests.
- Fix: iterate the generic `scripts/*.sh` / `.claude/lib/*.sh` globs already used for the exec-bit and syntax checks, instead of a hand-maintained name list.
- Blocks release: Yes if doctor is relied on as an onboarding/release gate.

**H4 — Off-git-root / monorepo install silently breaks everything with misleading errors, undocumented. [reproduced]**
- Files: `doctor.sh`, `tick.sh`, `sync.sh`, `autopilot.sh`, `models.sh`, `close-milestone.sh`, `record-grade.sh`, `next-adr.sh`, `test-evidence.sh` — all open with `cd "$(git rev-parse --show-toplevel …)"`.
- Evidence: install into a subdirectory of a git repo → install's auto-doctor prints **28 false "✗ missing"**; `models.sh exec=opus` (where the file genuinely exists) prints `role file '.claude/agents/executor.md' not found`. Zero docs mention "git root"/"monorepo"/"subdirectory". `test-hooks.sh` already avoids this exact trap ("git-toplevel is NOT reliable here").
- Fix: resolve the scaffold root script-relatively (like `test-hooks.sh`), or have `install.sh` refuse/warn when `TARGET != $(git rev-parse --show-toplevel)`.
- Blocks release: No for the documented git-root install; Yes for monorepo/subdir users. (SA rated Critical; downgraded here because the primary documented path works and there's no data corruption.)

**H5 — `test-high-stakes.sh` silent-pass: a security-gate regression can't fail CI. [reproduced]**
- File: `scripts/test-high-stakes.sh:125-137` — `FAILS` is incremented inside a bare `(...)` subshell (SC2030/2031), so its increment is lost. Breaking the per-line suppression case prints `✗ … WRONGLY suppressed` yet the script prints `All high-stakes detection tests passed.` and **exits 0**; CI gates on exit code.
- Fix: wrap each assertion `( … ) || FAILS=$((FAILS+1))` (the pattern already used correctly at L69-73 in the same file).
- Blocks release: Yes as a CI-trust issue for a security control.

**H6 — `sync.sh` undocumented in README (the whole v2.2.0 release). [triple-confirmed]**
- `grep -c sync README.md` → 0. Missing from the layout tree, Commands table, Health & maintenance, and Troubleshooting. Fix: add a `sync.sh` line + a short "Keeping a project up to date" subsection.
- Blocks release: No, but should be fixed before calling v2.2.0 "done."

**H7 — Unpinned `curl | bash` in the repo's own CI (supply-chain). [confirmed]**
- File: `.github/workflows/ci.yml:43` fetches+executes actionlint from `main` unpinned on every `pull_request`. The *shipped* `jaimitos-os-ci.yml` is clean (not affected). Fix: pin a tag + verify a checksum. Blocks release: No (repo CI, not the artifact), but fix soon.

### Medium (high-value subset; ~18 total)

- **M1 — Forgeable evidence in headless bypass mode.** `.phase-grade`/`.tick-evidence.json` are plaintext with no binding to a real evaluator process; `executor.md` never forbids writing them. In `--dangerously-skip-permissions` (headless-required) a builder can fabricate a PASS. Fix: name the prohibition in `executor.md`; ideally a harder binding. (SA3/SA7.)
- **M2 — Tick-gate deadlock for non-pytest/npm ecosystems. [reproduced with a passing Go repo]** `resolve_test_cmd` only knows uv/poetry/pytest/npm → `passed:null` → tick needs `no_tests_ok=1`, but the evaluator is forbidden from emitting `NO_TESTS_OK` when tests exist → permanent refusal unless `LEAN_TEST_CMD` is set. GUIDE:847 undersells it as "optional." Fix: detect `go.mod`/`Cargo.toml`/`Gemfile`/`pom.xml`/`Makefile` → loud "set LEAN_TEST_CMD" warning + upgrade the doc.
- **M3 — `models.sh` update path isn't frontmatter-scoped.** A body line starting with `model:` gets rewritten instead of the real frontmatter; reports "Updated" but the pin is never applied. (Not present in the shipped 4 agents.) Fix: scope to the `---`…`---` region.
- **M4 — `doctor.sh`'s `jq empty` (no `-e`) is a no-op on macOS's bundled jq → corrupt `settings.json` reported "valid JSON." [reproduced]** Adjacent checks already use `-e`. Fix: add `-e`.
- **M5 — sync agent-merge preserves *only* the `model:` line;** description/tools/body are taken wholesale from the toolkit while the prompt says "preserving your customized value?" [reproduced] This is by design (distinct from C3's total-destruction bug) but the UI implies more. Fix: clarify the prompt / detect "extra" diffs → manual review.
- **M6 — `.claude/settings.json` is `unknown` tier** (weakest), never shows a diff — PLAN-v2.2's own top merge candidate demoted. Fix: show diffs for `unknown`/`never` tiers (informational).
- **M7 — sync against a never-scaffolded project → silently broken pseudo-install** (adds scripts/hooks, skips CLAUDE.md/docs/settings.json). Fix: detect missing `settings.json` → warn "run install.sh first."
- **M8 — Retry manufactures a false green for non-idempotent test commands. [reproduced]** Fix: scope the code comment / add a doc note.
- **M9 — `tick.sh` has no clean-working-tree check;** secret/high-stakes scan covers only the committed range. Safe under autopilot (`cleanup_eval_changes`), but `/wrap` has no equivalent. Fix: `git status --porcelain` check inside tick.sh.
- **M10 — High-stakes exit-3 messages never mention the allowlist escape hatch;** the allowlist is undocumented in all security-facing narrative docs (README/SECURITY.md/GUIDE Part 4). Fix: one line in the refuse message + a paragraph in the security docs.
- **M11 — `doctor.sh` remediation hint (`install.sh --force`) only prints behind `--fix`,** not on the plain run install.sh auto-invokes. Fix: print unconditionally on any missing-file ✗.
- **M12 — `--help` footgun:** `lint-roadmap.sh`/`next-adr.sh` exit 0 silently ignoring it, and `run-guard-tests.sh --help` **runs the full 14-suite battery.** Fix: standard `-h|--help` case everywhere.
- **M13 — `install-smoke.sh` checks a sample, not the manifest** (misses `evaluator.md`, `phase.md`/`resume.md`/`wrap.md`/`autopilot.md`, 9/10 skills, `tick.sh`, `test-sync.sh`, 13/15 test files, all docs; never runs doctor on the installed tree). Mitigated by install's generic copy, but a regression tripwire gap.
- **M14 — Stale precedence comment in `test-gate.sh:12-15`** describes the pre-fix 3-step resolution, omitting uv/poetry + settings.json fallback. Fix: delete the duplicated list, point to `_test-cmd.sh`.
- Plus: no technical scope-guard on the executor (norm + retroactive evaluator only); `LEAN_TEST_CMD` eval'd from git-tracked `settings.json` not in SECURITY.md's threat model; `phase.md` lacks the all-ticked STOP that `autopilot.md` has.

### Low (~15; representative)

Root scratch-file clutter (`HANDOFF-*`, `REDTEAM-*`, `SESSIONLENS-*` untracked & un-gitignored; `PLAN-v2.2` stale "kickoff" banner); no `v2.0.0` tag / `v0.2.0` VERSION mismatch; `tick.sh` `grep -qxF "$heading"` leaks grep usage on a `-`-leading heading (add `--`); `tick.sh` uses `awk -v ph=` instead of `ENVIRON`; `format-on-edit.sh`/`close-milestone.sh --name` missing `--`/path-sanitization; `show_all` column misalignment for `research:`; sync confirmation-prompt order non-deterministic (unsorted `find`); no orphan detection; never-tier template drift invisible; `install-smoke.sh` second tempdir not trapped; GUIDE grammar leftover ("an four … subagents"); `test-evidence.sh` `run_id="HEAD"` leak in a zero-commit repo (latent, not exploitable); close-milestone ownership NOTE under-informative; `is_valid_value` allows a leading `"` (unterminated-quote YAML).

---

## 11. Files to rewrite / simplify / split / rename / remove

- **`scripts/sync.sh`** — *harden, don't rewrite.* The 3 merge functions need shape-validation before write (C2/C3/H1). The architecture (temp-file → diff → confirm, awk-ENVIRON) is sound; the bugs are missing guards, not a bad design.
- **`scripts/doctor.sh`** — replace the two hardcoded file lists (L45, L124) with globs (H3); add `-e` to the jq check (M4); print the remediation hint unconditionally (M11).
- **`scripts/models.sh`** — fix `remove_model` (H2); scope the update path to frontmatter (M3).
- **`scripts/test-doctor.sh`** — rewrite to assert doctor's *report text* flags missing/broken things (currently near-tautological).
- **`scripts/test-high-stakes.sh`** — fix the subshell-swallowed `FAILS` (H5).
- **Rename:** `scripts/test-evidence.sh` → `record-evidence.sh` (it's a producer, not a suite; the naming collision forces a carve-out in the guard runner).
- **Remove / relocate:** root scratch docs (`HANDOFF-MODELCOSTGUARD-TESTING.md`, `REDTEAM-PER-STAGE-MODELS-REPORT.md`, `SESSIONLENS-MISSION-PROMPT.md`) into a gitignored dir; archive `PLAN-v2.2-toolkit-sync.md` now that it shipped.
- **Consider splitting:** `scripts/` into `scripts/` (10 operational) + `scripts/tests/` (15 self-tests) to cut the fresh-install listing from 25 to ~10 — but batch this with a release already touching sync's tier classifier and install-smoke.
- **Do NOT rewrite:** `tick.sh`, `_high-stakes.sh` matcher core, `_secret-scan.sh`, the hooks, `install.sh`, `autopilot.sh`'s `cleanup_eval_changes`/lock — these are exemplary.

---

## 12. Prioritized fix plan

### P0 — must fix before relying on the release
1. **C1** — `tick.sh`: treat an edit to `.claude/high-stakes-path-allowlist` or `.claude/lib/_high-stakes.sh` within the phase diff as high-stakes → exit 3; regression-test both PoCs.
2. **C2** — `sync.sh`: `bash -n` the merged `_high-stakes.sh` and/or reject trailing `\`/odd-quote-count lines → manual review.
3. **C3** — `sync.sh`: bound `model:` merge to frontmatter delimiters in all branches; manual-review any file lacking a well-formed `---`…`---` pair.
4. **H1** — `sync.sh`: `paths_block_bounds` should only `break` on a real top-level key.
5. **H5** — `test-high-stakes.sh`: fix the subshell-swallowed `FAILS` so the security-gate test can fail.
6. Add regression tests for C1/C2/C3/H1 (the mixed-merge adversarial values + the self-exemption).

### P1 — should fix soon
7. **H2** `models.sh reset` false-success. 8. **H3** doctor glob-based checks. 9. **H4** off-git-root detection/warning + docs. 10. **H6** document `sync.sh` in README. 11. **M1** forbid evidence-file writes in `executor.md`. 12. **M2** ecosystem detection + loud LEAN_TEST_CMD warning. 13. **M4** doctor `jq -e`. 14. **M10** allowlist in refuse message + security docs. 15. **M12** standard `--help` (and stop `run-guard-tests.sh --help` from running the battery). 16. **M13** expand install-smoke; add `test-sync.sh`/`evaluator.md`. 17. **H7** pin the actionlint fetch.

### P2 — polish
Rename `test-evidence.sh`; scope the retry "never false green" comment (M8); `tick.sh` `grep --`/awk `ENVIRON`; sort sync's prompt order; remove root scratch files; tag `v2.0.0`; fix GUIDE grammar; column alignment; under-informative close notice; `is_valid_value` leading-quote guard.

---

## 13. Final verdict

### **GOOD** — with a hard asterisk.

The foundations are very good and the honesty is exemplary; but two Critical defects sit in the exact two features this release exists to deliver (autopilot high-stakes gating and sync mixed-merge), and both were reproduced by running the real code. Until P0 is done, treat v2.2.0 as **"good for supervised, single-repo use; not yet trustworthy for unattended high-stakes autopilot or for `sync.sh` on a heavily-customized project."** With P0 closed (all small, well-scoped fixes) this is a very good — near-excellent — toolkit.

---

## Top 10 findings

*(10 real issues found; more exist, these are the highest-severity.)*

| # | Sev | Title | File(s) | Blocks release? |
|---|---|---|---|---|
| 1 | Critical | High-stakes gate self-exemption → autopilot auto-pushes high-stakes work | `_high-stakes.sh`, `tick.sh:120,133`, `autopilot.sh:428` | **Yes** (autopilot) |
| 2 | Critical | sync truncates multi-line `HIGH_STAKES_RE`, corrupts the safety gate, reports success | `sync.sh:196-220` | **Yes** (sync) |
| 3 | Critical | sync agent-`model:` merge destroys the whole project file on frontmatter-less shape | `sync.sh:223-271` | **Yes** (sync) |
| 4 | High | Unindented comment in `paths:` silently narrows the high-stakes path list | `sync.sh:281-303` | **Yes** (sync) |
| 5 | High | `models.sh reset` false-success + `.tmp` debris on missing agent file | `models.sh:116-119,144-146` | Yes (no-false-success claim) |
| 6 | High | `doctor.sh` reports "All good" with `tick.sh`+`sync.sh` deleted | `doctor.sh:45,124` | Yes (if doctor is the gate) |
| 7 | High | `test-high-stakes.sh` silent-pass — security-gate regression can't fail CI | `test-high-stakes.sh:125-137` | Yes (CI trust) |
| 8 | High | Off-git-root/monorepo install silently breaks all scripts, misleading errors, undocumented | all `cd $(git rev-parse …)` scripts | Yes (monorepo users) |
| 9 | High | `sync.sh` (the whole release) undocumented in README | `README.md` | No |
| 10 | Med-High | Forgeable evidence + no executor prohibition → false PASS in headless bypass mode | `tick.sh:92-97`, `executor.md` | Partial (headless) |

Each finding's evidence, repro, and fix are in §10.

---

## Direct answers

1. **Is v2.2.0 actually better than v2.0.0?** Yes. Per-stage models, the auditable allowlist, evidence retry/re-measure, and sync are real improvements, and the fix-with-test discipline is excellent. Caveat: sync also *introduced* two Criticals, so it's "better with new sharp edges," not strictly safer.
2. **Did the new features preserve the lean philosophy?** Mostly yes. The shipped scaffold is still ~59 files, no logic is duplicated across surfaces, and CI/skills/tests are opt-in. Lean-ness slips only in shipping the 15-file self-test suite into every project and in repo-root clutter — not in the feature design.
3. **Are the new agents useful or over-architected?** Useful, not over-architected. Four narrowly-scoped stages (~52 lines each), the evaluator has a real tool restriction *and* a script backstop that discards its edits. The only cost is an unconditional ceremony floor for tiny phases.
4. **Is `/phase` more reliable or just more complex?** More reliable on the mechanical axis (independent re-measurement, strict verdict parsing that can't be misread as PASS, evaluator-edit discard — all reproduced) and modestly more complex. The residual risk is the semantic "does this satisfy Done-when" judgment (one LLM, single vendor) and the forgeable-evidence gap in bypass mode.
5. **Is `/models` safe enough?** The *mutation* engine is safe (injection-hardened, no allowlist, fail-safe on corrupt files — verified). Two bugs remain: `reset` false-success on a missing file (H2) and an un-scoped update path (M3). Safe after H2/M3.
6. **Is the high-stakes allowlist safe enough?** Its *matching* is safe (exact-path, reason-required, subtractive, fail-safe — all reproduced). Its *trust model is not* under headless autopilot: it can be self-added in the same phase to defeat the gate (C1). Not safe enough for unattended high-stakes use until C1 is fixed.
7. **Is the env-independent test resolver correct?** Yes — 25 conditions tested, 0 wrong picks, fails safe everywhere (env > settings.json fallback, jq type-guard, graceful degrade). Two caveats: it deadlocks the tick gate for unsupported ecosystems without `LEAN_TEST_CMD` (M2), and a stale comment in `test-gate.sh` misdescribes precedence (M14).
8. **Is evidence/tick/autopilot more trustworthy?** Yes, materially — evidence is bound to the exact HEAD, retry/re-measure and evaluator-change discard and the concurrency lock all reproduced. Residual: retry can false-green a *non-idempotent* suite (M8); no working-tree scan in tick itself (M9); forgeable evidence in bypass mode (M1).
9. **Is headless autopilot documented honestly?** Yes — `--dangerously-skip-permissions` is described candidly and consistently across five surfaces (never framed as safe). The one honesty gap is that the "high-stakes is never auto-pushed" guarantee is defeatable via C1, and the allowlist's role as a gate-narrowing escape hatch isn't in the security docs (M10).
10. **Is `sync.sh` reliable enough to use on real projects?** For the common case (fresh-ish scaffold, single-line values, model-frontmatter set by `models.sh`) — yes, verified. For a heavily-customized project — **no, not yet**: C2/C3/H1 can silently corrupt or destroy exactly the customized files it's meant to preserve. Reliable after P0.
11. **Does sync preserve project customization correctly?** For the three named single-line values in well-formed shapes — yes, byte-for-byte (verified). It does **not** preserve anything *outside* those values (agent tools/description/body are replaced — M5), and it *corrupts/destroys* them on multi-line/malformed/stray-content shapes (C2/C3/H1). So: narrowly correct, broadly not.
12. **Are the docs up to date?** Unusually accurate where they exist (no code/doc contradiction; all counts match). Incomplete in two real ways: `sync.sh` is absent from README (H6) and the allowlist is absent from all security-facing docs (M10). No stale "v2.0.0" claims of substance.
13. **Are the tests broad enough?** Broad and genuinely adversarial for most surfaces, with strong fix→test discipline — but with real holes exactly where the Criticals live: doctor's core diagnostics, sync's mixed-merge adversarial values, the self-exemption scenario, and a silent-pass bug in the high-stakes suite.
14. **What should be fixed before v2.3.0?** All of P0 (C1, C2, C3, H1, H5 + their tests), then the P1 set led by H2/H3/H4 and the README/allowlist doc gaps.
15. **What should absolutely NOT be changed because it's already good?** `tick.sh`'s fail-closed evidence-binding gate; `_high-stakes.sh`'s matcher core (exact-path allowlist + reason enforcement + fail-safe); `_secret-scan.sh`; `models.sh`'s injection-hardening; `autopilot.sh`'s `cleanup_eval_changes` + atomic lock; the awk-ENVIRON/`sed -n` metachar-safe substitution technique; the single-source `run-guard-tests.sh` with its self-enforcing drift guard; the Bash-3.2 discipline; and the fix-with-test-in-the-same-commit habit.

---

*Audit performed by 16 independent adversarial subagents + lead synthesis. Scratch artifacts and per-agent evidence retained under the session scratchpad. Where a subagent's severity differed from the scale in this report, the discrepancy is noted inline (e.g. H4 was rated Critical by its agent; downgraded here because the documented install path works and no data is corrupted).*
