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
echo "Regression (v2.15.0) — cannot-verify is never reported as verified"

# A LARGE changed-set. v2.14.0 tested membership with `printf "$CHANGED" | grep -qxF "$f"` under
# `set -o pipefail`: grep -q exits at the first match, printf then takes SIGPIPE once CHANGED exceeds
# the 64KB pipe buffer, and pipefail promotes 141 over grep's 0 — so the condition read FALSE and the
# changed file was silently reported unchanged. The old one-file fixture could never see it: the race
# needs the name list to OVERFLOW THE PIPE BUFFER *and* the match to sort early. Long padding names
# reach the byte threshold with few enough files to stay fast.
PAD='src/pad/a_deliberately_long_padding_file_name_to_overflow_the_pipe_buffer'
fresh
mkdir -p src/pad
for i in $(seq 1 3000); do printf 'x\n' > "${PAD}_$i.txt"; done
printf 'echo aaa\n' > src/aaa_first.txt                            # sorts FIRST in the changed list
git add -A >/dev/null; git commit -qm pad
BIGBASE=$(git rev-parse --short HEAD)
printf '# Plan\n\nPlan created at: %s\n\nTask: modify `src/aaa_first.txt` to satisfy REQ-001 (AC-001).\n' "$BIGBASE" > docs/plans/big.md
printf 'echo CHANGED\n' > src/aaa_first.txt
for i in $(seq 1 3000); do printf 'y\n' > "${PAD}_$i.txt"; done
git add -A >/dev/null; git commit -qm "move the world"
CHANGED_N=$(git diff --name-only "$BIGBASE" HEAD | wc -l | tr -d ' ')
CHANGED_B=$(git diff --name-only "$BIGBASE" HEAD | wc -c | tr -d ' ')
# GUARD: below the pipe buffer this fixture cannot exercise the race, and the test would pass against
# the BUGGY code — a green test that proves nothing. Fail loudly instead of silently going vacuous.
if [ "$CHANGED_B" -lt 65536 ]; then
  fail "fixture too small to exercise the SIGPIPE race (${CHANGED_B}B < 64KB) — this test would pass against the bug"
else
  BIG_OUT=$(bash "$CHK" docs/plans/big.md 2>&1)
  if printf '%s\n' "$BIG_OUT" | grep -q "src/aaa_first.txt"; then
    pass "a changed file is detected across a large changed-set (${CHANGED_N} paths / ${CHANGED_B}B > 64KB, no SIGPIPE)"
  else
    fail "large changed-set: a provably-changed cited file was silently reported fresh"
  fi
fi

# The id-resolution check is one of the three HARD blockers, so an absent target must fail CLOSED.
# v2.14.0 wrapped it in `if [ -f "$tgt" ]`, so DELETING docs/SPEC.md — the most complete form of
# "the requirement was removed" — produced a maximally confident all-clear.
fresh; plan
rm -f docs/SPEC.md
bash "$CHK" --strict docs/plans/p.md >/dev/null 2>&1 && \
  fail "cited id + missing docs/SPEC.md exited 0 (unverifiable reported as verified)" || \
  pass "cited id + missing docs/SPEC.md → --strict fails (unverifiable is not verified)"

# $tgt was a CWD-relative literal, so the same plan passed from a subdir and failed from the root.
fresh; plan
mkdir -p sub
( cd sub && bash "$CHK" --strict ../docs/plans/p.md >/dev/null 2>&1 )
RC_SUB=$?
( cd "$R" && bash "$CHK" --strict docs/plans/p.md >/dev/null 2>&1 )
RC_ROOT=$?
[ "$RC_SUB" = "$RC_ROOT" ] && pass "verdict is the same from a subdirectory as from the repo root (rc=$RC_ROOT)" \
                           || fail "verdict is CWD-dependent (sub=$RC_SUB root=$RC_ROOT)"
# and prove the subdir case is a REAL verdict, not a rc=2 "no such plan file" accident
[ "$RC_SUB" -le 1 ] && pass "the subdirectory run actually resolved the plan (rc<=1, not a usage error)" \
                    || fail "subdirectory run did not resolve the plan (rc=$RC_SUB)"

# "Baseline commit: <sha>" is a label used in the wild, but the old skip class [^0-9a-f]* could not
# cross the "c" of "commit" (c is a hex digit), so that label never parsed and freshness fell back
# to "undetermined" — a soft signal, exit 0.
fresh
printf '# Plan\n\nBaseline commit: %s\n\nTask: modify `src/foo.sh` to satisfy REQ-001 (AC-001).\n' "$BASE" > docs/plans/bc.md
BC_OUT=$(bash "$CHK" docs/plans/bc.md 2>&1)
printf '%s\n' "$BC_OUT" | grep -q "no baseline recorded" && \
  fail "'Baseline commit:' label did not parse (freshness silently undetermined)" || \
  pass "'Baseline commit:' parses as a baseline label"

echo ""
if [ "$FAILS" -eq 0 ]; then echo "All check-plan-freshness.sh tests passed."; exit 0
else echo "$FAILS check-plan-freshness.sh test(s) FAILED."; exit 1; fi
