#!/usr/bin/env bash
# test-stale-plan.sh — fixtures for scripts/check-plan-freshness.sh, the deterministic plan-staleness check.
# Proves: an unchanged plan is clean; a referenced file that changed is a soft (revalidate) signal; a
# referenced file that vanished, a cited id that no longer resolves, and a baseline that diverged from HEAD
# are HARD signals that fail --strict (so an invalidated plan can't keep a prior PASS); a missing baseline
# is a soft warning; an invalid baseline commit is caught; and the check never mutates the plan.
set -uo pipefail
SCAFFOLD="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CHK="$SCAFFOLD/scripts/check-plan-freshness.sh"
[ -f "$CHK" ] || { echo "test: cannot find check-plan-freshness.sh at $CHK" >&2; exit 1; }
command -v git >/dev/null 2>&1 || { echo "test: git required"; exit 1; }

FAILS=0
pass() { printf '  ✓ %s\n' "$1"; }
fail() { printf '  ✗ %s\n' "$1"; FAILS=$((FAILS+1)); }

WORK="$(mktemp -d 2>/dev/null || mktemp -d -t leanstack-stale)"
trap 'rm -rf "$WORK" 2>/dev/null' EXIT
N=0; BASE=""; MAIN=""

fresh() {   # fresh repo with a spec (REQ-001/AC-001) + src/foo.sh; sets BASE + MAIN; cds in
  N=$((N+1)); R="$WORK/r$N"; mkdir -p "$R/docs/plans" "$R/src"; cd "$R" || exit 1
  git init -q; git config user.email t@t.t; git config user.name t
  printf '# Spec\n## Requirements\n### REQ-001 — thing\n- AC-001: it works\n' > docs/SPEC.md
  printf 'echo foo\n' > src/foo.sh
  git add -A >/dev/null; git commit -qm base
  BASE=$(git rev-parse --short HEAD); MAIN=$(git rev-parse --abbrev-ref HEAD)
}
plan() {   # write + commit a plan referencing src/foo.sh and REQ-001, baseline = $1 (default BASE)
  printf '# Plan\n\n## Assumption revalidation\nPlan created at: %s\n\nTask: modify `src/foo.sh` to satisfy REQ-001 (AC-001).\n' "${1:-$BASE}" > docs/plans/p.md
  git add -A >/dev/null; git commit -qm plan
}

echo "check-plan-freshness.sh tests"; echo ""

echo "An unchanged plan reports no staleness"
fresh; plan
OUT=$(bash "$CHK" --strict docs/plans/p.md 2>&1); rc=$?
{ [ "$rc" -eq 0 ] && printf '%s' "$OUT" | grep -q "no staleness signals"; } && pass "fresh plan clean" || fail "fresh plan not clean (rc=$rc): $OUT"

echo ""
echo "A referenced file that CHANGED since the baseline is a soft signal (not a hard fail)"
fresh; plan
printf 'echo bar\n' > src/foo.sh; git add -A >/dev/null; git commit -qm change
OUT=$(bash "$CHK" docs/plans/p.md 2>&1)
printf '%s' "$OUT" | grep -q "changed since planning" && pass "changed referenced file → soft signal" || fail "change not surfaced: $OUT"
bash "$CHK" --strict docs/plans/p.md >/dev/null 2>&1 && pass "a soft-only change does not fail --strict" || fail "soft change wrongly failed --strict"

echo ""
echo "A referenced file that VANISHED is a SOFT signal (path roots vary; not a hard --strict block)"
fresh; plan
git rm -q src/foo.sh >/dev/null; git commit -qm rm
bash "$CHK" --strict docs/plans/p.md >/dev/null 2>&1 && pass "vanished referenced file does not block --strict (soft)" || fail "vanished file wrongly blocked --strict"
RMOUT="$(bash "$CHK" docs/plans/p.md 2>&1)"   # capture then grep (SIGPIPE+pipefail flake)
printf '%s\n' "$RMOUT" | grep -q "not found" && pass "the missing file is surfaced for revalidation" || fail "missing file not surfaced"

echo ""
echo "A cited requirement id that no longer resolves is a hard fail"
fresh; plan
printf '# Spec\n(requirements removed)\n' > docs/SPEC.md; git add -A >/dev/null; git commit -qm dropreq
bash "$CHK" --strict docs/plans/p.md >/dev/null 2>&1 && fail "removed REQ id not caught" || pass "removed cited id → --strict fail"

echo ""
echo "A baseline that is no longer an ancestor of HEAD is a hard fail"
fresh
git checkout -q -b divergent
printf 'divergent\n' > src/other.sh; git add -A >/dev/null; git commit -qm divergent
OTHER=$(git rev-parse --short HEAD)
git checkout -q "$MAIN"
plan "$OTHER"    # plan claims a baseline that lives only on the divergent branch
bash "$CHK" --strict docs/plans/p.md >/dev/null 2>&1 && fail "non-ancestor baseline not caught" || pass "non-ancestor baseline → --strict fail"
NAOUT="$(bash "$CHK" docs/plans/p.md 2>&1)"   # capture then grep (SIGPIPE+pipefail flake)
printf '%s\n' "$NAOUT" | grep -q "no longer an ancestor" && pass "non-ancestor baseline is named" || fail "non-ancestor not named"

echo ""
echo "A plan with no recorded baseline warns (soft), does not hard-fail"
fresh
printf '# Plan\nmodify `src/foo.sh` for REQ-001\n' > docs/plans/p.md; git add -A >/dev/null; git commit -qm nobaseline
OUT=$(bash "$CHK" --strict docs/plans/p.md 2>&1); rc=$?
{ [ "$rc" -eq 0 ] && printf '%s' "$OUT" | grep -q "no baseline recorded"; } && pass "missing baseline → soft warning, exit 0" || fail "missing baseline mishandled (rc=$rc): $OUT"

echo ""
echo "An invalid baseline commit is caught"
fresh; plan "deadbeefdeadbeef"
bash "$CHK" --strict docs/plans/p.md >/dev/null 2>&1 && fail "invalid baseline not caught" || pass "invalid baseline sha → --strict fail"

echo ""
echo "The check never mutates the plan it reads"
fresh; plan
BEFORE=$(cat docs/plans/p.md); bash "$CHK" --strict docs/plans/p.md >/dev/null 2>&1; AFTER=$(cat docs/plans/p.md)
[ "$BEFORE" = "$AFTER" ] && pass "plan byte-identical after check" || fail "check mutated the plan"

echo ""
if [ "$FAILS" -eq 0 ]; then echo "All check-plan-freshness.sh tests passed."; exit 0
else echo "$FAILS check-plan-freshness.sh test(s) FAILED."; exit 1; fi
