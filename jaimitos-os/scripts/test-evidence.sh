#!/usr/bin/env bash
# test-evidence.sh — AUTHORITATIVE producer of tick evidence (.claude/.tick-evidence.json).
#
# Why a dedicated producer (not the test-gate.sh Stop hook): the Stop hook runs BEFORE
# commit-on-stop.sh, and the builder updates docs/STATE.md after its last task commit, so
# commit-on-stop checkpoint-commits and ADVANCES HEAD past anything a Stop-time gate stamped.
# Bind evidence to HEAD only AFTER the builder has fully exited — that is this script's job.
# The orchestrator (scripts/autopilot.sh) and the in-session /wrap tick path call it once the
# tree is settled, so run_id == the exact commit scripts/tick.sh will verify against.
#
# It writes a SEPARATE file from the advisory test-gate.sh (which owns test-results.json), so
# the evaluator's own Stop-hook run of test-gate can't clobber the authoritative record.
#
# Output .claude/.tick-evidence.json: {passed, command, exit, run_id, note}
#   passed: true (suite green) | false (suite red) | null (no test command resolved)
# Exit: 0 = tests passed, OR no-tests with --allow-no-tests.
#       1 = tests failed, OR no test command resolved without --allow-no-tests (fail-closed:
#           "no evidence" is NOT "success"; whether null is acceptable for a TICK is decided
#           downstream by scripts/tick.sh via the evaluator's NO_TESTS_OK confirmation).
#
# Usage: bash scripts/test-evidence.sh [--allow-no-tests]
set -uo pipefail
cd "$(git rev-parse --show-toplevel 2>/dev/null || echo .)" || exit 1

ALLOW_NO_TESTS=0
for a in "$@"; do
  case "$a" in
    --allow-no-tests) ALLOW_NO_TESTS=1 ;;
    -h|--help)
      echo "usage: test-evidence.sh [--allow-no-tests]"
      echo "  Authoritative producer of .claude/.tick-evidence.json (test result bound to HEAD). Exit 0"
      echo "  tests passed (or no-tests with --allow-no-tests); 1 red, or no-tests without the flag."
      exit 0 ;;
    *) echo "test-evidence: unknown argument '$a'" >&2; exit 1 ;;
  esac
done

command -v jq >/dev/null 2>&1 || { echo "test-evidence: jq required" >&2; exit 1; }

OUT_FILE=".claude/.tick-evidence.json"
mkdir -p .claude 2>/dev/null || true
HEAD=$(git rev-parse HEAD 2>/dev/null || echo "")

[ -f .claude/lib/_test-cmd.sh ] && . .claude/lib/_test-cmd.sh 2>/dev/null || true
CMD=""
if command -v resolve_test_cmd >/dev/null 2>&1; then CMD=$(resolve_test_cmd 2>/dev/null || true); fi

# emit <passed-json-literal> <command-or-empty> <exit-or-null> <note-or-empty>
emit() {
  jq -nc \
     --argjson passed "$1" \
     --arg cmd "$2" \
     --argjson exit "${3:-null}" \
     --arg run_id "$HEAD" \
     --arg note "$4" \
     '{passed: $passed,
       command: (if $cmd == "" then null else $cmd end),
       exit: $exit,
       run_id: $run_id}
      + (if $note == "" then {} else {note: $note} end)' \
     > "$OUT_FILE" 2>/dev/null || true
}

if [ -z "$CMD" ]; then
  emit null "" null "no test command resolved"
  if [ "$ALLOW_NO_TESTS" -eq 1 ]; then
    echo "test-evidence: no test command resolved — recorded passed:null (--allow-no-tests)."
    exit 0
  fi
  echo "test-evidence: no test command resolved — fail-closed (pass --allow-no-tests to record null and continue)." >&2
  exit 1
fi

# Retry-with-backoff before recording red: this script is invoked in the most fragile window
# of an autopilot iteration — right after the builder subprocess exits, when leftover
# ports/locks/cold caches from the builder's last turn are least settled. tick.sh trusts this
# file's `passed` value as the SOLE authority (it never re-checks), so a single transient
# failure sampled here would permanently block a genuinely-green phase. Re-run the resolved
# command up to TEST_EVIDENCE_RETRIES additional times before giving up; record passed:true as
# soon as ANY attempt is green (a majority/any-green vote over one fragile sample). For an IDEMPOTENT
# suite this only absorbs a flake — a genuinely-red suite fails every attempt and still records
# passed:false. CAVEAT (M8): for a NON-IDEMPOTENT suite — one whose earlier run mutates state so a later
# run passes (a leaked DB row, a created file, a freed port) — any-green CAN mask a real first-attempt
# failure. Keep test suites idempotent; this is an "absorb the fragile-window flake" heuristic, NOT a
# guarantee against a state-dependent false green. Small, clearly-named constants so this is tunable.
TEST_EVIDENCE_RETRIES=2      # extra attempts after the first (total attempts = 1 + this)
TEST_EVIDENCE_RETRY_SLEEP=1  # seconds to wait between attempts

attempt=0
max_attempts=$((TEST_EVIDENCE_RETRIES + 1))
RC=1
OUT=""
while [ "$attempt" -lt "$max_attempts" ]; do
  attempt=$((attempt + 1))
  OUT=$(eval "$CMD" 2>&1); RC=$?
  [ "$RC" -eq 0 ] && break
  if [ "$attempt" -lt "$max_attempts" ]; then
    echo "test-evidence: attempt $attempt/$max_attempts of '$CMD' failed (exit $RC) — retrying in ${TEST_EVIDENCE_RETRY_SLEEP}s (possible flake)..." >&2
    sleep "$TEST_EVIDENCE_RETRY_SLEEP"
  fi
done

if [ "$RC" -eq 0 ]; then
  emit true "$CMD" 0 ""
  echo "test-evidence: ✓ '$CMD' passed on attempt $attempt/$max_attempts (run_id ${HEAD:0:12})."
  exit 0
fi

emit false "$CMD" "$RC" ""
echo "test-evidence: ✗ '$CMD' failed on all $max_attempts attempt(s) (exit $RC). Last lines:" >&2
printf '%s\n' "$OUT" | tail -15 >&2
exit 1
