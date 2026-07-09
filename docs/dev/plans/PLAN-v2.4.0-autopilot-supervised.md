# PLAN / HANDOFF — v2.4.0: Autopilot Containment + Supervised Approval

> **Status:** APPROVED plan, NOT yet implemented. Prepared for execution in a **fresh session**.
> **Source of the findings:** the SessionLens dogfood round —
> `docs/audits/DOGFOOD-ROUND4-SESSIONLENS-V2.3.1.md` (this repo). Read its §6 (autopilot runaway)
> and §9 M3-retro (supervised dead-end) for the raw evidence.
> **Scratch copy of the same plan:** `~/.claude/plans/kind-soaring-parasol.md` (session-scoped; this
> file is the durable one).

---

## 0. How to execute this handoff (fresh session kickoff)

1. `cd ~/projects/Claude_SETUP` and confirm you're on `master` with a clean tree (the untracked
   `AUDIT-JAIMITOS-CLAUDE-SETU-V2.3.0.md` is pre-existing — leave it).
2. Read THIS file top to bottom. §5 (Exploration Appendix) has every code anchor you need — you
   should NOT have to re-explore the scripts.
3. `git checkout -b fix/dogfood-autopilot-supervised`.
4. Work the task checklist in §8, in order (P0 → P1 tick → P1 milestone → P1 docs). Commit per §7.
5. Verify per §6. Report per the "Final report" shape in §9.
6. **Do NOT push, do NOT tag, do NOT bump VERSION.** Do NOT run real `claude` or
   `--dangerously-skip-permissions` in tests — use the fake-`claude` stub (§5.4).

**Hard rules (do not violate):** macOS Bash 3.2 only (no `wait -n`, no `timeout(1)`/`gtimeout`, no
`declare -A`, no `mapfile`/`readarray`, no `${x^^}`). Do not weaken `tick.sh`. Do not make
supervised phases auto-tickable. Do not bypass secret/high-stakes scanning. No broad refactors.
If a check isn't run, mark it `NOT RUN`; if a claim is from reading only, mark it
`code-inspected only`.

---

## 1. Context & goals
A real headless dogfood run of v2.3.1 found:
- **Critical (P0):** `scripts/autopilot.sh --dangerously-skip-permissions` spawned a runaway of
  ~9–13 concurrent `claude` processes. `AGENT_STOP` didn't stop it, `kill -TERM` didn't; only
  `kill -9` did. `autopilot.log` was empty. **Root cause:** builder + evaluator run **foreground
  with no per-child timeout**, and `AGENT_STOP` is only checked **between iterations**, so a wedged
  child (and its nested `claude --agent` subtree) blocks the parent and can't be signalled.
- **High (P1):** `Mode: supervised` phases are un-tickable (`tick.sh` `exit 3` unconditionally, no
  approval path), so a roadmap with one can never close via `close-milestone.sh` (Modo B).

**Goal:** contain autopilot's children (watchdog + timeout + working AGENT_STOP, fail-closed on
cleanup failure, non-empty log); add an explicit, auditable supervised-approval tick path that does
NOT weaken any gate; make milestone-close messaging distinguish the cases; correct the docs. Ship
as **v2.4.0** (separate checkpoint — this patch does not bump/tag).

---

## 2. Branch & preconditions
- Base: `master` @ `10ee0ca` (or later). Branch: `fix/dogfood-autopilot-supervised`.
- The concurrency-refusal requirement is **already met** by the existing noclobber PID lock — do
  not re-implement it (see §5.1).

---

## 3. THE PLAN

### P0 — Contain headless autopilot child processes  (`jaimitos-os/scripts/autopilot.sh`)
Add two helpers and re-wire the two `claude` invocations + traps.

- **`terminate_child_tree <pid> [SIG]`** — depth-first: for each `pgrep -P <pid>` descendant,
  recurse, then `kill -SIG <pid>`. Portable (`pgrep -P` on macOS+Linux). Best-effort; document the
  orphan/re-parent limitation. Prefer killing a **process group** (`kill -SIG -<pgid>`) when the
  child was started as a group leader (see below).
- **`run_child_with_watchdog <stdout_file> <timeout_secs> <label> -- <cmd...>`:**
  1. Start the child **backgrounded**, preferably as a **process-group leader** if `setsid` (or
     `perl -e 'setpgrp; exec @ARGV' -- ...`) is available — record PGID; else plain `&` + `$!`.
     Store globals `CURRENT_CHILD_PID` / `CURRENT_CHILD_PGID` so traps can reach it.
  2. Redirect child **stdout → `<stdout_file>`**, **stderr → `autopilot.log`** (a hung/killed child
     still leaves diagnosable output — fixes the empty log).
  3. Poll every `POLL_INTERVAL` (default 5s) while alive, checking **(a) timeout exceeded,
     (b) `AGENT_STOP`** in worktree CWD or `ORIG_ROOT` (reuse the `315-317` condition — THIS is what
     makes AGENT_STOP work during a child run), **(c) the lock still holds our PID**.
  4. On any breach → `terminate_child_tree TERM`; `sleep 2`; if still alive `... KILL`; if STILL
     alive → **fail-closed**. Return rc: `124` timeout, `125` AGENT_STOP, `126` lock-lost,
     `127` cleanup-failed; else the child's own rc.
  5. Emit lifecycle lines (autopilot pid, child pid/pgid, label, timeout, stop reason, cleanup
     result) to **both `autopilot.log` and stderr** (visible regardless of CWD).
  6. Clear `CURRENT_CHILD_*` on return.
- **Wire-in:**
  - Builder (`autopilot.sh:341-343`): replace `claude -p "/phase" ... | tee` with
    `run_child_with_watchdog "$BUILDER_OUT" "$CHILD_TIMEOUT" builder -- claude -p "/phase" "${CLAUDE_PERM_FLAGS[@]}"`
    then `cat "$BUILDER_OUT" >> autopilot.log`. rc ≥124 → log + `break` (never reaches grade/tick).
  - Evaluator (`autopilot.sh:398-399`): run via watchdog to `$EVAL_OUT`, then `VERDICT=$(cat "$EVAL_OUT")`;
    rc ≥124 → treat as failure + `break`.
  - Traps (`autopilot.sh:129-131`): `cleanup_on_exit` also `terminate_child_tree "$CURRENT_CHILD_PID"`
    (TERM→KILL) if set; change `trap 'exit 130' INT` / `trap 'exit 143' TERM` to handlers that
    terminate the child tree first, then exit (satisfies "SIGTERM to parent triggers cleanup").
  - Fail-closed push: new `RUN_ABORTED=1` on any watchdog rc ≥124; OR it into the existing no-push
    guard (keyed on `HS_BLOCKED`, `--pr` finish block ~`autopilot.sh:509+`).
  - Config: `CHILD_TIMEOUT` ← env `AUTOPILOT_CHILD_TIMEOUT` (default 1200s/20min); `POLL_INTERVAL`
    default 5s. Print resolved `autopilot.log` absolute path + worktree at loop start.
- **Tests** (extend `test-autopilot-gates.sh`, reuse its fake-`claude` stub `:34` + `mkrepo` `:102`
  + `run()` `:141`; add stub env-modes; use short `AUTOPILOT_CHILD_TIMEOUT`/`POLL_INTERVAL`):
  (1) normal exit → proceeds; (2) infinite sleep → timeout kills + no tick; (3) spawns child then
  sleeps → child gone after cleanup (or document re-parent limitation + assert parent gone);
  (4) `AGENT_STOP` during sleep → killed without a tool hook (not at an iteration boundary);
  (5) SIGTERM to parent during sleep → child terminated, no orphan; (6) concurrent invocation
  refused (existing lock); (7) cleanup-failure → `RUN_ABORTED` prevents tick/push; (8) fake writes
  output → `autopilot.log` non-empty (empty-log regression).

### P1 — Supervised approval  (`tick.sh`, `.gitignore`, `test-tick.sh`)
- **Interface:** `bash scripts/tick.sh --supervised-approved "<phase title>" --note "<note>"`.
  Add a flag loop mirroring `close-milestone.sh:20-31`, but the `*)` case captures the bare
  positional heading (keep the `.claude/.phase-ready` fallback at `tick.sh:85`). Update `-h/--help`.
- **Artifact:** `.claude/.supervised-approval` — key=value like `.phase-grade`
  (`record-grade.sh:37-42`): `run_id=<HEAD>`, `title=<exact heading>`, `approved_at=<UTC>`,
  `note=<note>`. **Add explicit `.gitignore` entry** in the state block (`.gitignore:8-14`) — the
  ignore list is per-file (no wildcard), so this is required.
- **Behavior — override ONLY the supervised block (`tick.sh:199-210`), nothing else.** Replace the
  `*supervised*)` body with a call to `supervised_approval_valid "$heading"`:
  - `--supervised-approved` passed this run → **write** the approval file (bound to HEAD + heading +
    now + note), return valid → fall through to open-item + tick.
  - else → **read** `.claude/.supervised-approval`; valid iff well-formed AND `title==heading` AND
    `run_id==HEAD` (same freshness idiom as the grade check `tick.sh:104`). Else invalid.
  - invalid → existing `exit 3` **plus** a line telling the human how to approve.
  - **Why safe:** grade-PASS (99-105), evidence (107-123), secret (161-167), GATE_CFG (169-182),
    high-stakes PATH (183-187) + CONTENT (188-197) all run ABOVE the supervised block → approval
    cannot bypass any of them. Heading match (78-94) + open-item (212-219) below stay intact.
- **Tests** (add to `test-tick.sh`): no-approval refuses; valid approval ticks; old-SHA-after-commit
  refuses; wrong-title refuses; malformed refuses (fail-closed); does NOT bypass a planted secret;
  does NOT bypass a high-stakes path; does NOT allow a heading absent from ROADMAP.

### P1 — Milestone close  (`close-milestone.sh`, `test-close-milestone.sh`, `milestone/SKILL.md`)
- Keep the unchecked-`- [ ]` refusal (`close-milestone.sh:41`); replace its flat message with a
  classifier over the first open phase (reuse tick.sh's `Mode:` awk `201-205`): (a) normal
  incomplete, (b) supervised awaiting approval (name it + point at `--supervised-approved`),
  (c) gate-blocked if `NEXT_FINDINGS.md` present.
- Approved+ticked supervised phase is `- [x]` → no longer blocks. Document the flow in
  `milestone/SKILL.md` Modo B. **Do NOT** implement milestone-slice closure — note as follow-up.
- Tests: unapproved supervised phase → can't close, message names it; approved+ticked → closes.

### P1 — Docs (surgical; anchors in §5.5)
- `CLAUDE.md:48` + `README.md:193`: AGENT_STOP is now **parent-polled during a child run and kills
  the child tree** (was between-iterations only, so a wedged child ignored it).
- `commands/autopilot.md:11`: note intra-child polling + per-child timeout.
- `commands/autopilot-parallel.md:93-96`: **do-not-use warning** until it inherits containment.
- `SECURITY.md:51,77,83` + `README.md:231-234,308-312`: keep `--dangerously-skip-permissions`
  **sandbox-only**; add that AGENT_STOP now works at parent level + a per-child timeout exists, but
  arbitrary local execution under bypass is still the reason for sandbox-only.
- `commands/phase.md` + `wrap.md`: supervised phases complete via `tick.sh --supervised-approved`.
- `rules/high-stakes.md`: fix an over-broad `HIGH_STAKES_RE` in a commit **before** the blocked
  phase's base (GATE_CFG forbids fixing it inside the phase); tag the code that **touches** the data,
  not code near a feature (stats-only export/dashboard ≠ high-stakes; the redaction path is).

### P2 — Only if trivial while editing
Note that dogfooding should start from the target-project root (so slash commands/skills register);
add the two high-stakes examples above. Skip anything that grows.

---

## 4. (reserved)

## 5. EXPLORATION APPENDIX — code-grounded anchors (so you don't re-explore)

### 5.1 `autopilot.sh` process model (535 lines)
- Perm flags built once `92-96` (`CLAUDE_PERM_FLAGS=(--dangerously-skip-permissions)` or
  `(--permission-mode acceptEdits)`; `SKIP_PERMISSIONS` set by arg `:61`).
- `ORIG_ROOT` `:109`. Preflight `111-167`.
- **Lock (already meets P0 concurrency): `114-150`** — `LOCK="$ORIG_ROOT/.claude/.autopilot.lock"`
  `:117`, `LOCK_HELD` `:118`, atomic acquire via `set -o noclobber` `136-150`, PID liveness
  `kill -0` refuses a live concurrent run, reclaims a stale one.
- `cleanup_on_exit()` `119-127` (releases lock; leaves worktree on abnormal exit); `trap
  cleanup_on_exit EXIT` `:129`; `trap 'exit 130' INT` `:130`; `trap 'exit 143' TERM` `:131`.
  **No child-kill logic in traps today.**
- `claude` on PATH check `:153`. Worktree create `171-177` (`WT_DIR` `:174`, `cd "$WT_DIR"` `:177`
  → this is why `autopilot.log` lives in the throwaway worktree). `START_REF=$(git rev-parse HEAD)`
  `:194`.
- Loop `for i in $(seq 1 "$MAX_ITER"); do` `313-502`.
- **AGENT_STOP checked ONLY at `315-317`** (`[ -f AGENT_STOP ] || [ -f "$ORIG_ROOT/AGENT_STOP" ]`),
  between iterations. **Parent never polls it during a child run** (confirmed).
- STEER mirror `322-324`; `OPEN_SIGNATURE` `:326`; trusted `PHASE_BASE` `333-336`.
- **BUILDER `341-343`:** `if ! claude -p "/phase" "${CLAUDE_PERM_FLAGS[@]}" 2>&1 | tee -a autopilot.log; then ... break; fi` (foreground).
- phase-ready gate `352-360`; override `.claude/.phase-base` with trusted base `368-370`;
  `bash scripts/test-evidence.sh --allow-no-tests >>autopilot.log` `:378`; pre-grade snapshot `384-386`.
- `GATE_CONTROL_FILES` `:294`; `gate_control_intact()` `295-311` (byte-compares each vs `${START_REF}:$p`
  via `git show | cmp -s`); called `:463`.
- **EVALUATOR `398-399`:** `VERDICT=$(claude --agent evaluator -p "Grade the phase just completed." "${CLAUDE_PERM_FLAGS[@]}" 2>>autopilot.log)` (stdout→VERDICT, stderr→log).
- empty-verdict gate `401-406`; `cleanup_eval_changes` `:410`; last-line parse `:419`; case `421-501`.
- record-grade `:436`; re-measure evidence `:453`; **TICK `468-469`:**
  `TICK_BASE="$PHASE_BASE" bash scripts/tick.sh 2>&1 | tee -a autopilot.log; TICK_RC="${PIPESTATUS[0]}"`.
  Branches `470-496`: `0)` commit + reset counters; `3)` `HS_BLOCKED=1` + `break`; `*)` `git reset -q`
  + `break` (no explicit `1)` arm). Worktree-removal instructions at `:511`, `:532`.
- **Empty-`autopilot.log` causes:** (a) log written to CWD = worktree (`:177`), invisible from
  ORIG_ROOT; (b) preflight uses stderr only → preflight exit = no log; (c) hung headless child emits
  nothing into `tee` (no timeout) → empty; (d) evaluator stdout captured to VERDICT, not the log,
  at capture time.
- **Bash 3.2:** file is already 3.2-safe. Uses indexed arrays, `PIPESTATUS`, `[[ =~ ]]`, process
  substitution, `md5||md5sum`, `date -u ...||echo`. **Do NOT** add `declare -A`, `mapfile`,
  `${x^^}`, `wait -n`, or assume `timeout(1)`/`gtimeout` (absent on stock macOS) — the watchdog must
  be a manual background-timer + `kill` pattern.

### 5.2 `tick.sh` check order (237 lines) — supervised override goes INSIDE `199-210`, after all gates
`refuse()` `30-34`; `update_state()` `36-76`. Then in order: heading parse (positional only; no flag
loop) `78-94` (`-h/--help` `79-88`; `heading=${1:-}` then `.claude/.phase-ready` fallback `:85`);
HEAD+jq `96-97`; **grade PASS + `run_id==HEAD`** `99-105` (`grep -E '^run_id=' | cut -d= -f2-`;
compare `:104`); **fresh evidence `run_id==HEAD`** `107-123` (`jq -e type`; `.run_id`; compare `:116`);
BASE derivation + source `_secret-scan.sh`/`_high-stakes.sh` `125-159`; **secret scan** `161-167`;
**GATE_CFG anti-self-exempt (exit 3)** `169-182`; **high-stakes PATH (exit 3)** `183-187`;
**high-stakes CONTENT (exit 3)** `188-197`; **`Mode: supervised` (exit 3)** `199-210` (awk
`PHASE_MODE` `201-205`; `case *supervised*) ... exit 3` at `:209`); **roadmap open-item** `212-219`;
**tick + verify count dropped** `221-232`; cleanup + `update_state` + `exit 0` `234-237`.
> All secret/high-stakes/grade/evidence checks are ABOVE `199-210`, so a supervised override there is
> safe. Argv is positional-only → you must add a flag loop (mirror `close-milestone.sh:20-31`).

### 5.3 Evidence/grade binding model (mirror it for the approval file)
`record-grade.sh:37-42` writes `.claude/.phase-grade` = `run_id=$(git rev-parse HEAD)` + `verdict=PASS`
+ `no_tests_ok=...`. `test-evidence.sh:40-62` writes `.claude/.tick-evidence.json`
(`OUT_FILE` `:40`, `HEAD` `:42`, `emit()` `49-62` via `jq -nc --arg run_id "$HEAD"` `:58`).
Freshness = stored `run_id` must equal current HEAD (new commit → stale → refuse). `.claude/.supervised-approval`
should use the same key=value + `run_id==HEAD` invalidation; fail closed on missing/malformed.

### 5.4 `close-milestone.sh` + test harness + .gitignore
- `close-milestone.sh`: flag loop `20-31` (`--name` pattern to copy); `refuse()` `:33`; gates `40-42`
  — **open-item detector + flat refuse is line 41**; `NEXT_FINDINGS.md` check `:42`.
- **`.gitignore` is per-file (NO wildcard)** — state entries `6-14` (`.phase-ready` `:6`,
  `.tick-evidence.json` `:10`, `.phase-base` `:11`, `.phase-grade` `:12`, `.autopilot.lock` `:13`,
  `.last-changed` `:14`). A new `.claude/.supervised-approval` **must be added explicitly**.
- Test harness: `test-autopilot-gates.sh` has an **env-driven fake `claude` stub** `:34`, `mkrepo`
  `:102`, and `run() { ... PATH="$BIN:$PATH" LEAN_TEST_CMD=true bash scripts/autopilot.sh "$@"; }`
  `:141`. `run-guard-tests.sh` has `TESTS=()` `32-48` + a drift guard `49-56` (every
  `scripts/test-*.sh` must be listed; `test-evidence.sh` excluded). `.github/scripts/install-smoke.sh`
  exists (~9.3 KB).

### 5.5 Docs anchors to edit
`CLAUDE.md:48` ("touch AGENT_STOP halts the loop at the next tool call"); `README.md:193`
(kill-switch row), `:223`, `:231-234`, `:308-312` (skip-permissions/sandbox);
`commands/autopilot.md:11` ("Check controls first, every iteration");
`commands/autopilot-parallel.md:26,49,93-96` (AGENT_STOP only preflight + before each integration;
worktree agents have no own AGENT_STOP check); `SECURITY.md:51,77,83` (skip-permissions);
`commands/phase.md`, `commands/wrap.md`, `skills/milestone/SKILL.md` (supervised wording);
`rules/high-stakes.md` (no existing pre-phase gate-fix guidance — add it).

---

## 6. Verification
```
bash jaimitos-os/scripts/test-autopilot-gates.sh
bash jaimitos-os/scripts/test-tick.sh
bash jaimitos-os/scripts/test-close-milestone.sh
bash jaimitos-os/scripts/run-guard-tests.sh < /dev/null
bash .github/scripts/install-smoke.sh
find . -name "*.sh" -not -path "./.git/*" -print0 | xargs -0 -n1 bash -n
command -v shellcheck >/dev/null 2>&1 && find . -name "*.sh" -not -path "./.git/*" -print0 | xargs -0 shellcheck -S warning -e SC1090,SC1091
```
Plus the 6 manual fake-`claude` simulations (normal / infinite-sleep / spawns-child / AGENT_STOP-during
/ SIGTERM-to-parent / concurrent-lock), short `AUTOPILOT_CHILD_TIMEOUT`. Report any `NOT RUN` /
`code-inspected only`.

## 7. Commit plan (separate commits; DO NOT push, DO NOT tag)
1. `fix(autopilot): contain headless child processes` — autopilot.sh, test-autopilot-gates.sh,
   README.md, SECURITY.md, commands/autopilot.md, commands/autopilot-parallel.md.
2. `feat(tick): add supervised phase approval` — tick.sh, .gitignore, test-tick.sh,
   commands/phase.md, commands/wrap.md.
3. `fix(milestone): handle supervised approval lifecycle` — close-milestone.sh,
   test-close-milestone.sh, skills/milestone/SKILL.md.
4. `docs(dogfood): record SessionLens safety follow-ups` — CHANGELOG.md, rules/high-stakes.md.
(End commit messages with the repo's `Co-Authored-By` trailer.)

## 8. Task checklist (work in order)
- [ ] Branch `fix/dogfood-autopilot-supervised`.
- [ ] P0: `terminate_child_tree` + `run_child_with_watchdog` in autopilot.sh; re-wire builder (341),
      evaluator (398-399), traps (129-131), `RUN_ABORTED` no-push; config + startup log path.
- [ ] P0 tests: 8 cases in test-autopilot-gates.sh (fake-claude modes; short timeout).
- [ ] Commit 1.
- [ ] P1 tick: flag loop + `.supervised-approval` + `supervised_approval_valid` override in the
      `199-210` block; `.gitignore` entry.
- [ ] P1 tick tests: 8 cases in test-tick.sh.
- [ ] Commit 2.
- [ ] P1 milestone: classifier message in close-milestone.sh; SKILL.md doc; 2 tests.
- [ ] Commit 3.
- [ ] P1 docs: the surgical edits in §5.5; CHANGELOG entry.
- [ ] Commit 4.
- [ ] Run §6 verification; record results.

## 9. Risks / rollback / release / verdict
- **Risks:** the Bash-3.2 watchdog is subtle (background child + poll + recursive `pgrep -P` kill;
  a re-parented grandchild can escape — mitigated by preferring a process-group leader when
  `setsid`/`perl` exists; document + test the limitation). Builder loses live `tee` streaming
  (mitigated by stderr heartbeats). Approval staleness must fail closed (tests 3–5).
- **Rollback:** everything is on the branch; `git checkout master` reverts. Each concern is its own
  commit.
- **Release:** **v2.4.0** (adds the approval path). Do NOT bump VERSION / tag / push here — separate
  checkpoint.
- **Final-report shape:** root cause; containment design; is the fake runaway killed?; does
  AGENT_STOP work at parent level?; are logs useful?; approval interface; milestone behavior; files
  changed; commits; tests run; manual sims run; remaining risks; release classification; **blunt
  verdict: safe to headless-autopilot again, or not.**
- **Expected verdict (re-confirm after tests):** with the watchdog, headless autopilot is safe again
  **in a sandboxed / no-prod-credentials environment**; it is NOT made safe to run
  `--dangerously-skip-permissions` on a machine with real credentials, and `/autopilot-parallel`
  should stay disabled until it inherits the same containment.
