# Adversarial Quality Audit — jaimitos-os v2.3

> **⚠ Archived audit — superseded by v2.3.1 (2026-07-07).** Release-state statements below (e.g.
> "code-complete-but-unreleased", "local, unpushed", "origin at v2.2.0", "safe to push only with
> approval") were TRUE when written, during the pre-release audit. v2.3.0 was subsequently released,
> tagged, and pushed; post-release hardening then shipped as **v2.3.1**. The findings are preserved
> verbatim for the historical record — only this banner was added.

**Scope:** everything introduced across v2.1.0, v2.2.0, v2.2.1, and the code-complete-but-unreleased v2.3.0
(`trust-boundary & maintenance hardening`).
**Method:** 11 parallel adversarial sub-agents, each working read-only against the repo and running destructive
experiments only in `/tmp` scratch git repos. Every claim below is backed by command output, `cmp`/byte
comparison, git state, or a reproduced exploit against pre-fix code (`git show v2.2.0:` / `v2.2.1:`). The
toolkit's own 14-suite guard battery was run (`run-guard-tests.sh </dev/null` → **exit 0**), and every
representative suite was mutation-tested to confirm it can actually fail.

> **Layout note (verified):** the installable toolkit is dogfooded as a subdirectory `jaimitos-os/` of the
> wrapper git repo `Claude_SETUP`. Scripts live at `jaimitos-os/scripts/`, libs at `jaimitos-os/.claude/lib/`,
> agents/commands/hooks/rules under `jaimitos-os/.claude/`, docs at `jaimitos-os/docs/` + `jaimitos-os/toolkit-docs/`.
> Toolkit *meta* (`install.sh`, `README.md`, `CHANGELOG.md`, `SECURITY.md`, `VERSION`, `skills/`, `.github/`)
> lives at the repo root. `install.sh` copies `jaimitos-os/` + `skills/` into a target project's root.

---

## 1. Executive summary

**v2.3 is a genuine, disciplined improvement over v2.2/v2.2.1, and the lean philosophy survived.** The
milestone's centerpiece — a trusted `.phase-base` model plus gate-control byte-integrity — is not marketing
prose: it withstood a dedicated red team that ran 17 tick-forgery attacks, 9 gate-control-drift attacks, and
injection-shaped base values, and **could not break it within its stated threat model** (headless
`autopilot.sh --dangerously-skip-permissions` in a no-credentials sandbox). 20 of 23 previous
Critical/High/Medium findings are genuinely fixed, each with a regression test proven to flip red on pre-fix
code and green on current. Injection surfaces in the load-bearing scripts (`models.sh`, `sync.sh`,
`autopilot.sh`, `tick.sh`) are PoC-verified safe; all 37 shell scripts parse clean and carry zero
warning-level shellcheck findings on real Bash 3.2.57; the guard suites empirically bite.

**No Critical and no High-severity defect was found.** That is a real change from the v2.2 audit (which had
three Criticals sitting in the two features that release shipped). The remaining issues are a cluster of
Medium/Low items with a clear, honest through-line: **v2.3's trust hardening is concentrated on the headless
autopilot path; the human-supervised in-session `/wrap` path retains inherited, lower-severity residuals**,
and a couple of docs/packaging blemishes are conspicuous precisely because this is a *trust-honesty*
milestone.

The two things that should be fixed before the tag are cheap and non-code-risky: (1) `install.sh` ships the
toolkit's own `PLAN-*.md` dev docs into every user project, and (2) `README.md`/`SECURITY.md` overclaim that
editing `scripts/tick.sh` forces `tick.sh` exit 3 — which contradicts both the code *and the project's own
CHANGELOG*. Neither is a safety hole; both are embarrassing on a milestone whose entire theme is honesty
about trust boundaries.

**The unreleased state is correct and honestly documented.** `VERSION=2.2.1`, no `v2.3.0` tag, `[2.3.0] —
unreleased` in the CHANGELOG with an explicit "VERSION is intentionally NOT bumped" note and a written
version/tag checkpoint rule. Holding the tag for a human checkpoint is the right call.

---

## 2. Overall rating

### **8.5 / 10**

Up from the v2.2 audit's 7.0. Excellent, mechanically-enforced trust engineering and exemplary honesty about
where enforcement is mechanical vs. advisory; dragged down only by cheap docs/packaging blemishes and a set
of low-severity in-session residuals — none of which corrupt data, bypass a guardrail in the documented
threat model, or falsely mark bad work done. Close the two SHOULD-FIX items and address the `/wrap`-path
residuals over the next milestone and this is a legitimate 9.

---

## 3. Ratings by area

| Area | Score | Basis (evidence-backed) |
|---|---:|---|
| Structure | 7/10 | Clean taxonomy + one-gate design; but ~56 shipped units + 15 test scripts make "grok in 10 min" optimistic, and install ships dev docs (F1). |
| Lean-ness | 6/10 | Credible per-unit; dragged by `PLAN-*.md` shipping into targets + tracked root clutter (`AUDIT-*`, `PLAN-v2.2-*`, `PRACTICE-PROJECT.md`). |
| Clarity | 7/10 | Unusually honest on the hard parts; one security overclaim contradicting the CHANGELOG (F-Docs1), plus a comment overclaim in `tick.sh:131-132`. |
| Automation reliability | 8/10 | Retry/re-measure, O_EXCL lock + stale reclaim, worktree isolation, thrash cap, evaluator-change discard all verified; M8 (non-idempotent) now honestly documented; M9 open. |
| Claude Code usability | 8/10 | Few prompts, actionable errors, recoverable; doctor verbose. |
| Staged agent design | 8/10 | researcher tool-enforced read-only; evaluator no-edit + headless change-discard; executor gate-control ban (new v2.3, advisory + mechanically-backed headless). Planner is the softest link. |
| `/phase` lifecycle | 8/10 | Exact-then-partial selection correct and consistent with the gate; "set base only on new phase" correct; orchestrator-authoritative base documented. |
| `/models` + per-stage model config | 9/10 | H2 + M3 fixed (revert-to-red proven); injection-airtight (`awk ENVIRON`, byte-exact round-trip). |
| High-stakes gate | 8/10 | C1 fixed + regression-tested; exact-path allowlist genuinely exact; content backstop is honest, over-matching, fail-safe. |
| Evidence/tick/autopilot trust model | 8/10 | Headless ≈9 (forgery classes mechanically defeated); `/wrap` ≈6 (M9 + valid-ancestor narrowing). |
| `.phase-base` trusted-base model | 9/10 | Red team could not break it; strict-ancestor guard on both sources; set-once-per-phase preserved on retry. |
| `sync.sh` | 9/10 | No data loss found; honest failure semantics; deterministic; injection-safe. |
| Mixed-file merge safety | 9.5/10 | Every adversarial value round-trips byte-identical or fails safe to manual review (verified by `cmp` + sourcing). |
| Doctor/install/setup | 9/10 | H3/M4/M11 verified load-bearing on the user's own jq; clean brownfield/greenfield handling. |
| Monorepo/off-git-root | 7/10 | install.sh + doctor.sh detect+refuse/warn (H4 fixed); **sync.sh left unguarded** (F-Sync1). |
| Test ecosystem detection | 8.5/10 | M2 substantially fixed (go/cargo/make/mvn/gradle + loud fallback), no re-deadlock; loud message swallowed by callers (F-Test1). |
| Shell quality | 9/10 | 37/37 parse clean on Bash 3.2.57; 0 warning-level shellcheck; no 3.2 breakers. |
| Security/permissions | 8/10 | Injection PoC-safe; `--dangerously-skip-permissions` confined + honest; Bash deny list is defense-in-depth only (inherent). |
| Documentation accuracy | 7/10 | Honest on the hard parts; one overclaim, one missing-feature doc (`--allow-subdir`), one underclaim (`LEAN_TEST_CMD`). |
| Test coverage | 9/10 | Every representative suite mutation-proven fail-capable; no swallowed-counter; drift-guard enforces coverage. |
| Developer experience | 8/10 | One-command setup, honest doctor, recoverable sync; minor CLI inconsistencies. |
| Maintainability | 9/10 | Consistent idioms, `refuse()`/`fail()` discipline, ENVIRON-awk everywhere. |
| Scalability | 7/10 | Fine for one-repo-per-project; monorepo/subdir is the documented boundary (and sync doesn't yet honor it). |
| Release readiness | 8/10 | Safe to hold; a short list of cheap fixes recommended before tagging. |

---

## 4. What works well (verified, not assumed)

- **The forged-`.phase-base` attack is dead under headless autopilot.** `autopilot.sh` derives the base in
  its own trusted shell (`:320,:327-330`), set-once-per-phase and preserved across NEEDS_WORK retries,
  overwrites the builder's `.claude/.phase-base` before the evaluator (`:362-364`), and passes it to the gate
  via `TICK_BASE="$PHASE_BASE"` (`:462`). `tick.sh` prefers `TICK_BASE`, never falls back to the file when
  it's set, and strict-ancestor-validates **both** sources — real commit, `!= HEAD`, `merge-base
  --is-ancestor` (`tick.sh:133-150`). Empty / `==HEAD` / non-ancestor / bogus / injection-shaped bases all
  fail closed; the value is a quoted parameter to `git rev-parse`, so no shell injection (canary never fired).
- **Gate-control neutering is dead.** `gate_control_intact()` byte-compares 7 gate-control files against
  `START_REF`'s git blob via `git show START_REF:$p | cmp -s -` (`autopilot.sh:288-305`), run *before* the
  gate (`:457-461`), catching committed **and** uncommitted edits (and newly-introduced files), independent of
  a forged base or a neutered worktree `tick.sh`. Any drift → `HS_BLOCKED=1`: no auto-tick, branch stays
  local, no push even with `--pr`. Reproduced for `tick.sh` and `test-evidence.sh` neutering.
- **C1 self-exemption is genuinely fixed.** In-phase edits to the allowlist or `_high-stakes.sh` → `tick.sh`
  exit 3 (`tick.sh:173-178`), regression-tested (`test-tick.sh` 9d/9e, flip red on v2.2.0).
- **`sync.sh` loses no data.** No case produced a silently-lost project value or a silently-broken file;
  every ambiguity (multi-line `HIGH_STAKES_RE`, malformed frontmatter, garbage in a `paths:` block) routes to
  manual review **byte-identical** (verified by `cmp`, not grep). Adversarial metacharacter values round-trip
  byte-for-byte (verified by sourcing the merged file). C2/C3/H1/M5/M6/M7 all pass against the real shipped files.
- **`/models` is injection-airtight.** Every validation-passing value writes byte-exact via `awk ENVIRON`;
  `$(id)`/backtick/redirection payloads are written as literal bytes and never executed. H2 + M3 fixed and
  proven by reverting each fix to red.
- **Evaluator independence is enforced, not asked.** No Write/Edit tools (`evaluator.md:6`) + headless
  `cleanup_eval_changes` (`autopilot.sh:231-262`) that reverts edits *and commits* and STOPs if it can't
  restore the pre-grade tree. Forged `.phase-grade`/`.tick-evidence.json` are re-derived by the orchestrator
  and neutralized.
- **Shell + tests are solid.** 37/37 scripts parse clean on Bash 3.2.57; 0 warning-level shellcheck findings
  (CI gate genuinely passes); every representative guard suite empirically fails when its code-under-test is
  broken; the full battery passes `</dev/null` (exit 0, no hang).
- **The docs are honest on the genuinely hard parts.** The `.phase-base` / `--dangerously-skip-permissions`
  model (README:303-312, SECURITY:72-82) refuses to overclaim ("a fully-malicious builder with arbitrary
  shell access can still tamper… the executor's forbidden-writes rule is advisory"). The secret scanner's
  self-description matches its behavior exactly ("regex prefix-matcher, NOT a scanner… CANNOT catch
  prefix-less secrets").

---

## 5. What does not work

- **The `/wrap` in-session tick path is materially weaker than headless autopilot** — three independent
  residuals converge there (M9 open, valid-later-ancestor base narrowing, no gate-control integrity check).
  All are human-supervised and none can silently push a secret to a remote (Stop-hook + push-gate backstop),
  but the in-session gate is not the airtight gate the headless path is.
- **`install.sh` ships the toolkit's own dev-planning docs into every target project** (`PLAN-v2.2.1-*.md`,
  `PLAN-v2.3.0-*.md`) — verified end-to-end, and a direct contradiction of install.sh's own header.
- **`sync.sh` mutates the wrong tree in a monorepo/subdir** with a false-success report — the one H4-family
  surface the milestone's Phase 4 did not harden.
- **The Phase-5 "loud `LEAN_TEST_CMD` guidance" never reaches the operator in-flow** — both production
  callers redirect the resolver's stderr to `/dev/null`.

---

## 6. What is fragile

- **The in-session `.phase-base` trust.** `/wrap` and `/autopilot-parallel` call `tick.sh` with no
  `TICK_BASE`, so the scan floor comes from the builder-writable `.claude/.phase-base`. The strict-ancestor
  guard blocks empty/`==HEAD`/non-ancestor, but **not** a base advanced forward to a valid later ancestor,
  which narrows `BASE..HEAD` and can hide an earlier in-phase high-stakes/secret commit. Reproduced (ticked,
  exit 0). Headless is immune.
- **`tick.sh:109` `jq empty`.** The authoritative evidence gate still uses the exact idiom doctor.sh migrated
  off for M4; on the user's Apple jq-1.6 build, malformed evidence passes `jq empty`. Currently backstopped
  (downstream `.passed`/`.run_id` extraction refuses), so not a false-tick today, but a latent inconsistency
  in the gate that decides ticking.
- **The version stamp is not a reliable indicator of what's installed** — declining every sync update still
  bumps `.claude/.jaimitos-os-version`, so doctor can report a version the project rejected.
- **Bash-level secret deny rules** (`Bash(cat *.env*)`, `Bash(env)`) are trivially bypassable
  (`head`/`less`/`python -c`), an inherent Claude-Code limitation; they are defense-in-depth, not a boundary.

---

## 7. What is over-engineered

- **Not much.** The staged four-agent flow is the closest candidate: plan+execute+verify run unconditionally,
  so even a one-line roadmap item spins up ≥3 subagents, and the toolkit ships no `/fast` escape hatch.
  Research is at least conditional (`phase.md:54-60`). This is a defensible design judgment (ceremony is
  proportional to a *phase*, not a line), not waste — the "duplication" across stages is fresh-context
  re-reading, an intentional context-isolation trade.
- The **planner** stage is the weakest-ROI link: its only mechanical boundary is "no Bash/Edit" (it holds
  `Write`); its value is context separation, which pays off on large phases and is near-zero on tiny ones.

---

## 8. What is under-tested

- **The `/wrap` in-session gate path.** All the money-tests exercise the headless `autopilot.sh` path
  (`test-autopilot-gates.sh`). There is no test that a dirty working tree (M9) or a valid-later-ancestor
  `.phase-base` is caught on `/wrap` — because it isn't; the gap is untested *and* unimplemented.
- **`evaluator.md` integrity.** No test plants a PASS-forging `evaluator.md` against the gate-control
  integrity check (which does not cover it — see §10).
- **Skills manifest.** install-smoke checks 1 of 10 shipped skills; doctor checks 0. A dropped skill passes
  both gates (caught only indirectly by the run-guard drift-guard in CI).
- **`test-autopilot-gates.sh` #16/#17** include a `ticked "$REPO"` sub-assertion that is weak in `--pr`
  worktree mode; the decisive sub-assertions still bite, so the tests remain valid.

Everything else is well-tested: the guard suites are unusually adversarial and every representative one was
proven fail-capable.

---

## 9. What is missing

- A `git status --porcelain` clean-tree check inside `tick.sh` for the `/wrap` path (M9).
- `--allow-subdir` / monorepo docs in any user-facing doc (feature exists only in `install.sh`/`doctor.sh`
  code + CHANGELOG).
- A monorepo/subdir guard in `sync.sh` mirroring the one Phase 4 added to install.sh/doctor.sh.
- `evaluator.md` (and ideally `rules/high-stakes.md`) in the gate-control integrity list.
- Surfacing of the resolver's `LEAN_TEST_CMD` guidance through the production callers.
- A user-facing note that `LEAN_TEST_CMD` is *required* (not "optional") for stacks outside the 10 detected
  ecosystems; GUIDE:847 still says "optional".

---

## 10. Specific bugs / regressions found

None rise to Critical or High. Ordered by severity within Medium/Low.

### Medium

**M-Ship1 — `install.sh` ships jaimitos-os's own dev-planning docs into every target project.**
`install.sh:118-129` copy loop excludes only `toolkit-docs/*`, `.github/*`, `*.DS_Store|*.swp`; it copies
`jaimitos-os/PLAN-v2.2.1-audit-p0-fixes.md` and `jaimitos-os/PLAN-v2.3.0-trust-maintenance-hardening.md`.
Reproduced by installing into a fresh `mktemp -d` — both PLAN files landed in the project root next to
`CLAUDE.md`/`SCAFFOLD.md`. Contradicts install.sh's own header (`:20-21` "never copied into a target"). No
smoke/doctor negative assertion catches it. **Fix:** add `PLAN-*.md` to the `case` exclusion at `:120-127`
(or relocate the PLANs out of `jaimitos-os/`) + a negative install-smoke assertion. **Blocks tag:** not on
safety — SHOULD-FIX (ships to 100% of users; the v2.3 PLAN is *new this milestone*, so v2.3 made it worse).

**M-Docs1 — Security docs overclaim: editing `scripts/tick.sh` does NOT force `tick.sh` exit 3.**
`README.md:297-299` and `SECURITY.md:69-71` list `scripts/tick.sh` among files whose in-phase edit "forces
supervised review (`tick.sh` exit 3), regardless of the new contents." But `tick.sh:173` greps exactly two
paths — `.claude/high-stakes-path-allowlist` and `.claude/lib/_high-stakes.sh`. A phase that neuters
`scripts/tick.sh` runs the neutered gate → exit 0 (reproduced). tick.sh is protected *only* by the
**headless-only** `gate_control_intact` byte-compare, and not at all on `/wrap`. The repo's own CHANGELOG
agrees with the code, not the docs (`CHANGELOG.md:30`: "even `tick.sh` itself, which the C1 guard cannot
cover"). **Fix:** split the claim — allowlist/`_high-stakes.sh` → `tick.sh` exit 3 (in-session + headless);
`tick.sh` itself → detected only by the headless byte-compare. **Blocks tag:** not on safety — SHOULD-FIX
(a security claim contradicting your own CHANGELOG, on a trust-honesty milestone). *New this milestone
(commit `200cc86`).* (Corroborated independently by two agents.)

**M-Wrap1 — M9 (no clean-working-tree check) is not fixed and was silently dropped.**
`tick.sh` scans only `BASE..HEAD`; there is no `git status --porcelain` guard. Reproduced: with a valid PASS
grade + green evidence at HEAD, an **uncommitted** `auth/login.py` + a file containing
`AWS="AKIAIOSFODNN7EXAMPLE"` → `tick.sh` → `✓ ticked` (exit 0); the dirty secret and high-stakes path were
never scanned. Headless autopilot is immune (`cleanup_eval_changes` requires a clean pre-grade tree). M9 does
not appear in the v2.3 PLAN or CHANGELOG — dropped, not deferred-on-the-record. Backstopped by the Stop-hook
+ push-gate secret scans (cannot silently reach a remote). **Fix:** add a `git status --porcelain` refuse in
`tick.sh`, or document a "`/wrap` requires a clean tree" expectation. **Blocks tag:** no (human-supervised),
but record it as a known limitation. *Inherited (v2.2 M9).*

**M-Sync1 — `sync.sh` operates on the wrong tree in a monorepo/subdir, with false success.**
`sync.sh:36` `cd "$(git rev-parse --show-toplevel)"` silently jumps to the outer git root. From a subproject
nested in a *scaffolded* parent, sync merged `outer/.claude/lib/_high-stakes.sh`, stamped
`outer/.claude/.jaimitos-os-version`, left the subproject untouched, and reported "updated: 1" rc=0. (When
the outer repo is unscaffolded, M7 safely refuses.) Phase 4 hardened install.sh + doctor.sh but not sync.sh.
No data loss (outer's own value preserved), but a wrong-target mutation + silent no-op of the intended
target. **Fix:** mirror install.sh's `--allow-subdir` guard (compare `--show-toplevel` vs `$PWD`).
**Blocks tag:** no (documented one-repo-per-project assumption) — recommended for the trust milestone.

**M-Sync2 — Declining every sync update still bumps the version stamp.**
`sync.sh:570-573`. Decline all prompts → files unchanged, yet `.claude/.jaimitos-os-version` advances;
`doctor.sh:234` then reports "scaffolded from jaimitos-os `<new>`" for a project that rejected every change.
Deliberate (comment `:557-560`), but makes the stamp unreliable — a trust wart on a trust-hardening
milestone. Recoverable (`--dry-run` re-surfaces the declined diffs). **Fix:** stamp only when `UPDATED>0`
(or nothing was pending), or record "synced-against" vs "fully-applied" separately. **Blocks tag:** no.

**M-Test1 — the resolver's `LEAN_TEST_CMD` guidance is swallowed by both production callers.**
`_test-cmd.sh:97` emits the actionable "set `LEAN_TEST_CMD` / add `.env.LEAN_TEST_CMD`" line to stderr, but
`test-evidence.sh:46` and `test-gate.sh:36` both call `resolve_test_cmd 2>/dev/null`. Through the normal
autopilot/tick flow the operator sees only `test-evidence.sh:70` — which points to `--allow-no-tests` (record
`null` / *skip* tests), never to wiring up `LEAN_TEST_CMD`. So the Phase-5 headline is undelivered in-flow
and nudges toward skipping tests. **Fix:** surface the resolver's stderr on the empty-CMD path, or append the
`LEAN_TEST_CMD` instruction to `test-evidence.sh:70`. **Blocks tag:** no. *New (introduced with the Phase-5
message).*

### Low

- **L-Wrap2 — valid-later-ancestor base narrowing on `/wrap` + a comment overclaim.** `tick.sh:137-149`
  consumers `wrap.md`, `autopilot-parallel.md:77`. A `.claude/.phase-base` forged to a valid later ancestor
  passes the strict-ancestor guard and narrows `BASE..HEAD`, hiding an earlier in-phase high-stakes/secret
  commit (reproduced, exit 0). Headless is immune (`TICK_BASE`). The comment `tick.sh:131-132` overclaims
  ("neither a forged env nor a forged file can **narrow**…"); `:143-144`'s "narrow the scan **to nothing**"
  is accurate. **Fix:** tighten the comment; optionally give `/wrap` a trusted-base derivation. *Residual
  inherited; overclaiming comment new (`9835640`).* (Converged on by 4 agents.)
- **L-Eval1 — gate-control integrity omits `.claude/agents/evaluator.md`.** The 7-file `GATE_CONTROL_FILES`
  list covers the executable gate code + allowlist but not the evaluator prompt. Under headless bypass a
  builder could rewrite `evaluator.md` to always emit PASS. **Bounded:** the integrity-checked `tick.sh` +
  pristine-sourced libs still gate any high-stakes/secret change, so a forged-PASS evaluator can only tick
  low-stakes, non-secret, test-green junk. **Fix:** add `.claude/agents/*.md` (≥ `evaluator.md`) to the list,
  or document the residual in SECURITY.md. *New (bounded residual of the flagship fix).*
- **L-Jq1 — `tick.sh:109` uses the M4-weak `jq empty` on the authoritative evidence gate.** doctor.sh already
  migrated to `jq -e 'type'` for M4; tick.sh did not. On Apple jq, malformed evidence passes `jq empty`.
  Backstopped downstream (not a false-tick today). **Fix:** `jq -e 'type' "$EVIDENCE" || refuse …`. *Inherited
  inconsistency.*
- **L-Cli1 — `lint-roadmap.sh` / `next-adr.sh` silently accept unknown flags → false success.** `lint-roadmap.sh
  --stric` (typo of `--strict`) is treated as a filename → "nothing to lint", exit 0. **Fix:** reject
  unrecognized `-*` args (exit 2) before treating a token as a path. *New (surfaced by M12 work).*
- **L-Test2 — Makefile `^test:` regex imprecision.** `test:=hi` (a make *variable*) matches → spurious `make
  test` (a false red, not a false green); `test :` and `GNUmakefile` are missed. *New.*
- **L-Zsh1 — allowlist `sed`-trim breaks under zsh.** `_high-stakes.sh:54`'s nested `$(printf|sed)` errors
  under interactive zsh → allowlist silently disabled (fails *safe* → over-gate). Correct under Bash 3.2.
  **Fix:** pure-shell trim. *Inherited (v2.2.1 C1 fix).*
- **L-Models1 — `reset`/`all=` is non-atomic on a per-file failure.** If a *later* role file is
  missing/malformed, earlier files are already rewritten before the non-zero exit. Only reachable on an
  already-corrupt tree; drift is "toward the requested value." *Inherited.*
- **L-M10 — the exit-3 refuse messages never name the allowlist.** `tick.sh:175,180,189,204`. Security docs
  are thorough, but at the moment of a false-positive block there's no inline pointer to the sanctioned
  escape hatch. **Fix:** one line in the refuse messages. *Partial (M10 docs done, message not).*
- **L-M14 — stale precedence comment.** `.claude/hooks/test-gate.sh:13-16` byte-identical to v2.2.1; still
  lists the pre-fix 3-step resolution, omitting uv/poetry/settings.json + the 5 new ecosystems. Behavior is
  correct (delegates to `resolve_test_cmd`); only the comment misleads. *Not fixed (out of accepted P2 scope).*
- **L-Smoke1 — install-smoke/doctor verify 1 of 10 skills** despite the "full manifest" claim (M13). A
  silently-dropped skill passes both. *New (M13 partial).*
- **L-Test3 — `test-gate.sh` advisory `test-results.json` built via `printf`** can be malformed JSON when the
  resolved command contains `"`/`\`. The *authoritative* `.tick-evidence.json` is immune (`jq -nc --arg`).
  *New, advisory-only.*

### Informational (non-release, flag to maintainer)

- **INFO-Key — a live-looking OpenRouter key (`sk-or-…`) sits in an untracked working-tree scratch file**
  (`MODELCOSTGUARD-MISSION-PROMPT.md:104`). Never committed, explicitly gitignored, won't ship — but it's in
  the working tree. **Delete the file and rotate the key.** Confirms the untracked
  `MODELCOSTGUARD-*`/`SESSIONLENS-*`/`HANDOFF-*`/`REDTEAM-*` scratch belongs to *unrelated* workstreams and is
  correctly untracked.
- INFO: `autopilot.log` lacks iteration boundaries/timestamps; `test-evidence.sh` in a non-git dir writes
  `run_id:""` (harmless — tick refuses on unresolvable HEAD); doctor is verbose on a healthy repo; CI actions
  pinned to mutable tags not SHAs (H7's `main` `curl|bash` hole *is* fixed → `v1.7.7`); inconsistent
  stray-arg exit codes across scripts; `sync.sh` per-iteration `mktemp` not trap-cleaned (leaks on SIGINT).

---

## 11. Previous audit findings status

| Finding | Old severity | v2.3 status | Evidence | Regression test exists & can-fail? | Remaining risk |
|---|---:|---|---|---|---|
| C1 high-stakes self-exempt (allowlist) | Critical | **fixed** | v2.2.0 ticks exit 0; current `tick.sh:173-178` → exit 3 | Yes — `test-tick.sh` 9d, flips red on v2.2.0 | None material |
| C1 self-narrow `HIGH_STAKES_RE` | Critical | **fixed** | v2.2.0 exit 0; current → exit 3 (lib in diff) | Yes — 9e, flips red on v2.2.0 | None |
| C2 sync multi-line `HIGH_STAKES_RE` corruption | Critical | **fixed** | backslash/odd-quote → manual review, `cmp` byte-identical, sources cleanly | Yes — `test-sync.sh`, backslash case uniquely necessary (proven not redundant with `bash -n`) | Over-conservative (fails safe) |
| C3 sync agent `model:` destruction | Critical | **fixed** | frontmatter-less/malformed → manual review, byte-identical | Yes — 17a/17b/17c, flip red on v2.2.0 | None |
| H1 `paths:` narrowing | High | **fixed** | later paths preserved; garbage → manual review | Yes — flips red on v2.2.0 | None |
| H5 / H5b swallowed-counter tests | High | **fixed** | assertions top-level; break one → exit 1 (was exit 0) | Yes — self-referential, proven | None |
| H2 `models.sh reset` false-success + `.tmp` | High | **fixed** | v2.2.1 exit 0 + stray `.tmp`; current exit 1, no `.tmp` | Yes — `test-models.sh`, flips red on v2.2.1 | None |
| M3 `models.sh` not frontmatter-scoped | Medium | **fixed** | body `model:` ignored; malformed FM fails loud | Yes — 3 cases, flip red on v2.2.1 | None |
| H3 doctor blind to deleted `tick.sh`/`sync.sh` | High | **fixed** | v2.2.1 "Installed OK" exit 0; current exit 1, "3 problems" | Yes — `test-doctor.sh` 4 cases | None |
| M4 doctor `jq empty` no-op | Medium | **fixed (doctor)** | Apple jq: `jq empty` exit 0, `jq -e type` exit 4; doctor uses `-e` | Yes — 2 cases | **`tick.sh:109` still uses `jq empty`** (L-Jq1) |
| M11 remediation hint only behind `--fix` | Medium | **fixed** | hint prints on any problem run | Yes | None |
| H4 off-git-root / monorepo install | High | **fixed (install+doctor)** | install refuses subdir; `--allow-subdir` warns; doctor one clear message | Yes — `test-doctor.sh` 2 H4 cases | **`sync.sh` still unguarded** (M-Sync1) |
| H6 README missing `sync.sh` | High | **fixed** | `grep -ci sync README.md` 0→8; layout + "Keeping a project up to date" | n/a (doc) | None |
| H7 unpinned actionlint `curl\|bash` | High | **fixed** | `ci.yml` pins `v1.7.7` | n/a (CI) | Tag (not SHA) pin — INFO |
| M1 forgeable `.phase-grade`/`.tick-evidence.json` | Medium | **fixed (autopilot)** | re-derived in trusted shell; neutralized under autopilot | Indirect | `evaluator.md` not integrity-checked (L-Eval1); `/wrap` procedural |
| **NEW** `.phase-base` forgery (tick) | Critical | **fixed** | forged `=HEAD` → refuse; strict-ancestor both sources | Yes — `test-tick.sh` TICK_BASE matrix, flips red on v2.2.1 | Valid-later-ancestor on `/wrap` (L-Wrap2) |
| **NEW** `.phase-base` re-derivation (autopilot) | Critical | **fixed** | trusted base overrides file; money test #16 | Yes — flips red on pre-fix autopilot.sh | None |
| **NEW** gate-control integrity (autopilot) | Critical | **fixed** | `cmp` 7 files vs `START_REF`; money test #17 | Yes — flips red on pre-fix | Omits `evaluator.md` (L-Eval1) |
| M2 non-pytest/npm deadlock | Medium | **fixed** | go/cargo/make/mvn/gradle + loud fallback; E2E Go → `passed:true` | Yes — `test-test-cmd.sh` | Guidance swallowed in-flow (M-Test1); GUIDE says "optional" |
| M5/M6/M7 sync UX safety | Medium | **fixed** | prompt names only preserved value; informational diff; never-scaffolded refuse | Yes — 3 cases | None |
| M8 retry "never false green" comment | Medium | **fixed (doc)** | comment corrected; retry logic byte-unchanged | n/a | Non-idempotent false-green still possible (now honest) |
| M9 no `/wrap` clean-tree check | Medium | **not fixed (dropped)** | uncommitted secret/HS ticks through `/wrap` | No | M-Wrap1 |
| M10 allowlist docs + refuse message | Medium | **partial** | docs done; refuse message doesn't name allowlist | n/a | L-M10 |
| M12 `--help` footgun | Medium | **fixed** | `run-guard-tests.sh --help` no longer runs the battery; 10 scripts safe | Yes — behavioral | Two scripts accept unknown flags (L-Cli1) |
| M13 install-smoke sample-not-manifest | Medium | **fixed (mostly)** | full manifest + doctor on installed tree; deleting `evaluator.md` → exit 1 | Yes | 1/10 skills checked (L-Smoke1) |
| M14 stale precedence comment | Medium | **not fixed** | `test-gate.sh:13-16` byte-identical to v2.2.1 | No | L-M14 (doc-only) |

**Tally: 20 fixed · 1 partial (M10) · 2 not-fixed (M9, M14) · 0 regressed.** Two "fixed" items have a bounded
carry-over into an unhardened surface (M4→`tick.sh:109`, H4→`sync.sh`).

---

## 12. v2.3-specific findings

- **The centerpiece holds.** The trusted `.phase-base` + gate-control integrity model is real, mechanically
  enforced, honestly documented, and survived a dedicated red team. This is the milestone's reason to exist
  and it delivers.
- **The hardening is headless-focused by design.** Every mechanical backstop (base re-derivation, gate
  integrity, evaluator-change discard, grade/evidence re-derivation) lives in `autopilot.sh`. The in-session
  `/wrap` + `/autopilot-parallel` paths rely on prose + a watching human. This is a coherent, documented
  boundary — but v2.3 introduced/left three residuals on that path (M9, valid-ancestor narrowing, and the new
  comment overclaim), and the security docs occasionally over-summarize it (M-Docs1).
- **New-this-milestone blemishes:** the v2.3 PLAN doc now ships into user projects (M-Ship1), the SECURITY.md
  tick.sh-guard overclaim (M-Docs1), the swallowed `LEAN_TEST_CMD` guidance (M-Test1), and the
  `evaluator.md` gate-integrity omission (L-Eval1).
- **Scope discipline was good.** 13 commits, 28 files, +1086/−79 — exactly matching the CHANGELOG's structural
  claim. No unrelated feature work leaked into the tracked diff (the ModelCostGuard/SessionLens scratch is
  untracked and correctly excluded). Every CHANGELOG "Fixed" claim maps to a concrete fail-closed diff hunk.

---

## 13. Files to rewrite / simplify / split / rename / relocate / remove

- **`install.sh`** — add `PLAN-*.md` to the copy-exclusion `case` (M-Ship1); optionally add its own
  `-h|--help`.
- **`scripts/tick.sh`** — add a `git status --porcelain` clean-tree guard (M9); switch `:109` `jq empty` →
  `jq -e 'type'` (L-Jq1); tighten the `:131-132` comment (L-Wrap2).
- **`scripts/sync.sh`** — add a monorepo/subdir guard mirroring install.sh (M-Sync1); stamp only on applied
  changes (M-Sync2); trap-clean the per-iteration `mktemp` (INFO).
- **`scripts/autopilot.sh`** — add `.claude/agents/evaluator.md` to `GATE_CONTROL_FILES` (L-Eval1); add
  iteration timestamps to `autopilot.log` (INFO).
- **`README.md` + `SECURITY.md`** — correct the `scripts/tick.sh` self-guard attribution (M-Docs1); document
  `--allow-subdir` (F7); reframe `LEAN_TEST_CMD` as required-not-optional.
- **`toolkit-docs/GUIDE.md:847`** — `LEAN_TEST_CMD` no longer "optional" for unsupported stacks.
- **`.claude/hooks/test-gate.sh:13-16`** — delete the stale precedence comment, point to `_test-cmd.sh`
  (L-M14); build `test-results.json` with `jq -n --arg` (L-Test3); stop swallowing the resolver's stderr
  (M-Test1).
- **`scripts/lint-roadmap.sh` / `next-adr.sh`** — reject unknown `-*` flags (L-Cli1).
- **`.github/scripts/install-smoke.sh`** — loop over all 10 skills (L-Smoke1); add a `PLAN-*.md`-leak negative
  assertion.
- **`.claude/lib/_test-cmd.sh`** — tighten the `^test:` Makefile regex + add `GNUmakefile` (L-Test2).
- **`.claude/lib/_high-stakes.sh:54`** — pure-shell trim instead of `sed` (L-Zsh1).
- **Relocate/remove (confirm with maintainer):** the tracked root clutter `AUDIT-JAIMITOS-OS-V2.2.md`,
  `PLAN-v2.2-toolkit-sync.md`, `PRACTICE-PROJECT.md`, `MODELCOSTGUARD-MISSION-PROMPT.md` into a `docs/`
  or gitignored working dir; **delete `MODELCOSTGUARD-MISSION-PROMPT.md` and rotate its key regardless**.
- **Do NOT rename `test-evidence.sh`** — the deferral is correct and documented (many references; its header
  already says "producer, not a test suite").

---

## 14. Prioritized fix plan

### P0 — must fix before tagging/releasing v2.3.0
*None on safety.* The trust boundary holds within its documented threat model; no data loss, no guardrail
bypass, no false-tick of bad work. The tag is not safety-blocked.

### P1 — should fix before tagging (cheap, and conspicuous on a trust-honesty milestone)
1. **M-Ship1** — stop shipping `PLAN-*.md` into target projects (one `case` line + a smoke assertion).
2. **M-Docs1** — correct the `scripts/tick.sh` self-guard overclaim in `README:297-299` + `SECURITY:69-71`
   to match the code and the CHANGELOG.
3. **INFO-Key** — delete `MODELCOSTGUARD-MISSION-PROMPT.md` and rotate the OpenRouter key.
4. Record **M9** and the **`/wrap` valid-ancestor narrowing** (L-Wrap2) as explicit known-limitations if not
   fixed; tighten the `tick.sh:131-132` comment (trivial).

### P1 — should fix soon (next milestone)
5. **M9** — `git status --porcelain` clean-tree guard in `tick.sh`.
6. **M-Sync1** — monorepo/subdir guard in `sync.sh` (mirror `--allow-subdir`).
7. **L-Eval1** — add `evaluator.md` to the gate-control integrity list.
8. **L-Jq1** — `tick.sh:109` → `jq -e 'type'`.
9. **M-Test1 + GUIDE:847 + L-M14** — surface the `LEAN_TEST_CMD` guidance and finish the Phase-5 doc updates.
10. **M-Sync2** — stamp only on applied changes.

### P2 — polish
`--allow-subdir` docs; `lint-roadmap.sh`/`next-adr.sh` unknown-flag rejection; full skills manifest in
install-smoke/doctor; Makefile regex + `GNUmakefile`; zsh-safe allowlist trim; `models.sh` reset atomicity;
allowlist named in exit-3 messages; `autopilot.log` timestamps; SHA-pin CI actions; relocate tracked root
clutter; standardize stray-arg exit codes.

---

## 15. Final release recommendation

### **Safe to tag v2.3.0 — after the P1 pre-tag items (all cheap docs/packaging).**

On pure safety, nothing blocks the tag: the centerpiece survived red-teaming, 20/23 prior findings are fixed
with fail-capable tests, there is no data loss and no guardrail bypass within the documented threat model,
and the suites are green. But two items (M-Ship1: shipping your own PLAN docs to every user; M-Docs1: a
security claim that contradicts your own CHANGELOG) are the wrong blemishes to ship on a trust-boundary
milestone and cost minutes to fix. Fix those two, delete/rotate the stray key, and record M9 +
the `/wrap` narrowing as known-limitations — then tag.

For anyone using it **today**, before the tag: it is **safe for supervised, single-repo use, including
headless autopilot in a sandboxed no-credentials container** — that path is the most hardened surface here.
The residuals are confined to the human-supervised `/wrap` path and the monorepo/subdir case.

---

## 16. Blunt final verdict

### **VERY GOOD.**

This is honest, mechanically-enforced, well-tested trust engineering that measurably improved on v2.2/v2.2.1
and kept its lean character. The centerpiece works and I could not break it within its stated envelope. The
gap between this and "excellent" is small and entirely closeable: a couple of cheap docs/packaging fixes, and
bringing the in-session `/wrap` path up to the same standard as the headless path over the next milestone.

---

## Top 10 findings

*(All real. None Critical or High. Ranked by a blend of severity, blast radius, and how conspicuous each is
on a trust-honesty milestone.)*

1. **M-Ship1 (Medium)** — `install.sh` ships the toolkit's own `PLAN-*.md` dev docs into every user project.
2. **M-Docs1 (Medium)** — README/SECURITY overclaim that editing `tick.sh` forces `tick.sh` exit 3;
   contradicts the code and the CHANGELOG.
3. **M-Wrap1 / M9 (Medium)** — no clean-working-tree check on `/wrap`; an uncommitted secret/high-stakes
   change ticks through unscanned (dropped, not deferred-on-record).
4. **M-Sync1 (Medium)** — `sync.sh` mutates the outer tree in a monorepo/subdir with a false-success report
   (H4 gap).
5. **M-Test1 (Medium)** — the Phase-5 "loud `LEAN_TEST_CMD`" guidance is swallowed by both production
   callers; operators are nudged to skip tests instead.
6. **M-Sync2 (Medium)** — declining every sync update still bumps the version stamp, making it unreliable.
7. **L-Wrap2 (Low-Med)** — valid-later-ancestor `.phase-base` narrowing on `/wrap` + an overclaiming comment
   (`tick.sh:131-132`). Headless-immune; converged on by 4 independent agents.
8. **L-Eval1 (Low-Med)** — gate-control integrity omits `evaluator.md`; a bypass-mode builder could forge a
   PASS-emitting evaluator (bounded to low-stakes test-green junk).
9. **L-Jq1 (Low)** — `tick.sh:109` still uses the M4-weak `jq empty` on the authoritative evidence gate
   (backstopped, but M4 was only half-applied).
10. **INFO-Key** — a live-looking OpenRouter key sits in an untracked working-tree scratch file; delete +
    rotate (won't ship, but real).

---

## v2.3 release readiness

- **VERSION state:** `2.2.1` — intentionally NOT bumped (verified; documented in CHANGELOG + the version/tag rule).
- **Tag state:** no `v2.3.0` tag. Existing tags: `v2.2.1`, `v2.2.0`, `v2.1.0`, `v0.2.0`. (Historical:
  `v2.0.0` was never tagged; `v0.2.0`'s VERSION content reads an older value — both honestly recorded in the
  CHANGELOG "Known limitations," no history rewrite.)
- **Pushed/not pushed:** the v2.3 branch `v2.3.0-trust-maintenance-hardening` is **local, unpushed** (13
  commits ahead of local `master`=v2.2.1). Note `origin/master` is at `v2.2.0`, so even v2.2.1 is unpushed to
  origin — a maintainer choice, consistent with holding the checkpoint.
- **CHANGELOG state:** `## [2.3.0] — unreleased`, accurate and non-inflated (every claim maps to real
  fail-closed code; the deferrals — `test-evidence.sh` rename, `v2.0.0` tag, root scratch relocation — are
  disclosed).
- **User checkpoint still required:** **Yes.** Milestone close + VERSION bump + tag is its own explicit
  checkpoint per CLAUDE.md and the plan; it must not be inferred from a "continue"/"resume".
- **Safe to bump VERSION / tag:** After the P1 pre-tag items (M-Ship1, M-Docs1, key rotation) and an explicit
  human go-ahead. Nothing safety-blocks it.
- **Safe to push:** Only with explicit approval; the branch and even v2.2.1 are deliberately unpushed.

---

## Direct answers

1. **Better than v2.2/v2.2.1?** Yes, clearly — 20/23 prior findings fixed with fail-capable tests, the new
   `.phase-base`/gate-integrity trust model added, zero remaining Criticals (v2.2 had three).
2. **Lean philosophy preserved?** Mostly yes. The everyday UX didn't bloat; the blemishes are shipping dev
   docs + tracked root clutter, not everyday friction.
3. **What is new in v2.3?** Trusted `.phase-base` (autopilot-derived, strict-ancestor-validated); gate-control
   byte-integrity vs `START_REF`; executor forbidden from orchestrator/gate state; `models.sh` H2/M3;
   `doctor.sh` H3/M4/M11 + monorepo detection; `install.sh` H4 subdir refuse/`--allow-subdir`; `_test-cmd.sh`
   go/cargo/make/mvn/gradle + loud fallback; `sync.sh` M5/M6/M7; universal `--help` (M12); install-smoke
   expansion (M13); H7 CI pin; docs (H6/M10); M8 comment.
4. **New hardening useful or over-architected?** Useful, and mechanically enforced where it counts — not
   over-architected. The reliability guarantees are concentrated in choke points (the single tick gate,
   evaluator discard, base re-derivation, gate integrity).
5. **Any regressed guarantee?** No. No regression found; the set-once base logic even cures a latent pre-fix
   self-narrowing bug. Two "fixed" items have bounded carry-over into unhardened surfaces (M4→`tick.sh`,
   H4→`sync.sh`), but nothing previously-guaranteed broke.
6. **Staged agents still useful/well-bounded?** Yes. researcher is tool-enforced read-only; evaluator no-edit
   + headless discard; executor's new gate-control ban is advisory + mechanically backed headless. Planner is
   the softest link.
7. **`/phase` more reliable or just more complex?** More reliable — the added complexity buys mechanical trust
   guarantees; ceremony is proportional to a phase, not a line.
8. **`/models` safe after H2/M3?** Yes — 9/10, injection-airtight, both fixes proven by revert-to-red.
9. **High-stakes allowlist safe after v2.2.1 + v2.3?** Yes — C1 fixed, exact-path matching genuinely exact,
   reason required, strictly subtractive, gate-control edits force supervised. Documented honestly (minus the
   tick.sh-self-guard overclaim, M-Docs1).
10. **Env-independent + multi-ecosystem resolver correct?** Yes — precedence exact, no wrong picks, no
    re-deadlock; residuals are the swallowed guidance (M-Test1) + a slightly loose Makefile regex.
11. **Evidence/tick/autopilot trustworthy?** Under headless autopilot, yes (near-airtight, money-tested). On
    `/wrap`, weaker (M9 + narrowing) but human-supervised and unable to silently push a secret.
12. **`.phase-base` model robust?** Yes for the headless path (9/10, unbroken by the red team). The file-based
    `/wrap` fallback is the weak edge (L-Wrap2).
13. **Can a builder still forge orchestrator state / hide a high-stakes diff?** Not under headless autopilot —
    every attempted forgery and gate-neutering was caught and forced supervised. On `/wrap`, a
    valid-later-ancestor base or a dirty tree can hide a change from the scan (supervised, can't reach a
    remote). `evaluator.md` forging is possible but bounded to low-stakes junk (L-Eval1).
14. **Headless autopilot documented honestly?** Yes — SECURITY.md states the sandbox is load-bearing and a
    fully-malicious builder with shell can still exfiltrate/side-effect; the executor ban is advisory. No
    overclaim (the one exception is the tick.sh-edit attribution, M-Docs1).
15. **`sync.sh` reliable on real projects?** Yes for single-repo use (9/10, no data loss). The monorepo/subdir
    case (M-Sync1) and the decline-still-stamps wart (M-Sync2) are the caveats.
16. **Sync preserves customization after all patch fixes?** Yes — byte-verified across every adversarial value
    from both sides; C2/C3/H1 solidly closed; fails safe to manual review on ambiguity.
17. **Doctor/install/setup trustworthy now?** Yes (9/10) — H3/M4/M11 verified load-bearing on the user's own
    jq; clean brownfield/greenfield/subdir handling.
18. **Monorepo/off-git-root acceptable?** For install + doctor, yes. For sync, not yet (M-Sync1). Documented
    one-repo-per-project assumption is reasonable but should be honored by sync too.
19. **Guard tests actually capable of failing?** Yes — every representative suite was mutation-proven
    (break→red→revert→green); no swallowed-counter; drift-guard enforces coverage; full battery passes
    `</dev/null`.
20. **Docs up to date for v2.3?** Mostly — with the overclaim (M-Docs1), the missing `--allow-subdir` doc, the
    stale `LEAN_TEST_CMD`/`test-gate.sh` comments, and the shipped PLAN docs as the exceptions.
21. **CI/release hygiene acceptable?** Yes — H7 fixed (actionlint pinned), install-smoke expanded, VERSION/tag
    honestly held. Residual: tag- not SHA-pinned actions (INFO).
22. **Tests broad enough for the risk surface?** Yes for the headless trust surface (adversarial, money-tested).
    Gaps: `/wrap` gate path, `evaluator.md` integrity, full skills manifest.
23. **Fix before tagging v2.3?** M-Ship1 (stop shipping PLAN docs), M-Docs1 (correct the tick.sh overclaim),
    rotate the stray key; record M9 + L-Wrap2 as known-limitations.
24. **Fix before v2.4?** M9 clean-tree guard, M-Sync1 monorepo guard, L-Eval1 evaluator integrity, L-Jq1
    tick.sh jq, M-Test1 + GUIDE + L-M14 docs, M-Sync2 stamp semantics.
25. **What must NOT change (already good)?** The trusted-base + gate-integrity architecture, the single
    `tick.sh` gate, the `awk ENVIRON` injection-safety idiom, the fail-safe-to-manual-review sync design, the
    evaluator no-edit + headless discard, the honest SECURITY.md framing of the sandbox, and the deliberate
    non-rename of `test-evidence.sh`.
26. **Blunt final verdict:** **VERY GOOD.**
27. **Final recommendation:** **Safe to tag v2.3.0 after the listed cheap P1 pre-tag fixes** (M-Ship1,
    M-Docs1, key rotation) and explicit human approval; safe today for supervised single-repo use including
    sandboxed headless autopilot.

---

*Audit performed 2026-07-07 against branch `v2.3.0-trust-maintenance-hardening` @ `d5ad9ab`. 11 parallel
adversarial sub-agents; all destructive testing in `/tmp` scratch repos; the repo working tree was read-only
throughout (`git status --short` unchanged but for this report + pre-existing untracked scratch). Guard
battery: `run-guard-tests.sh </dev/null` → exit 0, 14 suites, every representative suite mutation-proven
fail-capable.*
