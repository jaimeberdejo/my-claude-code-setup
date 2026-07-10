# PLAN / HANDOFF — v2.7.0: Act on the v2.6.0 audit

> **Status:** APPROVED scope, NOT yet implemented. Prepared for execution in a **fresh session**.
> **Source:** the independent 6-auditor review `docs/dev/audits/AUDIT-v2.6.0.md` (on branch
> `origin/claude/new-session-7tbpgu`; read its "SÍNTESIS" §4 "las tres cosas que arreglaría mañana",
> §F1/F2, and G12). This plan implements the audit's actionable findings at the scope the user chose.
> **Repo:** `~/projects/Claude_SETUP`. Scaffold lives under `jaimitos-os/`; the `skills/` pack and
> `README.md`/`SECURITY.md`/`CHANGELOG.md` are at the repo root.

---

## 0. Context — why this change

The v2.6.0 audit scored the toolkit **7.5/10 "usable with improvements."** The deterministic core
(`tick.sh` + `_eval-isolation.sh` + the 4-agent pipeline) is judged state-of-the-art and is **not**
touched here. What this plan fixes is the audit's concrete debt: two bounded security gaps, one
manual-path correctness gap, a few cheap accuracy bugs, plus two convergent "you built too much"
trims. Intended outcome: close the real gaps, cut dead surface, and keep CI green — **without
weakening any gate.**

**Scope decisions (locked by the user):**
1. **All concrete fixes** — F1, F2, G12, "3 shared libs"→4, remove obsolete `MultiEdit`.
2. **Retire the native-duplicated skills** — `explain-diff` (≈ `/code-review`) and `ship-check`
   (≈ `/security-review` + `/verify`); add an `auto`-mode-complements note. **Keep `scope-guard`.**
3. **Cut `/autopilot-parallel` only** — the audit's "minimum safe cut". Keep the tick gate, `/phase`,
   in-session `/autopilot`, and headless `scripts/autopilot.sh`.
4. **Add a dbt test runner** to `_test-cmd.sh`.

**Release:** ship as **v2.7.0** (bump `VERSION` + tag) — a separate checkpoint, decided at the end.

---

## 1. Hard rules (do not violate)

- **macOS Bash 3.2** (no `declare -A`, `mapfile`, `${x^^}`, `wait -n`; no `timeout(1)`/`gtimeout`).
- **Do not weaken any gate.** `tick.sh`, `_secret-scan.sh`, `_high-stakes.sh`, `record-grade.sh`,
  gate-control integrity in `autopilot.sh` — behavior-preserving edits only, unless a fix explicitly
  *tightens* a gate (F2, G12 do).
- **CI must stay green.** After the CI-repair session, `master` is green. Every guard manifest is
  cross-checked by a test — a stale reference fails CI. Specifically:
  - `scripts/test-docs.sh:26-39` recomputes the real skill count and fails on any stale "`<N> skills`"
    string, so **every** count mention must be updated when the skill count changes.
  - `scripts/run-guard-tests.sh` has a drift guard: every `scripts/test-*.sh` must be in `TESTS[]`, so
    removing a test means **deleting the file**, not just the array line.
  - `scripts/doctor.sh` + `.github/scripts/install-smoke.sh` carry skill/command manifests that
    `test-doctor.sh`/`install-smoke` assert — keep them in sync.
- **Verify like CI, not just locally.** This session's lesson: several failures were CI-only
  (claude-less runner, BSD-vs-GNU, tool-in-`/usr/bin`). Run the guard suite **with the real `claude`
  masked off PATH** (see §6) before pushing.
- If a check isn't run, mark it `NOT RUN`; if a claim is read-only, mark it `code-inspected only`.

---

## 2. Branch & preconditions

- Base: `master` (currently green, VERSION `2.6.0`). Branch: `fix/v2.7.0-audit-fixes`.
- Leave the pre-existing untracked `AUDIT-JAIMITOS-CLAUDE-SETU-V2.3.0.md` alone.
- The audit lives on a separate remote branch; read it via
  `git show origin/claude/new-session-7tbpgu:docs/dev/audits/AUDIT-v2.6.0.md` (already fetched).

---

## 3. Workstreams (do in this order; commit per §5)

### WS1 — Security & correctness (F1, F2, G12)

**F1 — document the transient add-and-delete-secret blind spot + recommend gitleaks for `--pr`.**
- Behavior (code-inspected): `secret_scan_diff` scans the net `BASE..HEAD` diff, so a secret added in
  one commit and `git rm`'d later within the phase nets to zero and is missed; `--pr` would still push
  the intermediate commit. The real scanners already close it: `_secret-scan.sh:86-98`
  (`LEAN_SECRET_SCANNER=gitleaks|trufflehog`) run the scanner over the range **per-commit** and are
  **fail-closed** if the binary is absent. The gap is purely **documentation** — the audit's only
  ask.
- Anchors: `jaimitos-os/.claude/lib/_secret-scan.sh:46-48,86-98`; the `--pr` push-gate in
  `jaimitos-os/scripts/autopilot.sh` (the finish block that calls `secret_scan_diff "${START_REF}..HEAD"`
  before `git push`).
- Fix (docs only): add a bullet to **`SECURITY.md`** (near the secret-scan / `--pr` discussion) and a
  line to the **`--dangerously-skip-permissions`/`--pr`** notes in **`README.md`**: the regex default
  can miss a secret that's added-then-removed inside one phase; for `--pr`/real coverage set
  `LEAN_SECRET_SCANNER=gitleaks` (commit-by-commit, fail-closed). Mention it in
  `jaimitos-os/.claude/rules/high-stakes.md` if a natural spot exists. No code change.

**F2 — `doctor.sh` lists active `high-stakes-ok:` content markers (symmetry with the path allowlist).**
- Behavior: the path allowlist is reported by doctor for auditability (`doctor.sh:185-204`) but the
  inline, **builder-forgeable** `high-stakes-ok: <reason>` content-suppression marker is not — so a
  suppression can hide silently.
- Anchors: matcher `jaimitos-os/.claude/lib/_high-stakes.sh:113-122` (`HIGH_STAKES_OK_RE`,
  `high_stakes_content_match`); the allowlist-reporting block to **mirror** at
  `jaimitos-os/scripts/doctor.sh:185-204`.
- Fix: add a doctor report block (right after the allowlist block) that greps the tracked tree for
  `high-stakes-ok:` markers (reuse `HIGH_STAKES_OK_RE`, or `git grep -n`), lists each `path:line —
  reason` as an `info`/`warn`, and says "these are suppressions — review them." Bash-3.2 safe; no
  gate behavior change (report-only). Add a `test-doctor.sh` case mirroring the allowlist test: plant
  a marker → doctor lists it; none → silent.

**G12 — bind the manual `/wrap` grade to the tree the evaluator actually graded.**
- Behavior: `record-grade.sh` stamps `run_id = git rev-parse HEAD` at **record** time
  (`jaimitos-os/scripts/record-grade.sh:39`), blind to the graded HEAD; `tick.sh` only checks
  `g_run == HEAD`. Headless closes this via `_eval-isolation.sh` (`eval_snapshot`/`eval_restore` +
  authoritative re-measure); the **manual `/wrap`** path is open (audit G12).
- Anchors: `jaimitos-os/scripts/record-grade.sh:37-42`; `jaimitos-os/scripts/tick.sh` grade check
  (`g_run`); the reusable helpers in `jaimitos-os/.claude/lib/_eval-isolation.sh`
  (`eval_snapshot`, `eval_changed_files`); the flow in `jaimitos-os/.claude/commands/wrap.md`
  (and compare to `phase.md`, which per the v2.6.0 CHANGELOG already snapshots before grading).
- **Executor: first confirm the current `/wrap` flow** (does it already `eval_snapshot` like `/phase`?).
  Then the minimal real fix, reusing existing helpers (do NOT write new isolation logic):
  - If `/wrap` does **not** yet snapshot: wire `eval_snapshot` before the evaluator and
    `eval_changed_files` after — if the grader wrote to the tree, refuse to record/tick and name the
    files (mirror `phase.md`). This binds the grade to the graded tree.
  - Residual either way: make `record-grade.sh` **fail-closed if the tracked tree is dirty** at record
    time (the grade must describe a clean, committed tree). Add a `test-tick.sh`/`test-*.sh` case:
    grader writes a file → manual path refuses.
- Keep it small; if the correct wiring is ambiguous, stop and ask rather than inventing isolation.

### WS2 — Accuracy fixes

**"3 shared libs" → 4.** There are **4** libs (`_secret-scan.sh`, `_high-stakes.sh`, `_test-cmd.sh`,
`_eval-isolation.sh`). Fix the stale "3"/"three" wording and name the 4th:
- `README.md:68` ("7 deterministic shell hooks + **3** shared libs (_secret-scan, _high-stakes,
  _test-cmd)") → 4 + add `_eval-isolation`.
- `README.md:188` ("plus **three** shared libs") → four; and `README.md:199` (the "`_secret-scan.sh`,
  `_high-stakes.sh`, and `_test-cmd.sh` are sourced libraries" sentence) → add `_eval-isolation.sh`.
- `jaimitos-os/toolkit-docs/GUIDE.md:1199` ("**three** shared libs") → four.
- **Add a drift guard** so this can't rot again: extend `scripts/test-docs.sh` with a check that binds
  the declared shared-lib count to the real `ls .claude/lib/_*.sh | wc -l` (mirror its existing
  skill-count binding at `test-docs.sh:26-39`). Grep pattern: `[0-9]+ (shared\|sourced) lib`.

**Remove obsolete `MultiEdit` from skill frontmatter.** `MultiEdit` is a stale tool name in
`disallowed-tools:` lists. After WS5 retires `explain-diff`+`ship-check`, the only remaining occurrence
is **`skills/scope-guard/SKILL.md:5,34`** (+ the catalog wording `skills/README.md:40`). Remove
`MultiEdit` from the frontmatter list and the prose (leave `Edit, Write, NotebookEdit`).
- **Leave the hook matchers alone**: `jaimitos-os/.claude/settings.json:65` and
  `hooks/format-on-edit.sh:2` use `"Write|Edit|MultiEdit"` as a *matcher* — a defensive superset,
  not a stale contract; not in scope.

### WS3 — dbt test runner in the resolver

- Anchor: `jaimitos-os/.claude/lib/_test-cmd.sh` `resolve_test_cmd`, the manifest→runner chain
  (`go.mod`→`go test` `:78`, `Cargo.toml`→`cargo test` `:81`, Makefile+`test:`→`make test` `:84`,
  `pom.xml`→`mvn` `:89`, `build.gradle`→`gradle` `:92`) — each guarded by `command -v <runner>`.
- Fix: add a dbt entry in the chain (place it with the other manifests, after LEAN_TEST_CMD +
  settings.json precedence which stay first): `[ -f dbt_project.yml ] && command -v dbt` →
  `dbt build` (runs models **and** tests; falls to the loud fallback if `dbt` absent, like the others).
  Update the header comment's ordered list.
- Test: mirror an existing manifest case in `jaimitos-os/scripts/test-test-cmd.sh` (`expect_cmd` for
  "dbt_project.yml + dbt on PATH → dbt build"; and a "dbt absent" case that uses the **runner-free
  PATH pattern** just added there — a controlled dir with only the coreutils the harness needs, NOT
  `PATH=/usr/bin:/bin`, because CI runners may ship the tool in `/usr/bin`).

### WS4 — Cut `/autopilot-parallel` (keep everything else)

Delete the command + its test, then scrub every live reference (historical docs excepted). Run
`grep -rln autopilot-parallel . | grep -v '^./.git'` to confirm completeness. Known references:
- **Delete files:** `jaimitos-os/.claude/commands/autopilot-parallel.md` (162 lines),
  `jaimitos-os/scripts/test-autopilot-parallel.sh` (230 lines).
- **Edit — CI-load-bearing (a miss breaks CI):**
  - `jaimitos-os/scripts/run-guard-tests.sh:38` — remove the `test-autopilot-parallel.sh` `TESTS[]`
    entry. **Coupled:** the drift guard (`:55-63`) fails if a `test-*.sh` file exists but isn't listed,
    and the runner (`:65-68`) execs every entry — so you must **delete the test file AND remove line 38**
    together (doing one breaks the build).
  - `jaimitos-os/scripts/doctor.sh:112` — drop `autopilot-parallel` from the `for c in resume wrap
    phase autopilot autopilot-parallel models` command manifest.
  - `.github/scripts/install-smoke.sh:62` — drop `.claude/commands/autopilot-parallel.md` from the
    command manifest.
  - `jaimitos-os/scripts/test-docs-invariants.sh:21,22` — remove BOTH assertions (they grep the
    now-deleted command file: "routes ticking through tick.sh"; "does not claim it can flip checkboxes").
- **Edit — docs/prose (clean cut):** `README.md:65,172,222,244,246-250` (layout comment, command-table
  row, merge-conflicts line, Autonomy "Parallel watchable loop" row, the "Advanced/experimental"
  callout); `jaimitos-os/toolkit-docs/GUIDE.md:67,493,523,537,603,609,1095,1161`; `SECURITY.md:94`;
  `jaimitos-os/.claude/commands/phase.md:15` (reword); `skills/merge-conflicts/SKILL.md:3,20,26`
  (keep the skill — only drop the `/autopilot-parallel` cite; the merge guidance stands alone);
  `skills/README.md:32,61`; `jaimitos-os/.claude/hooks/ownership-nudge.sh:32` (comment only — cosmetic).
  **Note:** `wrap.md` and `jaimitos-os/CLAUDE.md` have NO reference (verified — don't chase them).
- **Leave historical:** `CHANGELOG.md` (append a v2.7.0 note instead), `docs/dev/audits/*`,
  `docs/dev/plans/*`, and the untracked v2.3.0 audit.

### WS5 — Retire `explain-diff` + `ship-check` (keep `scope-guard`)

- **`explain-diff` fully overlaps `/code-review` → delete outright.** **`ship-check` mostly overlaps
  `/security-review`+`/verify`, but Step 3 "Check the paper trail" (`skills/ship-check/SKILL.md:21-22`:
  docs/STATE.md updated? ADR written?) is scaffold-specific and NOT native — preserve it** (fold into
  `wrap.md`/`CLAUDE.md` or another skill) before deleting the dir.
- **Delete dirs:** `skills/explain-diff/`, `skills/ship-check/`.
- **Manifests — CI hard-fail if unchanged:**
  - `jaimitos-os/scripts/doctor.sh:70` `REQUIRED_SKILLS` — remove `ship-check` + `explain-diff`.
  - `.github/scripts/install-smoke.sh:71-72` skill loop — remove both (comment says keep in sync with
    doctor).
- **Counts — CI-enforced** (`test-docs.sh` check #1 recomputes real total/portable and scans
  **only** `README.md` + `skills/README.md` for `[0-9]+ (portable )?skills`; total 18→16, portable
  17→15): **must** fix `README.md:42,69` and `skills/README.md:6,65`. For accuracy (not gated) also fix
  `skills/README.md:6` breakdown "10 workflow"→8, `jaimitos-os/SCAFFOLD.md:20-22`,
  `jaimitos-os/toolkit-docs/GUIDE.md:89,93,1134,1137,1168`, `CONTRIBUTING.md:17`; add a `CHANGELOG.md`
  entry (don't rewrite `:117` history).
- **Prose refs:** `skills/README.md:25,27,39-45,74,88,90,96,98` (table rows, the "three review skills
  report-only" contract, hand-install list, examples, the `scope-guard → explain-diff → ship-check`
  chain); `README.md:44,206,213,215,228` (workflow-count heading, the two bullets, the pre-commit
  chain); `GUIDE.md:1125,1137,1168`.
- **The pre-commit chain** `scope-guard → explain-diff → ship-check`: replace with `scope-guard` +
  native `/code-review` and `/security-review`/`/verify` (state the natives supersede the retired
  skills). Only `scope-guard` remains report-only — fix that wording.
- **auto-mode note (small):** add one line that Claude Code's `auto`-mode is an in-session *semantic
  complement*, **not** a replacement for the deterministic high-stakes gate (it's ignored for
  subagents + aborts under `-p`, so it can't be the headless mechanism). **Primary anchor:**
  `SECURITY.md:73-79` (juxtapose the permission-mode bullet `:73-74` with the "high-stakes gate only
  protects paths YOU point it at / `HIGH_STAKES_RE`" bullet `:75-79`). Secondary: `rules/high-stakes.md:57`.
- **Sanity:** `grep -rln "explain-diff\|ship-check" . | grep -v '^./.git'` should return only
  historical `docs/dev/*` + `CHANGELOG.md` when done.

---

## 4. (reserved)

## 5. Commit plan (separate commits; push at the end after CI-style verification)

1. `fix(secret-scan+high-stakes): document F1 blind spot; doctor lists high-stakes-ok markers` — WS1
   F1+F2 (`SECURITY.md`, `README.md`, `rules/high-stakes.md`, `doctor.sh`, `test-doctor.sh`).
2. `fix(wrap): bind the manual grade to the graded tree` — WS1 G12 (`record-grade.sh`, `wrap.md`,
   maybe `_eval-isolation.sh` wiring, a guard test).
3. `fix(docs+skills): correct shared-lib count; drop stale MultiEdit` — WS2 (`README.md`, `GUIDE.md`,
   `test-docs.sh`, `scope-guard/SKILL.md`, `skills/README.md`).
4. `feat(test-cmd): add a dbt test runner` — WS3 (`_test-cmd.sh`, `test-test-cmd.sh`).
5. `chore(autopilot): remove /autopilot-parallel` — WS4.
6. `chore(skills): retire explain-diff + ship-check (native /code-review, /security-review, /verify)` —
   WS5 (+ auto-mode note).
7. `docs(changelog): v2.7.0 audit-fix notes` — `CHANGELOG.md` `[Unreleased]`.
(End every message with the repo's `Co-Authored-By` trailer.)

## 6. Verification (run BEFORE pushing — mimic CI, which is stricter than a plain local run)

```
# static analysis exactly as CI does (from repo root)
shellcheck -S warning -e SC1090,SC1091 install.sh .github/scripts/*.sh \
  jaimitos-os/scripts/*.sh jaimitos-os/.claude/hooks/*.sh jaimitos-os/.claude/lib/*.sh jaimitos-os/sandbox/*.sh
actionlint -color .github/workflows/ci.yml jaimitos-os/.github/workflows/jaimitos-os-ci.yml
find . -name "*.sh" -not -path "./.git/*" -print0 | xargs -0 -n1 bash -n

# guard suite + install-smoke UNDER A CLAUDE-MASKED PATH (CI has no claude CLI). Build a PATH farm of
# every tool EXCEPT claude, then:
PATH="$FARM" bash jaimitos-os/scripts/run-guard-tests.sh < /dev/null      # all suites green
PATH="$FARM" bash .github/scripts/install-smoke.sh < /dev/null            # PASS
```
Farm recipe (this session's technique): symlink every executable on `$PATH` into a temp dir except
`claude`, then run with `PATH=<that dir>`. This catches the claude-less / manifest failures CI sees.
Then push and confirm the GitHub Actions `scaffold-checks` job is green (`gh run watch <id> --exit-status`).

Targeted checks: doctor lists a planted `high-stakes-ok:` marker (F2); manual grade refuses when the
grader dirties the tree (G12); `test-docs.sh` passes with the new lib-count + skill-count (WS2/WS5);
`resolve_test_cmd` emits `dbt build` on `dbt_project.yml`+dbt and falls through when dbt is absent (WS3);
`grep -rln 'autopilot-parallel\|explain-diff\|ship-check'` returns only historical files (WS4/WS5).

## 7. Release / risks / verdict

- **Release:** after all green, bump `VERSION` → `2.7.0`, promote `CHANGELOG [Unreleased]` → `[2.7.0]`,
  `chore(release): v2.7.0`, tag `v2.7.0`, push master + tag (the repo convention). **Separate
  checkpoint — get explicit go-ahead before the tag push.** Leave prior tags immutable.
- **Risks:**
  - **WS5 count/manifest drift** is the highest-risk item — `test-docs.sh`, `doctor.sh`,
    `install-smoke.sh` all assert the skill set; miss one and CI fails. Use the §6 farm run to catch it
    before pushing.
  - **G12** must not invent new isolation — reuse `_eval-isolation.sh`; if the `/wrap` wiring is
    unclear, stop and ask. It tightens a gate, so re-run `test-tick.sh`/`test-autopilot-gates.sh`.
  - **WS4** merge-conflicts skill reword: don't delete the skill, only its `/autopilot-parallel` cite.
- **Out of scope (audit "don't do"), do NOT attempt:** re-packaging as a native plugin; swapping
  `/autopilot-parallel`'s idea for native agent-teams; ripping out the high-stakes regex for
  `auto`-mode; cutting the whole headless autopilot subsystem (only `/autopilot-parallel` goes now —
  the dated 2026-09-09 keep/cut TODO for the rest stands).
- **Verdict to re-confirm after execution:** the core is untouched and remains SOTA; this plan closes
  the two bounded security gaps + the manual-path grade binding, removes ~400 lines of dead
  `/autopilot-parallel` + two duplicated skills, and adds the day-one dbt runner — moving the toolkit
  back toward "lean" without touching a single guarantee.
