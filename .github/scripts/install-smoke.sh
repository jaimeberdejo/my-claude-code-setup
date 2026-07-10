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
# M-Ship1: the toolkit's own dev/audit PLANs (PLAN-*.md) must never ship into a target project.
PLANS_SHIPPED="$(find . -name 'PLAN-*.md' -not -path './.git/*')"
[ -z "$PLANS_SHIPPED" ] && ok "no toolkit PLAN-*.md dev docs shipped into target" || bad "toolkit PLAN-*.md shipped into target: $(printf '%s' "$PLANS_SHIPPED" | tr '\n' ' ')"
# SCAFFOLD.md present.
[ -f SCAFFOLD.md ] && ok "SCAFFOLD.md copied" || bad "SCAFFOLD.md missing"
# Pre-existing README untouched, and no scaffold content leaked into it.
[ "$(cat README.md)" = "$README_BEFORE" ] && ok "existing README.md untouched" || bad "README.md was modified/clobbered"
grep -q "Jaimitos OS — the scaffold" README.md && bad "scaffold README content landed in target README.md" || ok "no scaffold content in target README.md"
# CI absent by default.
[ -e .github/workflows/jaimitos-os-ci.yml ] && bad "CI copied without --with-ci" || ok "CI absent by default"
# Core scaffold + shared libs present.
# M13: check the full shipped manifest (was a sample — missed evaluator.md, phase/resume/wrap/autopilot
# commands, _test-cmd.sh, test-sync.sh, etc.). doctor.sh on the installed tree (below) is the broader
# backstop; this explicit list keeps the smoke test self-describing about what a complete install is.
for f in CLAUDE.md .claude/settings.json \
         scripts/autopilot.sh scripts/tick.sh scripts/test-evidence.sh scripts/record-grade.sh \
         scripts/models.sh scripts/sync.sh scripts/doctor.sh scripts/run-guard-tests.sh \
         scripts/close-milestone.sh scripts/next-adr.sh scripts/lint-roadmap.sh \
         scripts/test-models.sh scripts/test-sync.sh scripts/test-tick.sh scripts/test-test-cmd.sh \
         .claude/lib/_secret-scan.sh .claude/lib/_high-stakes.sh .claude/lib/_test-cmd.sh .claude/lib/_eval-isolation.sh \
         .claude/agents/researcher.md .claude/agents/planner.md .claude/agents/executor.md .claude/agents/evaluator.md \
         .claude/commands/resume.md .claude/commands/wrap.md .claude/commands/phase.md \
         .claude/commands/autopilot.md .claude/commands/models.md \
         .claude/high-stakes-path-allowlist \
         sandbox/Dockerfile.autopilot sandbox/run-autopilot-sandboxed.sh; do
  [ -f "$f" ] && ok "installed $f" || bad "missing $f"
done
# Skills installed per-project — assert the FULL shipped manifest (every project skill lands with its
# SKILL.md). A bare roadmap-only check let a dropped/renamed skill ship silently (v2.3.1 fix); this loop
# is the authoritative shipped-skill gate. The installer/meta skill setup-jaimitos-os is NOT copied
# per-project (it installs only via --global-skills). Keep this list in sync with doctor.sh REQUIRED_SKILLS.
for sk in roadmap milestone adr scope-guard unstick teach-back mapme quizme \
          grill to-spec glossary design-twice tdd diagnose merge-conflicts; do
  [ -f ".claude/skills/$sk/SKILL.md" ] && ok "skill installed: $sk/SKILL.md" || bad "skill missing or lacks SKILL.md: .claude/skills/$sk"
done
[ -e .claude/skills/setup-jaimitos-os ] && bad "setup-jaimitos-os copied per-project (should be --global-skills only)" || ok "setup-jaimitos-os not copied per-project"
# Installed version is stamped for doctor.sh.
[ -f .claude/.jaimitos-os-version ] && ok "version stamp written (.claude/.jaimitos-os-version)" || bad "version stamp missing"
# Sync manifest: written on install, sha256sum -c-verifiable, and toolkit-owned only (no
# project-owned entries — sync never manages those files).
MANIFEST=.claude/.jaimitos-manifest
if [ -f "$MANIFEST" ]; then
  ok "sync manifest written ($MANIFEST)"
  if command -v sha256sum >/dev/null 2>&1; then MF_CHECK="sha256sum -c --quiet"; else MF_CHECK="shasum -a 256 -c"; fi
  $MF_CHECK "$MANIFEST" >/dev/null 2>&1 && ok "manifest verifies (sha256sum -c) on a clean install" || bad "manifest does NOT verify with sha256sum -c"
  { ! grep -qF "  CLAUDE.md" "$MANIFEST" && ! grep -q "  docs/" "$MANIFEST" && ! grep -qF "  SCAFFOLD.md" "$MANIFEST"; } \
    && ok "manifest lists toolkit-owned files only" || bad "manifest lists project-owned files"
else
  bad "sync manifest missing ($MANIFEST)"
fi
# .gitignore merged, pre-existing rule preserved.
grep -q "jaimitos-os control/secret ignores" .gitignore && ok ".gitignore merge block added" || bad ".gitignore not merged"
grep -qx "node_modules/" .gitignore && ok "pre-existing .gitignore rule preserved" || bad "pre-existing .gitignore rule lost"

# Idempotent re-run.
OUT2="$(bash "$REPO/install.sh" . 2>&1)" || bad "re-run exited non-zero"
case "$OUT2" in *"skip (exists)"*) ok "re-run skips existing files (idempotent)" ;; *) bad "re-run did not skip existing files" ;; esac
[ "$(grep -c "jaimitos-os control/secret ignores" .gitignore)" -eq 1 ] && ok ".gitignore block not duplicated on re-run" || bad ".gitignore merge block duplicated"

# --with-ci adds the workflow (named jaimitos-os-ci.yml, not ci.yml).
bash "$REPO/install.sh" . --with-ci >/dev/null 2>&1 || bad "--with-ci run exited non-zero"
[ -f .github/workflows/jaimitos-os-ci.yml ] && ok "--with-ci installs jaimitos-os-ci.yml" || bad "--with-ci did not install CI"

# The installed tree (scaffold at git root) passes its own hook smoke tests.
if ( cd "$TMP" && bash scripts/test-hooks.sh ) >/dev/null 2>&1; then
  ok "installed tree passes scripts/test-hooks.sh"
else
  bad "installed tree FAILED scripts/test-hooks.sh"
fi

# M13: run doctor.sh on the installed tree — its own manifest (REQUIRED_SCRIPTS/REQUIRED_LIBS + all
# agents/commands/hooks) is the comprehensive backstop against a shipped-file regression this smoke
# test would otherwise miss. A fresh install is UNCONFIGURED (CLAUDE.md placeholders) so doctor exits 0
# with warnings; we assert only that it finds NO missing files.
if [ -x "$TMP/scripts/doctor.sh" ]; then
  DOC_OUT="$( ( cd "$TMP" && bash scripts/doctor.sh ) 2>&1 || true )"
  if printf '%s\n' "$DOC_OUT" | grep -q "✗ missing"; then
    bad "doctor.sh reports missing files on a fresh install: $(printf '%s\n' "$DOC_OUT" | grep '✗ missing' | head -3 | tr '\n' ';')"
  else
    ok "doctor.sh on the installed tree reports no missing scaffold/scripts/libs/agents/commands"
  fi
fi

# Brownfield: a target that already has its OWN .claude/settings.json must be PRESERVED and the
# user WARNED that the jaimitos-os hooks/permissions.deny were not merged (else the kill-switch/secret
# guard are silently inert). This is the documented adoption gotcha — it must be surfaced, not silent.
BF="$(mktemp -d)" && ( cd "$BF" && git init -q && git config user.email t@t.t && git config user.name t )
mkdir -p "$BF/.claude"; printf '{"hooks":{}}\n' > "$BF/.claude/settings.json"
BF_BEFORE="$(cat "$BF/.claude/settings.json")"
BF_OUT="$(bash "$REPO/install.sh" "$BF" 2>&1)"
[ "$(cat "$BF/.claude/settings.json")" = "$BF_BEFORE" ] && ok "brownfield: existing settings.json preserved" || bad "brownfield settings.json clobbered"
case "$BF_OUT" in *"NOT merged"*) ok "brownfield: install warns jaimitos-os hooks not wired" ;; *) bad "brownfield: NO warning that hooks were left unwired" ;; esac
rm -rf "$BF"

# H4: refuse installing into a SUBDIRECTORY of an existing git repo (one-repo-per-project assumption);
# --allow-subdir overrides (with a loud warning). A fresh non-git dir is unaffected (tested above).
SUB="$(mktemp -d)" && ( cd "$SUB" && git init -q && git config user.email t@t.t && git config user.name t )
mkdir -p "$SUB/pkg"
H4_OUT="$(bash "$REPO/install.sh" "$SUB/pkg" 2>&1)"; H4_RC=$?
{ [ "$H4_RC" -ne 0 ] && case "$H4_OUT" in *SUBDIRECTORY*) true ;; *) false ;; esac; } \
  && ok "H4: install refuses a subdirectory of a git repo (clear message, non-zero)" || bad "H4: subdir install not refused"
[ -e "$SUB/pkg/.claude/settings.json" ] && bad "H4: subdir refusal still wrote files" || ok "H4: subdir refusal wrote nothing"
H4_OUT2="$(bash "$REPO/install.sh" "$SUB/pkg" --allow-subdir 2>&1)"; H4_RC2=$?
{ [ "$H4_RC2" -eq 0 ] && [ -f "$SUB/pkg/.claude/settings.json" ]; } \
  && ok "H4: --allow-subdir proceeds (installs into the subdir)" || bad "H4: --allow-subdir did not proceed"
case "$H4_OUT2" in *SUBDIRECTORY*) ok "H4: --allow-subdir still warns loudly" ;; *) bad "H4: --allow-subdir did not warn" ;; esac
rm -rf "$SUB"

echo ""
if [ "$FAILS" -eq 0 ]; then echo "install smoke test: PASS"; exit 0
else echo "install smoke test: $FAILS failure(s)"; exit 1; fi
