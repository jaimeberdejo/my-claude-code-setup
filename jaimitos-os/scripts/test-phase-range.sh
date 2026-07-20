#!/usr/bin/env bash
# test-phase-range.sh — the SHARED phase-range resolver (.claude/lib/_phase-range.sh) + its CLI
# (scripts/phase-range.sh). Proves ONE precedence (TICK_BASE → .phase-anchor → .phase-base), the
# strict-ancestor guard, the anchor base-integrity (narrowing) refusal, and that the CLI prints the
# window every consumer shares. Runs in throwaway git repos; mutates nothing outside $WORK.
set -uo pipefail
SCAFFOLD="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LIB="$SCAFFOLD/.claude/lib/_phase-range.sh"
RMLIB="$SCAFFOLD/.claude/lib/_roadmap.sh"
CLI="$SCAFFOLD/scripts/phase-range.sh"
[ -f "$LIB" ] || { echo "test: cannot find $LIB" >&2; exit 1; }
WORK="$(mktemp -d 2>/dev/null || mktemp -d -t phrange)"; trap 'rm -rf "$WORK" 2>/dev/null' EXIT
FAILS=0
pass() { printf '  ✓ %s\n' "$1"; }
fail() { printf '  ✗ %s\n' "$1"; FAILS=$((FAILS+1)); }

# A repo with the resolver lib + roadmap lib, two commits (so an ancestor base exists), one open phase.
mkrepo() {
  REPO="$WORK/$1"; rm -rf "$REPO"; mkdir -p "$REPO/.claude/lib" "$REPO/scripts" "$REPO/docs"
  cp "$LIB" "$REPO/.claude/lib/_phase-range.sh"; cp "$RMLIB" "$REPO/.claude/lib/_roadmap.sh"
  cp "$CLI" "$REPO/scripts/phase-range.sh"
  printf '## Phase 1 — Work\n\n- [ ] do the work\nDone when: x\nMode: loopable\n' > "$REPO/docs/ROADMAP.md"
  printf '.claude/.phase-base\n.claude/.phase-anchor\n' > "$REPO/.gitignore"   # keep both untracked unless a test tracks the anchor
  ( cd "$REPO" && git init -q && git config user.email t@t.t && git config user.name t && git config gc.auto 0 \
      && git add -A && git commit -q -m base && echo one > f1 && git add -A && git commit -q -m c1 )
}
# resolve <repo> [TICK_BASE]: source the lib in a subshell, run resolve_phase_range, echo "rc|base|source".
resolve() {
  local r="$1"; shift
  ( cd "$r" && . .claude/lib/_roadmap.sh 2>/dev/null; . .claude/lib/_phase-range.sh
    if [ "$#" -gt 0 ]; then export TICK_BASE="$1"; fi
    resolve_phase_range; rc=$?
    printf '%s|%s|%s\n' "$rc" "$PR_BASE_SHA" "$PR_SOURCE" )
}

echo "phase-range resolver tests"; echo ""

BASE0() { git -C "$1" rev-parse HEAD~1; }   # the pre-phase commit (a real ancestor of HEAD)
HEADSHA() { git -C "$1" rev-parse HEAD; }

# 1 — legacy .phase-base (no anchor): resolves that base, source is .phase-base, rc 0.
mkrepo t1; b=$(BASE0 "$REPO"); printf '%s\n' "$b" > "$REPO/.claude/.phase-base"
out=$(resolve "$REPO"); rc="${out%%|*}"; src="${out##*|}"
{ [ "$rc" = 0 ] && [ "$(printf '%s' "$out" | cut -d'|' -f2)" = "$b" ] && [ "$src" = ".claude/.phase-base" ]; } \
  && pass "legacy .phase-base resolves (rc 0, source .phase-base)" || fail "legacy .phase-base mishandled ($out)"

# 2 — a tracked .phase-anchor (authored like start-phase.sh: base=HEAD, then committed so the anchor
#     commit's parent IS the base) takes precedence over a STALE/garbage .phase-base.
mkrepo t2
( cd "$REPO" && printf 'heading=## Phase 1 — Work\nbase=%s\n' "$(git rev-parse HEAD)" > .claude/.phase-anchor \
   && sed -i.bak '/phase-anchor/d' .gitignore && rm -f .gitignore.bak && git add -A && git commit -q -m 'chore(phase-start)' )
printf 'deadbeefdeadbeefdeadbeefdeadbeefdeadbeef\n' > "$REPO/.claude/.phase-base"   # stale/garbage, must be IGNORED
out=$(resolve "$REPO"); rc="${out%%|*}"; src="${out##*|}"
{ [ "$rc" = 0 ] && [ "$src" = ".claude/.phase-anchor (start-phase.sh)" ]; } \
  && pass "tracked anchor preferred over a stale .phase-base" || fail "anchor precedence wrong ($out)"

# 3 — TICK_BASE overrides everything (headless-trusted), even a present anchor.
out=$(resolve "$REPO" "$(BASE0 "$REPO")"); src="${out##*|}"
{ [ "${out%%|*}" = 0 ] && [ "$src" = "TICK_BASE env (orchestrator-trusted)" ]; } \
  && pass "TICK_BASE overrides the anchor (orchestrator-trusted)" || fail "TICK_BASE precedence wrong ($out)"

# 4 — nothing recorded → fail closed (rc 1).
mkrepo t4; out=$(resolve "$REPO"); [ "${out%%|*}" = 1 ] && pass "no base recorded → rc 1 (fail-closed)" || fail "missing base not fail-closed ($out)"

# 5 — base == HEAD → empty window → rc 1.
mkrepo t5; printf '%s\n' "$(HEADSHA "$REPO")" > "$REPO/.claude/.phase-base"
out=$(resolve "$REPO"); [ "${out%%|*}" = 1 ] && pass "base == HEAD → rc 1 (empty window)" || fail "base==HEAD not refused ($out)"

# 6 — unresolvable base → rc 1.
mkrepo t6; printf 'nonsense\n' > "$REPO/.claude/.phase-base"
out=$(resolve "$REPO"); [ "${out%%|*}" = 1 ] && pass "unresolvable base → rc 1" || fail "unresolvable base not refused ($out)"

# 7 — a resolvable but NON-ANCESTOR base (divergent history) → rc 1 (the ancestor guard).
mkrepo t7
other=$( cd "$REPO" && git commit-tree "$(git rev-parse 'HEAD^{tree}')" -m orphan </dev/null )
printf '%s\n' "$other" > "$REPO/.claude/.phase-base"
out=$(resolve "$REPO"); [ "${out%%|*}" = 1 ] && pass "non-ancestor base → rc 1 (ancestor guard)" || fail "non-ancestor base not refused ($out)"

# 8 — anchor base-integrity: an anchor authored as an ORDINARY commit whose base= is NOT that commit's
#     parent (the naive "advance the base to narrow the window" forge) → rc 3 (supervised). Setup: add a
#     commit C, then write the anchor with base=A (a valid strict ancestor, but NOT C) and commit it — so
#     the anchor-setting commit's parent is C while base=A ≠ C.
mkrepo t8
( cd "$REPO" && echo x > f3 && git add -A && git commit -q -m c2 )   # HEAD = C
A=$( cd "$REPO" && git rev-parse HEAD~2 )                            # the original 'base' commit A (strict ancestor of HEAD, ≠ C)
( cd "$REPO" && printf 'heading=## Phase 1 — Work\nbase=%s\n' "$A" > .claude/.phase-anchor \
   && sed -i.bak '/phase-anchor/d' .gitignore && rm -f .gitignore.bak \
   && git add -A && git commit -q -m 'anchor with a base that is not this commit parent' )
out=$(resolve "$REPO"); [ "${out%%|*}" = 3 ] && pass "anchor base ≠ setting-commit parent → rc 3 (supervised)" || fail "anchor narrowing not caught ($out)"

# 9 — CLI: prints Phase/Base/Head/Range/Source and --base/--range single values.
mkrepo t9; b=$(BASE0 "$REPO"); printf '%s\n' "$b" > "$REPO/.claude/.phase-base"
cliout=$( cd "$REPO" && bash scripts/phase-range.sh 2>&1 ); clirc=$?
{ [ "$clirc" = 0 ] && printf '%s' "$cliout" | grep -q '^Base:' && printf '%s' "$cliout" | grep -q '^Range:'; } \
  && pass "CLI prints the Base/Range block" || fail "CLI block wrong (rc=$clirc): $cliout"
cb=$( cd "$REPO" && bash scripts/phase-range.sh --base 2>/dev/null )
[ "$cb" = "$b" ] && pass "CLI --base prints the resolved base sha" || fail "CLI --base wrong ($cb vs $b)"
mkrepo t9b   # CLI fails closed with a nonzero exit when nothing is recorded
( cd "$WORK/t9b" && bash scripts/phase-range.sh >/dev/null 2>&1 ); [ "$?" != 0 ] && pass "CLI fails closed (nonzero) with no base" || fail "CLI did not fail closed"

# 10 — MUTATION (non-vacuity): a resolver that DROPS the .phase-base fallback (returns 1 even when a
#      valid base is recorded) makes test 1's positive resolution fail. Prove the guard can fail.
mkrepo t10; b=$(BASE0 "$REPO"); printf '%s\n' "$b" > "$REPO/.claude/.phase-base"
MUT="$WORK/t10/.claude/lib/_phase-range.sh"
# Neuter the .phase-base branch: make it set an empty base so resolution fails.
sed -i.bak 's|PR_BASE=$(cat .claude/.phase-base 2>/dev/null \|\| true)|PR_BASE=""|' "$MUT" && rm -f "$MUT.bak"
out=$( cd "$WORK/t10" && . .claude/lib/_roadmap.sh 2>/dev/null; . .claude/lib/_phase-range.sh; resolve_phase_range; echo $? )
[ "$out" != 0 ] && pass "mutation: dropping the .phase-base fallback makes resolution fail (non-vacuous)" || fail "mutation not caught — test 1 would pass on a broken resolver"

echo ""
if [ "$FAILS" -eq 0 ]; then echo "All phase-range resolver tests passed."; exit 0
else echo "$FAILS phase-range test(s) FAILED."; exit 1; fi
