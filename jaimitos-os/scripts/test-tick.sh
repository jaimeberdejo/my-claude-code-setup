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
RG="$SCAFFOLD/scripts/record-grade.sh"
HS_LIB="$SCAFFOLD/.claude/lib/_high-stakes.sh"
SS_LIB="$SCAFFOLD/.claude/lib/_secret-scan.sh"
TC_LIB="$SCAFFOLD/.claude/lib/_test-cmd.sh"

FAILS=0
pass() { printf '  ✓ %s\n' "$1"; }
fail() { printf '  ✗ %s\n' "$1"; FAILS=$((FAILS+1)); }

for f in "$TICK" "$EVID" "$RG" "$HS_LIB" "$SS_LIB" "$TC_LIB"; do
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
  cp "$SCAFFOLD/.claude/lib/_roadmap.sh" "$REPO/.claude/lib/_roadmap.sh"
  cp "$SCAFFOLD/.claude/lib/_phase-range.sh" "$REPO/.claude/lib/_phase-range.sh"
  printf '## Phase 1 — Work\n\n- [ ] do the work\n' > "$REPO/docs/ROADMAP.md"
  printf 'next: work\n' > "$REPO/docs/STATE.md"
  cat > "$REPO/.gitignore" <<'GI'
NEXT_FINDINGS.md
test-results.json
.claude/.tick-evidence.json
.claude/.phase-base
.claude/.phase-ready
.claude/.phase-grade
.claude/.supervised-approval
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
# The heading tick judges (from .phase-ready) and the base the resolver reads (from .phase-base, or the
# anchor if present) — the v2.17 grade/evidence binding must stamp these so they match the phase window.
GRADE_HEADING='## Phase 1 — Work'
_base() { local r; r="$(_resolve "$1")"; if [ -f "$r/.claude/.phase-anchor" ]; then grep -E '^base=' "$r/.claude/.phase-anchor" | head -1 | cut -d= -f2-; else cat "$r/.claude/.phase-base" 2>/dev/null; fi; }
set_grade()    { printf 'run_id=%s\nverdict=%s\nno_tests_ok=%s\nheading=%s\nbase=%s\n' "$2" "$3" "${4:-0}" "$GRADE_HEADING" "$(_base "$1")" > "$(_resolve "$1")/.claude/.phase-grade"; }
set_evidence() { printf '%s\n' "$2" > "$(_resolve "$1")/.claude/.tick-evidence.json"; }
good_grade()   { set_grade "$1" "$HEAD" PASS 0; }
good_evidence(){ set_evidence "$1" "{\"schema_version\":3,\"passed\":true,\"run_id\":\"$HEAD\",\"heading\":\"$GRADE_HEADING\",\"base\":\"$(_base "$1")\"}"; }
# set_mode <repo> <mode>: append a `Mode: <mode>` line to docs/ROADMAP.md AND COMMIT it, then
# re-capture HEAD. Real roadmaps carry their Mode lines in git, so the tree is clean at tick time;
# the fixtures used to append WITHOUT committing, which tick.sh's clean-tree gate (H5) now correctly
# refuses. Callers must (re-)grade after this, since HEAD advances.
set_mode() {
  local r; r="$(_resolve "$1")"
  ( cd "$r" && printf 'Mode: %s\n' "$2" >> docs/ROADMAP.md && git add docs/ROADMAP.md && git commit -q -m "mark $2" )
  HEAD=$(git -C "$r" rev-parse HEAD)
}
runtick() { local r="$1"; shift; ( cd "$r" && bash scripts/tick.sh "$@" ) >"$WORK/out" 2>&1; echo $?; }
# Like runtick but passes the orchestrator-trusted base via the TICK_BASE env var (headless autopilot
# path). An empty base ("") is passed as SET-but-empty (distinct from unset) to exercise fail-closed.
runtick_base() { local r="$1" b="$2"; shift 2; ( cd "$r" && TICK_BASE="$b" bash scripts/tick.sh "$@" ) >"$WORK/out" 2>&1; echo $?; }
ticked()  { ! grep -q '\- \[ \] do the work' "$1/docs/ROADMAP.md"; }   # 0 if ticked
md5of()   { md5 -q "$1" 2>/dev/null || md5sum "$1" 2>/dev/null | cut -d' ' -f1; }

echo "tick gate tests"; echo ""

# 1 — PASS grade + fresh passed:true → ticks AND updates the STATE machine block.
mkrepo t1; good_grade t1; good_evidence t1; rc=$(runtick "$REPO")
{ [ "$rc" = 0 ] && ticked "$REPO"; } && pass "PASS + fresh green evidence → ticks" || fail "did not tick on valid evidence (rc=$rc)"
{ grep -q "lean:auto:begin" "$REPO/docs/STATE.md" && grep -q "Last ticked" "$REPO/docs/STATE.md"; } \
  && pass "successful tick writes the STATE machine block" || fail "STATE machine block not written on tick"

# 1b — v2.14.0: explicit schema_version 2 evidence is accepted (v2 is a superset of v1).
mkrepo t1b; good_grade t1b; set_evidence t1b "{\"schema_version\":2,\"passed\":true,\"run_id\":\"$HEAD\"}"; rc=$(runtick "$REPO")
{ [ "$rc" = 0 ] && ticked "$REPO"; } && pass "schema_version 2 evidence → ticks" || fail "v2 evidence not accepted (rc=$rc)"
# 1c — an unknown/future schema_version fails CLOSED (don't trust evidence from a producer we can't read).
mkrepo t1c; good_grade t1c; set_evidence t1c "{\"schema_version\":99,\"passed\":true,\"run_id\":\"$HEAD\"}"; rc=$(runtick "$REPO")
{ [ "$rc" = 1 ] && ! ticked "$REPO"; } && pass "unknown schema_version 99 → refuses (fail-closed)" || fail "unknown schema_version not rejected (rc=$rc)"

# --- M4 (v2.17): grade/evidence bind to phase identity (heading+base), not just HEAD ---
# 1d — a grade whose base is a DIFFERENT window (here HEAD, a valid commit but not this phase's base)
#      is refused, even though run_id==HEAD — no cross-phase grade reuse at the same commit.
mkrepo t1d; good_evidence t1d
printf 'run_id=%s\nverdict=PASS\nno_tests_ok=0\nheading=%s\nbase=%s\n' "$HEAD" "$GRADE_HEADING" "$HEAD" > "$REPO/.claude/.phase-grade"
rc=$(runtick "$REPO")
{ [ "$rc" = 1 ] && ! ticked "$REPO" && grep -qi 'different phase window' "$WORK/out"; } \
  && pass "M4: grade bound to a wrong base → refuse (no cross-window reuse)" || fail "M4 wrong-base grade not refused (rc=$rc)"

# 1e — a grade for a DIFFERENT heading (another phase at the same HEAD) is refused.
mkrepo t1e; good_evidence t1e
printf 'run_id=%s\nverdict=PASS\nno_tests_ok=0\nheading=%s\nbase=%s\n' "$HEAD" '## Phase 9 — Elsewhere' "$(_base t1e)" > "$REPO/.claude/.phase-grade"
rc=$(runtick "$REPO")
{ [ "$rc" = 1 ] && ! ticked "$REPO" && grep -qi 'cross-phase grade reuse' "$WORK/out"; } \
  && pass "M4: grade for a different heading → refuse (cross-phase reuse)" || fail "M4 wrong-heading grade not refused (rc=$rc)"

# 1f — a stale pre-v2.17 grade (no heading/base fields) → refuse; must re-record to bind it.
mkrepo t1f; good_evidence t1f
printf 'run_id=%s\nverdict=PASS\nno_tests_ok=0\n' "$HEAD" > "$REPO/.claude/.phase-grade"
rc=$(runtick "$REPO")
{ [ "$rc" = 1 ] && ! ticked "$REPO" && grep -qi 'pre-v2.17 grade' "$WORK/out"; } \
  && pass "M4: unbound pre-v2.17 grade → refuse (re-record required)" || fail "M4 unbound grade not refused (rc=$rc)"

# 1g — schema-3 evidence for a DIFFERENT window → refuse (evidence reuse across phases).
mkrepo t1g; good_grade t1g
set_evidence t1g "{\"schema_version\":3,\"passed\":true,\"run_id\":\"$HEAD\",\"heading\":\"$GRADE_HEADING\",\"base\":\"$HEAD\"}"
rc=$(runtick "$REPO")
{ [ "$rc" = 1 ] && ! ticked "$REPO" && grep -qi 'evidence.*different phase window' "$WORK/out"; } \
  && pass "M4: evidence bound to a wrong base → refuse" || fail "M4 wrong-base evidence not refused (rc=$rc)"

# 1h — schema-3 evidence whose content_hash does not match its body → refuse (tamper-evident).
mkrepo t1h; good_grade t1h
set_evidence t1h "{\"schema_version\":3,\"passed\":true,\"run_id\":\"$HEAD\",\"heading\":\"$GRADE_HEADING\",\"base\":\"$(_base t1h)\",\"content_hash\":\"deadbeefdeadbeef\"}"
rc=$(runtick "$REPO")
{ [ "$rc" = 1 ] && ! ticked "$REPO" && grep -qi 'content_hash mismatch' "$WORK/out"; } \
  && pass "M4: evidence content_hash tamper → refuse" || fail "M4 content_hash tamper not refused (rc=$rc)"

# 1i — POSITIVE: a schema-3 evidence carrying the REAL content_hash (computed like test-evidence.sh)
#      + matching heading/base ticks — proves the hash check does not false-reject honest evidence.
mkrepo t1i; good_grade t1i
body="{\"schema_version\":3,\"passed\":true,\"run_id\":\"$HEAD\",\"heading\":\"$GRADE_HEADING\",\"base\":\"$(_base t1i)\"}"
ch=$(printf '%s' "$body" | jq -cS 'del(.content_hash)' | { shasum -a 256 2>/dev/null || sha256sum 2>/dev/null; } | cut -d' ' -f1)
set_evidence t1i "$(printf '%s' "$body" | jq -c --arg h "$ch" '. + {content_hash:$h}')"
rc=$(runtick "$REPO")
{ [ "$rc" = 0 ] && ticked "$REPO"; } && pass "M4: valid schema-3 evidence (real content_hash) → ticks" || fail "M4 valid v3 evidence did not tick (rc=$rc)"

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

# 5b — missing .claude/.phase-base → refuses (would otherwise narrow secret/high-stakes scan).
mkrepo t5b; good_grade t5b; good_evidence t5b; rm -f "$REPO/.claude/.phase-base"; rc=$(runtick "$REPO")
{ [ "$rc" = 1 ] && ! ticked "$REPO"; } && pass "missing .phase-base → refuses (no scan-window narrowing)" || fail "missing phase-base mishandled (rc=$rc)"

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

# 9b — high-stakes CONTENT in a benignly-named path → exit 3, not ticked.
mkrepo t9b src/utils.py 'cursor.execute("DROP TABLE users")'; good_grade t9b; good_evidence t9b; rc=$(runtick "$REPO")
{ [ "$rc" = 3 ] && ! ticked "$REPO"; } && pass "high-stakes content (DROP TABLE in benign path) → exit 3" || fail "content high-stakes mishandled (rc=$rc)"

# 9c — a phase marked "Mode: supervised" → exit 3 (enforced), not ticked.
mkrepo t9c; set_mode t9c supervised; good_grade t9c; good_evidence t9c; rc=$(runtick "$REPO")
{ [ "$rc" = 3 ] && ! ticked "$REPO"; } && pass "Mode: supervised → exit 3 (tag enforced, not auto-ticked)" || fail "Mode:supervised not enforced (rc=$rc)"

# 9d (C1) — phase edits the high-stakes path ALLOWLIST → exit 3 (a phase cannot self-EXEMPT the gate
# by adding its own allowlist line in the same commit tick.sh then reads). The allowlist path is not
# itself in HIGH_STAKES_RE, so only the new gate-config guard catches this.
mkrepo t9d .claude/high-stakes-path-allowlist 'src/foo.py: reviewed, safe'; good_grade t9d; good_evidence t9d; rc=$(runtick "$REPO")
{ [ "$rc" = 3 ] && ! ticked "$REPO" && [ ! -f "$REPO/NEXT_FINDINGS.md" ]; } \
  && pass "phase edits high-stakes-path-allowlist → exit 3 (no self-exempt)" || fail "allowlist-in-diff not gated (rc=$rc)"

# 9g (H4/N-4) — a malformed HIGH_STAKES_RE must make tick REFUSE (fail-closed), NOT tick. Before the
# three-state matcher + three-way caller, `if HS=$(high_stakes_match ...)` swallowed the matcher's
# error rc exactly like "no match", so a typo'd ENFORCED regex silently disabled the gate and the
# phase auto-ticked. The malformed regex is committed BEFORE the phase base (so editing the lib is not
# itself the in-phase gate-config change 9d/9e cover) — this isolates the matcher-error path.
mkrepo t9g
# overwrite the copied lib's regex with an uncompilable one, and re-baseline so the edit is pre-phase
sed -i.bak "s|^HIGH_STAKES_RE=.*|HIGH_STAKES_RE='['|" "$REPO/.claude/lib/_high-stakes.sh" && rm -f "$REPO/.claude/lib/_high-stakes.sh.bak"
( cd "$REPO" && git add -A && git commit -q -m 'break the regex (pre-phase)' \
    && git rev-parse HEAD > .claude/.phase-base \
    && printf 'def widget2(): return 2\n' > src/widget2.py && git add -A && git commit -q -m 'phase work' )
HEAD=$(git -C "$REPO" rev-parse HEAD); good_grade t9g; good_evidence t9g; rc=$(runtick "$REPO")
{ [ "$rc" != 0 ] && ! ticked "$REPO"; } \
  && pass "malformed HIGH_STAKES_RE → tick refuses (fail-closed, rc=$rc), not ticked" \
  || fail "malformed HIGH_STAKES_RE FAILED OPEN — tick proceeded (rc=$rc)"

# 9e (C1) — phase modifies the high-stakes matcher LIB (_high-stakes.sh) → exit 3 (a phase cannot
# self-NARROW the gate by shrinking HIGH_STAKES_RE in the same commit). Bespoke fixture: mkrepo
# commits _high-stakes.sh at INIT (before phase-base), so we modify it INSIDE the phase — appending
# a harmless comment (the lib still sources cleanly; a garbage overwrite would instead trip tick's
# "library unavailable" refuse, rc=1) — then re-stamp grade+evidence against the new HEAD.
mkrepo t9e
( cd "$REPO" && printf '# v2.2.1 regression tweak (still valid bash, sourced return is above)\n' >> .claude/lib/_high-stakes.sh \
    && git add -A && git commit -q -m tweak-hslib )
HEAD=$(git -C "$REPO" rev-parse HEAD)
good_grade t9e; good_evidence t9e; rc=$(runtick "$REPO")
{ [ "$rc" = 3 ] && ! ticked "$REPO" && [ ! -f "$REPO/NEXT_FINDINGS.md" ]; } \
  && pass "phase modifies _high-stakes.sh → exit 3 (no self-narrow)" || fail "_high-stakes.sh-in-diff not gated (rc=$rc)"

# 9f (C1 control) — a PRE-EXISTING allowlist entry (committed BEFORE phase-base, so NOT in the phase
# diff) must still suppress a high-stakes path changed in the phase → exit 0 ticks. Proves the guard
# fires ONLY on an in-phase gate-config change and does not break legitimate pre-existing allowlists.
REPO="$WORK/t9f"; rm -rf "$REPO"; mkdir -p "$REPO/.claude/lib" "$REPO/scripts" "$REPO/docs"
cp "$TICK" "$REPO/scripts/tick.sh"; cp "$HS_LIB" "$REPO/.claude/lib/_high-stakes.sh"; cp "$SS_LIB" "$REPO/.claude/lib/_secret-scan.sh"; cp "$SCAFFOLD/.claude/lib/_roadmap.sh" "$REPO/.claude/lib/_roadmap.sh"; cp "$SCAFFOLD/.claude/lib/_phase-range.sh" "$REPO/.claude/lib/_phase-range.sh"
printf '## Phase 1 — Work\n\n- [ ] do the work\n' > "$REPO/docs/ROADMAP.md"
printf 'next: work\n' > "$REPO/docs/STATE.md"
printf 'auth/login.py: reviewed at init, pre-existing entry\n' > "$REPO/.claude/high-stakes-path-allowlist"
cat > "$REPO/.gitignore" <<'GI'
NEXT_FINDINGS.md
.claude/.tick-evidence.json
.claude/.phase-base
.claude/.phase-ready
.claude/.phase-grade
GI
( cd "$REPO" && git init -q && git config user.email t@t.t && git config user.name t && git config gc.auto 0 \
    && git add -A && git commit -q -m init \
    && git rev-parse HEAD > .claude/.phase-base \
    && mkdir -p auth && printf 'def login(): return True\n' > auth/login.py \
    && git add -A && git commit -q -m build \
    && printf '## Phase 1 — Work\n' > .claude/.phase-ready )
HEAD=$(git -C "$REPO" rev-parse HEAD)
good_grade t9f; good_evidence t9f; rc=$(runtick "$REPO")
{ [ "$rc" = 0 ] && ticked "$REPO"; } \
  && pass "pre-existing allowlist entry (not in phase diff) still suppresses → ticks" || fail "pre-existing allowlist not honored (rc=$rc)"

# 10 — already-ticked phase (no open item) → refuses.
mkrepo t10; good_grade t10; good_evidence t10
sed_i() { perl -i -pe 's/- \[ \] do the work/- [x] do the work/' "$1"; }
sed_i "$REPO/docs/ROADMAP.md"; rc=$(runtick "$REPO")
[ "$rc" = 1 ] && pass "no open item under heading → refuses" || fail "already-ticked mishandled (rc=$rc)"

# 11 — heading not present verbatim as a line → refuses (heading-existence gate).
mkrepo t11; good_grade t11; good_evidence t11; rc=$(runtick "$REPO" "## Phase 99 — Nope")
{ [ "$rc" = 1 ] && ! ticked "$REPO"; } && pass "bogus heading (absent) → refuses" || fail "bogus heading mishandled (rc=$rc)"
# 11b — a substring of a real heading (not a full line) → refuses (exact -x match hardening).
mkrepo t11b; good_grade t11b; good_evidence t11b; rc=$(runtick "$REPO" "Phase 1")
{ [ "$rc" = 1 ] && ! ticked "$REPO"; } && pass "heading substring (not a full line) → refuses" || fail "heading substring mishandled (rc=$rc)"

# 12 — malformed/garbage grade file (no run_id=/verdict= fields) → refuses.
mkrepo t12; good_evidence t12; printf 'garbage not a grade\n' > "$REPO/.claude/.phase-grade"; rc=$(runtick "$REPO")
{ [ "$rc" = 1 ] && ! ticked "$REPO"; } && pass "malformed grade file → refuses" || fail "malformed grade mishandled (rc=$rc)"

# 13 — invalid .claude/.phase-base → secret scan cannot resolve the range → fail-closed refuse
#      (guards against a forged/rewritten base silently narrowing OR bypassing the secret/high-stakes scan).
mkrepo t13; good_grade t13; good_evidence t13
printf 'deadbeefdeadbeefdeadbeefdeadbeefdeadbeef\n' > "$REPO/.claude/.phase-base"; rc=$(runtick "$REPO")
{ [ "$rc" = 1 ] && ! ticked "$REPO"; } && pass "invalid .phase-base (unresolvable range) → fail-closed refuse" || fail "invalid phase-base mishandled (rc=$rc)"

# --- TICK_BASE env (headless autopilot passes the orchestrator-derived TRUSTED base) ---

# 14 — a FORGED .claude/.phase-base pointing at HEAD (empty window, would hide the phase's high-stakes
# change) is IGNORED when TICK_BASE supplies the trusted base: tick scans the real window → exit 3.
# Proves the trusted env overrides the untrusted file (this is the tick-level half of the .phase-base
# forgery fix). If tick had used the forged file (==HEAD) it would refuse rc=1, so rc=3 proves override.
mkrepo t14 auth/login.py 'def login(): return True'
# Bind grade+evidence to the TRUSTED base (the original .phase-base == HEAD~1, what record-grade sees via
# TICK_BASE in headless) BEFORE forging the file, so the v2.17 binding passes and the high-stakes scan of
# the real window fires (rc 3) rather than the binding refusing (rc 1).
good_grade t14; good_evidence t14
printf '%s\n' "$HEAD" > "$REPO/.claude/.phase-base"
rc=$(runtick_base "$REPO" "$(git -C "$REPO" rev-parse HEAD~1)")
{ [ "$rc" = 3 ] && ! ticked "$REPO"; } \
  && pass "TICK_BASE overrides a forged .phase-base → real window scanned (exit 3)" || fail "TICK_BASE did not override forged file (rc=$rc)"

# 14b — TICK_BASE with a valid base + clean range → ticks (env path works end-to-end).
mkrepo t14b; good_grade t14b; good_evidence t14b
rc=$(runtick_base "$REPO" "$(cat "$REPO/.claude/.phase-base")")
{ [ "$rc" = 0 ] && ticked "$REPO"; } \
  && pass "TICK_BASE (valid base) → ticks (env path end-to-end)" || fail "valid TICK_BASE did not tick (rc=$rc)"

# 14c — strict-ancestor guard: TICK_BASE == HEAD → empty window → refuse (fail-closed, not a silent tick).
mkrepo t14c; good_grade t14c; good_evidence t14c
rc=$(runtick_base "$REPO" "$HEAD")
{ [ "$rc" = 1 ] && ! ticked "$REPO"; } \
  && pass "TICK_BASE == HEAD → refuse (empty window)" || fail "TICK_BASE==HEAD not refused (rc=$rc)"

# 14d — strict-ancestor guard: bogus/unresolvable sha via env → refuse.
mkrepo t14d; good_grade t14d; good_evidence t14d
rc=$(runtick_base "$REPO" "deadbeefdeadbeefdeadbeefdeadbeefdeadbeef")
{ [ "$rc" = 1 ] && ! ticked "$REPO"; } \
  && pass "TICK_BASE bogus sha (unresolvable) → refuse" || fail "bogus TICK_BASE not refused (rc=$rc)"

# 14e — TICK_BASE SET but EMPTY → refuse (a trusted base must be a real commit; NEVER silently fall
# back to the untrusted .claude/.phase-base file).
mkrepo t14e; good_grade t14e; good_evidence t14e
rc=$(runtick_base "$REPO" "")
{ [ "$rc" = 1 ] && ! ticked "$REPO"; } \
  && pass "TICK_BASE set-but-empty → refuse (no silent file fallback)" || fail "empty TICK_BASE not refused (rc=$rc)"

# 14f — TICK_BASE ABSENT → the /wrap path still reads .claude/.phase-base (backward compatible).
mkrepo t14f; good_grade t14f; good_evidence t14f; rc=$(runtick "$REPO")
{ [ "$rc" = 0 ] && ticked "$REPO"; } \
  && pass "TICK_BASE absent → .phase-base file path intact (/wrap)" || fail "file fallback broke (rc=$rc)"

echo ""
echo "supervised-approval tests (v2.4.0)"; echo ""
# A "Mode: supervised" phase ticks ONLY with an explicit, HEAD-bound human approval, and that approval
# clears the supervised refusal ALONE — every gate above it (grade, evidence, secret, high-stakes,
# heading existence) still fires first. Approval staleness / mismatch / malformation all fail closed.

# S1 — supervised phase, NO approval → exit 3 (refused, not ticked). (Baseline: same as old behaviour.)
mkrepo s1; set_mode s1 supervised; good_grade s1; good_evidence s1
rc=$(runtick "$REPO")
{ [ "$rc" = 3 ] && ! ticked "$REPO"; } && pass "supervised, no approval → exit 3 (refused)" || fail "supervised no-approval mishandled (rc=$rc)"

# S2 — supervised phase + --supervised-approved → writes a HEAD-bound approval and ticks.
mkrepo s2; set_mode s2 supervised; good_grade s2; good_evidence s2
rc=$(runtick "$REPO" --supervised-approved --note "reviewed the auth flow by hand")
{ [ "$rc" = 0 ] && ticked "$REPO"; } && pass "supervised + --supervised-approved → ticks" || fail "valid supervised approval did not tick (rc=$rc)"

# S3 — an approval made at an OLD commit is STALE after a new commit (run_id != HEAD) → refuses.
# set_mode commits the Mode line (HEAD includes it); the approval is bound to that HEAD, then an empty
# commit advances HEAD past it. .supervised-approval is gitignored, so the tree stays clean → the
# clean-tree gate passes and the supervised/staleness block is the real reason for the refusal.
mkrepo s3; set_mode s3 supervised
OLD=$(git -C "$REPO" rev-parse HEAD); PR=$(cat "$REPO/.claude/.phase-ready")
printf 'run_id=%s\ntitle=%s\napproved_at=x\nnote=ok\n' "$OLD" "$PR" > "$REPO/.claude/.supervised-approval"
( cd "$REPO" && git commit -q --allow-empty -m "advance HEAD after approval" )
HEAD=$(git -C "$REPO" rev-parse HEAD); good_grade s3; good_evidence s3; rc=$(runtick "$REPO")
{ [ "$rc" = 3 ] && ! ticked "$REPO"; } && pass "stale approval (old SHA after a new commit) → refuses" || fail "stale approval mishandled (rc=$rc)"

# S4 — an approval whose title is for a DIFFERENT phase → refuses (title must match the heading).
mkrepo s4; set_mode s4 supervised; good_grade s4; good_evidence s4
printf 'run_id=%s\ntitle=## Phase 2 — Other\napproved_at=x\nnote=ok\n' "$HEAD" > "$REPO/.claude/.supervised-approval"
rc=$(runtick "$REPO")
{ [ "$rc" = 3 ] && ! ticked "$REPO"; } && pass "approval for a different title → refuses" || fail "wrong-title approval mishandled (rc=$rc)"

# S5 — a malformed approval file (no run_id/title fields) → refuses (fail-closed).
mkrepo s5; set_mode s5 supervised; good_grade s5; good_evidence s5
printf 'garbage not an approval\n' > "$REPO/.claude/.supervised-approval"; rc=$(runtick "$REPO")
{ [ "$rc" = 3 ] && ! ticked "$REPO"; } && pass "malformed approval → refuses (fail-closed)" || fail "malformed approval mishandled (rc=$rc)"

# S6 — approval must NOT bypass the SECRET gate: a supervised phase with a planted (committed) secret
# + the flag still fails at the secret scan (which runs ABOVE the supervised block) → exit 1, not
# ticked. set_mode commits the Mode line so the tree is clean and the SECRET gate (not the clean-tree
# gate, which would also exit 1) is the real reason — asserted by checking the output names a secret.
mkrepo s6 src/cfg.py 'AWS="AKIAIOSFODNN7EXAMPLE"'; set_mode s6 supervised
good_grade s6; good_evidence s6; rc=$(runtick "$REPO" --supervised-approved --note "approve")
{ [ "$rc" = 1 ] && ! ticked "$REPO" && grep -qi 'secret' "$WORK/out"; } \
  && pass "approval does NOT bypass the secret gate (exit 1, secret-scan reason)" || fail "approval bypassed secret gate (rc=$rc)"

# S7 — approval must NOT bypass the HIGH-STAKES path gate: supervised phase touching a high-stakes
# path + the flag still exits 3 AT the high-stakes gate (above the supervised block) and never ticks.
mkrepo s7 auth/login.py 'def login(): return True'; set_mode s7 supervised
good_grade s7; good_evidence s7; rc=$(runtick "$REPO" --supervised-approved --note "approve")
{ [ "$rc" = 3 ] && ! ticked "$REPO" && grep -q "HIGH-STAKES paths changed" "$WORK/out"; } \
  && pass "approval does NOT bypass the high-stakes path gate (exit 3 at high-stakes, not ticked)" || fail "approval bypassed high-stakes gate (rc=$rc)"

# S8 — approval must NOT invent a phase: --supervised-approved with a heading absent from ROADMAP is
# refused by the heading-existence check (above everything) → exit 1, not ticked, no approval written.
mkrepo s8; set_mode s8 supervised; good_grade s8; good_evidence s8
rc=$(runtick "$REPO" --supervised-approved "## Phase 99 — Nope" --note "approve")
{ [ "$rc" = 1 ] && ! ticked "$REPO" && [ ! -f "$REPO/.claude/.supervised-approval" ]; } \
  && pass "approval for a heading absent from ROADMAP → refuses (exit 1, no approval written)" || fail "approval invented a heading (rc=$rc)"

echo ""
echo "test-evidence producer tests"; echo ""

mkevrepo() {
  REPO="$WORK/$1"; rm -rf "$REPO"
  mkdir -p "$REPO/.claude/lib" "$REPO/scripts"
  cp "$EVID" "$REPO/scripts/test-evidence.sh"; cp "$TC_LIB" "$REPO/.claude/lib/_test-cmd.sh"
  cp "$RG" "$REPO/scripts/record-grade.sh"
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

# e5 — retry-with-backoff: a command that fails on its FIRST attempt but passes on a later one
# (a stateful fake command driven by a counter file) must have its failure absorbed as a flake —
# test-evidence retries before recording red, and records passed:true, run_id==HEAD.
mkevrepo e5
cat > "$REPO/flake.sh" <<'FLAKE'
#!/usr/bin/env bash
c=$(cat .flake-counter 2>/dev/null || echo 0)
c=$((c+1))
echo "$c" > .flake-counter
[ "$c" -ge 2 ]
FLAKE
chmod +x "$REPO/flake.sh"
( cd "$REPO" && LEAN_TEST_CMD="bash flake.sh" bash scripts/test-evidence.sh >/dev/null 2>&1 ); erc=$?
{ [ "$erc" = 0 ] && [ "$(jq -r .passed "$REPO/.claude/.tick-evidence.json")" = true ] \
    && [ "$(jq -r .run_id "$REPO/.claude/.tick-evidence.json")" = "$HEAD" ] \
    && [ "$(cat "$REPO/.flake-counter" 2>/dev/null || echo 0)" -ge 2 ]; } \
  && pass "test-evidence: fails once then passes on retry → passed:true (flake absorbed)" \
  || fail "retry-clears-flake mishandled (rc=$erc, attempts=$(cat "$REPO/.flake-counter" 2>/dev/null || echo 0))"

# e6 — a command that is genuinely ALWAYS red (every attempt fails) must still record
# passed:false and exit 1 after exhausting its retries — retries absorb a FLAKE, they must
# NEVER manufacture a false green. The counter proves more than one attempt actually ran.
mkevrepo e6
cat > "$REPO/always-red.sh" <<'ALWAYSRED'
#!/usr/bin/env bash
c=$(cat .always-red-counter 2>/dev/null || echo 0)
c=$((c+1))
echo "$c" > .always-red-counter
exit 1
ALWAYSRED
chmod +x "$REPO/always-red.sh"
( cd "$REPO" && LEAN_TEST_CMD="bash always-red.sh" bash scripts/test-evidence.sh >/dev/null 2>&1 ); erc=$?
{ [ "$erc" = 1 ] && [ "$(jq -r .passed "$REPO/.claude/.tick-evidence.json")" = false ] \
    && [ "$(jq -r .run_id "$REPO/.claude/.tick-evidence.json")" = "$HEAD" ] \
    && [ "$(cat "$REPO/.always-red-counter" 2>/dev/null || echo 0)" -ge 2 ]; } \
  && pass "test-evidence: genuinely always-red → retries exhausted, still passed:false (no false green)" \
  || fail "genuinely-red mishandled (rc=$erc, attempts=$(cat "$REPO/.always-red-counter" 2>/dev/null || echo 0))"

echo ""
echo "record-grade producer tests"; echo ""

# g1 — PASS verdict → grade with run_id==HEAD, verdict=PASS, no_tests_ok=0.
mkevrepo g1
( cd "$REPO" && bash scripts/record-grade.sh "all criteria met
PASS" ) >/dev/null 2>&1; grc=$?
gf="$REPO/.claude/.phase-grade"
{ [ "$grc" = 0 ] && grep -q "verdict=PASS" "$gf" && grep -q "run_id=$HEAD" "$gf" && grep -q "no_tests_ok=0" "$gf"; } \
  && pass "record-grade: PASS → grade bound to HEAD, no_tests_ok=0" || fail "record-grade PASS wrong (rc=$grc)"

# g2 — verdict carrying NO_TESTS_OK → no_tests_ok=1.
mkevrepo g2
( cd "$REPO" && bash scripts/record-grade.sh "no suite for this docs phase
NO_TESTS_OK
PASS" ) >/dev/null 2>&1
grep -q "no_tests_ok=1" "$REPO/.claude/.phase-grade" 2>/dev/null \
  && pass "record-grade: NO_TESTS_OK token recorded" || fail "record-grade did not record NO_TESTS_OK"

# g3 — non-PASS verdict → refuses, writes no grade file.
mkevrepo g3
( cd "$REPO" && bash scripts/record-grade.sh "NEEDS_WORK: missing tests" ) >/dev/null 2>&1; grc=$?
{ [ "$grc" = 1 ] && [ ! -f "$REPO/.claude/.phase-grade" ]; } \
  && pass "record-grade: non-PASS refuses, no grade written" || fail "record-grade non-PASS wrong (rc=$grc)"

# g4 — a per-criterion 'PASS' that is not the final line must NOT record a grade.
mkevrepo g4
( cd "$REPO" && bash scripts/record-grade.sh "Criterion 1: PASS
NEEDS_WORK: criterion 2 unmet" ) >/dev/null 2>&1; grc=$?
{ [ "$grc" = 1 ] && [ ! -f "$REPO/.claude/.phase-grade" ]; } \
  && pass "record-grade: mid-text 'PASS' line does not record (anchored last line)" || fail "record-grade anchored-parse wrong (rc=$grc)"

# g5 — NO_TESTS_OK appearing only mid-sentence (e.g. echoed from a diff) must NOT set the flag,
# so a passed:null phase can't skip the test gate via an incidental token in the verdict text.
mkevrepo g5
( cd "$REPO" && bash scripts/record-grade.sh "the diff adds a NO_TESTS_OK constant to a comment
PASS" ) >/dev/null 2>&1
grep -q "no_tests_ok=0" "$REPO/.claude/.phase-grade" 2>/dev/null \
  && pass "record-grade: mid-sentence NO_TESTS_OK ignored (leading-token only)" || fail "record-grade substring bypass NOT closed"

# g6 (audit G12) — the manual /wrap path must refuse a grade when the grader dirtied the tracked tree.
# run_id=HEAD only honestly describes what was graded if every tracked file is committed; a PASS
# recorded over an uncommitted edit binds tick.sh's run_id==HEAD check to a tree no commit contains.
# Simulate the evaluator writing to a TRACKED file mid-grade, then recording a PASS.
mkevrepo g6
printf 'grader wrote this during the grade\n' >> "$REPO/scripts/record-grade.sh"
( cd "$REPO" && bash scripts/record-grade.sh "all criteria met
PASS" ) > "$WORK/g6.out" 2>&1; grc=$?
{ [ "$grc" = 1 ] && [ ! -f "$REPO/.claude/.phase-grade" ] && grep -q "DIRTY" "$WORK/g6.out"; } \
  && pass "record-grade: dirty tracked tree → refuses a PASS, writes no grade (G12)" \
  || fail "record-grade recorded a grade over a dirty tree (rc=$grc)"

# g7 — UNTRACKED files must NOT trip g6's check: autopilot.log, NEXT_FINDINGS.md and the gitignored
# evidence files are untracked by design and say nothing about whether HEAD describes the graded code.
mkevrepo g7
printf 'noise\n' > "$REPO/autopilot.log"
printf 'findings\n' > "$REPO/NEXT_FINDINGS.md"
( cd "$REPO" && bash scripts/record-grade.sh "all criteria met
PASS" ) >/dev/null 2>&1; grc=$?
{ [ "$grc" = 0 ] && grep -q "verdict=PASS" "$REPO/.claude/.phase-grade" 2>/dev/null; } \
  && pass "record-grade: untracked files alone do not block a grade (tracked-tree check only)" \
  || fail "record-grade wrongly refused over untracked files (rc=$grc)"

# 15 — a RESOLVABLE but NON-ANCESTOR .phase-base (divergent branch) → fail-closed refuse.
# Guards tick.sh's `git merge-base --is-ancestor` check. Case 13 covers an UNRESOLVABLE sha (caught by
# rev-parse --verify) and 14c covers ==HEAD (caught by the !=HEAD guard); NEITHER exercises a real commit
# on divergent history — the exact input the ancestor guard exists for. Grade+evidence are made valid so
# tick reaches the base check (they're verified first); the refusal must name "ancestor" so this only
# passes when THAT guard fires (dropping the guard lets tick scan an arbitrary B..C range and tick → red).
REPO="$WORK/t15"; rm -rf "$REPO"; mkdir -p "$REPO/.claude/lib" "$REPO/scripts" "$REPO/docs"
cp "$TICK" "$REPO/scripts/tick.sh"; cp "$HS_LIB" "$REPO/.claude/lib/_high-stakes.sh"; cp "$SS_LIB" "$REPO/.claude/lib/_secret-scan.sh"; cp "$SCAFFOLD/.claude/lib/_roadmap.sh" "$REPO/.claude/lib/_roadmap.sh"; cp "$SCAFFOLD/.claude/lib/_phase-range.sh" "$REPO/.claude/lib/_phase-range.sh"
printf '## Phase 1 — Work\n\n- [ ] do the work\n' > "$REPO/docs/ROADMAP.md"
printf 'next: work\n' > "$REPO/docs/STATE.md"
printf '.claude/.phase-base\n.claude/.phase-grade\n.claude/.tick-evidence.json\nNEXT_FINDINGS.md\n' > "$REPO/.gitignore"
( cd "$REPO" && git init -q && git config user.email t@t.t && git config user.name t && git config gc.auto 0 \
    && git add -A && git commit -q -m A \
    && A=$(git rev-parse HEAD) \
    && printf 'more\n' >> docs/ROADMAP.md && git add -A && git commit -q -m C \
    && MAIN=$(git rev-parse --abbrev-ref HEAD) \
    && git checkout -q "$A" \
    && printf 'sidework\n' > side.txt && git add side.txt && git commit -q -m B \
    && B=$(git rev-parse HEAD) \
    && git checkout -q "$MAIN" \
    && printf '%s\n' "$B" > .claude/.phase-base )
HEAD=$(git -C "$REPO" rev-parse HEAD)
good_grade t15; good_evidence t15
rc=$(runtick "$REPO" "## Phase 1 — Work")
{ [ "$rc" = 1 ] && ! ticked "$REPO" && grep -qi 'ancestor' "$WORK/out"; } \
  && pass "non-ancestor .phase-base (divergent branch) → fail-closed refuse (ancestor guard)" \
  || fail "non-ancestor base not refused by the ancestor guard (rc=$rc)"

echo ""
echo "Clean-tree gate (H5) — exact-HEAD evidence is only honest when the checkout == HEAD. A dirty"
echo "tracked/untracked tree can hide an uncommitted secret/high-stakes change the BASE..HEAD scan"
echo "(committed-only) never sees. Gitignored runtime artifacts are exempt (porcelain omits them):"
# 16a — an uncommitted TRACKED modification → refuse, not ticked.
mkrepo t16a; good_grade t16a; good_evidence t16a
printf 'def widget(): return 999\n' > "$REPO/src/widget.py"   # modify a tracked file, do NOT commit
rc=$(runtick "$REPO")
{ [ "$rc" = 1 ] && ! ticked "$REPO" && grep -qi 'not clean\|uncommitted' "$WORK/out"; } \
  && pass "dirty tracked tree → refuse (not ticked)" || fail "dirty tracked tree ticked anyway (rc=$rc)"
# 16b — an untracked, non-ignored file (e.g. a leaked secret file) → refuse.
mkrepo t16b; good_grade t16b; good_evidence t16b
printf 'AKIAIOSFODNN7EXAMPLE\n' > "$REPO/leaked.txt"          # untracked, not gitignored
rc=$(runtick "$REPO")
{ [ "$rc" = 1 ] && ! ticked "$REPO"; } \
  && pass "dirty untracked (non-ignored) file → refuse" || fail "untracked file ticked anyway (rc=$rc)"
# 16c — only gitignored runtime artifacts dirty → MUST still tick (the exemption set; must not regress).
mkrepo t16c; good_grade t16c; good_evidence t16c
printf 'log line\n' > "$REPO/autopilot.log"                   # gitignored per scaffold... but this
# fixture's .gitignore doesn't list autopilot.log; use one it DOES list to prove the exemption:
rm -f "$REPO/autopilot.log"; printf 'stale finding\n' > "$REPO/NEXT_FINDINGS.md"   # NEXT_FINDINGS.md is gitignored
rc=$(runtick "$REPO")
{ [ "$rc" = 0 ] && ticked "$REPO"; } \
  && pass "only gitignored artifacts dirty → still ticks (exemption preserved)" || fail "ignored-only dirty blocked the tick (rc=$rc)"

echo ""
echo "Rollback-safe ROADMAP/STATE completion (F4) — a completion ends with BOTH files updated or BOTH at"
echo "their pre-tick state; no '✓ ticked' until both succeed; a read-only STATE is caught BEFORE any"
echo "mutation (N-2: never half-apply). Permission-injection cases are root-guarded (root bypasses chmod)."
NONROOT=1; [ "$(id -u 2>/dev/null || echo 0)" -eq 0 ] && NONROOT=0

# Fault-injection stubs: mv/cp that fail on a chosen target/source (portable, any user). Used to force a
# replacement or a rollback failure without relying on filesystem permissions.
STUBBIN="$WORK/faultbin"; mkdir -p "$STUBBIN"
cat > "$STUBBIN/mv" <<'M'
#!/bin/sh
for last in "$@"; do :; done
if [ -n "${FAIL_MV_TARGET:-}" ]; then case "$last" in *"$FAIL_MV_TARGET") echo "stub mv: injected failure" >&2; exit 1 ;; esac; fi
exec /bin/mv "$@"
M
cat > "$STUBBIN/cp" <<'C'
#!/bin/sh
if [ -n "${FAIL_CP_SRC:-}" ]; then case "$1" in *"$FAIL_CP_SRC") echo "stub cp: injected failure" >&2; exit 1 ;; esac; fi
exec /bin/cp "$@"
C
chmod +x "$STUBBIN/mv" "$STUBBIN/cp"
runtick_fault() { local r="$1"; shift; ( cd "$r" && PATH="$STUBBIN:$PATH" bash scripts/tick.sh "$@" ) >"$WORK/out" 2>&1; echo $?; }

# 16d (N-2 + F4) — read-only docs/STATE.md → tick refuses BEFORE mutating, no '✓ ticked', ROADMAP NOT
# ticked (the old code left ROADMAP ticked with STATE stale; the transaction never half-applies now).
if [ "$NONROOT" = 1 ]; then
  mkrepo t16d; good_grade t16d; good_evidence t16d
  chmod 0444 "$REPO/docs/STATE.md"
  rc=$(runtick "$REPO"); chmod 0644 "$REPO/docs/STATE.md" 2>/dev/null || true
  { [ "$rc" != 0 ] && ! grep -q '✓ ticked' "$WORK/out" && ! ticked "$REPO"; } \
    && pass "read-only STATE → refuse before mutating, no '✓ ticked', ROADMAP NOT ticked (N-2 + F4)" \
    || fail "read-only STATE mishandled (rc=$rc, ticked=$(ticked "$REPO" && echo yes))"
else pass "(root: skipped read-only-STATE chmod test — root bypasses permissions)"; fi

# 16e — the refusal message names ONLY real, supported actions: no never-implemented doctor.sh --state,
# and every scripts/<name>.sh it references must exist. Regression for the dangling reference (v2.8.1).
if [ "$NONROOT" = 1 ]; then
  mkrepo t16e; good_grade t16e; good_evidence t16e
  chmod 0444 "$REPO/docs/STATE.md"; rc=$(runtick "$REPO"); chmod 0644 "$REPO/docs/STATE.md" 2>/dev/null || true
  b_ok=0; grep -qE '\-\-state' "$WORK/out" && b_ok=1
  c_ok=0; for s in $(grep -oE 'scripts/[A-Za-z0-9_-]+\.sh' "$WORK/out" | sort -u); do [ -f "$REPO/$s" ] || { c_ok=1; break; }; done
  { [ "$rc" != 0 ] && [ "$b_ok" = 0 ] && [ "$c_ok" = 0 ]; } \
    && pass "refusal names only existing commands, no doctor.sh --state (v2.8.1)" \
    || fail "refusal message inaccurate (rc=$rc nostate=$b_ok cmds=$c_ok)"
else pass "(root: skipped refusal-message test)"; fi

# F4-1 — ROADMAP temp generation fails (docs/ read-only) → refuse, nothing ticked.
if [ "$NONROOT" = 1 ]; then
  mkrepo f4a; good_grade f4a; good_evidence f4a; chmod 0555 "$REPO/docs"
  rc=$(runtick "$REPO"); chmod 0755 "$REPO/docs" 2>/dev/null || true
  { [ "$rc" != 0 ] && ! grep -q '✓ ticked' "$WORK/out" && ! ticked "$REPO"; } \
    && pass "F4: ROADMAP temp-gen fails → refuse, nothing ticked" || fail "F4 ROADMAP-gen (rc=$rc)"
else pass "(root: skipped ROADMAP-gen-fail)"; fi

# F4-2 — STATE temp generation fails (STATE unreadable) → refuse, nothing ticked.
if [ "$NONROOT" = 1 ]; then
  mkrepo f4b; good_grade f4b; good_evidence f4b; chmod 0000 "$REPO/docs/STATE.md"
  rc=$(runtick "$REPO"); chmod 0644 "$REPO/docs/STATE.md" 2>/dev/null || true
  { [ "$rc" != 0 ] && ! ticked "$REPO"; } \
    && pass "F4: STATE temp-gen fails → refuse, nothing ticked" || fail "F4 STATE-gen (rc=$rc)"
else pass "(root: skipped STATE-gen-fail)"; fi

# F4-3 — first replacement (ROADMAP mv) fails → refuse, not ticked.
mkrepo f4c; good_grade f4c; good_evidence f4c
export FAIL_MV_TARGET=docs/ROADMAP.md; rc=$(runtick_fault "$REPO"); unset FAIL_MV_TARGET
{ [ "$rc" != 0 ] && ! grep -q '✓ ticked' "$WORK/out" && ! ticked "$REPO"; } \
  && pass "F4: ROADMAP replacement fails → refuse, not ticked" || fail "F4 first-replacement (rc=$rc)"

# F4-4/5 — second replacement (STATE mv) fails AFTER ROADMAP replaced → BOTH roll back (successful
# rollback): ROADMAP restored to pre-tick (not ticked) AND STATE unchanged.
mkrepo f4d; good_grade f4d; good_evidence f4d; orig=$(cat "$REPO/docs/STATE.md")
export FAIL_MV_TARGET=docs/STATE.md; rc=$(runtick_fault "$REPO"); unset FAIL_MV_TARGET
{ [ "$rc" != 0 ] && ! grep -q '✓ ticked' "$WORK/out" && ! ticked "$REPO" && [ "$(cat "$REPO/docs/STATE.md")" = "$orig" ]; } \
  && pass "F4: STATE replacement fails → BOTH rolled back (ROADMAP restored, STATE unchanged)" || fail "F4 rollback (rc=$rc)"

# F4-6 — rollback ITSELF fails (STATE mv fails AND the ROADMAP restore cp fails) → backups PRESERVED,
# recovery printed, exit non-zero.
mkrepo f4e; good_grade f4e; good_evidence f4e
export FAIL_MV_TARGET=docs/STATE.md FAIL_CP_SRC=ROADMAP.md.tick-bak
rc=$(runtick_fault "$REPO"); unset FAIL_MV_TARGET FAIL_CP_SRC
{ [ "$rc" != 0 ] && grep -qi 'PRESERVED' "$WORK/out" && [ -f "$REPO/docs/ROADMAP.md.tick-bak" ]; } \
  && pass "F4: rollback failure → backups preserved, recovery printed, exit non-zero" \
  || fail "F4 rollback-fail (rc=$rc bak=$([ -f "$REPO/docs/ROADMAP.md.tick-bak" ] && echo yes))"
rm -f "$REPO/docs/ROADMAP.md.tick-bak" "$REPO/docs/STATE.md.tick-bak" 2>/dev/null || true

# F4-7 — successful RETRY after a failed attempt (no injection) → ticks, both updated, no leftovers.
mkrepo f4f; good_grade f4f; good_evidence f4f
export FAIL_MV_TARGET=docs/STATE.md; rc1=$(runtick_fault "$REPO"); unset FAIL_MV_TARGET
rc2=$(runtick "$REPO")
{ [ "$rc1" != 0 ] && [ "$rc2" = 0 ] && ticked "$REPO" && grep -q 'lean:auto:begin' "$REPO/docs/STATE.md" \
  && [ ! -f "$REPO/docs/ROADMAP.md.tick-bak" ]; } \
  && pass "F4: retry after a failed attempt succeeds (both updated, no leftovers)" || fail "F4 retry (rc1=$rc1 rc2=$rc2)"

# F4-8 — ordinary successful tick → BOTH files updated, '✓ ticked', temps/backups cleaned.
mkrepo f4g; good_grade f4g; good_evidence f4g; rc=$(runtick "$REPO")
{ [ "$rc" = 0 ] && grep -q '✓ ticked' "$WORK/out" && ticked "$REPO" && grep -q 'Last ticked' "$REPO/docs/STATE.md" \
  && [ ! -f "$REPO/docs/ROADMAP.md.tick-tmp" ] && [ ! -f "$REPO/docs/ROADMAP.md.tick-bak" ]; } \
  && pass "F4: ordinary tick updates BOTH files and cleans temps/backups" || fail "F4 ordinary tick (rc=$rc)"

# F4-9 — a leftover *.tick-* artifact from an interrupted prior run → refuse clearly.
mkrepo f4h; good_grade f4h; good_evidence f4h
cp "$REPO/docs/ROADMAP.md" "$REPO/docs/ROADMAP.md.tick-bak"
rc=$(runtick "$REPO"); rm -f "$REPO/docs/ROADMAP.md.tick-bak" 2>/dev/null || true
{ [ "$rc" != 0 ] && grep -qi 'leftover completion-transaction' "$WORK/out"; } \
  && pass "F4: leftover *.tick-* artifact → refuse clearly (interrupted prior run)" || fail "F4 leftover (rc=$rc)"


# --- A roadmap is allowed to talk about its own notation ---------------------------------------
# tick.sh matched an open task UNANCHORED (`/- \[ \]/`) in its gate, its counts AND its gsub. So a
# phase whose PROSE merely mentioned "- [ ]" — a quoted example, a "Done when:" about checkboxes —
# was seen as having an open item, had that prose silently rewritten to "- [x]", and ticked. Two
# separate failures: a phase completing with no real work, and documentation corrupted in place.
POISON='Done when: every `- [ ]` under this phase is checked'

# P1 — prose-only phase (no real open task) → must REFUSE, and must not touch the file.
mkrepo p1
printf '## Phase 1 — Work\n\n- [x] do the work\n%s\nMode: loopable\n' "$POISON" > "$REPO/docs/ROADMAP.md"
( cd "$REPO" && git add -A && git commit -q -m roadmap )
HEAD=$(git -C "$REPO" rev-parse HEAD)
good_grade p1; good_evidence p1
before=$(md5of "$REPO/docs/ROADMAP.md"); rc=$(runtick "$REPO")
{ [ "$rc" = 1 ] && [ "$before" = "$(md5of "$REPO/docs/ROADMAP.md")" ]; } \
  && pass "prose mentioning '- [ ]' is not an open task → refuses, roadmap byte-identical" \
  || fail "prose was treated as an open task (rc=$rc) — tick completed a phase with no real work"

# P2 — real open task ALONGSIDE such prose → ticks the task, leaves the prose byte-for-byte.
mkrepo p2
printf '## Phase 1 — Work\n\n- [ ] do the work\n%s\nMode: loopable\n' "$POISON" > "$REPO/docs/ROADMAP.md"
( cd "$REPO" && git add -A && git commit -q -m roadmap )
HEAD=$(git -C "$REPO" rev-parse HEAD)
good_grade p2; good_evidence p2
rc=$(runtick "$REPO")
{ [ "$rc" = 0 ] && ticked "$REPO"; } \
  && pass "the real task still ticks when prose sits beside it" || fail "real task did not tick (rc=$rc)"
grep -qxF -- "$POISON" "$REPO/docs/ROADMAP.md" \
  && pass "the prose line survives the tick byte-for-byte (no gsub corruption)" \
  || fail "tick REWROTE the prose line — roadmap corruption"

echo ""
echo "Regression (v2.15.0) — a PLAN_CHECK verdict is not an implementation grade"
# v2.14.0 added a second evaluator mode whose verdict ALSO ended in `PASS`, while record-grade.sh
# trusts "last non-empty line == PASS" as proof of an implementation review. So a plan review — one
# explicitly stating no code had been written yet — recorded as a valid HEAD-bound grade, defeating
# one of tick.sh's three gates. The docs claimed "a separate channel record-grade.sh never reads";
# it was convention, not mechanism. PLAN_CHECK now emits PLAN_* tokens and record-grade names them.
for v in PLAN_PASS PLAN_PASS_WITH_WARNINGS PLAN_FAIL; do
  mkevrepo "pc_$v"
  ( cd "$REPO" && bash scripts/record-grade.sh "PLAN_CHECK verdict for docs/plans/p.md
Pre-mortem complete. This is a PLAN review only. NO CODE HAS BEEN WRITTEN YET.

$v" ) >/dev/null 2>&1
  rc=$?
  if [ "$rc" = "0" ] || [ -f "$REPO/.claude/.phase-grade" ]; then
    fail "$v was recorded as an implementation grade (rc=$rc) — a plan review can gate execution, never completion"
  else
    pass "$v refused by record-grade (rc=$rc, no grade file written)"
  fi
done
# and the honest half: a bare PASS still records — the PLAN_ prefix is the discriminator, so the
# evaluator emitting the right token for its mode stays MODEL-DEPENDENT. Do not overclaim this.
mkevrepo pc_ok
( cd "$REPO" && bash scripts/record-grade.sh "every criterion met

PASS" ) >/dev/null 2>&1
[ -f "$REPO/.claude/.phase-grade" ] && pass "a bare PASS still records (IMPLEMENTATION_REVIEW unaffected)" \
                                     || fail "the discriminator broke the normal implementation grade"

echo ""
if [ "$FAILS" -eq 0 ]; then echo "All tick gate + evidence tests passed."; exit 0
else echo "$FAILS tick test(s) FAILED."; echo "--- last tick output ---"; tail -n 20 "$WORK/out" 2>/dev/null; exit 1; fi
