#!/usr/bin/env bash
# record-grade.sh — write .claude/.phase-grade from an evaluator verdict so scripts/tick.sh can
# verify a phase was independently graded PASS. Used by the in-session /wrap and /autopilot tick
# paths; scripts/autopilot.sh (headless) calls it too, so the grade-file format has ONE writer.
#
# Stamps run_id = HEAD to bind the grade to the exact commit tick.sh will check. Refuses (writes
# nothing, exit 1) unless the verdict's LAST non-empty line is exactly PASS — a NEEDS_WORK or
# garbled verdict can never become a tick. If the verdict text contains NO_TESTS_OK, records it
# so tick.sh may accept a phase that legitimately has no test suite.
#
# Also refuses on a DIRTY tracked tree (audit G12): run_id=HEAD is only an honest description of
# what was graded if every tracked file is committed. Headless already guarantees this — autopilot.sh
# calls us only after eval_restore has proven the tree matches its pre-grade snapshot — but the
# manual /wrap path had no such check, so an evaluator that wrote to the live checkout could have its
# contaminated grade recorded against a HEAD that contains none of it.
#
# Usage: bash scripts/record-grade.sh "<full evaluator verdict text>"
set -uo pipefail
cd "$(git rev-parse --show-toplevel 2>/dev/null || echo .)" || exit 1

case "${1:-}" in
  -h|--help)
    echo "usage: record-grade.sh \"<full evaluator verdict text>\""
    echo "  Writes .claude/.phase-grade (run_id=HEAD) only if the verdict's last non-empty line is PASS."
    exit 0 ;;
esac
VERDICT="${1:-}"
[ -n "$VERDICT" ] || { echo "record-grade: pass the evaluator's verdict text as argument 1." >&2; exit 1; }

# Anchored: trust ONLY the last non-empty line, exactly like scripts/autopilot.sh.
LAST=$(printf '%s\n' "$VERDICT" | grep -vE '^[[:space:]]*$' | tail -1)
if [ "$LAST" != "PASS" ]; then
  echo "record-grade: evaluator verdict is not PASS (last line: '$LAST') — no grade recorded." >&2
  exit 1
fi

# Fail-closed on a dirty tracked tree. Untracked files are deliberately NOT considered: autopilot.log,
# NEXT_FINDINGS.md and the gitignored evidence files are untracked by design and say nothing about
# whether HEAD describes the graded code. This is the same window eval_restore asserts before it
# returns 0, so the headless path (which runs eval_restore first) reaches here already clean.
git rev-parse --is-inside-work-tree >/dev/null 2>&1 || {
  echo "record-grade: not a git repo — a grade must bind to a commit (fail-closed, nothing recorded)." >&2; exit 1; }
DIRTY=$(git status --porcelain --untracked-files=no 2>/dev/null)
if [ -n "$DIRTY" ]; then
  echo "record-grade: the tracked tree is DIRTY — refusing to record a grade that HEAD does not describe." >&2
  echo "  A grade must describe a clean, committed tree. If the evaluator wrote these files the grade is" >&2
  echo "  untrustworthy: discard them and re-grade. Uncommitted tracked changes:" >&2
  printf '%s\n' "$DIRTY" | sed 's/^/    /' >&2
  exit 1
fi

NO_TESTS_OK=0
# Match NO_TESTS_OK only as a leading token on its OWN line (per evaluator.md's contract), not as a
# bare substring — the verdict text is diff-influenced, so an incidental `NO_TESTS_OK` echoed from
# code the evaluator quoted must NOT flip the flag and let a passed:null phase skip the test gate.
printf '%s\n' "$VERDICT" | grep -qE '^[[:space:]]*NO_TESTS_OK([[:space:]]|$)' && NO_TESTS_OK=1

mkdir -p .claude
{
  echo "run_id=$(git rev-parse HEAD 2>/dev/null)"
  echo "verdict=PASS"
  echo "no_tests_ok=$NO_TESTS_OK"
} > .claude/.phase-grade
echo "record-grade: recorded PASS (no_tests_ok=$NO_TESTS_OK) at $(git rev-parse --short HEAD 2>/dev/null)."
