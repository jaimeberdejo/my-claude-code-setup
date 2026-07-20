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
# Output .claude/.tick-evidence.json — schema_version 2 (v1 fields kept verbatim for tick.sh):
#   {schema_version, passed, command, exit, run_id, source, config_sha, evidence_id, cwd, started_at,
#    finished_at, duration_seconds, classification, requirements, warnings, skipped, summary, redacted,
#    content_hash, note?}
#   passed: true (suite green) | false (suite red) | null (no test command resolved)
#   summary is bounded + secret-redacted; passed is always exit-derived so a summary cannot override it.
#   Optional env: EVIDENCE_ID/LEAN_EVIDENCE_ID, LEAN_EVIDENCE_REQUIREMENTS (id list), LEAN_EVIDENCE_CLASS.
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
command -v authorized_test_cmd >/dev/null 2>&1 || { echo "test-evidence: _test-cmd.sh unavailable (no authorized_test_cmd) — fail-closed" >&2; exit 1; }

# GRADED source only (H2): the command comes from authorized_test_cmd (LEAN_TEST_CMD env, or the
# gate-controlled .claude/test-command), NEVER from settings.json's env block or a mutable manifest.
CMD=$(authorized_test_cmd); AC_RC=$?
SRC="$(authorized_test_cmd_source 2>/dev/null || echo '')"
# config_sha: identity of the config that authorized the command, so tick evidence records WHICH
# configuration was in force (a mismatch across a phase is then detectable). Only .claude/test-command
# has a stable on-disk identity; an env override records its own literal as the identity input.
CFG_SHA=""
if [ "$SRC" = "file:.claude/test-command" ] && [ -f .claude/test-command ]; then
  CFG_SHA=$( { shasum -a 256 .claude/test-command 2>/dev/null || sha256sum .claude/test-command 2>/dev/null; } | cut -d' ' -f1 )
fi

# Phase IDENTITY (schema v3): bind the evidence to the heading + base of the phase, not just HEAD, so
# evidence produced for phase X cannot be reused to tick phase Y at the same commit (v2.17 OBJ-1710).
# Resolved via the SAME shared resolver tick.sh uses. Fail-safe: if the resolver is unavailable or the
# window can't be resolved, heading/base are left empty and tick fails closed on the mismatch.
EV_HEADING=""; EV_BASE=""
[ -f .claude/lib/_roadmap.sh ]     && . .claude/lib/_roadmap.sh     2>/dev/null || true
[ -f .claude/lib/_phase-range.sh ] && . .claude/lib/_phase-range.sh 2>/dev/null || true
if command -v resolve_phase_range >/dev/null 2>&1 && resolve_phase_range 2>/dev/null; then
  EV_HEADING="$PR_HEADING"; EV_BASE="$PR_BASE_SHA"
fi

# --- evidence schema v2 helpers -----------------------------------------------
iso_now() { date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || echo ""; }
EV_START_EPOCH=$(date +%s 2>/dev/null || echo 0)
EV_STARTED=$(iso_now)
# redact(): mask secret-shaped runs (32+ char base64/hex/token) so a bounded summary can never leak a key.
redact() { printf '%s' "$1" | sed -E 's/[A-Za-z0-9+/_=-]{32,}/***REDACTED***/g'; }

# emit <passed-json-literal> <command-or-empty> <exit-or-null> <note-or-empty> [raw-output-for-summary]
# Writes schema_version 2. The v1 fields (passed/command/exit/run_id/source/config_sha/note) are kept
# verbatim so scripts/tick.sh's reads are unchanged; v2 ADDS evidence_id, cwd, timestamps, duration,
# classification, requirement refs, warnings, skipped, a bounded+redacted summary, and an advisory
# content_hash (sha256 of the object without the hash — recomputable, so an edited field is detectable).
# `passed` is always exit-derived, so the summary can never override the real status.
emit() {
  local raw="${5:-}" fin dur summ summ_r red reqs_json base h
  fin=$(iso_now); dur=$(( $(date +%s 2>/dev/null || echo "$EV_START_EPOCH") - EV_START_EPOCH ))
  summ=""
  if [ -n "$raw" ]; then
    summ=$(printf '%s\n' "$raw" | awk 'NF{last=$0} END{if(last!="")print last}')
    summ=$(printf '%s' "$summ" | cut -c1-200)
  fi
  summ_r=$(redact "$summ")
  if [ "$summ_r" = "$summ" ]; then red=false; else red=true; fi
  reqs_json=$(printf '%s' "${LEAN_EVIDENCE_REQUIREMENTS:-}" | tr ', ' '\n\n' | awk 'NF' | jq -R . 2>/dev/null | jq -sc . 2>/dev/null)
  [ -n "$reqs_json" ] || reqs_json="[]"
  base=$(jq -nc \
     --argjson passed "$1" \
     --arg cmd "$2" \
     --argjson exit "${3:-null}" \
     --arg run_id "$HEAD" \
     --arg note "$4" \
     --arg source "$SRC" \
     --arg config_sha "$CFG_SHA" \
     --arg eid "${EVIDENCE_ID:-${LEAN_EVIDENCE_ID:-}}" \
     --arg started "$EV_STARTED" \
     --arg finished "$fin" \
     --argjson duration "${dur:-0}" \
     --arg classification "${LEAN_EVIDENCE_CLASS:-deterministic}" \
     --argjson requirements "$reqs_json" \
     --arg summary "$summ_r" \
     --argjson redacted "$red" \
     --arg heading "$EV_HEADING" \
     --arg base "$EV_BASE" \
     '{schema_version: 3,
       passed: $passed,
       command: (if $cmd == "" then null else $cmd end),
       exit: $exit,
       run_id: $run_id,
       heading: (if $heading == "" then null else $heading end),
       base: (if $base == "" then null else $base end),
       source: (if $source == "" then null else $source end),
       config_sha: (if $config_sha == "" then null else $config_sha end),
       evidence_id: (if $eid == "" then null else $eid end),
       cwd: ".",
       started_at: (if $started == "" then null else $started end),
       finished_at: (if $finished == "" then null else $finished end),
       duration_seconds: $duration,
       classification: $classification,
       requirements: $requirements,
       warnings: [],
       skipped: [],
       summary: (if $summary == "" then null else $summary end),
       redacted: $redacted}
      + (if $note == "" then {} else {note: $note} end)')
  [ -n "$base" ] || return 0
  # content_hash: sha256 of the sorted-canonical object WITHOUT the hash field. Recomputable by a verifier
  # with:  jq -cS 'del(.content_hash)' <file> | shasum -a 256   — an edited field then fails to re-hash.
  h=$(printf '%s' "$base" | jq -cS 'del(.content_hash)' 2>/dev/null | { shasum -a 256 2>/dev/null || sha256sum 2>/dev/null; } | cut -d' ' -f1)
  printf '%s' "$base" | jq -c --arg h "$h" '. + {content_hash: (if $h == "" then null else $h end)}' \
     > "$OUT_FILE" 2>/dev/null || true
}

case "$AC_RC" in
  2)  # a CONFIGURED command was rejected as a no-op (e.g. a builder wrote `true` to the file) — hard
      # fail, never record green. This is the H2 attack surface; it must not pass.
      emit false "" null "configured test command rejected as a no-op (fail-closed)"
      echo "test-evidence: ⛔ the configured test command is a no-op — refusing to record evidence (fail-closed)." >&2
      exit 1 ;;
  1|3)  # no tests: explicit `none:` sentinel (1) or nothing configured (3). Record passed:null; whether
        # null is acceptable for a TICK is still decided downstream by tick.sh via evaluator NO_TESTS_OK.
      emit null "" null "no test command resolved"
      if [ "$ALLOW_NO_TESTS" -eq 1 ]; then
        echo "test-evidence: no authorized test command — recorded passed:null (--allow-no-tests)."
        exit 0
      fi
      echo "test-evidence: no authorized test command — fail-closed (pass --allow-no-tests to record null and continue)." >&2
      exit 1 ;;
esac

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
  emit true "$CMD" 0 "" "$OUT"
  echo "test-evidence: ✓ '$CMD' passed on attempt $attempt/$max_attempts (run_id ${HEAD:0:12})."
  exit 0
fi

emit false "$CMD" "$RC" "" "$OUT"
echo "test-evidence: ✗ '$CMD' failed on all $max_attempts attempt(s) (exit $RC). Last lines:" >&2
printf '%s\n' "$OUT" | tail -15 >&2
exit 1
