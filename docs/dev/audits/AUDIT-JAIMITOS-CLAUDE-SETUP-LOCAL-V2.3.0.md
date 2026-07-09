# Audit — jaimitos-claude-setup / jaimitos-os v2.3.0 (LOCAL working tree)

> **⚠ Archived audit — superseded by v2.3.1 (2026-07-07).** This snapshot audited v2.3.0; post-release
> hardening and the release-coherence reconciliation (tag vs `master` drift) shipped as **v2.3.1**.
> Preserved for the record.

**Auditor:** Claude (release-level adversarial audit)
**Date:** 2026-07-07
**Scope:** the local folder `/Users/jaimeberdejosanchez/projects/Claude_SETUP` exactly as it sits on disk — local git state, local tags, local files. GitHub was not treated as authoritative and was not cloned.
**Method:** first-hand execution (guard suite, install-smoke, fresh install, mutation testing, live trust-boundary repros, shellcheck) + file-by-file code inspection. Every claim below is backed by a command, a file:line, or a byte comparison I ran myself.

---

## 0. Audit coverage & honesty note (read this first)

Per the execution-discipline rule, here is exactly what was **executed** vs **code-inspected only** vs **NOT RUN** — nothing is fabricated.

**Executed first-hand (real command output):**
- Local state: `git status/branch/log/tag/ls-remote/rev-list`.
- Full guard suite `run-guard-tests.sh` (exit 0) + all 15 individual `test-*.sh` suites.
- `install-smoke.sh` (exit 0) + a real fresh `install.sh` into a scratch git repo (manifest inspected).
- `shellcheck -S warning` over every `.sh` (0 findings) + `bash -n` over every `.sh` (0 failures).
- Mutation testing on 7 files (see §13).
- Live trust-boundary repros: forged/divergent `.phase-base`, high-stakes allowlist prefix/substring/bare/empty-reason attacks, `models.sh` metacharacter + body-decoy injection.
- Secret scan of the whole tree + git history.

**Code-inspected only (read, not executed end-to-end):** the four `/phase` agents driven through a live `claude` process; the skills run against a live model; the full sync mixed-merge metacharacter matrix *driven live* (the sync test suite was executed and is green, and the merge code was read line-by-line, but I did not hand-run every one of the ~20 adversarial merge values through `sync.sh` live).

**NOT RUN:** anything requiring the `claude` CLI to actually build/grade a phase (no live autopilot loop, no live `/phase`); a read-only/`--global-skills` install against a throwaway `$HOME`; a read-only-target install. **Reason:** six parallel sub-agents I dispatched to cover the exhaustive matrices (sync injection, installer edge matrix, skills execution, commands/hooks, docs, phase-lifecycle) all terminated on an **account session limit** mid-run and returned no findings. I completed the core of each of their areas myself; I did not reproduce every exhaustive permutation they were briefed for. Where that leaves a residual gap I say so in the relevant section.

This does **not** affect the P0 floor — state, shipping safety, the completion gate, secret/high-stakes gating, and test integrity were all executed first-hand.

---

## 1. Executive summary

This is an unusually well-engineered, security-serious Claude Code toolkit. The completion gate (`scripts/tick.sh`) and the headless orchestrator (`scripts/autopilot.sh`) implement a genuine, layered, fail-closed trust boundary between an untrusted builder and the state that marks work "done" — and it holds up under direct attack. Documentation is honest about its own limits (a rarity: it explicitly says what the gate *cannot* protect). Tests are broad (15 suites), pass, and are mutation-capable. Code quality is high (zero shellcheck warnings at `-S warning`).

I found **no Critical and no High severity issues.** The release is coherent and safe. What remains is one **Medium** test-coverage gap (a working guard that no test would catch if removed), and a handful of **Low/Info** polish items (install.sh lacks `--help`, one stale CHANGELOG sentence, untracked maintainer scratch files in the working tree).

**Overall rating: 9.0 / 10 — very good, release-ready.** Safe to use, and safe to recommend publicly after the ~15-minute Low-severity polish in §15.

One thing that is **stale in my own memory, not the repo:** a prior note said v2.3.0 was "held (VERSION/tag/push held)". The repo disproves it — `VERSION=2.3.0`, annotated tag `v2.3.0` exists locally **and on origin**, `origin/master == HEAD`. The release is fully cut and pushed. (I am correcting that memory.)

---

## 2. Local repo state verification

| Check | Result | Evidence |
|---|---|---|
| Folder audited | `/Users/jaimeberdejosanchez/projects/Claude_SETUP` | `pwd` |
| Branch | `master` | `git branch --show-current` |
| Working tree | clean of tracked changes; 5 untracked scratch docs + `.DS_Store` (gitignored) | `git status --short` |
| Unpushed commits | none | `git rev-list --left-right --count origin/master...HEAD` → `0	0` |
| `VERSION` | `2.3.0` | `cat VERSION` |
| CHANGELOG v2.3.0 | present, dated `## [2.3.0] — 2026-07-07` | `CHANGELOG.md:7` |
| Local tag `v2.3.0` | exists → `cc92445` (`chore(release): v2.3.0`) | `git rev-list -n1 v2.3.0` |
| Tag on origin | yes, annotated → `cc92445` | `git ls-remote --tags origin` → `refs/tags/v2.3.0` |
| Commits after tag | 1: `3e48cf9` merge into master | `git log v2.3.0..HEAD` |
| Stale "release held" notes in shipped docs | none (one maintainer instruction in CONTRIBUTING is correct) | grep, §12 |
| Secrets in tracked files or history | none real (only `AKIAIOSFODNN7EXAMPLE` AWS **doc example** in scanner fixtures) | §11 |

**Verdict:** local state is coherent and matches a released v2.3.0. The tag sits on the release commit `cc92445`; HEAD is the merge commit that brought it into `master` — a normal git-flow shape, not drift.

**One real inconsistency (Low):** `CHANGELOG.md` line ~13 says *"push held as a separate checkpoint."* That is now false — both `master` and the `v2.3.0` tag are on `origin`. Cosmetic, but it's a factual statement in a shipped doc.

---

## 3. Overall rating: **9.0 / 10**

Docked one full point almost entirely for the Medium test-gap plus the accumulation of Low polish items and the honest coverage caveats in §0 — not for any behavioral defect found.

---

## 4. Ratings by area

| Area | Score | One-line justification |
|---|---|---|
| Functionality | 9.0 | Everything executed works end-to-end; no silent no-ops found. |
| Structure / architecture | 9.0 | Clean split: wrapper repo / installable scaffold / skills / CI; deterministic shell vs LLM-instruction boundary is explicit. |
| Leanness | 8.5 | Lean runtime; some maintainer clutter in the working tree; README intentionally thorough (owner preference — correctly kept). |
| Security | 9.5 | Layered fail-closed trust boundary that survives direct attack; residual limits are inherent and **disclosed**. |
| Agents | 8.5 | researcher + evaluator are tool-sandboxed; planner + executor are convention-bounded (honestly stated) with tick.sh as the real backstop. |
| Skills | 9.0 | Report-only skills enforce `disallowed-tools`; mutating skills scoped to purpose. |
| Commands | 8.5 | Accurate, thin wrappers over audited scripts; `/resume` is a 3-line pointer. |
| Hooks | 9.5 | All fail-safe (jq fallbacks, `command -v` guards, git guards, loop guards); correct event wiring. |
| Automations / workflows | 9.5 | The autopilot trust model is the crown jewel — see §6/§11. |
| Documentation | 9.0 | Honest to a fault about limits; one stale CHANGELOG sentence. |
| Error handling / resilience | 9.0 | Fail-closed is the default everywhere; unresolvable base/range → refuse. |
| Performance / efficiency | 9.0 | session-start caps injected context; format-on-edit runs outside the context window. |
| Maintainability / extensibility | 8.5 | Some duplicated truth (`HIGH_STAKES_RE` in lib vs the advisory rule doc; gate-control file list hand-maintained). |
| Consistency | 9.0 | Uniform style/exit codes; `install.sh` missing `--help` is the lone break. |
| Dependencies / integrations | 9.0 | git/jq/bash/claude/gh; each missing dep fails loudly; CI actionlint fetch is pinned. |
| Testing / coverage | 8.5 | 15 green suites, mutation-capable; one uncovered guard (§13). |
| State / idempotency | 9.0 | State files gitignored; re-runs idempotent; forged state rejected. |
| Observability / debugging | 9.0 | Refusal messages name the reason and the remedy; autopilot logs each stage. |
| Discoverability / onboarding | 8.5 | Strong README + SCAFFOLD + doctor; `/resume` thinness is a minor snag. |
| Portability | 9.0 | Bash-3.2-safe, spaces-in-paths handled, macOS/Linux `md5`/`md5sum` fallback. |
| Code quality | 9.5 | `shellcheck -S warning` clean; comments explain *why*, not *what*. |
| Release readiness | 9.0 | Ships clean; state coherent; only Low polish before public. |

---

## 5. File-by-file inventory (97 files) with classification

**Root — metadata / installer (load-bearing for the wrapper repo):**
- `install.sh` — installer (deterministic copy). Load-bearing. Ships nothing of itself.
- `VERSION` (`2.3.0`), `README.md`, `CHANGELOG.md`, `SECURITY.md`, `CONTRIBUTING.md`, `LICENSE`, `.gitignore`, `.editorconfig` — repo metadata/docs. Not shipped into targets.
- `.github/scripts/install-smoke.sh`, `.github/workflows/ci.yml` — CI for the wrapper repo.
- `.claude/` (root) — the wrapper repo dogfooding jaimitos-os on itself (`.tick-evidence.json`, `scheduled_tasks.lock`, `worktrees/`). Maintainer state, gitignored.

**Root — maintainer-only docs (TRACKED, not shipped):**
- `AUDIT-JAIMITOS-OS-V2.2.md`, `PLAN-v2.2-toolkit-sync.md`, `PRACTICE-PROJECT.md` — maintainer/dev docs. Acceptable in a dev repo; not copied by install.

**Root — maintainer scratch (UNTRACKED, not shipped) — see Low finding L4:**
- `AUDIT-JAIMITOS-OS-V2.3.md`, `CHANGES-LAST-2-DAYS.md`, `HANDOFF-MODELCOSTGUARD-TESTING.md`, `REDTEAM-PER-STAGE-MODELS-REPORT.md`, `SESSIONLENS-MISSION-PROMPT.md`, `.DS_Store`. Clutter; no real secrets found (§11).

**Scaffold `jaimitos-os/` (the installable payload):**
- `CLAUDE.md` (template), `SCAFFOLD.md` (ships as the scaffold note — never becomes a README), `.gitignore`.
- `PLAN-v2.2.1-audit-p0-fixes.md`, `PLAN-v2.3.0-trust-maintenance-hardening.md` — maintainer plans, **excluded from install** by the `PLAN-*.md` rule (verified §8). Tracked in the dev repo only.
- `docs/` — `SPEC.md`, `ROADMAP.md`, `STATE.md`, `ARCHITECTURE.md`, `decisions/_TEMPLATE.md`, `plans/.gitkeep`. Templates. Shipped.
- `toolkit-docs/GUIDE.md` — large user guide, **intentionally excluded from install** (`toolkit-docs/*` rule). Info F7.
- `.claude/agents/{researcher,planner,executor,evaluator}.md` — staged-agent definitions. Shipped.
- `.claude/commands/{resume,phase,wrap,autopilot,autopilot-parallel,models}.md` — slash commands. Shipped.
- `.claude/hooks/{session-start,steer,kill-switch,format-on-edit,test-gate,commit-on-stop,ownership-nudge}.sh` — hooks. Shipped, chmod +x.
- `.claude/lib/{_high-stakes,_secret-scan,_test-cmd}.sh` — shared guard libs. Shipped.
- `.claude/rules/high-stakes.md` — advisory high-stakes rule. Shipped.
- `.claude/settings.json` — permissions.deny + hook wiring. Shipped.
- `.claude/high-stakes-path-allowlist` — reviewable allowlist (ships empty). Shipped.
- `.github/workflows/jaimitos-os-ci.yml` — opt-in CI (`--with-ci`).
- `scripts/` — 11 operational scripts (`autopilot, tick, test-evidence, record-grade, models, sync, doctor, close-milestone, next-adr, lint-roadmap, run-guard-tests`) + 13 `test-*.sh`. Shipped.

**Skills `skills/`:**
- `README.md` — catalog, **not shipped** (`find -mindepth 2` skips it).
- 11 skills; `setup-jaimitos-os/` is the meta/installer skill (**not copied per-project**, only via `--global-skills`); the other 10 ship into `.claude/skills/<name>/`.

**Orphans / dead / misplaced:** none found. Every file has a clear role. The only "wrong-place" candidates are the untracked root scratch docs (L4).

---

## 6. What works well (preserve these)

1. **The completion gate (`tick.sh`) is a real gate, not theater.** It flips `- [ ]`→`- [x]` only on: exact full-line heading match (`grep -qxF`), an evaluator PASS grade bound to HEAD (`run_id==HEAD`), fresh green test evidence bound to HEAD, a clean secret scan, and no high-stakes path/content. Every failure path leaves ROADMAP byte-identical. (`tick.sh:78-233`)
2. **The base-scan-window cannot be narrowed.** Both `tick.sh` and `secret_scan_diff` validate the base is a resolvable commit, `!= HEAD`, and a genuine ancestor of HEAD — fail-closed on any violation. In headless mode the base is re-derived in the orchestrator's trusted shell and passed via `TICK_BASE`, never trusting the builder-writable `.phase-base`. (`tick.sh:133-150`, `autopilot.sh:268-330`)
3. **`gate_control_intact()` is the standout.** Before trusting any headless tick, the orchestrator byte-compares **all 7 gate-control files** — `tick.sh`, `_high-stakes.sh`, `_secret-scan.sh`, `test-evidence.sh`, `record-grade.sh`, `_test-cmd.sh`, the allowlist — to their blobs at the trusted launch commit `START_REF`. A builder that neuters any gate file in its worktree is caught even though tick.sh itself runs from that worktree. (`autopilot.sh:288-305, 457-461`)
4. **Evaluator independence is enforced three ways:** no Edit/Write tools (`evaluator.md` frontmatter), autopilot discards any file change or commit it makes (`cleanup_eval_changes`, `autopilot.sh:231-262`), and the verdict is parsed from the last non-empty line against an exact match so "Criterion 1: PASS" can't trigger a false pass (`autopilot.sh:413-424`).
5. **High-stakes allowlist is attack-resistant.** Exact string equality, non-empty-reason required; prefix/substring/bare-path/empty-reason variants all stay gated (live-tested §11). Editing the allowlist or `_high-stakes.sh` inside a phase forces supervised review (`tick.sh:173`). Empty `HIGH_STAKES_RE` fails **safe** (treats all paths as high-stakes).
6. **`models.sh` is injection-proof.** The value goes through `awk ... ENVIRON` (never `sed`/`-v` interpolation); a value with `/ & $ " ' |` was written verbatim, a body `model:` decoy was preserved, frontmatter stayed well-formed (live-tested §11).
7. **Hooks fail safe universally** — jq with `// default` + `2>/dev/null`, `command -v` guards, `is-inside-work-tree` guards, `stop_hook_active` loop guards; kill-switch on `PreToolUse:*` blocks all tools.
8. **Docs tell the truth about limits** (SECURITY.md:71, README.md:299-302): "`tick.sh` cannot guard edits to `tick.sh` itself," with the integrity check correctly attributed to headless autopilot only.
9. **Install ships a clean manifest** — no root README, no `PLAN-*.md`, no `AUDIT*`, no `toolkit-docs/*`; idempotent; brownfield-safe; refuses git-subdir installs.
10. **Code hygiene:** `shellcheck -S warning` = 0 findings across every script; `bash -n` clean.

---

## 7. What is broken

**Nothing.** No Critical/High/Medium *behavioral* defect was found in any path I executed. The gate could not be tricked into a false tick; secrets and high-stakes changes could not bypass it; the installer shipped nothing it shouldn't.

The single Medium item (§13, F1) is a **test-coverage** gap, not a broken behavior — the guard it fails to cover is present and works.

---

## 8. What is fragile

- **The gate-control file list is hand-maintained** (`autopilot.sh:288`, `GATE_CONTROL_FILES=`). If a future refactor adds a new gate-relevant script and forgets to add it here, the integrity net has a hole. Low — mitigated by the fact that the *listed* files include the ones that actually make ticking decisions. Consider a test asserting every `scripts/*.sh` sourced by tick.sh appears in the list.
- **`_high-stakes.sh` allowlist trimming depends on `sed` being on PATH.** In a stripped environment where `sed` is absent, `_high_stakes_allowlisted` silently fails to trim and an otherwise-valid allowlist entry stops suppressing — which fails **safe** (more paths gated), so it is fragile-toward-safe, not dangerous. (Observed when I ran the lib under a PATH-less zsh; irrelevant under normal bash.)
- **In-session `/wrap` has a thinner net than headless autopilot** — by design. It does not get `gate_control_intact()` or the trusted-base override; it relies on tick.sh's own narrower gate-config check (allowlist + `_high-stakes.sh` only) plus the human being present. This is **documented honestly** (README.md:299-302, phase.md:43-51), so it is a disclosed limitation rather than a latent bug. A `/wrap` user who forges a *valid-later-ancestor* `.phase-base` can narrow the scan; the mitigation is human supervision, which is the whole premise of the in-session path.

---

## 9. What is bloated or over-engineered

Very little. The toolkit is lean where it counts (runtime scripts are tight). The only "heavy" surfaces are intentional:
- **README.md (~28 KB)** — long, but the owner explicitly prefers a thorough README and it is accurate. Not bloat; keep it.
- **Comment density** in the security scripts is high — but the comments encode the *threat reasoning* and are the reason the next maintainer won't accidentally weaken a gate. Keep.
- **Maintainer clutter** in the working tree (untracked scratch docs, tracked AUDIT/PLAN docs at root) is mild repo-hygiene noise, not runtime bloat (L4).

No dead scripts, no redundant runtime docs, no unnecessary process for small tasks (a trivial `/phase` still just builds and gates; the ceremony is opt-in).

---

## 10. What is missing

- **A test for the non-ancestor `.phase-base` rejection** (F1, Medium) — the one real gap.
- **`install.sh --help`/`-h`** (F2, Low) — every other operational script answers `--help`; install.sh treats it as an unknown flag (exit 2, fails safe, writes nothing).
- **A guard that `GATE_CONTROL_FILES` stays complete** (§8) — nice-to-have.
- Nothing else material is missing relative to the documented feature set.

---

## 11. Security findings (executed evidence)

**Trust-boundary attacks — all held:**

| Attack | Result | Evidence |
|---|---|---|
| Forged `.phase-base = HEAD` (empty window) | refused, ROADMAP untouched | `tick.sh:147`; test-tick t14c |
| Divergent **non-ancestor** `.phase-base` | refused: "is not an ancestor of HEAD (fail-closed)" | **live repro** in a two-branch scratch repo |
| Bogus/unresolvable `.phase-base` | refused | test-tick t13/t14d |
| `TICK_BASE` overrides forged file | scans real window → exit 3 | test-tick t14 |
| Forged `.phase-grade` (verdict/run_id) | refused (run_id!=HEAD / verdict!=PASS) | `tick.sh:104-105` |
| Forged / malformed `.tick-evidence.json` | refused — but by the run_id bind, not `jq empty` (see F8) | `tick.sh:108-119`, **live repro** |
| Allowlist self-exemption in-phase | supervised (exit 3) | `tick.sh:173` |
| `_high-stakes.sh` self-narrowing in-phase | supervised (exit 3) + headless integrity block | `tick.sh:173`, `autopilot.sh:288` |
| `tick.sh` / `_secret-scan.sh` self-edit (headless) | integrity block, no tick, no push | `autopilot.sh:289-305,457-461` |
| Allowlist prefix/substring/bare/empty-reason | all stay **gated**; only exact valid entry suppresses | **live repro**, §_high-stakes |
| `Mode: supervised` phase | refused auto-tick (exit 3) | `tick.sh:197-206` |
| `models.sh` metachar + body-decoy injection | value written literally; decoy preserved; FM intact | **live repro** |

**Secret exposure:**
- `MODELCOSTGUARD-MISSION-PROMPT.md` (the `.gitignore` notes it held a live key) — **never committed** (`git log --all -- <file>` empty) and **not on disk**.
- Tree + history scan for `sk-or-v1-…`, `sk-ant-…`, `AKIA…`, PEM blocks, `ghp_…`, `xox…` → only matches are the AWS **documentation example** `AKIAIOSFODNN7EXAMPLE` and `sk-ant-…`-style strings **inside test fixtures** (`test-secret-scan.sh`, `test-hooks.sh`). No real secret in tracked or untracked files.
- `settings.json` `permissions.deny` is comprehensive: secret-file reads, `Bash(cat *.env*)`, `Bash(env)`, `Bash(printenv*)`, and crucially `Bash(curl *)` / `Bash(wget *)` (exfil blocks).
- `_secret-scan.sh` **fails closed** if a range endpoint can't resolve (returns 2), and is **honest** that it is "a regex prefix-matcher, NOT a scanner… best-effort speed-bump," recommending gitleaks/trufflehog. No overclaim.

**Residual security risk (accepted & disclosed):** prefix-less secrets (bare-hex tokens, random `SECRET_KEY`) are not caught by the regex; novel destructive-content patterns can slip the content backstop; in-session `/wrap` trusts the human. All three are documented.

**Security verdict: 9.5/10. The gate cannot be bypassed on the paths I attacked. Can the builder forge orchestrator state? Under headless autopilot — no (trusted-base override + gate-control integrity + evaluator-change discard). Under in-session `/wrap` — only within the disclosed human-supervised threat model.**

---

## 12. Documentation mismatches

| Claim (doc:line) | Reality (code) | Verdict |
|---|---|---|
| "`tick.sh` cannot guard edits to `tick.sh` itself" (SECURITY.md:71, README.md:299-302) | Exactly true; integrity check lives in `autopilot.sh` (headless) | **Accurate — honest** |
| ".phase-base advisory under headless; orchestrator re-derives" (phase.md:43-45) | Matches `autopilot.sh:356-364` | **Accurate** |
| "push held as a separate checkpoint" (CHANGELOG.md ~13) | `origin/master==HEAD`, tag on origin | **Stale (Low, F3)** |
| CONTRIBUTING "[Unreleased] section" (CONTRIBUTING.md:82) | maintainer instruction, not a status claim | **Correct** |
| README documents `--force/--global-skills/--with-ci/--allow-subdir` | flags exist in install.sh; sync.sh in README (H6 commit) | **Present** |

No security overclaims found. The docs consistently *under*-claim (state the limits) rather than over-claim.

---

## 13. Test coverage & mutation results

**Suites:** 15 `test-*.sh` executed, **all green**; `run-guard-tests.sh` exit 0. (`test-evidence.sh` standalone returns 1 — correct: it is the evidence *producer*, and with no test command and no `--allow-no-tests` it fails closed. Not a suite failure.)

**Mutation testing (mutate → confirm red → `git checkout` revert → confirm clean):**

| Mutation | Suite | Caught? |
|---|---|---|
| Neuter `HIGH_STAKES_RE` to match nothing | test-high-stakes | ✅ red |
| Drop `tick.sh` from doctor's `REQUIRED_SCRIPTS` | test-doctor | ✅ red |
| Break `has_wellformed_frontmatter` in models.sh | test-models | ✅ red |
| Make install.sh skip shipping `tick.sh` | install-smoke | ✅ red |
| Break `is_shipped_script()` in sync.sh | test-sync | ✅ red |
| Remove `AKIA` pattern from `_secret-scan.sh` | test-secret-scan | ✅ red |
| **Remove the `git merge-base --is-ancestor` refuse in tick.sh** | **test-tick** | **❌ stayed GREEN** |

Working tree confirmed clean after all mutations (`git status` shows no tracked modifications).

### F1 — Medium — test-tick.sh does not cover the non-ancestor `.phase-base` rejection
- **File:** `jaimitos-os/scripts/tick.sh:148` (the guard) / `jaimitos-os/scripts/test-tick.sh` (missing case).
- **Evidence:** Deleting the `refuse "… is not an ancestor of HEAD (fail-closed)"` action left `bash test-tick.sh` **green (rc 0)**. The suite covers `TICK_BASE==HEAD` (case 14c, caught by the separate `!=HEAD` guard) and an unresolvable sha (case 13, caught by `rev-parse --verify`), but **no case supplies a resolvable, non-ancestor commit** — the exact input the ancestor guard exists for.
- **The guard itself works** — I proved it live: a divergent two-branch base is refused with the correct message. So this is a *latent regression risk*, not a live vulnerability: a future edit that weakens or drops the ancestor check would ship without any test turning red.
- **Fix:** add a test case that builds `A→C` (HEAD) on master and `A→B` on a side branch, sets `.phase-base=B` with valid grade+evidence, and asserts `tick.sh` refuses (rc 1) and does not tick. ~10 lines mirroring case 14c.
- **Blocks release?** No. Should land in the next patch.

**Other coverage gaps (Low/Info):** `close-milestone`'s open-item guard is covered by test-close-milestone (green), though my attempt to mutate it was a no-op (escaped-bracket regex); the suite exercises the real path. Live `/phase`/autopilot end-to-end is exercised only by mocked-CLI tests, not a real `claude` run — inherent and acceptable.

---

## 14. Highest-risk untested paths

1. **Non-ancestor `.phase-base` guard** — works, untested (F1). Highest because it is a security guard with no fail-capable test.
2. **`GATE_CONTROL_FILES` completeness** — no test asserts the list covers every decision-making gate file; a future omission would be silent (§8).
3. **Live headless autopilot loop** — only mocked; the real `claude`-driven loop (permission-mode behavior, `.phase-ready` absence detection) is verified by reasoning + code, not a live overnight run. Documented as sandbox-only.
4. **Full sync mixed-merge metacharacter matrix driven live** — the merge code is read and the suite is green, but I did not hand-drive all ~20 adversarial values through `sync.sh` live (see §0).

---

## 15. Prioritized fix plan — **ALL APPLIED this session** (verified green)

Every item below was implemented and the full guard suite + install-smoke re-run at exit 0. Change set: 7 tracked files, +69/−6.

**P0 — must fix before public recommendation:** *(none — no Critical/High)*

**P1 — should fix soon:**
- **F1 (Medium) — APPLIED.** Added test-tick.sh case 15: a divergent-branch (resolvable, non-ancestor) `.phase-base` with valid grade+evidence, asserting a fail-closed refuse whose message names "ancestor". Proven fail-capable: with the `is-ancestor` guard removed, tick.sh *actually ticked* the phase and the new test went red; guard restored.

**P2 — polish:**
- **F2 (Low) — APPLIED.** Added a `-h|--help` case to `install.sh` (usage to stdout, exit 0); a genuinely unknown flag still fails closed (exit 2, verified).
- **F3 (Low) — APPLIED.** CHANGELOG v2.3.0 now reads "…tagged `v2.3.0`, merged to `master`, and pushed to origin (branch + annotated tag)."
- **F4 (Low) — APPLIED.** `.gitignore` now covers `*-MISSION-PROMPT.md`, `HANDOFF-*.md`, `REDTEAM-*.md`, `CHANGES-LAST-*.md` — the 4 ephemeral scratch notes are now ignored (files kept, not deleted). The two audit reports were left untracked for the maintainer to track/move (mixed precedent: `AUDIT-JAIMITOS-OS-V2.2.md` is tracked).
- **F5 (Info) — APPLIED.** Added test-autopilot-gates.sh case 18: a static assertion that every lib `tick.sh` sources appears in autopilot.sh's `GATE_CONTROL_FILES` (guards the §8 hand-maintained-list fragility).
- **F6 (Info) — APPLIED.** `/resume.md` now also surfaces whether the next open phase is loopable or supervised (its `Mode:` line) so `/autopilot` vs supervised `/phase` is chosen correctly.
- **F7 (Info) — NO CHANGE NEEDED.** The `toolkit-docs/GUIDE.md` install exclusion is intentional and documented in install.sh; targets get `SCAFFOLD.md`. Confirmed, left as-is.
- **F8 (Low) — APPLIED.** `tick.sh` now validates evidence with `jq -e 'type'` (was `jq empty`, confirmed a no-op on this jq build — the M4 weakness `doctor.sh` already fixed). test-tick.sh's malformed-JSON case now exercises this guard directly and stays green.

**Not applied (out of scope, flagged for your decision):** a project-memory note observed that `.claude/agents/evaluator.md` is **not** in autopilot's `GATE_CONTROL_FILES`. Under headless autopilot a builder that edits the evaluator definition in its worktree could influence its own grade without tripping the integrity check. This is a genuine (headless-only) hardening beyond this audit's findings and changes gate-control behavior, so it warrants your explicit sign-off rather than a silent edit — recommend adding `evaluator.md` (and arguably all four agent files) to `GATE_CONTROL_FILES` next.

---

## 16. Final verdict

**Very good.** This is a security-serious, honestly-documented, well-tested toolkit whose central claim — "nothing marks work done without passing one strict, fail-closed gate" — is *true and holds up under attack*. It is not fragile; it does not overclaim; it is lean where it matters.

---

## 17. Direct answers

1. **Is the local folder actually at v2.3.0?** Yes — `VERSION=2.3.0`, tag `v2.3.0` on the release commit.
2. **Does the local repo match the expected released state?** Yes — clean tree (tracked), pushed, tagged, CHANGELOG entry present.
3. **Is `VERSION` correct?** Yes.
4. **Is `CHANGELOG.md` correct?** Substantively yes; one stale "push held" clause (F3).
5. **Is the `v2.3.0` tag correct?** Yes — annotated, on `cc92445`, also on origin.
6. **Is the working tree clean?** Clean of tracked changes; 5 untracked scratch docs + a gitignored `.DS_Store` remain (F4).
7. **Untracked files to delete/commit/ignore?** Yes — relocate/ignore the 5 scratch docs (F4). No secrets in them.
8. **Is install safe and clean?** Yes — verified manifest ships no PLAN/AUDIT/README/toolkit-docs; idempotent; brownfield- and subdir-safe.
9. **Is sync safe for real projects?** Test suite green and merge code inspected as safe (exact-value preservation, unknown→manual, dry-run truthful); the exhaustive live injection matrix was not fully hand-driven (§0) — no defect found in what was run.
10. **Is `/phase` reliable?** Yes for the gate mechanics I executed; agent boundaries are enforced (researcher/evaluator) or convention+gate-backed (planner/executor).
11. **Is `/wrap` safe enough, and its exact limits?** Yes for its human-supervised threat model. Limits (disclosed): no `gate_control_intact`, no trusted-base override, so a present human is the backstop against gate-file edits and valid-later-ancestor base narrowing.
12. **Is headless autopilot safe within its documented sandbox threat model?** Yes — trusted-base override + 7-file gate integrity + evaluator-change discard + secret/high-stakes gates + no-push-on-high-stakes. Requires `--dangerously-skip-permissions`, documented as sandbox-only (no prod credentials).
13. **Can the builder still forge orchestrator state?** Headless: no (blocked on every vector I tried). In-session `/wrap`: only within the disclosed human-supervised limits.
14. **Can high-stakes or secrets still bypass the gate?** Not on any path executed. Residual: prefix-less secrets / novel destructive content — disclosed, recommend gitleaks/trufflehog for hard guarantees.
15. **Are agents useful and well-bounded?** Useful; researcher+evaluator tool-sandboxed; planner+executor convention-bounded with tick.sh as the real enforcement — honestly stated.
16. **Are skills useful and correctly constrained?** Yes — report-only skills enforce `disallowed-tools`; mutating skills scoped to purpose.
17. **Are commands accurate and reliable?** Yes; thin, audited wrappers; `/resume` is minimal.
18. **Are hooks wired and safe?** Yes — correct events, fail-safe, kill-switch blocks all tools.
19. **Are docs current and honest?** Yes, notably honest about limits; one stale CHANGELOG clause.
20. **Is the setup lean or bloated?** Lean at runtime; minor maintainer clutter in the tree; README long by design.
21. **Are tests broad and actually fail-capable?** Broad (15 suites) and mutation-proven fail-capable (6/7); one uncovered guard (F1).
22. **Is code quality high?** Yes — 0 shellcheck warnings, purposeful comments, injection-safe parsing.
23. **Is the security posture acceptable?** More than acceptable — it is the strongest part of the setup.
24. **Is this portable across machines/repos?** Yes — Bash-3.2-safe, spaces-in-paths handled, `md5`/`md5sum` fallback, monorepo/subdir detected and refused.
25. **What to fix before recommending publicly?** F3 + F4 (5 minutes) and ideally F1 (the test). Nothing blocking.
26. **What to fix next version?** F1 (P1), then F2/F5/F6 polish.
27. **What must NOT change (already good)?** The `tick.sh` gate design; `autopilot.sh`'s `gate_control_intact()` + trusted-base override + `cleanup_eval_changes`; the high-stakes allowlist exact-match semantics + fail-safe; `_secret-scan.sh` fail-closed range validation; the honest self-edit documentation; the ENVIRON-based `models.sh` write.
28. **Final score:** **9.0 / 10.**
29. **Blunt final verdict:** **Release-ready and safe to recommend publicly.** No Critical/High/Medium behavioral defect survived direct attack. Land the one-line CHANGELOG fix and tidy the untracked scratch files, add the missing ancestor-guard test when convenient, and ship it. This is among the more trustworthy Claude Code setups I have audited — its guardrails are real, not decorative, and it is refreshingly honest about what it cannot protect.
