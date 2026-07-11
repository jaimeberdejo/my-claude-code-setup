#!/usr/bin/env bash
# autopilot.sh — fresh-context autonomous loop with guardrails.
#
# Runs roadmap phases one at a time, each in a FRESH claude process (so context
# never rots), grading each with an INDEPENDENT evaluator process before ticking.
# The SCRIPT is the sole roadmap-ticker — the builder never marks its own work done.
# State persists in docs/ + git between iterations.
#
# Usage:
#   bash scripts/autopilot.sh [COUNT] [--allow-dirty] [--no-worktree] [--pr] [--dangerously-skip-permissions] [--i-understand-no-sandbox]
#     COUNT can be:
#       N         run up to N phases   (e.g. 5  → "only 5")
#       N-M       run up to M phases, aiming for at least N  (e.g. 3-5 → "from 3 to 5")
#       all|max   run until the roadmap is empty or a guardrail trips (capped at 50 for safety)
#       (omitted) default 15
#     Malformed counts (e.g. 5x, 3-) are rejected, not silently ignored.
#     --no-worktree    run IN-PLACE in the current checkout instead of an isolated
#                      worktree. Isolation is the DEFAULT (a bad run can't touch your
#                      main checkout); pass this only when you accept that risk.
#     --pr             on finish, push the branch and open a PR with `gh` (only meaningful
#                      with the default worktree; nothing is ever pushed to your current
#                      branch). A secret-scan gate runs before any push.
#     --allow-dirty    skip the clean-tree preflight (commit/stash is otherwise required)
#     --dangerously-skip-permissions   run the builder and evaluator with ALL permission
#                      checks skipped (same flag name as the `claude` CLI's own). Without
#                      a TTY, `--permission-mode acceptEdits` (the default) CANNOT approve
#                      writes to `.claude/` or Bash commands like the test suite — a truly
#                      headless run needs this to complete even one phase. Use ONLY in a
#                      sandboxed container with NO production credentials. If no sandbox SIGNAL
#                      is detected (JAIMITOS_SANDBOXED env, /.dockerenv, or a container cgroup),
#                      this flag is REFUSED unless --i-understand-no-sandbox is also passed.
#                      The supported path is the wrapper: sandbox/run-autopilot-sandboxed.sh.
#     --i-understand-no-sandbox   run --dangerously-skip-permissions on a bare host anyway (no
#                      sandbox signal). Prints an unmistakable banner and records it in
#                      autopilot.log. A reminder, not a boundary — the signals are forgeable.
# Stop:    touch AGENT_STOP
# Steer:   echo "use Decimal not float for money" > STEER.md
#
# Guardrails: preflight, max iterations, kill-switch, fresh context per loop,
# independent evaluator with STRICT verdict parsing + evaluator-change cleanup,
# per-phase thrash cap, the script as sole ticker, high-stakes gate, shared
# secret-scan before commit/push, default worktree isolation. Set a budget cap in
# your Claude Code / gateway config as the authoritative outer backstop on real cost.

set -uo pipefail

MAX_ITER=15
MIN_TARGET=0
UNBOUNDED=0
ALLOW_DIRTY=0
USE_WORKTREE=1         # isolation is the DEFAULT; --no-worktree opts out
OPEN_PR=0
HS_BLOCKED=0          # set to 1 if a high-stakes phase tripped the gate (never push it)
SKIP_PERMISSIONS=0    # --dangerously-skip-permissions opts INTO bypassing all permission checks
ACK_NO_SANDBOX=0      # --i-understand-no-sandbox: run bypass OUTSIDE a sandbox anyway (explicit)
RUN_ABORTED=0         # set to 1 if the child watchdog aborted the run (timeout / AGENT_STOP / lock / cleanup) — never push
RUN_RESULT="failed"   # F1: the SINGLE authoritative publication decision. Defaults NON-publishable; only a
                      # COMPLETE, fully-successful requested run flips it to "success". Push/PR requires it.
CURRENT_CHILD_PID=""  # pid of the in-flight builder/evaluator child, so traps + cleanup can reach it
CURRENT_CHILD_PGID="" # its process-group id when we started it as a group leader (whole-subtree kill)
# Per-child wall-clock cap (default 20 min) + watchdog poll cadence. The child runs BACKGROUNDED and
# the parent polls, so a wedged headless `claude` (and its nested `claude --agent` subtree) is timed
# out / stop-able instead of blocking the parent forever. macOS has no timeout(1)/gtimeout, so this is
# a hand-rolled background-timer + kill loop (see run_child_with_watchdog).
CHILD_TIMEOUT="${AUTOPILOT_CHILD_TIMEOUT:-1200}"
POLL_INTERVAL="${AUTOPILOT_POLL_INTERVAL:-5}"
for arg in "$@"; do
  case "$arg" in
    -h|--help)
      echo "usage: autopilot.sh [COUNT] [--allow-dirty] [--no-worktree] [--pr] [--dangerously-skip-permissions] [--i-understand-no-sandbox]"
      echo "  COUNT: N | N-M | all|max (default 15). Headless loop: builds each roadmap phase in a fresh"
      echo "  process, grades it with an independent evaluator, and ticks via scripts/tick.sh. See the"
      echo "  header of this script for the full flag reference and safety notes."
      exit 0 ;;
    --allow-dirty) ALLOW_DIRTY=1 ; continue ;;
    --worktree)    USE_WORKTREE=1 ; continue ;;            # explicit (already the default)
    --no-worktree) USE_WORKTREE=0 ; continue ;;            # opt out of isolation
    --pr)          OPEN_PR=1 ; continue ;;
    --dangerously-skip-permissions) SKIP_PERMISSIONS=1 ; continue ;;
    --i-understand-no-sandbox) ACK_NO_SANDBOX=1 ; continue ;;  # run bypass outside a sandbox anyway
    all|max|ALL|MAX) MAX_ITER=50; UNBOUNDED=1 ; continue ;;  # advance as much as you can
  esac
  # Numeric COUNT forms — anchored validation; reject malformed loudly (no silent ignore).
  if [[ "$arg" =~ ^[0-9]+$ ]]; then
    MAX_ITER="$arg"
  elif [[ "$arg" =~ ^[0-9]+-[0-9]+$ ]]; then
    MIN_TARGET="${arg%%-*}"; MAX_ITER="${arg##*-}"
  else
    echo "autopilot: unrecognized argument '$arg'." >&2
    echo "  expected: N | N-M | all | --no-worktree | --worktree | --allow-dirty | --pr | --dangerously-skip-permissions | --i-understand-no-sandbox" >&2
    exit 1
  fi
done

# Built once, used for both the builder and evaluator invocations below. Default
# (acceptEdits) matches Claude Code's own permission modes; without a TTY it CANNOT
# approve writes to .claude/ or non-trivial Bash commands (e.g. the test suite) —
# confirmed by dogfooding against a real (non-stubbed) `claude` binary, not just the
# mocked-CLI test suite. --dangerously-skip-permissions is the only thing that lets a
# truly headless run complete a phase; it trades away the permission boundary entirely,
# so it's opt-in, never the default.
#
# A NARROWER headless profile was investigated and is NOT currently possible: a scoped
# `permissions.allow` list (+ `--permission-mode dontAsk`) CAN auto-approve git/test Bash
# calls, but `.claude/` is a Claude-Code PROTECTED PATH whose writes are denied in every
# mode except bypass — even with an explicit `Write(.claude/**)` allow rule. Since /phase
# writes .claude/.phase-base and .claude/.phase-ready from inside the session, no allowlist
# can replace bypass unless those state-writes are moved OUT of the claude process (a change
# to /phase's contract, deferred). So today: headless == --dangerously-skip-permissions ==
# sandbox-only. (Verified against Claude Code docs/CLI, 2026-07.)
if [ "$SKIP_PERMISSIONS" -eq 1 ]; then
  CLAUDE_PERM_FLAGS=(--dangerously-skip-permissions)
else
  CLAUDE_PERM_FLAGS=(--permission-mode acceptEdits)
fi

# Sandbox SIGNALS (a reminder, NOT a security boundary — an env var is forgeable and /.dockerenv
# can be faked; treat these as hints, not proof). Computed once here so the refusal below runs
# BEFORE any side effect (lock, worktree), and the banner further down can reuse it. Two
# independent hints: the wrapper's marker (JAIMITOS_SANDBOXED=1, exported by
# sandbox/run-autopilot-sandboxed.sh) and a container indicator (Docker's /.dockerenv or a
# container reference in pid 1's cgroup).
# The two container-indicator PATHS are overridable ONLY to make this refusal testable (a test
# points them at nonexistent files to simulate a bare host). This is not a bypass: overriding them
# can only REMOVE a signal (→ stricter, more likely to refuse), never forge one more easily than the
# already-acknowledged forgeable JAIMITOS_SANDBOXED env var.
SANDBOX_SIGNAL=0
if [ "$SKIP_PERMISSIONS" -eq 1 ]; then
  [ "${JAIMITOS_SANDBOXED:-0}" = "1" ] && SANDBOX_SIGNAL=1
  [ -f "${JAIMITOS_DOCKERENV_PATH:-/.dockerenv}" ] && SANDBOX_SIGNAL=1
  grep -qaE '(docker|containerd|kubepods|lxc)' "${JAIMITOS_CGROUP_PATH:-/proc/1/cgroup}" 2>/dev/null && SANDBOX_SIGNAL=1
  # Bypass on a bare host with no sandbox signal → refuse unless the human explicitly accepts it.
  # Refuse HERE, before the lock/worktree, so a refusal leaves nothing behind.
  if [ "$SANDBOX_SIGNAL" -eq 0 ] && [ "$ACK_NO_SANDBOX" -eq 0 ]; then
    echo "autopilot: ⛔ --dangerously-skip-permissions with NO sandbox signal detected." >&2
    echo "autopilot:   This removes the permission boundary on a bare host: the builder/evaluator can run" >&2
    echo "autopilot:   anything your OS user can, against any credentials on this machine. Run it in the" >&2
    echo "autopilot:   shipped sandbox:  bash sandbox/run-autopilot-sandboxed.sh $*" >&2
    echo "autopilot:   or, if you truly accept the risk on THIS host, re-run with --i-understand-no-sandbox." >&2
    exit 1
  fi
fi

# Default the test gate ON for headless runs so each turn writes test-results.json
# evidence (the test-gate.sh Stop hook reads $LEAN_TEST_GATE). Set it to `block`
# to hard-fail on failing/missing tests, or `off` to disable the gate entirely.
export LEAN_TEST_GATE="${LEAN_TEST_GATE:-warn}"

cd "$(git rev-parse --show-toplevel 2>/dev/null || echo .)" || exit 1

# Original repo root, captured BEFORE any --worktree cd. Operators are told to
# `touch AGENT_STOP` (or write STEER.md) in their original checkout, so the loop's
# stop checks must look here as well as in the (possibly worktree) working dir.
# Defined unconditionally so the checks work whether or not the worktree is used.
ORIG_ROOT="$PWD"

# ----------------------------- preflight -----------------------------
fail() { echo "autopilot: PREFLIGHT FAILED — $1" >&2; exit 1; }

# ---- single-run lock + cleanup trap ----
# Prevent two autopilots from racing the same checkout, and never leave a stale lock or silently
# orphan a worktree. The lock lives in the ORIGINAL checkout (the worktree is per-run).
LOCK="$ORIG_ROOT/.claude/.autopilot.lock"
LOCK_HELD=0

# Lifecycle line → BOTH autopilot.log and stderr, so watchdog activity is visible regardless of the
# operator's CWD (the log lives in the throwaway worktree). Fixes the "empty autopilot.log" symptom.
wd_log() {
  printf 'autopilot[watchdog]: %s\n' "$*" >&2
  printf 'autopilot[watchdog]: %s\n' "$*" >> "${AUTOPILOT_LOG:-$PWD/autopilot.log}" 2>/dev/null || true
}

# terminate_child_tree <pid> [SIG] — best-effort recursive kill of <pid> and its descendants.
# Depth-first: reap grandchildren (via `pgrep -P`, portable on macOS+Linux) BEFORE the parent, so a
# parent can't re-fork after we signal it. When <pid> is ALSO a process-group leader (we started it
# with setpgrp/setsid → CURRENT_CHILD_PGID == pid) we additionally signal the whole group, catching
# descendants that were re-parented to init but stayed in the group. LIMITATION: a descendant that
# started its OWN session/group (setsid) escapes both — documented; starting the child as a group
# leader below minimizes it for the common `claude` → `claude --agent` subtree.
terminate_child_tree() {
  local pid="$1" sig="${2:-TERM}" kid
  [ -n "$pid" ] || return 0
  for kid in $(pgrep -P "$pid" 2>/dev/null); do
    terminate_child_tree "$kid" "$sig"
  done
  kill -"$sig" "$pid" 2>/dev/null || true
  if [ -n "${CURRENT_CHILD_PGID:-}" ] && [ "$pid" = "$CURRENT_CHILD_PGID" ]; then
    kill -"$sig" "-$CURRENT_CHILD_PGID" 2>/dev/null || true
  fi
}

cleanup_on_exit() {
  local rc=$?
  # A child still in flight on an abnormal exit (signal / error) must not be orphaned as a runaway:
  # TERM the whole tree, give it a moment, then KILL. This is the backstop the INT/TERM handlers and
  # the watchdog escalation both lean on. CURRENT_CHILD_PID is "" on any normal exit, so this no-ops.
  if [ -n "${CURRENT_CHILD_PID:-}" ]; then
    terminate_child_tree "$CURRENT_CHILD_PID" TERM
    sleep 1
    kill -0 "$CURRENT_CHILD_PID" 2>/dev/null && terminate_child_tree "$CURRENT_CHILD_PID" KILL
  fi
  [ -n "${BUILDER_OUT:-}" ] && rm -f "$BUILDER_OUT" 2>/dev/null
  [ -n "${EVAL_OUT:-}" ] && rm -f "$EVAL_OUT" 2>/dev/null
  [ "$LOCK_HELD" -eq 1 ] && rm -f "$LOCK" 2>/dev/null
  # Abnormal exit (signal / error) AFTER a worktree was created: do NOT auto-remove it — it may
  # hold unpushed or high-stakes commits. Point the operator at it instead.
  if [ "$rc" -ne 0 ] && [ "${USE_WORKTREE:-0}" -eq 1 ] && [ -n "${WT_DIR:-}" ] && [ -d "${WT_DIR:-/nonexistent}" ]; then
    echo "autopilot: ⚠ exited early (rc $rc); worktree left for inspection: $WT_DIR" >&2
    echo "autopilot:   review it, then remove with: git worktree remove \"$WT_DIR\" (add --force to discard)." >&2
  fi
}
trap cleanup_on_exit EXIT
# INT/TERM to the PARENT must terminate the in-flight child tree FIRST (so ^C or `kill` reaches the
# wedged `claude` subtree), then exit — the EXIT trap then escalates TERM→KILL as the final backstop.
trap 'terminate_child_tree "${CURRENT_CHILD_PID:-}" TERM 2>/dev/null; exit 130' INT
trap 'terminate_child_tree "${CURRENT_CHILD_PID:-}" TERM 2>/dev/null; exit 143' TERM

mkdir -p "$ORIG_ROOT/.claude" 2>/dev/null || true
# Atomic acquire: `set -o noclobber` makes `>` fail if the file already exists (O_EXCL), so two
# simultaneous launches can't both win the check-then-write race.
if ( set -o noclobber; echo "$$" > "$LOCK" ) 2>/dev/null; then
  LOCK_HELD=1
else
  OLDPID=$(head -1 "$LOCK" 2>/dev/null)
  if [ -n "$OLDPID" ] && kill -0 "$OLDPID" 2>/dev/null; then
    fail "another autopilot run is active (pid $OLDPID; lock $LOCK). Wait for it, or remove the lock if you're certain it's dead."
  fi
  echo "autopilot: stale lock from dead pid ${OLDPID:-?} — reclaiming."
  rm -f "$LOCK"
  if ( set -o noclobber; echo "$$" > "$LOCK" ) 2>/dev/null; then
    LOCK_HELD=1
  else
    fail "could not acquire lock $LOCK (racing another run?)."
  fi
fi

git rev-parse --is-inside-work-tree >/dev/null 2>&1 || fail "not inside a git repository (run 'git init')."
command -v claude >/dev/null 2>&1 || fail "'claude' CLI not found on PATH."
command -v jq     >/dev/null 2>&1 || fail "'jq' not found (hooks need it)."
[ -f .claude/settings.json ] || fail "missing .claude/settings.json."
[ -f docs/ROADMAP.md ]       || fail "missing docs/ROADMAP.md."
[ -f docs/STATE.md ]         || fail "missing docs/STATE.md."

if [ "$ALLOW_DIRTY" -eq 0 ] && [ -n "$(git status --porcelain 2>/dev/null)" ]; then
  fail "working tree is dirty. Commit/stash first, or pass --allow-dirty."
fi
if [ "$OPEN_PR" -eq 1 ] && ! command -v gh >/dev/null 2>&1; then
  fail "--pr requested but 'gh' (GitHub CLI) is not installed."
fi
if ! grep -qE "^[[:space:]]*- \[ \] " docs/ROADMAP.md 2>/dev/null; then
  echo "autopilot: roadmap has no open items. Nothing to do."; exit 0
fi

# ----------------------- worktree isolation (default ON) -----------------------
BRANCH=""
if [ "$USE_WORKTREE" -eq 1 ]; then
  STAMP=$(date +%Y%m%d-%H%M%S)
  BRANCH="autopilot/$STAMP"
  WT_DIR="$(cd .. && pwd)/$(basename "$PWD")-autopilot-$STAMP"
  echo "autopilot: creating isolated worktree → $WT_DIR (branch $BRANCH)"
  git worktree add -b "$BRANCH" "$WT_DIR" HEAD >/dev/null 2>&1 || fail "could not create worktree."
  cd "$WT_DIR" || fail "could not enter worktree."
else
  echo "autopilot: ⚠ running IN-PLACE in your current checkout ($PWD)."
  echo "autopilot:   a runaway loop can mutate the files you're working on. Isolation is the"
  echo "autopilot:   default (--worktree, a throwaway branch); you opted out with --no-worktree."
fi

if [ "$SKIP_PERMISSIONS" -eq 1 ]; then
  echo "autopilot: ⚠ --dangerously-skip-permissions is ON — the builder and evaluator run with"
  echo "autopilot:   ALL permission checks skipped (same as the claude CLI's own flag of this"
  echo "autopilot:   name). Use this ONLY in a sandboxed container with NO production"
  echo "autopilot:   credentials — it removes the interactive permission boundary entirely for"
  echo "autopilot:   the duration of this run, on both the builder and the evaluator process."
  # SANDBOX_SIGNAL was computed at parse time; if we got here with none, the human passed
  # --i-understand-no-sandbox. Record an unmistakable banner in the run log for any post-mortem.
  if [ "$SANDBOX_SIGNAL" -eq 0 ]; then
    {
      echo "=============================================================================="
      echo "autopilot: ⚠⚠ RUNNING BYPASS OUTSIDE ANY DETECTED SANDBOX (--i-understand-no-sandbox)."
      echo "autopilot:   No JAIMITOS_SANDBOXED / container signal was found. If this host has production"
      echo "autopilot:   credentials, a bad run can reach them. This banner is recorded in autopilot.log."
      echo "=============================================================================="
    } | tee -a autopilot.log >&2
  fi
fi

# Baseline commit for the push-gate: secrets must not enter the remote even though
# the builder's per-task commits never pass through the Stop-hook secret guard.
START_REF=$(git rev-parse HEAD 2>/dev/null)

chmod +x .claude/hooks/*.sh scripts/*.sh 2>/dev/null || true

# Source the SHARED guard libraries now that the final working dir is set. These
# are installed into every project; if absent we warn LOUDLY (the matching gate is
# then disabled — better to know than to silently skip a safety check).
if [ -f .claude/lib/_secret-scan.sh ]; then
  . .claude/lib/_secret-scan.sh 2>/dev/null || true
else
  echo "autopilot: WARNING — .claude/lib/_secret-scan.sh not found; commit/push secret-gate DISABLED." >&2
fi
if [ -f .claude/lib/_high-stakes.sh ]; then
  . .claude/lib/_high-stakes.sh 2>/dev/null || true
else
  echo "autopilot: WARNING — .claude/lib/_high-stakes.sh not found; high-stakes gate DISABLED." >&2
fi
# Evaluator-isolation lib (shared with in-session /phase). eval_snapshot/eval_restore below
# REQUIRE it — fail closed if it's missing rather than grade without the discard net.
if [ -f .claude/lib/_eval-isolation.sh ]; then
  . .claude/lib/_eval-isolation.sh 2>/dev/null || true
fi
if ! command -v eval_snapshot >/dev/null 2>&1 || ! command -v eval_restore >/dev/null 2>&1; then
  fail ".claude/lib/_eval-isolation.sh missing/unloadable — the evaluator-change discard net is unavailable (fail-closed)."
fi
# Shared roadmap parser — the pre-build supervised gate (C2) REQUIRES it. Fail closed if missing:
# without it we cannot determine the next phase's Mode before spawning the builder, and a supervised
# phase could be built unattended.
if [ -f .claude/lib/_roadmap.sh ]; then
  . .claude/lib/_roadmap.sh 2>/dev/null || true
fi
if ! command -v roadmap_first_open_heading >/dev/null 2>&1 || ! command -v roadmap_phase_mode >/dev/null 2>&1; then
  fail ".claude/lib/_roadmap.sh missing/unloadable — cannot check the next phase's Mode: before building (fail-closed)."
fi

if [ "$UNBOUNDED" -eq 1 ]; then
  echo "autopilot: advancing until the roadmap is empty (safety cap $MAX_ITER). touch AGENT_STOP to halt."
elif [ "$MIN_TARGET" -gt 0 ]; then
  echo "autopilot: aiming for $MIN_TARGET–$MAX_ITER phases (hard cap $MAX_ITER). touch AGENT_STOP to halt."
else
  echo "autopilot: up to $MAX_ITER iterations. touch AGENT_STOP to halt."
fi

# Roadmap ticking + ALL completion gates (evidence freshness, secret scan, high-stakes,
# and — in Phase 2B — the STATE machine block) now live in the SHARED scripts/tick.sh,
# called below on a PASS. The in-session /wrap path calls the same script, so no command,
# prompt, or model can mark roadmap work done without passing the identical gate.

# Decision A — discard any file changes the EVALUATOR made before trusting its verdict (so a grader
# that edits code into passing can't influence the ticked tree). The mechanism now lives in the
# shared lib .claude/lib/_eval-isolation.sh as eval_snapshot() + eval_restore() (sourced above), so
# in-session /phase can reuse the SAME logic. Headless calls eval_restore (DESTRUCTIVE — safe here
# because this is a throwaway worktree, tracked tree clean pre-grade). Behavior is byte-identical to
# the former inline cleanup_eval_changes; the autopilot gate tests verify that.

PREV_OPEN_SIGNATURE=""
SAME_PHASE_FAILS=0
MAX_SAME_PHASE_FAILS=3

# ---- trusted phase base (set-once-per-new-phase, preserved across NEEDS_WORK retries) ----
# .claude/.phase-base is UNTRUSTED under headless bypass mode: the builder writes it (phase.md), and a
# compromised/prompt-injected builder could forge it (e.g. BASE=HEAD) to empty the secret/high-stakes
# scan window in tick.sh + the evaluator. We instead derive the base HERE, in the orchestrator's
# trusted shell, at the top of each iteration: capture HEAD when a NEW phase starts and hold it verbatim
# across retries of the same phase. PHASE_BASE overrides the builder's file (before the evaluator) and
# is passed to tick.sh via TICK_BASE. BASE_SIGNATURE remembers which phase PHASE_BASE was captured for.
PHASE_BASE=""
BASE_SIGNATURE=""

# ---- gate-control integrity (trusted-shell check, independent of the worktree tick.sh) ----
# The scan window is derived in THIS trusted shell, but tick.sh and the guard libs are still EXECUTED
# from the worktree — a builder under --dangerously-skip-permissions could neuter the gate itself
# (rewrite tick.sh to always exit 0, shrink HIGH_STAKES_RE) in its worktree and the gate would run
# neutered. Before trusting a tick, verify each gate-control file is byte-identical to its version at
# START_REF (the trusted commit autopilot launched from and branched the worktree off). Comparing to
# START_REF (not the worktree) catches COMMITTED and UNCOMMITTED edits and is independent of the
# possibly-forged .phase-base AND the possibly-neutered worktree tick.sh (tick.sh's own C1 check cannot
# guard tick.sh itself). Any drift → treated exactly like a high-stakes hit (no auto-tick, no push).
# Works in worktree and --no-worktree (a committed edit still differs from START_REF's committed blob).
# The four STAGED AGENT PROMPTS (.claude/agents/*.md) are part of the headless control surface too: the
# evaluator prompt IS the grading contract, and a builder that rewrote it (or the researcher/planner/
# executor prompts) mid-phase could steer its own grade or the next phase's build. Editing an autonomous
# control prompt should force supervised review, not silently continue — so they are integrity-checked
# here alongside the scripts. (A legitimate agent-prompt change is a supervised toolkit edit, not an
# unattended autopilot phase.)
GATE_CONTROL_FILES="scripts/tick.sh .claude/lib/_high-stakes.sh .claude/lib/_secret-scan.sh .claude/lib/_eval-isolation.sh .claude/lib/_roadmap.sh scripts/test-evidence.sh scripts/record-grade.sh .claude/lib/_test-cmd.sh .claude/test-command .claude/high-stakes-path-allowlist .claude/agents/researcher.md .claude/agents/planner.md .claude/agents/executor.md .claude/agents/evaluator.md"
gate_control_intact() {
  local p
  for p in $GATE_CONTROL_FILES; do
    if git cat-file -e "${START_REF}:$p" 2>/dev/null; then
      # Present at launch → must still be present AND byte-identical to the trusted original.
      if [ ! -e "$p" ] || ! git show "${START_REF}:$p" 2>/dev/null | cmp -s - "$p"; then
        echo "autopilot: ⛔ gate-control file changed/removed since launch: $p" >&2
        return 1
      fi
    elif [ -e "$p" ]; then
      # Absent at launch but present now → a newly-introduced gate file is suspicious.
      echo "autopilot: ⛔ gate-control file introduced since launch: $p" >&2
      return 1
    fi
  done
  return 0
}

# run_child_with_watchdog <stdout_file> <timeout_secs> <label> -- <cmd...>
#
# Runs <cmd...> as a BACKGROUND child so the parent can (a) enforce a per-child wall-clock timeout,
# (b) keep polling AGENT_STOP DURING the child's run (not just between iterations), and (c) drop the
# child if it loses the run lock. Without this a wedged headless `claude` (and its nested
# `claude --agent` subtree) blocked the parent forever and ignored AGENT_STOP — the P0 runaway. The
# child is started as its OWN process-group leader (perl setpgrp; setsid fallback) so the whole
# subtree can be signalled by group id; a manual TERM→(2s)→KILL escalation reaps it, and if it
# survives even SIGKILL we FAIL CLOSED (rc 127). stdout → <stdout_file>; stderr → autopilot.log (a
# hung/killed child still leaves diagnosable output). rc: 124 timeout · 125 AGENT_STOP · 126
# lock-lost · 127 cleanup-failed · else the child's own rc.
run_child_with_watchdog() {
  local out_file="$1" timeout="$2" label="$3"
  shift 3
  [ "${1:-}" = "--" ] && shift

  CURRENT_CHILD_PID=""
  CURRENT_CHILD_PGID=""
  if command -v perl >/dev/null 2>&1; then
    # perl backgrounded → setpgrp(0,0) makes it its own group leader → exec keeps the SAME pid, so $!
    # is exactly the child pid AND its pgid (deterministic, unlike setsid's fork-or-not behaviour).
    perl -e 'setpgrp(0,0); exec @ARGV' -- "$@" >"$out_file" 2>>"$AUTOPILOT_LOG" &
    CURRENT_CHILD_PID=$!
    CURRENT_CHILD_PGID=$CURRENT_CHILD_PID
  elif command -v setsid >/dev/null 2>&1; then
    setsid "$@" >"$out_file" 2>>"$AUTOPILOT_LOG" &
    CURRENT_CHILD_PID=$!
    CURRENT_CHILD_PGID=$CURRENT_CHILD_PID
  else
    # No group-leader tool: child shares our group; only pgrep -P recursion can reach its subtree.
    "$@" >"$out_file" 2>>"$AUTOPILOT_LOG" &
    CURRENT_CHILD_PID=$!
  fi
  local child=$CURRENT_CHILD_PID
  wd_log "start label=$label parent=$$ child=$child pgid=${CURRENT_CHILD_PGID:-none} timeout=${timeout}s poll=${POLL_INTERVAL}s"

  local start_ts now elapsed reason="" rc=0
  start_ts=$(date +%s 2>/dev/null || echo 0)
  while kill -0 "$child" 2>/dev/null; do
    now=$(date +%s 2>/dev/null || echo 0)
    elapsed=$(( now - start_ts ))
    if [ "$start_ts" -gt 0 ] && [ "$elapsed" -ge "$timeout" ]; then reason="timeout"; rc=124; break; fi
    if [ -f AGENT_STOP ] || [ -f "$ORIG_ROOT/AGENT_STOP" ]; then reason="AGENT_STOP"; rc=125; break; fi
    if [ "${LOCK_HELD:-0}" -eq 1 ] && [ "$(head -1 "$LOCK" 2>/dev/null)" != "$$" ]; then reason="lock-lost"; rc=126; break; fi
    sleep "$POLL_INTERVAL"
  done

  local cleanup="ok"
  if [ -n "$reason" ]; then
    terminate_child_tree "$child" TERM
    sleep 2
    if kill -0 "$child" 2>/dev/null; then
      terminate_child_tree "$child" KILL
      sleep 1
      kill -0 "$child" 2>/dev/null && { cleanup="FAILED"; rc=127; }
    fi
    wait "$child" 2>/dev/null || true
    wd_log "BREACH label=$label child=$child reason=$reason cleanup=$cleanup rc=$rc"
  else
    wait "$child" 2>/dev/null; rc=$?
    wd_log "done label=$label child=$child rc=$rc"
  fi
  CURRENT_CHILD_PID=""
  CURRENT_CHILD_PGID=""
  return "$rc"
}

# Absolute log path (the log lives in the CWD = worktree, invisible from the operator's original
# checkout) + scratch capture files for the two watched children, kept OUTSIDE the repo so they never
# dirty the tracked tree or the pre-grade snapshot. Print the resolved path so the log is findable.
AUTOPILOT_LOG="$PWD/autopilot.log"
BUILDER_OUT=$(mktemp 2>/dev/null || echo "${TMPDIR:-/tmp}/autopilot-builder.$$")
EVAL_OUT=$(mktemp 2>/dev/null || echo "${TMPDIR:-/tmp}/autopilot-eval.$$")
echo "autopilot: log → $AUTOPILOT_LOG   (working dir: $PWD)"

for i in $(seq 1 "$MAX_ITER"); do
  # F1: each iteration starts pessimistic. A run publishes only if it ENDS on a fully-successful
  # iteration (tick rc 0 + commit) or the roadmap-complete break below — ANY failure/abort/block
  # break leaves RUN_RESULT "failed", and the finish gate refuses to push it.
  RUN_RESULT="failed"
  # Kill-switch: present in the worktree working dir OR the operator's original checkout. A user
  # AGENT_STOP is an interruption, not a completed run — RUN_RESULT stays "failed" → never published.
  if [ -f AGENT_STOP ] || [ -f "$ORIG_ROOT/AGENT_STOP" ]; then
    echo "autopilot: AGENT_STOP present — stopping at iteration $i."; break
  fi
  grep -qE "^[[:space:]]*- \[ \] " docs/ROADMAP.md 2>/dev/null || { echo "autopilot: roadmap complete. Done."; RUN_RESULT="success"; break; }

  # STEER mirror: operators write STEER.md in their ORIGINAL checkout, but the loop
  # runs in the worktree. Move it in so the builder (which reads ./STEER.md) sees it.
  if [ "$PWD" != "$ORIG_ROOT" ] && [ -f "$ORIG_ROOT/STEER.md" ]; then
    mv "$ORIG_ROOT/STEER.md" ./STEER.md 2>/dev/null || true
  fi

  OPEN_SIGNATURE=$(grep -nE "^[[:space:]]*- \[ \] " docs/ROADMAP.md 2>/dev/null | { md5 2>/dev/null || md5sum 2>/dev/null; })

  # Capture the TRUSTED phase base when a NEW phase starts; preserve it across NEEDS_WORK retries.
  # "New phase" ⇔ the set of open roadmap checkboxes changed since we last set the base (a prior phase
  # ticked, advancing the scan floor); a retry leaves that set byte-identical, so we keep the same base
  # (re-capturing every iteration would self-NARROW the window on a retry, the exact bug phase.md's
  # "set base only on a new phase" rule avoids — but derived here in the trusted shell, not the builder).
  if [ "$OPEN_SIGNATURE" != "$BASE_SIGNATURE" ]; then
    PHASE_BASE=$(git rev-parse HEAD 2>/dev/null)
    BASE_SIGNATURE="$OPEN_SIGNATURE"
  fi

  echo ""; echo "=== iteration $i / $MAX_ITER ==="

  # --- pre-build supervised gate (C2) ---
  # Resolve the next open phase and its Mode: BEFORE spawning the builder. tick.sh's Mode: supervised
  # refusal only protects the CHECKBOX — it runs after the phase is fully built, so without this an
  # unattended loop would carry out a supervised phase's actual work (auth, money, migration, deletion,
  # deploy, webhook — any live external effect it requires) before being blocked from ticking it. This
  # is the headless equivalent of the in-session /autopilot command's own pre-build check
  # (.claude/commands/autopilot.md). Fail closed on supervised AND on a missing/duplicate/invalid Mode
  # (Mode is mandatory per the roadmap template + skill — an unclassified phase must not run unattended).
  NEXT_HEADING=$(roadmap_first_open_heading docs/ROADMAP.md); nh_rc=$?
  if [ "$nh_rc" != 0 ]; then
    echo "autopilot: ⛔ cannot resolve a single next open phase (rc=$nh_rc; duplicate/ambiguous heading?) — refusing to build unattended." | tee -a "$AUTOPILOT_LOG"; break
  fi
  NEXT_MODE=$(roadmap_phase_mode docs/ROADMAP.md "$NEXT_HEADING"); nm_rc=$?
  if [ "$nm_rc" != 0 ]; then
    echo "autopilot: ⛔ next phase Mode: is duplicate/invalid (rc=$nm_rc) — refusing to build: $NEXT_HEADING" | tee -a "$AUTOPILOT_LOG"; break
  fi
  case "$NEXT_MODE" in
    supervised)
      echo "autopilot: ⛔ next phase is Mode: supervised — NOT building it unattended:" | tee -a "$AUTOPILOT_LOG"
      echo "autopilot:    $NEXT_HEADING" | tee -a "$AUTOPILOT_LOG"
      echo "autopilot:    Build it with plain /phase under human review, then approve at HEAD:" | tee -a "$AUTOPILOT_LOG"
      echo "autopilot:      bash scripts/tick.sh --supervised-approved \"$NEXT_HEADING\" --note \"<why it's safe>\"" | tee -a "$AUTOPILOT_LOG"; break ;;
    loopable) : ;;   # classified low-risk — ok to build
    "" )
      echo "autopilot: ⛔ next phase has NO Mode: line — refusing to build unattended (add 'Mode: loopable' or 'Mode: supervised'): $NEXT_HEADING" | tee -a "$AUTOPILOT_LOG"; break ;;
    *)
      echo "autopilot: ⛔ next phase has an unexpected Mode ('$NEXT_MODE') — refusing to build: $NEXT_HEADING" | tee -a "$AUTOPILOT_LOG"; break ;;
  esac

  # Builder: fresh context, builds ONE phase, does NOT tick the roadmap. Run under the watchdog so a
  # wedged builder (and its nested claude subtree) is timed-out / stop-able / lock-checked instead of
  # blocking the parent forever (the P0 runaway). Its stdout is captured to $BUILDER_OUT then appended
  # to the log; the watchdog streams its stderr straight to the log.
  run_child_with_watchdog "$BUILDER_OUT" "$CHILD_TIMEOUT" builder -- claude -p "/phase" "${CLAUDE_PERM_FLAGS[@]}"
  BUILDER_RC=$?
  cat "$BUILDER_OUT" >> "$AUTOPILOT_LOG" 2>/dev/null || true
  if [ "$BUILDER_RC" -ge 124 ]; then
    RUN_ABORTED=1
    echo "autopilot: ⛔ builder watchdog aborted the run (rc $BUILDER_RC — 124=timeout 125=AGENT_STOP 126=lock-lost 127=cleanup-failed) — STOPPING; branch stays LOCAL." | tee -a "$AUTOPILOT_LOG"; break
  fi
  if [ "$BUILDER_RC" -ne 0 ]; then
    echo "autopilot: builder process exited non-zero (rc $BUILDER_RC) — stopping." | tee -a "$AUTOPILOT_LOG"; break
  fi

  # Deterministic check: /phase's own step 2 ALWAYS writes .claude/.phase-ready (the exact
  # heading it's building), new phase or retry alike — so its absence right after a
  # successful-exit builder run is a reliable signal the builder was BLOCKED from writing
  # it, not that it genuinely finished. The most common cause without a TTY: a permission
  # prompt for a .claude/ write or a Bash command (pytest, git add) that acceptEdits mode
  # cannot approve headlessly. Catch it HERE, deterministically, instead of burning an
  # evaluator grading pass against a phase that was never actually attempted.
  if [ ! -f .claude/.phase-ready ]; then
    echo "autopilot: ⛔ .claude/.phase-ready is missing after the builder exited — the phase" | tee -a autopilot.log
    echo "autopilot:   was most likely blocked by a permission prompt it couldn't answer" | tee -a autopilot.log
    echo "autopilot:   headlessly (no TTY). Check autopilot.log above for what the builder" | tee -a autopilot.log
    echo "autopilot:   actually reported. If you're in a sandboxed container with NO" | tee -a autopilot.log
    echo "autopilot:   production credentials, retry with --dangerously-skip-permissions." | tee -a autopilot.log
    echo "autopilot:   STOPPING (won't grade a phase that was never really attempted)." | tee -a autopilot.log
    break
  fi

  # Override the builder-written .claude/.phase-base with the TRUSTED base captured above, BEFORE the
  # evaluator (which reads .phase-base for its phase-diff + criteria-integrity check, evaluator.md:38,48)
  # and tick.sh (via TICK_BASE below) run. The builder writes this file from inside its bypass-mode
  # session; under headless autopilot it is UNTRUSTED (a forged BASE=HEAD would empty the scan window
  # and hide a high-stakes/secret commit). .claude/.phase-base is gitignored, so this write never dirties
  # the tracked tree or the pre-grade snapshot.
  if [ -n "$PHASE_BASE" ]; then
    printf '%s\n' "$PHASE_BASE" > .claude/.phase-base
  fi

  # Produce AUTHORITATIVE tick evidence now that the builder has fully exited and HEAD is
  # final. The Stop-hook test-gate is advisory and races commit-on-stop (which advances HEAD
  # past any sha a Stop-time gate stamped), so it cannot be trusted for the run_id binding.
  # --allow-no-tests records passed:null without failing the loop; scripts/tick.sh still
  # requires the evaluator's NO_TESTS_OK before it will tick a no-test phase. Run BEFORE the
  # pre-grade snapshot so the (gitignored) evidence file is settled and survives cleanup.
  bash scripts/test-evidence.sh --allow-no-tests >>autopilot.log 2>&1 || true

  # Snapshot the tree BEFORE grading so we can discard whatever the evaluator changes (shared lib;
  # sets EVAL_PRE_* consumed by eval_restore below). Fail-closed: if the snapshot can't be taken,
  # do NOT grade — better to stop than to grade without the discard net.
  if ! eval_snapshot; then
    echo "autopilot: could not snapshot the tree before grading — STOPPING (fail-closed)." | tee -a autopilot.log
    break
  fi

  # Independent grader: separate process, runs AS the evaluator (its system prompt +
  # no-edit-tools restriction). This is the sole gate for ticking.
  # NOTE: same $CLAUDE_PERM_FLAGS as the builder — the evaluator has no Edit/Write tools
  # regardless, AND any file change it does make is discarded by cleanup_eval_changes
  # below, so bypassing permissions here does not weaken its no-edit contract; it only
  # lets it actually RUN the test suite/typecheck/lint via Bash headlessly (with the
  # default acceptEdits and no TTY, those Bash calls would otherwise be denied outright,
  # producing an empty/uninformative grade rather than a real one). Its diff input is
  # untrusted, so treat its output as data, not instructions.
  # stderr → autopilot.log (not /dev/null) so an empty/garbled grade is debuggable. Run under the same
  # watchdog as the builder: a wedged evaluator subtree must be contained too, not block the parent.
  # stdout → $EVAL_OUT → VERDICT; the watchdog streams its stderr to the log.
  run_child_with_watchdog "$EVAL_OUT" "$CHILD_TIMEOUT" evaluator -- \
    claude --agent evaluator -p "Grade the phase just completed." "${CLAUDE_PERM_FLAGS[@]}"
  EVAL_RC=$?
  VERDICT=$(cat "$EVAL_OUT" 2>/dev/null)
  if [ "$EVAL_RC" -ge 124 ]; then
    RUN_ABORTED=1
    echo "autopilot: ⛔ evaluator watchdog aborted the run (rc $EVAL_RC) — treating as failure, STOPPING." | tee -a "$AUTOPILOT_LOG"; break
  fi

  if [ -z "$(printf '%s' "$VERDICT" | tr -d '[:space:]')" ]; then
    echo "autopilot: evaluator returned no output — treating as FAILURE, stopping." | tee -a autopilot.log
    echo "autopilot: --- last 20 lines of autopilot.log (evaluator stderr) ---" >&2
    tail -n 20 autopilot.log 2>/dev/null >&2 || true
    break
  fi
  echo "evaluator says: $VERDICT" | tee -a autopilot.log

  # Decision A: discard the evaluator's file changes BEFORE parsing/ticking/committing.
  if ! eval_restore; then
    echo "autopilot: evaluator-change cleanup failed or ambiguous — not ticking. STOPPING." | tee -a autopilot.log
    break
  fi

  # Anchored verdict parsing: trust ONLY the LAST non-empty line, matched against an
  # exact verdict. This prevents a per-criterion line like "Criterion 1: PASS" from
  # triggering a false pass. Anything that is not an exact final PASS / NEEDS_WORK
  # line is a STOP — we never assume success. (STRICT — do not loosen.)
  LASTLINE=$(printf '%s\n' "$VERDICT" | grep -vE '^[[:space:]]*$' | tail -1)

  case "$LASTLINE" in
    NEEDS_WORK*)
      printf '%s\n' "$VERDICT" > NEXT_FINDINGS.md
      echo "autopilot: phase needs work — findings written to NEXT_FINDINGS.md." | tee -a autopilot.log
      if [ "$OPEN_SIGNATURE" = "$PREV_OPEN_SIGNATURE" ]; then SAME_PHASE_FAILS=$((SAME_PHASE_FAILS+1)); else SAME_PHASE_FAILS=1; fi
      PREV_OPEN_SIGNATURE="$OPEN_SIGNATURE"
      if [ "$SAME_PHASE_FAILS" -ge "$MAX_SAME_PHASE_FAILS" ]; then
        echo "autopilot: same phase failed $SAME_PHASE_FAILS times — stopping to avoid thrash. See NEXT_FINDINGS.md." | tee -a autopilot.log; break
      fi
      ;;
    PASS)
      # Record the independent grade as evidence for the shared tick gate (same writer the
      # in-session /wrap path uses, so the grade-file format has one source). run_id binds it to
      # the exact commit; NO_TESTS_OK (only if the grader emitted it) authorizes ticking a phase
      # that legitimately has no test suite.
      bash scripts/record-grade.sh "$VERDICT" >>autopilot.log 2>&1

      # Re-measure evidence ONE more time, here — on the PASS path only, AFTER
      # cleanup_eval_changes (above) has already reverted any evaluator edits/commits and
      # confirmed the tree exactly matches the pre-grade snapshot — and BEFORE tick.sh reads
      # .claude/.tick-evidence.json as authoritative. Why: the FIRST measurement (a few lines
      # above the builder check, right after the builder subprocess exits) is taken in the most
      # fragile window of the whole iteration — leftover ports/locks/cold caches from the
      # builder's last turn are least settled there. The evaluator then independently re-runs
      # the suite itself (evaluator.md step 3) and can come back green on that SAME tree
      # (HEAD hasn't moved — the evaluator has no edit tools and any stray commit was already
      # reverted), but that reconciliation was never captured: tick.sh trusts ONLY this file, so
      # one flaky sample there could permanently block a genuinely-green phase. Re-running here
      # takes the freshest possible sample — closest to the grading decision, on the now-settled
      # tree — as the one tick.sh will actually check. run_id is still HEAD, so tick.sh's
      # run_id==HEAD binding is unaffected; `|| true` matches the first call so a still-red
      # re-measure doesn't abort the loop early — tick.sh's own fail-closed check is the backstop.
      bash scripts/test-evidence.sh --allow-no-tests >>autopilot.log 2>&1 || true

      # Route through the SINGLE completion gate. tick.sh verifies the evidence (grade + fresh
      # green tests bound to HEAD), secret-scans the whole phase diff, blocks high-stakes paths,
      # updates the STATE machine block, and only then flips the checkbox — the SAME gate /wrap
      # uses. It reads its inputs from the filesystem and committed history, so nothing needs
      # staging beforehand; we stage + commit the resulting roadmap/STATE change only on success.
      PHASE_HEADING=$(cat .claude/.phase-ready 2>/dev/null || echo "phase")   # tick.sh consumes .phase-ready
      # Trusted-shell gate-control integrity check BEFORE running the (worktree) gate: a builder that
      # neutered tick.sh / _high-stakes.sh in its worktree must never get an auto-tick or auto-push.
      if ! gate_control_intact; then
        HS_BLOCKED=1   # treat like a high-stakes hit: no auto-tick, branch stays LOCAL even with --pr
        echo "autopilot: ⛔ gate-control tampering detected — SUPERVISED review required, NOT auto-ticking; branch stays LOCAL (no push even with --pr)." | tee -a autopilot.log
        break
      fi
      TICK_BASE="$PHASE_BASE" bash scripts/tick.sh 2>&1 | tee -a autopilot.log
      TICK_RC="${PIPESTATUS[0]}"
      case "$TICK_RC" in
        0)
          # Persist the resolved failure trail (don't just delete it): a phase that needed work
          # before passing leaves a record in docs/FAILURES.md so recurring blockers are visible.
          if [ -f NEXT_FINDINGS.md ]; then
            {
              echo ""
              echo "## ${PHASE_HEADING#\#\# } — resolved $(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || echo unknown)"
              cat NEXT_FINDINGS.md
            } >> docs/FAILURES.md
            rm -f NEXT_FINDINGS.md
          fi
          git add -A 2>/dev/null
          git commit -m "autopilot: phase passed independent grade (iteration $i)" >/dev/null 2>&1 || true
          SAME_PHASE_FAILS=0; PREV_OPEN_SIGNATURE=""
          RUN_RESULT="success"   # F1: this iteration fully succeeded (built → graded PASS → ticked → committed).
          ;;
        3)
          HS_BLOCKED=1   # high-stakes: finish block must NOT push this branch, even with --pr
          echo "autopilot: ⛔ HIGH-STAKES phase — finish it SUPERVISED. Branch stays LOCAL (no push even with --pr)." | tee -a autopilot.log
          break
          ;;
        *)
          git reset -q 2>/dev/null || true
          echo "autopilot: tick gate REFUSED (rc $TICK_RC) — not ticking. See NEXT_FINDINGS.md / autopilot.log. STOPPING." | tee -a autopilot.log
          break
          ;;
      esac
      ;;
    *)
      echo "autopilot: unrecognized verdict (final line: '$LASTLINE') — stopping (won't assume success)." | tee -a autopilot.log; break
      ;;
  esac
done

# ----------------------------- finish / PR -----------------------------
# F1 — ONE authoritative publication gate. A branch is pushed / PR'd ONLY on a complete, fully-
# successful run (RUN_RESULT=success). Every other outcome keeps the branch LOCAL. Ordinary failures
# and watchdog aborts exit non-zero so a caller can tell the run did not complete; an intentional
# supervised/high-stakes stop exits 0 (it is a correct refusal, not an error).
FINAL_RC=0
if [ "$HS_BLOCKED" -eq 1 ]; then
  # A high-stakes / supervised phase tripped the gate. The builder's per-task commits are already
  # in this branch, but high-stakes work is human-on-the-loop: it is NEVER auto-pushed, even with
  # --pr. Leave the branch local for supervised review. Intentional stop → exit 0.
  echo "autopilot: high-stakes phase reached — branch $BRANCH stays LOCAL for supervised review (not pushed)." | tee -a autopilot.log
  if [ "$USE_WORKTREE" -eq 1 ]; then
    echo "autopilot: review it in $PWD, then merge or 'git worktree remove' when finished."
  fi
elif [ "$RUN_ABORTED" -eq 1 ]; then
  # The child watchdog aborted the run (timeout / AGENT_STOP / lock-lost / cleanup-failed). A wedged
  # or killed child leaves an unverified tree — fail closed: never push, even with --pr. Exit non-zero.
  echo "autopilot: run aborted by the child watchdog — branch ${BRANCH:-<current>} stays LOCAL, NOT pushed (even with --pr)." | tee -a autopilot.log
  if [ "$USE_WORKTREE" -eq 1 ]; then
    echo "autopilot: review it in $PWD, then merge or 'git worktree remove' when finished."
  fi
  FINAL_RC=1
elif [ "$RUN_RESULT" != "success" ]; then
  # F1: an ordinary failure or INCOMPLETE run (builder crashed, ungraded/empty/garbled verdict, thrash
  # cap, tick REFUSED, a supervised NEXT phase, AGENT_STOP boundary, or the roadmap never fully cleared).
  # The branch may hold ungraded per-task builder commits — NEVER publish it. Keep it local, exit non-zero.
  echo "autopilot: ⛔ run did NOT complete successfully (result: $RUN_RESULT) — branch ${BRANCH:-<current>} stays LOCAL, NOT pushed (even with --pr)." | tee -a autopilot.log
  if [ "$USE_WORKTREE" -eq 1 ]; then
    echo "autopilot: review it in $PWD, then merge or 'git worktree remove' when finished."
  fi
  FINAL_RC=1
elif [ "$USE_WORKTREE" -eq 1 ] && [ "$OPEN_PR" -eq 1 ]; then
  # Reached ONLY on a fully-successful run. Push-gate: the builder's per-task commits never passed
  # through the Stop-hook secret guard, so scan the WHOLE range (across every phase) before anything
  # reaches the remote — a defense-in-depth backstop even though each phase's tick already scanned its
  # own range.
  if type -t secret_scan_diff >/dev/null 2>&1; then
    PUSH_FINDINGS=$(secret_scan_diff "${START_REF:-HEAD~1}..HEAD"); PUSH_RC=$?
    if [ "$PUSH_RC" -ne 0 ]; then
      echo "autopilot: ⛔ SECRET GUARD — commit range contains a secret. NOT pushing / no PR." >&2
      printf '%s\n' "$PUSH_FINDINGS" >&2
      echo "autopilot: branch $BRANCH stays local — clean the history before pushing." >&2
      exit 1
    fi
  fi
  echo "autopilot: pushing $BRANCH and opening a PR..."
  if git push -u origin "$BRANCH" >/dev/null 2>&1; then
    gh pr create --fill --title "autopilot: $BRANCH" 2>&1 | tee -a autopilot.log || echo "autopilot: gh pr create failed — open it manually."
  else
    echo "autopilot: git push failed (no remote / auth?). Branch $BRANCH is local; review and push manually."
  fi
elif [ "$USE_WORKTREE" -eq 1 ]; then
  echo "autopilot: done. Review branch $BRANCH in $PWD, then merge or 'git worktree remove' when finished."
fi

echo "autopilot: finished."
exit "$FINAL_RC"
