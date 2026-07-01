#!/usr/bin/env bash
# install-smoke.sh — prove install.sh produces a CLEAN target install:
#   - toolkit README / legacy tool meta-docs are NOT copied
#   - SCAFFOLD.md IS copied (and never lands as the target's README.md)
#   - a pre-existing target README.md is never clobbered
#   - the CI workflow is absent by default, present with --with-ci
#   - re-running is idempotent (skips existing files; .gitignore block not duplicated)
#   - scaffold .gitignore rules are merged into a pre-existing target .gitignore
#   - the installed tree passes its own hook smoke tests (scaffold at git root)
#
# Lives at repo-root .github/scripts/ so it is NEVER part of the shipped scaffold.
# Run: bash .github/scripts/install-smoke.sh
set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"   # …/.github/scripts/../.. = repo root
FAILS=0
ok()  { printf '  ✓ %s\n' "$1"; }
bad() { printf '  ✗ %s\n' "$1"; FAILS=$((FAILS+1)); }

TMP="$(mktemp -d)" || { echo "install-smoke: mktemp failed" >&2; exit 2; }
trap 'rm -rf "$TMP"' EXIT
cd "$TMP" || exit 2
git init -q . && git config user.email t@t.t && git config user.name t

echo "install smoke test (target: $TMP)"
echo ""

# Pre-existing project files we must not damage.
printf '# My Project\nhand-written README, must survive\n' > README.md
printf 'node_modules/\n' > .gitignore
README_BEFORE="$(cat README.md)"

bash "$REPO/install.sh" . >/dev/null 2>&1 || bad "install.sh exited non-zero"

# Tool meta-docs must be absent — neither the files nor the legacy toolkit-docs/ dir ship.
for d in GUIDE.md LOOP-ENGINEERING.md toolkit-docs/GUIDE.md toolkit-docs/LOOP-ENGINEERING.md; do
  [ -e "$d" ] && bad "tool-doc $d was copied (should be excluded)" || ok "$d not copied"
done
[ -e toolkit-docs ] && bad "toolkit-docs/ dir was copied (should be excluded by directory)" || ok "toolkit-docs/ not copied"
# SCAFFOLD.md present.
[ -f SCAFFOLD.md ] && ok "SCAFFOLD.md copied" || bad "SCAFFOLD.md missing"
# Pre-existing README untouched, and no scaffold content leaked into it.
[ "$(cat README.md)" = "$README_BEFORE" ] && ok "existing README.md untouched" || bad "README.md was modified/clobbered"
grep -q "Lean Stack — the scaffold" README.md && bad "scaffold README content landed in target README.md" || ok "no scaffold content in target README.md"
# CI absent by default.
[ -e .github/workflows/lean-stack-ci.yml ] && bad "CI copied without --with-ci" || ok "CI absent by default"
# Core scaffold + shared libs present.
for f in CLAUDE.md .claude/settings.json scripts/autopilot.sh \
         .claude/lib/_secret-scan.sh .claude/lib/_high-stakes.sh; do
  [ -f "$f" ] && ok "installed $f" || bad "missing $f"
done
# Skills installed per-project — but the installer/meta skill is NOT.
[ -d .claude/skills/roadmap ] && ok "skills installed (.claude/skills/roadmap)" || bad "skills not installed"
[ -e .claude/skills/setup-lean-stack ] && bad "setup-lean-stack copied per-project (should be --global-skills only)" || ok "setup-lean-stack not copied per-project"
# Installed version is stamped for doctor.sh.
[ -f .claude/.lean-stack-version ] && ok "version stamp written (.claude/.lean-stack-version)" || bad "version stamp missing"
# .gitignore merged, pre-existing rule preserved.
grep -q "lean-stack control/secret ignores" .gitignore && ok ".gitignore merge block added" || bad ".gitignore not merged"
grep -qx "node_modules/" .gitignore && ok "pre-existing .gitignore rule preserved" || bad "pre-existing .gitignore rule lost"

# Idempotent re-run.
OUT2="$(bash "$REPO/install.sh" . 2>&1)" || bad "re-run exited non-zero"
case "$OUT2" in *"skip (exists)"*) ok "re-run skips existing files (idempotent)" ;; *) bad "re-run did not skip existing files" ;; esac
[ "$(grep -c "lean-stack control/secret ignores" .gitignore)" -eq 1 ] && ok ".gitignore block not duplicated on re-run" || bad ".gitignore merge block duplicated"

# --with-ci adds the workflow (named lean-stack-ci.yml, not ci.yml).
bash "$REPO/install.sh" . --with-ci >/dev/null 2>&1 || bad "--with-ci run exited non-zero"
[ -f .github/workflows/lean-stack-ci.yml ] && ok "--with-ci installs lean-stack-ci.yml" || bad "--with-ci did not install CI"

# The installed tree (scaffold at git root) passes its own hook smoke tests.
if ( cd "$TMP" && bash scripts/test-hooks.sh ) >/dev/null 2>&1; then
  ok "installed tree passes scripts/test-hooks.sh"
else
  bad "installed tree FAILED scripts/test-hooks.sh"
fi

# Brownfield: a target that already has its OWN .claude/settings.json must be PRESERVED and the
# user WARNED that the lean hooks/permissions.deny were not merged (else the kill-switch/secret
# guard are silently inert). This is the documented adoption gotcha — it must be surfaced, not silent.
BF="$(mktemp -d)" && ( cd "$BF" && git init -q && git config user.email t@t.t && git config user.name t )
mkdir -p "$BF/.claude"; printf '{"hooks":{}}\n' > "$BF/.claude/settings.json"
BF_BEFORE="$(cat "$BF/.claude/settings.json")"
BF_OUT="$(bash "$REPO/install.sh" "$BF" 2>&1)"
[ "$(cat "$BF/.claude/settings.json")" = "$BF_BEFORE" ] && ok "brownfield: existing settings.json preserved" || bad "brownfield settings.json clobbered"
case "$BF_OUT" in *"NOT merged"*) ok "brownfield: install warns lean hooks not wired" ;; *) bad "brownfield: NO warning that hooks were left unwired" ;; esac
rm -rf "$BF"

echo ""
if [ "$FAILS" -eq 0 ]; then echo "install smoke test: PASS"; exit 0
else echo "install smoke test: $FAILS failure(s)"; exit 1; fi
