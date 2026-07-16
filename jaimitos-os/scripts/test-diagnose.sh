#!/usr/bin/env bash
# test-diagnose.sh — STATIC invariants for the diagnose skill's deterministic-feedback-loop discipline.
# These are grep assertions: they prove the RULE IS STATED in the skill, never that a real debugging
# session followed it (static tests cannot prove debugging quality — see docs/dev/AUTHORING.md on
# model-dependent vs deterministic guarantees). They exist so the hard-won discipline can't silently
# regress out of the skill text.
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
DIAG="$ROOT/skills/diagnose/SKILL.md"
[ -f "$DIAG" ] || { echo "test: cannot find diagnose SKILL.md at $DIAG" >&2; exit 1; }

FAILS=0
pass() { printf '  ✓ %s\n' "$1"; }
fail() { printf '  ✗ %s\n' "$1"; FAILS=$((FAILS+1)); }
have() { if grep -qF "$1" "$DIAG"; then pass "$2"; else fail "$2 (missing: '$1')"; fi; }

echo "diagnose static-invariant tests (the rule is STATED, not that it was FOLLOWED)"; echo ""

echo "Feedback loop first"
have "Build a feedback loop" "a feedback loop is Phase 1 (built before hypothesising)"
have "Do NOT hypothesize without a loop" "hypothesising without a loop is forbidden"
have "red-capable on the user's exact symptom" "Done-when names a red-capable command already run"

echo ""
echo "Improve the loop"
have "Tighten the loop" "the loop is tightened (faster/sharper/more deterministic)"

echo ""
echo "Flaky bugs — measure and repeat, never one run"
have "higher reproduction rate" "flaky goal is a higher reproduction rate"
have "Record the measured rate" "the measured flaky rate is recorded as a baseline"
have "one green run is NOT resolution" "one green run does not resolve a flaky bug"
have "record the new rate" "post-fix the loop is re-run many times and the new rate recorded"

echo ""
echo "Hypotheses — ranked and falsifiable"
have "ranked, falsifiable" "3–5 ranked, falsifiable hypotheses before testing any"

echo ""
echo "Instrumentation — tagged and removed"
have "[DEBUG-" "debug probes carry a unique searchable marker"
grep -qF "removed" "$DIAG" && pass "cleanup requires temporary instrumentation removal" || fail "no instrumentation-removal requirement"

echo ""
echo "Differential + bisection methods"
have "git bisect run" "bisection drives the Phase 1 loop to name the bad commit"
have "Differential loop" "a differential loop compares two variants (build/config/dataset/query-plan)"

echo ""
echo "Regression seam honesty + completion"
have "that is itself the finding" "an absent regression seam is reported, not faked"
have "Original repro green" "completion requires the original reproduction to pass again"

echo ""
if [ "$FAILS" -eq 0 ]; then echo "All diagnose static-invariant checks passed."; exit 0
else echo "$FAILS diagnose static-invariant check(s) FAILED."; exit 1; fi
