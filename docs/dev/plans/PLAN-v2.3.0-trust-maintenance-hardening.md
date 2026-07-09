# PLAN — jaimitos-os v2.3.0 · Trust Boundary & Maintenance Hardening

**Status:** in progress · **Base:** v2.2.1 (`4e2a9da`, tagged) · **Branch:** `v2.3.0-trust-maintenance-hardening`
**Sources of truth:** `AUDIT-JAIMITOS-OS-V2.2.md` (repo root), `CHANGELOG.md` (`## [2.2.1]` + Known limitations),
the v2.2.1 commits. This is a hardening/maintenance milestone — **no new features, no guardrail
weakening, no redesign.** All line anchors below were verified against the working tree before execution.

**Hard scope rule:** if any fix turns into a major architecture rewrite, stop, write a design note, and
get approval. The `.phase-base` fix is pre-designed (~15-20 lines + an integrity check), not a rewrite.

## Confirmed decisions
- **Phase 1 `.phase-base`:** FULL trusted-base fix — derive the base in autopilot's trusted shell, feed
  it to the evaluator *and* `tick.sh`, validate strict-ancestor in `tick.sh`, forbid executor writes,
  and integrity-check the gate-control files before the gate runs.
- **Phase 4 monorepo:** DETECT + REFUSE/WARN (don't rewrite the 9 scripts' git-root resolution).
- **Phase 5 ecosystems:** SUPPORT common (go/cargo/make, +mvn/gradle) + a loud precise fallback.

## Trust classification (Phase 1)
- **TRUSTED** (held by autopilot's own shell, outside the builder): the phase base (this fix); the
  evaluator verdict → `.phase-grade` (re-derived via `record-grade.sh`, autopilot.sh:365); test evidence
  → `.tick-evidence.json` (re-derived via `test-evidence.sh`, autopilot.sh:307,382); the gate-control
  *code* only when byte-identical to autopilot's trusted launch checkout.
- **UNTRUSTED** (builder-writable in the worktree under `--dangerously-skip-permissions`): everything the
  builder can Write — `.claude/.phase-base`, `.claude/.phase-ready` (heading only, roadmap-validated), and
  every gate-control execution file in the worktree (`scripts/tick.sh`, `scripts/test-evidence.sh`,
  `scripts/record-grade.sh`, `.claude/lib/_high-stakes.sh`, `.claude/lib/_test-cmd.sh`,
  `.claude/high-stakes-path-allowlist`).
- **FORCE SUPERVISED when changed** (checked by autopilot's trusted shell, independent of the
  possibly-modified worktree `tick.sh`): the gate-control files above — at minimum `scripts/tick.sh` and
  `.claude/lib/_high-stakes.sh`.

---

## Phase 1 — `.phase-base` forgery / forgeable orchestrator state (centerpiece)

**Threat (verified):** `autopilot.sh` never reads/writes `.claude/.phase-base` (only a comment at :82).
The untrusted builder writes it via `/phase` (`phase.md:42`) under `--dangerously-skip-permissions`;
it is gitignored and *not* re-derived by autopilot. `tick.sh` reads BASE only from that file
(`tick.sh:116`) with **no ancestor check** (only `-n`, :117), then scans `BASE..HEAD` (:118) for
secrets (:125), high-stakes path (:133), the C1 gate-config self-edit (:141-146), and high-stakes
content (:155). The evaluator also reads `.phase-base` (`evaluator.md:38,48`). A builder that writes
`BASE=HEAD` empties the range → every gate sees nothing → auto-tick + auto-push. Because the C1 check
keys off `$CHANGED` (from `BASE..HEAD`), a forged BASE also hides gate edits from C1.

**Verified loop facts:** builder spawn autopilot.sh:280; evaluator :327; `bash scripts/tick.sh` :390
(no `$1`, no env). Thrash tracking: `PREV_OPEN_SIGNATURE`/`SAME_PHASE_FAILS` init :258-260, signature
(md5 of open `- [ ]` roadmap lines) computed :275, compared :354-355, reset on tick :406. **No
`BASH_SOURCE`/`$0`** anywhere — autopilot `cd`s to git toplevel (:97), captures `ORIG_ROOT="$PWD"`
(:103) and `START_REF` (:188) *before* the worktree `cd` (:171), then operates entirely inside the
builder-mutable worktree (`tick.sh`, `test-evidence.sh`, and the libs all resolve from `$PWD`=worktree).

**Design:**
1. `scripts/autopilot.sh` — capture the trusted base in autopilot's shell at the **top of the loop**
   (before the builder spawn at :280) as `git rev-parse HEAD` in the worktree, **set-once-per-new-phase,
   preserved across NEEDS_WORK retries** using the existing `OPEN_SIGNATURE` tracking (a new phase = the
   open-checkbox signature changed; a retry = signature unchanged → keep the base). Mirrors `phase.md`'s
   "set base only on a new phase" rule; a naive per-iteration recapture would self-narrow on retries.
2. After the builder exits and **before the evaluator runs** (~between :299 and :327), overwrite
   `echo "$PHASE_BASE" > .claude/.phase-base` in autopilot's shell so the evaluator reads the trusted
   value (fixes both the evaluator phase-diff and the criteria-integrity check).
3. Pass it to `tick.sh` via **env**: `TICK_BASE="$PHASE_BASE" bash scripts/tick.sh` at :390.
4. `scripts/tick.sh` — base resolution with **strict validation**: if `TICK_BASE` is **set**, use it and
   do **not** fall back to the file — if it's invalid (empty, `==HEAD`, or not a strict ancestor of HEAD)
   **refuse**. Fall back to `.claude/.phase-base` only when `TICK_BASE` is **absent** (the `/wrap` path).
   Apply the same strict-ancestor guard on either source: refuse unless `BASE != HEAD` AND
   `git merge-base --is-ancestor "$BASE" HEAD`. Preserve existing fail-closed on missing/unresolvable.
5. **Gate-control integrity (autopilot's trusted shell, before running the gate).** Before auto-ticking,
   `cmp` each gate-control file in the worktree against its trusted original resolved from
   `START_REF`/`ORIG_ROOT` — **`git show "$START_REF:<path>" | cmp - <worktree path>`** (catches
   committed AND uncommitted edits; works in worktree and `--no-worktree`; independent of the forged
   BASE and the possibly-edited worktree `tick.sh`). Any mismatch → **force supervised** (same block as
   an HS hit: `HS_BLOCKED=1`, no auto-tick, no push). Minimum coverage `tick.sh` + `_high-stakes.sh`;
   extend to the full list if cheap. Document the `--no-worktree` residual (reduced isolation).
6. `.claude/agents/executor.md` — extend the Constraints/HARD-RULE block (:23-31) to forbid writing/
   editing `.claude/.phase-base`, `.phase-ready`, `.phase-grade`, `.tick-evidence.json`, or any
   gate-control script. Advisory — the real protection is autopilot's re-derivation + integrity check.
7. `.claude/.phase-ready` stays builder-authored but **validated-not-trusted** (tick.sh validates the
   heading against the roadmap). Document it; confirm no auto-tick/push path depends on it beyond the
   roadmap-validated heading.
8. Symmetric note in `phase.md`/`evaluator.md` that the base is orchestrator-authoritative under
   autopilot (builder-written file overridden before grading).

**Tests (reproduce forgery → prove blocked):**
- `test-autopilot-gates.sh`: stubbed builder forges `.phase-base=HEAD` hiding a high-stakes/secret
  commit → autopilot's trusted base overrides it → tick sees the real window → exit 3 / no push.
  (Money test — must FAIL on pre-fix code, pass after.)
- `test-tick.sh`: `TICK_BASE` env precedence over the file; strict-ancestor guard rejects `BASE=HEAD`
  and a non-ancestor; `/wrap`-style call (file only, no env) still works; existing t9x/C1 cases green.
- Confirm forged `.phase-grade`/`.tick-evidence.json` remain neutralized by autopilot re-derivation (M1).
- Gate-control edit (committed AND uncommitted) → integrity check forces supervised. Must FAIL pre-fix.

**Files:** `scripts/autopilot.sh`, `scripts/tick.sh`, `.claude/agents/executor.md`,
`.claude/agents/evaluator.md`, `.claude/commands/phase.md` (note), `scripts/test-autopilot-gates.sh`,
`scripts/test-tick.sh`.

## Phase 2 — models/frontmatter (H2, M3)
`scripts/models.sh`: give `remove_model()` (:116-119) the existence-check + error-propagation +
permission-preservation its sibling `set_model()` (:71-114) has; the three `reset` calls (:144-146) also
need `|| exit 1`, but the function itself must fail first (it currently never returns a meaningful
failure). Scope model detection/update to the `---`…`---` frontmatter block (reuse sync.sh's
`has_wellformed_frontmatter` :238 + `fm_model_lines` :246) so a body `model:` line is never
rewritten/stripped; missing/malformed frontmatter fails loudly, file byte-identical. Keep metachar-safety.
**Tests** (`test-models.sh`): reset-with-missing-file → non-zero + no `.tmp`; reset on valid files still
works; body `model:` untouched; missing/malformed frontmatter fails loud; valid update works.

## Phase 3 — doctor/install health (H3, M4, M11)
`scripts/doctor.sh`: replace the hardcoded scaffold list (:45) and lib list (:124) with globs / a
manifest so deleting `tick.sh`/`sync.sh`/`_test-cmd.sh` is *detected* (reuse the `scripts/*.sh` /
`.claude/lib/*.sh` globs already at :154/:163); add `-e` to the `settings.json` `jq empty` check (:131);
print the `install.sh --force` remediation hint on any missing-file ✗ (not only behind `--fix`, :194).
Keep quiet on a healthy repo. **Tests** (`test-doctor.sh`): assert the *report text* flags each missing
lib/script + invalid JSON + prints remediation; `--fix` still correct; healthy repo not noisy.

## Phase 4 — monorepo / off-git-root (H4) — DETECT + REFUSE/WARN
`install.sh`: detect `TARGET != $(git -C "$TARGET" rev-parse --show-toplevel)` → refuse without an
explicit `--allow-subdir` (or warn loudly); `doctor.sh`: report the mismatch clearly instead of a wall of
false "missing". Document the one-repo-per-project assumption. **Do not** change the 9 scripts' git-root
resolution. **Tests:** install at git root works; install into a subdir refuses/warns clearly; scripts
don't emit misleading missing-file errors in that state.

## Phase 5 — test ecosystems (M2) — SUPPORT common + loud fallback
`.claude/lib/_test-cmd.sh`: after the uv/poetry/pytest/npm chain (:48-60), add `go.mod`→`go test ./...`,
`Cargo.toml`→`cargo test`, a `Makefile` with a `^test:` target→`make test` (optionally `pom.xml`→`mvn
test`, `build.gradle`→`gradle test`); anything still unresolved → **loud, precise** "no known test runner
— set LEAN_TEST_CMD" on stderr (the resolver currently returns silent `return 1` at :61). Preserve
precedence (env > settings.json > lockfiles > new ecosystems > loud fail) and the v2.2.1 resolver fixes.
Update docs so `LEAN_TEST_CMD` is not framed as merely "optional" for unsupported stacks.
**Tests** (`test-test-cmd.sh`): Go/Rust/Makefile resolve; unknown → clear instruction; precedence
unchanged; jq-missing/non-string still safe.

## Phase 6 — sync UX/safety (M5, M6, M7)
`scripts/sync.sh` + docs: the mixed-merge confirm prompt (:445) states plainly it preserves **only** the
named value (`model:` / `HIGH_STAKES_RE` / `paths:`), not arbitrary body/tools; detect a
**never-scaffolded** target (no `.claude/settings.json`) and tell the user to run `install.sh` first
instead of a pseudo-install; show informational (non-writing) diffs for `unknown`/`never`-tier drift
(settings.json is `unknown`, :119-120); sort the enumeration order (:89/:105 unsorted `find`) for
deterministic prompts without changing semantics. Keep C2/C3/H1 green. **Tests** (`test-sync.sh`):
never-scaffolded → clear refusal; prompt wording; deterministic order; C2/C3/H1 still pass.

## Phase 7 — docs / security / help / install-smoke / CI (H6, M10, M12, M13, H7)
- **H6:** add concise `sync.sh` coverage to `README.md` (layout tree :60, a "Keeping a project up to
  date" subsection; what/when/dry-run/local-checkout/risk).
- **M10:** document `.claude/high-stakes-path-allowlist` in `README.md` Security + `SECURITY.md` (:59-63)
  — exact-path, reason-required, and that gate-control edits now force supervised — an *auditable
  false-positive escape hatch*, not a bypass. Document `--dangerously-skip-permissions` residual risk and
  the `.phase-base` trust model honestly.
- **M12:** add a safe `-h|--help` to operational `scripts/*.sh` (only `doctor.sh:23` has one); **fix the
  footgun where `run-guard-tests.sh --help` runs the whole suite** (it has zero arg handling today).
- **M13:** expand **root** `.github/scripts/install-smoke.sh` (there is no `jaimitos-os/.github/scripts/`)
  to check all shipped files — add `evaluator.md`, all 6 commands, `test-sync.sh`, `_test-cmd.sh`, the
  full skills set; run `doctor.sh` on the installed tree if feasible (it currently runs `test-hooks.sh`).
- **H7:** pin the `ci.yml:43` actionlint fetch to a tagged release + checksum (no unpinned `main`
  `curl|bash`). Shipped `jaimitos-os-ci.yml` already clean.

## Phase 8 — P2 polish (only after P1 green; skip anything destabilizing)
`test-evidence.sh` rename→`record-evidence.sh` *only if* references are trivially updatable, else header
note + defer; correct the retry "never false green" comment; `tick.sh` `grep -qxF --`/awk `ENVIRON` tidy;
deterministic sync prompt (if not done in P6); relocate root scratch docs (`HANDOFF-*`, `REDTEAM-*`,
`SESSIONLENS-*`) into a gitignored dir **(confirm before deleting anything)**; CHANGELOG note on the
missing `v2.0.0` tag / VERSION mismatch (**no history rewrite**); grammar + close-milestone ownership text.

## Phase 9 — independent adversarial re-audit (Agent K)
Re-test every critical path in disposable scratch repos: `.phase-base` forgery (+ forged
grade/evidence), gate-control edits, models frontmatter edges, doctor missing-file cases, monorepo
install, unsupported-ecosystem behavior, sync C2/C3/H1 regressions, help behavior, install-smoke coverage.
Output pass/fail by area, any reproduced bypass, any new regression, and a tag-readiness verdict. Fix
blockers before close.

## Version / tag rule
Do **not** bump VERSION or tag until all accepted P1 items are green **and** the Agent-K re-audit passes
**and** the user explicitly approves the close. Milestone close is its own explicit checkpoint — never
inferred from "continue"/"resume"/"go ahead". Do not push.

## Verification of done
`run-guard-tests.sh` green incl. new assertions; `.phase-base` forgery test fails pre-fix / passes after;
gate-control-edit test forces supervised; doctor detects deleted `tick.sh`/`sync.sh`; `models.sh reset` on
a missing file exits non-zero with no `.tmp`; Go/Rust/Make resolve or fail loudly; monorepo install
refuses/warns; README+SECURITY document sync + allowlist; `run-guard-tests.sh --help` no longer runs the
suite; install-smoke covers the full manifest; CI actionlint pinned; `bash -n` + `shellcheck -S warning`
+ `install-smoke.sh` clean. VERSION/tag untouched until the checkpoint.
