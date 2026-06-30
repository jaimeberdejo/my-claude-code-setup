#!/usr/bin/env bash
# test-tick.sh — behavioral tests for the shared completion gate (scripts/tick.sh) and the
# authoritative evidence producer (scripts/test-evidence.sh). Runs the REAL scripts in
# throwaway git repos and asserts: a phase ticks ONLY with a PASS grade + fresh green test
# evidence bound to HEAD; every missing/stale/malformed/red/secret/high-stakes case is
# fail-closed and leaves docs/ROADMAP.md byte-identical. Exit 0 = all gates behave.
set -uo pipefail
SCAFFOLD="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TICK="$SCAFFOLD/scripts/tick.sh"
EVID="$SCAFFOLD/scripts/test-evidence.sh"
HS_LIB="$SCAFFOLD/.claude/lib/_high-stakes.sh"
SS_LIB="$SCAFFOLD/.claude/lib/_secret-scan.sh"
TC_LIB="$SCAFFOLD/.claude/lib/_test-cmd.sh"

FAILS=0
pass() { printf '  ✓ %s\n' "$1"; }
fail() { printf '  ✗ %s\n' "$1"; FAILS=$((FAILS+1)); }

for f in "$TICK" "$EVID" "$HS_LIB" "$SS_LIB" "$TC_LIB"; do
  [ -f "$f" ] || { echo "test: missing $f" >&2; exit 1; }
done
command -v jq  >/dev/null 2>&1 || { echo "test: jq required";  exit 1; }
command -v git >/dev/null 2>&1 || { echo "test: git required"; exit 1; }

WORK="$(mktemp -d 2>/dev/null || mktemp -d -t leanstack-tick)"
cleanup() { rm -rf "$WORK" 2>/dev/null; }
trap cleanup EXIT

# mkrepo <name> [path] [content]: a repo with one open phase and a committed phase change.
# Default change is a benign src file; pass path/content to plant high-stakes or secrets.
mkrepo() {
  REPO="$WORK/$1"; rm -rf "$REPO"
  local path="${2:-src/widget.py}" content="${3:-def widget(): return 1}"
  mkdir -p "$REPO/.claude/lib" "$REPO/scripts" "$REPO/docs"
  cp "$TICK" "$REPO/scripts/tick.sh"
  cp "$HS_LIB" "$REPO/.claude/lib/_high-stakes.sh"
  cp "$SS_LIB" "$REPO/.claude/lib/_secret-scan.sh"
  printf '## Phase 1 — Work\n\n- [ ] do the work\n' > "$REPO/docs/ROADMAP.md"
  printf 'next: work\n' > "$REPO/docs/STATE.md"
  cat > "$REPO/.gitignore" <<'GI'
NEXT_FINDINGS.md
test-results.json
.claude/.tick-evidence.json
.claude/.phase-base
.claude/.phase-ready
.claude/.phase-grade
GI
  ( cd "$REPO" && git init -q && git config user.email t@t.t && git config user.name t \
      && git config gc.auto 0 && git add -A && git commit -q -m init \
      && git rev-parse HEAD > .claude/.phase-base \
      && mkdir -p "$(dirname "$path")" && printf '%s\n' "$content" > "$path" \
      && git add -A && git commit -q -m build \
      && printf '## Phase 1 — Work\n' > .claude/.phase-ready )
  HEAD=$(git -C "$REPO" rev-parse HEAD)
}
# good evidence for the current HEAD; individual tests override pieces.
# First arg may be a short repo name (resolved under $WORK) or a full path.
_resolve()     { case "$1" in */*) printf '%s' "$1" ;; *) printf '%s/%s' "$WORK" "$1" ;; esac; }
set_grade()    { printf 'run_id=%s\nverdict=%s\nno_tests_ok=%s\n' "$2" "$3" "${4:-0}" > "$(_resolve "$1")/.claude/.phase-grade"; }
set_evidence() { printf '%s\n' "$2" > "$(_resolve "$1")/.claude/.tick-evidence.json"; }
good_grade()   { set_grade "$1" "$HEAD" PASS 0; }
good_evidence(){ set_evidence "$1" "{\"passed\":true,\"run_id\":\"$HEAD\"}"; }
runtick() { local r="$1"; shift; ( cd "$r" && bash scripts/tick.sh "$@" ) >"$WORK/out" 2>&1; echo $?; }
ticked()  { ! grep -q '\- \[ \] do the work' "$1/docs/ROADMAP.md"; }   # 0 if ticked
md5of()   { md5 -q "$1" 2>/dev/null || md5sum "$1" 2>/dev/null | cut -d' ' -f1; }

echo "tick gate tests"; echo ""

# 1 — PASS grade + fresh passed:true → ticks.
mkrepo t1; good_grade t1; good_evidence t1; rc=$(runtick "$REPO")
{ [ "$rc" = 0 ] && ticked "$REPO"; } && pass "PASS + fresh green evidence → ticks" || fail "did not tick on valid evidence (rc=$rc)"

# 2 — passed:false → refuses, roadmap unchanged, NEXT_FINDINGS written.
mkrepo t2; good_grade t2; set_evidence t2 "{\"passed\":false,\"run_id\":\"$HEAD\"}"
before=$(md5of "$REPO/docs/ROADMAP.md"); rc=$(runtick "$REPO")
{ [ "$rc" = 1 ] && ! ticked "$REPO" && [ "$before" = "$(md5of "$REPO/docs/ROADMAP.md")" ] && [ -f "$REPO/NEXT_FINDINGS.md" ]; } \
  && pass "passed:false → refuses, roadmap byte-identical, NEXT_FINDINGS written" || fail "passed:false mishandled (rc=$rc)"

# 3 — missing evidence file → refuses.
mkrepo t3; good_grade t3; rm -f "$REPO/.claude/.tick-evidence.json"; rc=$(runtick "$REPO")
{ [ "$rc" = 1 ] && ! ticked "$REPO"; } && pass "missing test evidence → refuses" || fail "missing evidence mishandled (rc=$rc)"

# 4 — malformed evidence JSON → refuses.
mkrepo t4; good_grade t4; set_evidence t4 "{not json"; rc=$(runtick "$REPO")
{ [ "$rc" = 1 ] && ! ticked "$REPO"; } && pass "malformed evidence → refuses" || fail "malformed evidence mishandled (rc=$rc)"

# 5 — stale evidence (run_id != HEAD) → refuses.
mkrepo t5; good_grade t5; set_evidence t5 "{\"passed\":true,\"run_id\":\"deadbeefstale\"}"; rc=$(runtick "$REPO")
{ [ "$rc" = 1 ] && ! ticked "$REPO"; } && pass "stale evidence (run_id mismatch) → refuses" || fail "stale evidence mishandled (rc=$rc)"

# 6a — passed:null + grade no_tests_ok=1 → ticks.
mkrepo t6; set_grade t6 "$HEAD" PASS 1; set_evidence t6 "{\"passed\":null,\"run_id\":\"$HEAD\"}"; rc=$(runtick "$REPO")
{ [ "$rc" = 0 ] && ticked "$REPO"; } && pass "passed:null + NO_TESTS_OK → ticks" || fail "null+NO_TESTS_OK did not tick (rc=$rc)"
# 6b — passed:null WITHOUT no_tests_ok → refuses.
mkrepo t6b; set_grade t6b "$HEAD" PASS 0; set_evidence t6b "{\"passed\":null,\"run_id\":\"$HEAD\"}"; rc=$(runtick "$REPO")
{ [ "$rc" = 1 ] && ! ticked "$REPO"; } && pass "passed:null without NO_TESTS_OK → refuses" || fail "null without confirm mishandled (rc=$rc)"

# 7a — missing grade → refuses.
mkrepo t7; good_evidence t7; rm -f "$REPO/.claude/.phase-grade"; rc=$(runtick "$REPO")
{ [ "$rc" = 1 ] && ! ticked "$REPO"; } && pass "missing evaluator grade → refuses" || fail "missing grade mishandled (rc=$rc)"
# 7b — grade run_id mismatch (stale grade) → refuses.
mkrepo t7b; set_grade t7b "oldsha" PASS 0; good_evidence t7b; rc=$(runtick "$REPO")
{ [ "$rc" = 1 ] && ! ticked "$REPO"; } && pass "stale grade (run_id mismatch) → refuses" || fail "stale grade mishandled (rc=$rc)"
# 7c — verdict != PASS → refuses.
mkrepo t7c; set_grade t7c "$HEAD" NEEDS_WORK 0; good_evidence t7c; rc=$(runtick "$REPO")
{ [ "$rc" = 1 ] && ! ticked "$REPO"; } && pass "non-PASS verdict → refuses" || fail "non-PASS verdict mishandled (rc=$rc)"

# 8 — secret in the phase diff → refuses, roadmap unchanged.
mkrepo t8 src/cfg.py 'AWS="AKIAIOSFODNN7EXAMPLE"'; good_grade t8; good_evidence t8
before=$(md5of "$REPO/docs/ROADMAP.md"); rc=$(runtick "$REPO")
{ [ "$rc" = 1 ] && ! ticked "$REPO" && [ "$before" = "$(md5of "$REPO/docs/ROADMAP.md")" ]; } \
  && pass "secret in phase diff → refuses, roadmap byte-identical" || fail "secret-in-diff mishandled (rc=$rc)"

# 9 — high-stakes PATH change → exit 3 (supervised), not ticked, NO NEXT_FINDINGS.
mkrepo t9 auth/login.py 'def login(): return True'; good_grade t9; good_evidence t9; rc=$(runtick "$REPO")
{ [ "$rc" = 3 ] && ! ticked "$REPO" && [ ! -f "$REPO/NEXT_FINDINGS.md" ]; } \
  && pass "high-stakes path → exit 3 supervised, not ticked" || fail "high-stakes path mishandled (rc=$rc)"

# 10 — already-ticked phase (no open item) → refuses.
mkrepo t10; good_grade t10; good_evidence t10
sed_i() { perl -i -pe 's/- \[ \] do the work/- [x] do the work/' "$1"; }
sed_i "$REPO/docs/ROADMAP.md"; rc=$(runtick "$REPO")
[ "$rc" = 1 ] && pass "no open item under heading → refuses" || fail "already-ticked mishandled (rc=$rc)"

echo ""
echo "test-evidence producer tests"; echo ""

mkevrepo() {
  REPO="$WORK/$1"; rm -rf "$REPO"
  mkdir -p "$REPO/.claude/lib" "$REPO/scripts"
  cp "$EVID" "$REPO/scripts/test-evidence.sh"; cp "$TC_LIB" "$REPO/.claude/lib/_test-cmd.sh"
  printf '.claude/.tick-evidence.json\n' > "$REPO/.gitignore"
  ( cd "$REPO" && git init -q && git config user.email t@t.t && git config user.name t \
      && git add -A && git commit -q -m init )
  HEAD=$(git -C "$REPO" rev-parse HEAD)
}

# e1 — green suite → exit 0, passed:true, run_id == HEAD.
mkevrepo e1; ( cd "$REPO" && LEAN_TEST_CMD=true bash scripts/test-evidence.sh >/dev/null 2>&1 ); erc=$?
ev="$REPO/.claude/.tick-evidence.json"
{ [ "$erc" = 0 ] && [ "$(jq -r .passed "$ev")" = true ] && [ "$(jq -r .run_id "$ev")" = "$HEAD" ]; } \
  && pass "test-evidence: green suite → exit0, passed:true, run_id==HEAD" || fail "green suite evidence wrong (rc=$erc)"

# e2 — red suite → exit 1, passed:false.
mkevrepo e2; ( cd "$REPO" && LEAN_TEST_CMD=false bash scripts/test-evidence.sh >/dev/null 2>&1 ); erc=$?
{ [ "$erc" = 1 ] && [ "$(jq -r .passed "$REPO/.claude/.tick-evidence.json")" = false ]; } \
  && pass "test-evidence: red suite → exit1, passed:false" || fail "red suite evidence wrong (rc=$erc)"

# e3 — no test command, default → exit 1 (fail-closed), passed:null.
mkevrepo e3; ( cd "$REPO" && bash scripts/test-evidence.sh >/dev/null 2>&1 ); erc=$?
{ [ "$erc" = 1 ] && [ "$(jq -r .passed "$REPO/.claude/.tick-evidence.json")" = null ]; } \
  && pass "test-evidence: no tests default → exit1 (fail-closed), passed:null" || fail "no-tests default wrong (rc=$erc)"

# e4 — no test command, --allow-no-tests → exit 0, passed:null.
mkevrepo e4; ( cd "$REPO" && bash scripts/test-evidence.sh --allow-no-tests >/dev/null 2>&1 ); erc=$?
{ [ "$erc" = 0 ] && [ "$(jq -r .passed "$REPO/.claude/.tick-evidence.json")" = null ]; } \
  && pass "test-evidence: no tests --allow-no-tests → exit0, passed:null" || fail "no-tests allow wrong (rc=$erc)"

echo ""
if [ "$FAILS" -eq 0 ]; then echo "All tick gate + evidence tests passed."; exit 0
else echo "$FAILS tick test(s) FAILED."; echo "--- last tick output ---"; tail -n 20 "$WORK/out" 2>/dev/null; exit 1; fi
