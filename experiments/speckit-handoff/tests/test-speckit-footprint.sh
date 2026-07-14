#!/usr/bin/env bash
# test-speckit-footprint.sh — the ownership-aware install-footprint check.
#
# The naive rule ("after `specify init`, nothing but speckit-* may change") is WRONG twice over:
#   - Spec Kit is SUPPOSED to create .claude/skills/speckit-*/ — that is correct behavior, not a
#     collision. A name-only check fires on the thing working.
#   - Spec Kit's Claude integration is multi-install-safe and its documented footprint includes an
#     agent-context file (CLAUDE.md). Auto-rejecting that rejects documented, correct behavior.
#
# So the check is about OWNERSHIP, not names:
#     same path + same owner       = expected
#     same path + different owner  = COLLISION
# Both toolkits publish a manifest. We cross-check them.
#
# No network: the fixtures below SIMULATE a post-init tree. The real thing runs in the live tier.
set -uo pipefail

EXP="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FP="$EXP/bin/speckit-footprint.sh"
MANIFEST="$EXP/footprint/speckit-0.12.13.json"

FAILS=0
pass() { printf '  ✓ %s\n' "$1"; }
fail() { printf '  ✗ %s\n' "$1"; FAILS=$((FAILS+1)); }
command -v jq >/dev/null 2>&1 || { echo "test: jq required" >&2; exit 1; }

WORK="$(mktemp -d 2>/dev/null || mktemp -d -t speckit-fp)"
trap 'rm -rf "$WORK" 2>/dev/null' EXIT

sha() { shasum -a 256 "$1" 2>/dev/null | cut -d' ' -f1 || sha256sum "$1" | cut -d' ' -f1; }

# mkinstalled <name> — a Jaimitos project as install.sh leaves it: skills on disk, and a
# .claude/.jaimitos-manifest recording the sha256 of every toolkit-owned file it wrote.
mkinstalled() {
  P="$WORK/$1"; rm -rf "$P"
  mkdir -p "$P/.claude/skills/tdd" "$P/.claude/skills/roadmap" "$P/docs" "$P/scripts"
  printf 'name: tdd\n' > "$P/.claude/skills/tdd/SKILL.md"
  printf 'name: roadmap\n' > "$P/.claude/skills/roadmap/SKILL.md"
  printf '# Roadmap\n## Phase 1 — x\n- [ ] a\nDone when: x\nMode: loopable\n' > "$P/docs/ROADMAP.md"
  printf '# State\n' > "$P/docs/STATE.md"
  printf '# Project\n' > "$P/CLAUDE.md"
  : > "$P/.claude/.jaimitos-manifest"
  for f in .claude/skills/tdd/SKILL.md .claude/skills/roadmap/SKILL.md; do
    printf '%s  %s\n' "$(sha "$P/$f")" "$f" >> "$P/.claude/.jaimitos-manifest"
  done
}

# speckit_init <project> — SIMULATE `specify init --integration claude`: write the speckit-* skills,
# the .specify tree, and — crucially — Spec Kit's OWN manifest recording what it wrote.
speckit_init() {
  local p="$1"
  mkdir -p "$p/.specify/memory" "$p/.specify/integrations" "$p/specs"
  printf '# Constitution\n' > "$p/.specify/memory/constitution.md"
  local owned=""
  for c in specify clarify plan tasks implement analyze converge checklist constitution taskstoissues; do
    mkdir -p "$p/.claude/skills/speckit-$c"
    # Real spec-kit SKILL.md carries YAML frontmatter between --- fences, and
    # `disable-model-invocation: false` — so every description is ALWAYS-LOADED context.
    printf -- '---\nname: speckit-%s\ndescription: Run the %s step of the spec-driven workflow on the current feature, reading and updating the feature pack under specs/.\ndisable-model-invocation: false\n---\n' "$c" "$c" > "$p/.claude/skills/speckit-$c/SKILL.md"
    owned="$owned\".claude/skills/speckit-$c/SKILL.md\","
  done
  owned="$owned\".specify/memory/constitution.md\""
  printf '{"version":"0.12.13","integration":"claude","files":[%s]}\n' "$owned" \
    > "$p/.specify/integrations/speckit.manifest.json"
}

# The check is DIFFERENTIAL: a snapshot BEFORE `specify init`, a check against it after. A file
# merely existing proves nothing — docs/ROADMAP.md is "forbidden" because Spec Kit must not WRITE
# it, not because it may not be there. (The first draft classified absolute state and reported 13
# violations on a perfectly correct install.)
snapshot() { bash "$FP" --project "$1" --manifest "$MANIFEST" --snapshot "$WORK/base-$(basename "$1")" >/dev/null 2>&1; }
check()    { bash "$FP" --project "$1" --manifest "$MANIFEST" --baseline "$WORK/base-$(basename "$1")" >"$WORK/out" 2>&1; echo $?; }
outof() { cat "$WORK/out"; }

echo "speckit footprint (ownership-aware) tests"; echo ""

# ---------------------------------------------------------------- the good case
echo "a correct install:"
mkinstalled clean; snapshot "$P"; speckit_init "$P"
rc=$(check "$P")
[ "$rc" = 0 ] && pass "speckit-* skills + .specify/ + specs/ → clean (exit 0)" \
              || { fail "a correct install was flagged (rc=$rc)"; outof | sed 's/^/      /'; }
outof | grep -qi 'speckit-implement' \
  && pass "reports what Spec Kit owns (including the 10 always-loaded skills)" || fail "no ownership report"

# ---------------------------------------------------------------- R1: the context tax
echo ""
echo "the context tax (R1) — measured, not estimated:"
# Assert the MEASUREMENT, not the wording. The first version grepped for the words "always-loaded"
# and passed while the tool reported 0B — a lying assertion, on the very criterion (R1) that decides
# whether this integration ships. A measurement that silently returns zero biases the whole go/no-go.
MEASURED=$(outof | sed -n 's/.*model-invoked speckit-\* skill(s): \([0-9]*\)B.*/\1/p')
NSKILLS=$(outof | sed -n 's/.*· \([0-9]*\) model-invoked speckit-\* skill(s).*/\1/p')
{ [ "${NSKILLS:-0}" = 10 ] && [ "${MEASURED:-0}" -gt 500 ]; } \
  && pass "measures the always-loaded tax: 10 skills, ${MEASURED}B loaded every turn" \
  || fail "R1 measurement is wrong (skills='$NSKILLS' bytes='$MEASURED') — a 0B reading would silently exonerate Spec Kit"

# ---------------------------------------------------------------- ownership violations
echo ""
echo "ownership violations:"
# A Jaimitos-owned file whose content changed → its sha no longer matches .jaimitos-manifest.
mkinstalled mutate; snapshot "$P"; speckit_init "$P"
printf 'name: tdd\n# HIJACKED\n' > "$P/.claude/skills/tdd/SKILL.md"
rc=$(check "$P")
{ [ "$rc" = 1 ] && outof | grep -q 'skills/tdd/SKILL.md'; } \
  && pass "a MODIFIED jaimitos-owned file → refuses, naming it" || fail "jaimitos file mutation not caught (rc=$rc)"

# A speckit-*-looking skill that Spec Kit's own manifest does NOT claim: same name, different owner.
mkinstalled squat; snapshot "$P"; speckit_init "$P"
mkdir -p "$P/.claude/skills/speckit-rogue"
printf 'name: speckit-rogue\n' > "$P/.claude/skills/speckit-rogue/SKILL.md"
rc=$(check "$P")
{ [ "$rc" = 1 ] && outof | grep -q 'speckit-rogue'; } \
  && pass "a speckit-* path Spec Kit's manifest does NOT claim → refuses (same name, different owner)" \
  || fail "unowned speckit-* path accepted (rc=$rc)"

# A forbidden path: the queue itself.
mkinstalled forbid; snapshot "$P"; speckit_init "$P"
printf '## Phase 9 — injected\n- [ ] x\nDone when: y\nMode: loopable\n' >> "$P/docs/ROADMAP.md"
rc=$(check "$P")
{ [ "$rc" = 1 ] && outof | grep -q 'docs/ROADMAP.md'; } \
  && pass "a touched FORBIDDEN path (docs/ROADMAP.md) → refuses" || fail "forbidden path not caught (rc=$rc)"

# A stray file outside every expected pattern.
mkinstalled stray; snapshot "$P"; speckit_init "$P"
printf 'x\n' > "$P/.claude/settings.json"
rc=$(check "$P")
{ [ "$rc" = 1 ] && outof | grep -q 'settings.json'; } \
  && pass "an unexpected non-speckit file → refuses" || fail "stray file not caught (rc=$rc)"

# ---------------------------------------------------------------- CLAUDE.md is NOT forbidden
echo ""
echo "CLAUDE.md is classified, not auto-rejected:"
# Spec Kit's Claude integration is multi_install_safe and its documented footprint includes an
# agent-context file. Rejecting every non-speckit-* change would reject correct, documented behavior.
mkinstalled ctx; snapshot "$P"; speckit_init "$P"
printf '\n<!-- speckit agent context -->\n' >> "$P/CLAUDE.md"
rc=$(check "$P")
[ "$rc" = 0 ] && pass "a modified CLAUDE.md → still clean (conditionally_modified, not forbidden)" \
              || { fail "CLAUDE.md change wrongly rejected (rc=$rc)"; outof | sed 's/^/      /'; }
outof | grep -q 'CLAUDE.md' \
  && pass "...but it is REPORTED, so a human classifies the diff" || fail "CLAUDE.md change not reported"

# ---------------------------------------------------------------- fail-closed
echo ""
echo "fail-closed:"
mkinstalled nomanifest; snapshot "$P"; speckit_init "$P"
rm -f "$P/.specify/integrations/speckit.manifest.json"
rc=$(check "$P")
[ "$rc" = 1 ] && pass "no Spec Kit manifest → refuses (ownership is unverifiable, not 'fine')" \
              || fail "missing spec-kit manifest treated as clean (rc=$rc)"

mkinstalled nojm; snapshot "$P"; speckit_init "$P"
rm -f "$P/.claude/.jaimitos-manifest"
rc=$(check "$P")
[ "$rc" = 1 ] && pass "no Jaimitos manifest → refuses (cannot prove our files are intact)" \
              || fail "missing jaimitos manifest treated as clean (rc=$rc)"

echo ""
echo "argument discipline:"
rc=$(bash "$FP" --help >/dev/null 2>&1; echo $?);      [ "$rc" = 0 ] && pass "--help → 0"       || fail "--help not 0 (rc=$rc)"
rc=$(bash "$FP" --nonsense >/dev/null 2>&1; echo $?);  [ "$rc" = 2 ] && pass "unknown flag → 2" || fail "unknown flag not 2 (rc=$rc)"

echo ""
if [ "$FAILS" -eq 0 ]; then echo "All footprint tests passed."; exit 0
else echo "$FAILS footprint test(s) FAILED."; echo "--- last output ---"; tail -n 20 "$WORK/out" 2>/dev/null; exit 1; fi
