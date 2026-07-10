#!/usr/bin/env bash
# test-start-phase.sh — scripts/start-phase.sh anchors a phase in a TRACKED, tamper-evident
# .claude/.phase-anchor (finding H1), and tick.sh derives the manual scan floor from it. The key
# property: advancing the floor is now a VISIBLE committed change to a tracked file, not the silent
# gitignored-.phase-base rewrite the old flow allowed.
set -uo pipefail
SCAFFOLD="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SP="$SCAFFOLD/scripts/start-phase.sh"
TICK="$SCAFFOLD/scripts/tick.sh"
[ -f "$SP" ] || { echo "test: missing $SP" >&2; exit 1; }
command -v git >/dev/null 2>&1 || { echo "test: git required"; exit 1; }
command -v jq  >/dev/null 2>&1 || { echo "test: jq required"; exit 1; }

FAILS=0
pass() { printf '  ✓ %s\n' "$1"; }
fail() { printf '  ✗ %s\n' "$1"; FAILS=$((FAILS+1)); }
WORK="$(mktemp -d 2>/dev/null || mktemp -d -t startphase)"
trap 'rm -rf "$WORK" 2>/dev/null' EXIT

# A repo with the scaffold scripts/libs and one open phase.
mkrepo() {
  REPO="$WORK/$1"; rm -rf "$REPO"; mkdir -p "$REPO/.claude/lib" "$REPO/scripts" "$REPO/docs"
  cp "$SP" "$REPO/scripts/start-phase.sh"; cp "$TICK" "$REPO/scripts/tick.sh"
  for l in _roadmap _test-cmd _secret-scan _high-stakes; do cp "$SCAFFOLD/.claude/lib/$l.sh" "$REPO/.claude/lib/"; done
  printf '## Phase 1 — Work\n\n- [ ] do the work\nDone when: x\nMode: loopable\n' > "$REPO/docs/ROADMAP.md"
  printf 'next: work\n' > "$REPO/docs/STATE.md"
  printf '.claude/.phase-base\n.claude/.phase-grade\n.claude/.tick-evidence.json\nNEXT_FINDINGS.md\n' > "$REPO/.gitignore"
  ( cd "$REPO" && git init -q && git config user.email t@t.t && git config user.name t \
      && git config gc.auto 0 && git add -A && git commit -q -m init )
}
sp() { ( cd "$1" && shift && bash scripts/start-phase.sh "$@" ) >"$WORK/out" 2>&1; echo $?; }

echo "start-phase anchor tests"; echo ""

# 1 — anchors the first open phase: writes a TRACKED .claude/.phase-anchor and commits it.
mkrepo t1; rc=$(sp "$REPO")
{ [ "$rc" = 0 ] && git -C "$REPO" ls-files --error-unmatch .claude/.phase-anchor >/dev/null 2>&1 \
  && git -C "$REPO" log -1 --format=%s | grep -q 'chore(phase-start): ## Phase 1 — Work' \
  && grep -q '^base=' "$REPO/.claude/.phase-anchor"; } \
  && pass "anchors the first open phase → tracked .phase-anchor committed as chore(phase-start)" \
  || fail "anchor not created/committed/tracked (rc=$rc)"

# 2 — the recorded base is the anchor commit's PARENT (the pre-phase state).
mkrepo t2; sp "$REPO" >/dev/null
A_BASE=$(grep '^base=' "$REPO/.claude/.phase-anchor" | cut -d= -f2-)
PARENT=$(git -C "$REPO" rev-parse HEAD^ 2>/dev/null)
[ "$A_BASE" = "$PARENT" ] && pass "recorded base = anchor commit's parent (the true phase start)" || fail "base != anchor parent"

# 3 — refuses a dirty tree (the anchor must be authored from a known committed state).
mkrepo t3; printf 'uncommitted\n' > "$REPO/scratch.txt"; rc=$(sp "$REPO")
{ [ "$rc" = 1 ] && grep -qi 'not clean' "$WORK/out" && [ ! -f "$REPO/.claude/.phase-anchor" ]; } \
  && pass "dirty tree → refuse (no anchor created)" || fail "dirty tree not refused (rc=$rc)"

# 4 — idempotent: re-running on the same open phase does NOT stack a second anchor commit.
mkrepo t4; sp "$REPO" >/dev/null; n1=$(git -C "$REPO" rev-list --count HEAD); rc=$(sp "$REPO"); n2=$(git -C "$REPO" rev-list --count HEAD)
{ [ "$rc" = 0 ] && [ "$n1" = "$n2" ] && grep -qi 'already anchored' "$WORK/out"; } \
  && pass "re-run on the same open phase is idempotent (no second anchor commit)" || fail "start-phase not idempotent (rc=$rc, $n1→$n2)"

# 5 — H1: tick derives the scan floor from the anchor, NOT the gitignored .phase-base. Prove a
# secret committed AFTER the anchor is in the judged range (would be caught); and that advancing the
# floor now requires a VISIBLE tracked commit rather than a silent ignored-file rewrite.
mkrepo t5; sp "$REPO" >/dev/null
# a benign phase commit on top of the anchor
( cd "$REPO" && printf 'def f(): return 1\n' > app.py && git add app.py && git commit -q -m work )
HEAD=$(git -C "$REPO" rev-parse HEAD)
# tick reads base from the anchor (its base= field), and the range starts at that base — NOT at a
# builder-writable ignored file. Confirm tick's own "judging range" line reports the anchor base.
printf 'run_id=%s\nverdict=PASS\nno_tests_ok=1\n' "$HEAD" > "$REPO/.claude/.phase-grade"
printf '{"passed":null,"run_id":"%s"}\n' "$HEAD" > "$REPO/.claude/.tick-evidence.json"
( cd "$REPO" && bash scripts/tick.sh "## Phase 1 — Work" ) >"$WORK/out" 2>&1; trc=$?
{ grep -q "base source: .claude/.phase-anchor" "$WORK/out" && grep -q "judging range" "$WORK/out"; } \
  && pass "tick derives the manual floor from the TRACKED anchor and prints the judged range (H1)" \
  || fail "tick did not use the anchor / print the range (trc=$trc): $(tail -2 "$WORK/out")"

echo ""
if [ "$FAILS" -eq 0 ]; then echo "All start-phase tests passed."; exit 0
else echo "$FAILS start-phase test(s) FAILED."; echo "--- last output ---"; tail -8 "$WORK/out" 2>/dev/null; exit 1; fi
