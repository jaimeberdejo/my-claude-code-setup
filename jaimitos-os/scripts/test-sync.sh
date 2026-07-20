#!/usr/bin/env bash
# test-sync.sh — scripts/sync.sh must pull toolkit fixes into an already-scaffolded project
# driven by the checksum manifest (.claude/.jaimitos-manifest), fail-closed:
#   unchanged (local sha == manifest) → batch update; modified → NEVER written (diff shown);
#   project-owned → never touched or reported; deleted locally → never recreated (--restore
#   reinstalls); new toolkit file → added + manifest entry; pre-manifest → refuses and points
#   at --adopt-manifest, which records the local baseline without touching content.
# Also covers: real install.sh writes a valid manifest, sha256sum -c passes, paths with spaces,
# exec-bit restore, the CI opt-in gate for .github/* adds, --dry-run writes nothing at all.
set -uo pipefail
SCAFFOLD="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SYNC="$SCAFFOLD/scripts/sync.sh"
INSTALL="$SCAFFOLD/../install.sh"
[ -f "$SYNC" ] || { echo "test: missing $SYNC" >&2; exit 1; }
command -v git >/dev/null 2>&1 || { echo "test: git required"; exit 1; }

FAILS=0
pass() { printf '  ✓ %s\n' "$1"; }
fail() { printf '  ✗ %s\n' "$1"; FAILS=$((FAILS+1)); }
skip() { printf '  - SKIPPED (%s): %s\n' "$2" "$1"; }
sha() { if command -v sha256sum >/dev/null 2>&1; then sha256sum "$1" | awk '{print $1}'; else shasum -a 256 "$1" | awk '{print $1}'; fi; }

WORK="$(mktemp -d 2>/dev/null || mktemp -d -t leanstack-sync)"
trap 'rm -rf "$WORK" 2>/dev/null' EXIT

# mktoolkit: fresh fake jaimitos-os checkout + sibling skills/ root + repo-root VERSION,
# including the enumeration-exclusion fixtures and a skill file whose name contains a space.
mktoolkit() {
  rm -rf "$WORK/src"
  TOOLKIT="$WORK/src/jaimitos-os"
  mkdir -p "$TOOLKIT/scripts" "$TOOLKIT/.github/scripts" "$TOOLKIT/.github/workflows" \
           "$TOOLKIT/.claude/hooks" "$TOOLKIT/.claude/lib" "$TOOLKIT/docs" "$TOOLKIT/toolkit-docs" \
           "$WORK/src/skills/demo-skill" "$WORK/src/skills/setup-jaimitos-os"
  printf '9.9.9\n' > "$WORK/src/VERSION"
  printf '#!/usr/bin/env bash\necho toolkit-foo-v1\n'   > "$TOOLKIT/scripts/foo.sh"
  printf '#!/usr/bin/env bash\necho toolkit-a-v1\n'     > "$TOOLKIT/scripts/a.sh"
  printf '#!/usr/bin/env bash\necho toolkit-guard-v1\n' > "$TOOLKIT/.claude/hooks/guard.sh"
  printf '#!/usr/bin/env bash\nHIGH_STAKES_RE=toolkit-default-v1\n' > "$TOOLKIT/.claude/lib/_high-stakes.sh"
  printf '#!/usr/bin/env bash\necho toolkit-z-v1\n'     > "$TOOLKIT/.github/scripts/z.sh"
  printf 'name: ci\n'                                    > "$TOOLKIT/.github/workflows/y"
  printf 'legacy toolkit doc\n'                          > "$TOOLKIT/toolkit-docs/x"
  printf 'dev plan — never shipped\n'                    > "$TOOLKIT/PLAN-v0.0-fixture.md"
  : > "$TOOLKIT/.DS_Store"
  printf '{"hooks":{}}\n'            > "$TOOLKIT/.claude/settings.json"
  printf '# Spec\ntoolkit copy\n'    > "$TOOLKIT/docs/SPEC.md"
  printf '# Project\ntoolkit copy\n' > "$TOOLKIT/CLAUDE.md"
  printf '# Demo skill v1\n'         > "$WORK/src/skills/demo-skill/SKILL.md"
  printf 'notes v1 with a space\n'   > "$WORK/src/skills/demo-skill/my notes.md"
  printf 'skills catalog readme (never copied per-project)\n' > "$WORK/src/skills/README.md"
  printf 'meta/installer skill (global-only)\n' > "$WORK/src/skills/setup-jaimitos-os/SKILL.md"
}

# mkproject <name>: fresh throwaway git repo; cd's the current shell into it.
mkproject() {
  REPO="$WORK/$1"; rm -rf "$REPO"; mkdir -p "$REPO/.claude"
  printf '{"hooks":{}}\n' > "$REPO/.claude/settings.json"
  ( cd "$REPO" && git init -q )
  cd "$REPO" || exit 1
}

# scaffold_project: emulate an installed project — copy the fake toolkit's shippable files in
# (default install: no .github/*), then record the manifest baseline via --adopt-manifest.
scaffold_project() {
  mkdir -p scripts .claude/hooks .claude/lib .claude/skills/demo-skill docs
  cp "$TOOLKIT/scripts/foo.sh" scripts/foo.sh
  cp "$TOOLKIT/scripts/a.sh" scripts/a.sh
  cp "$TOOLKIT/.claude/hooks/guard.sh" .claude/hooks/guard.sh
  cp "$TOOLKIT/.claude/lib/_high-stakes.sh" .claude/lib/_high-stakes.sh
  cp "$TOOLKIT/.claude/settings.json" .claude/settings.json
  cp "$TOOLKIT/docs/SPEC.md" docs/SPEC.md
  cp "$TOOLKIT/CLAUDE.md" CLAUDE.md
  cp "$WORK/src/skills/demo-skill/SKILL.md" .claude/skills/demo-skill/SKILL.md
  cp "$WORK/src/skills/demo-skill/my notes.md" ".claude/skills/demo-skill/my notes.md"
  bash "$SYNC" --toolkit "$TOOLKIT" --adopt-manifest >/dev/null 2>&1
}

runsync() { bash "$SYNC" --toolkit "$TOOLKIT" "$@" >"$WORK/out" 2>&1; echo $?; }

echo "sync.sh (manifest model) tests"; echo ""

# 1+2 — the REAL install.sh writes a valid, sha256sum -c-verifiable manifest on a clean install,
# with no project-owned entries.
if [ -f "$INSTALL" ]; then
  mkproject t1; rm -rf .claude   # truly clean target
  ( git init -q ) 2>/dev/null
  bash "$INSTALL" . >/dev/null 2>&1
  M=.claude/.jaimitos-manifest
  { [ -f "$M" ] && grep -qE '^[0-9a-f]{64}  ' "$M" \
    && grep -qF "  scripts/tick.sh" "$M" \
    && ! grep -qF "  CLAUDE.md" "$M" && ! grep -q "  docs/" "$M"; } \
    && pass "install.sh writes a well-formed manifest (toolkit-owned only, no CLAUDE.md/docs entries)" \
    || fail "install.sh manifest missing/malformed"
  if command -v sha256sum >/dev/null 2>&1; then CHECK="sha256sum -c --quiet"; else CHECK="shasum -a 256 -c"; fi
  if $CHECK "$M" >/dev/null 2>&1; then pass "sha256sum -c passes against a clean install"
  else fail "sha256sum -c fails after a clean install"; fi
else
  skip "real install.sh manifest checks" "install.sh not found next to scaffold"
fi

# 3 — unchanged locally + toolkit bump → --yes updates AND refreshes the manifest entry.
mktoolkit; mkproject t3; scaffold_project
printf '#!/usr/bin/env bash\necho toolkit-foo-v2\n' > "$TOOLKIT/scripts/foo.sh"
rc=$(runsync --yes)
{ [ "$rc" -eq 0 ] && cmp -s scripts/foo.sh "$TOOLKIT/scripts/foo.sh" \
  && grep -qF "$(sha scripts/foo.sh)  scripts/foo.sh" .claude/.jaimitos-manifest; } \
  && pass "unchanged file: --yes updates to toolkit bytes and refreshes its manifest entry" \
  || fail "unchanged-file update or manifest refresh broken (rc=$rc)"

# 4 — locally modified → NEVER written (even with --yes); diff shown, listed for manual merge.
mktoolkit; mkproject t4; scaffold_project
printf '#!/usr/bin/env bash\necho PROJECT-CUSTOM\n' > scripts/foo.sh
printf '#!/usr/bin/env bash\necho toolkit-foo-v2\n' > "$TOOLKIT/scripts/foo.sh"
rc=$(runsync --yes)
{ [ "$rc" -eq 0 ] && grep -q "PROJECT-CUSTOM" scripts/foo.sh \
  && grep -qi "manual merge required" "$WORK/out" \
  && grep -q "toolkit-foo-v2" "$WORK/out"; } \
  && pass "modified file: never overwritten even with --yes; toolkit↔local diff shown" \
  || fail "modified file was overwritten or diff not shown (rc=$rc)"

# 5 — project-owned: never touched, never reported, even with --yes and a differing toolkit copy.
mktoolkit; mkproject t5; scaffold_project
printf '# Project\nproject customized\n' > CLAUDE.md
printf '# Spec\nproject customized\n'    > docs/SPEC.md
printf '# Project\ntoolkit v2\n' > "$TOOLKIT/CLAUDE.md"
printf '# Spec\ntoolkit v2\n'    > "$TOOLKIT/docs/SPEC.md"
rc=$(runsync --yes)
{ [ "$rc" -eq 0 ] && grep -q "project customized" CLAUDE.md && grep -q "project customized" docs/SPEC.md \
  && ! grep -q "CLAUDE.md" "$WORK/out" && ! grep -q "docs/SPEC.md" "$WORK/out"; } \
  && pass "project-owned files untouched AND unreported even with --yes" \
  || fail "project-owned file touched or reported (rc=$rc)"

# 6 — pre-manifest project → refuses, names --adopt-manifest, writes nothing.
mktoolkit; mkproject t6
mkdir -p scripts; printf 'old local foo\n' > scripts/foo.sh
rc=$(runsync --yes)
{ [ "$rc" -ne 0 ] && grep -q -- "--adopt-manifest" "$WORK/out" \
  && grep -q "old local foo" scripts/foo.sh && [ ! -f .claude/.jaimitos-manifest ]; } \
  && pass "pre-manifest project: refused with --adopt-manifest guidance, nothing written" \
  || fail "pre-manifest project not refused cleanly (rc=$rc)"

# 7 — --adopt-manifest records the LOCAL state as baseline without touching content; a second
# adopt refuses (no silent re-baselining).
mktoolkit; mkproject t7
mkdir -p scripts; printf '#!/usr/bin/env bash\necho LOCAL-BASELINE\n' > scripts/foo.sh
rc=$(runsync --adopt-manifest)
{ [ "$rc" -eq 0 ] && grep -q "LOCAL-BASELINE" scripts/foo.sh \
  && grep -qF "$(sha scripts/foo.sh)  scripts/foo.sh" .claude/.jaimitos-manifest; } \
  && pass "--adopt-manifest: baseline = current local sha, content untouched" \
  || fail "--adopt-manifest broken (rc=$rc)"
rc=$(runsync --adopt-manifest)
[ "$rc" -ne 0 ] && pass "second --adopt-manifest refuses (manifest already exists)" \
  || fail "re-adopt did not refuse (rc=$rc)"

# 8 — after adoption, a toolkit bump on an unmodified file syncs in.
mktoolkit; mkproject t8
mkdir -p scripts; cp "$TOOLKIT/scripts/foo.sh" scripts/foo.sh
rc=$(runsync --adopt-manifest)
printf '#!/usr/bin/env bash\necho toolkit-foo-v2\n' > "$TOOLKIT/scripts/foo.sh"
rc=$(runsync --yes)
{ [ "$rc" -eq 0 ] && cmp -s scripts/foo.sh "$TOOLKIT/scripts/foo.sh"; } \
  && pass "post-adoption sync updates an unmodified file" \
  || fail "post-adoption update broken (rc=$rc)"

# 9 — a NEW toolkit file (not in manifest, absent locally) is installed and enters the manifest.
mktoolkit; mkproject t9; scaffold_project
printf '#!/usr/bin/env bash\necho brand-new\n' > "$TOOLKIT/scripts/new-tool.sh"
rc=$(runsync --yes)
{ [ "$rc" -eq 0 ] && cmp -s scripts/new-tool.sh "$TOOLKIT/scripts/new-tool.sh" \
  && grep -qF "  scripts/new-tool.sh" .claude/.jaimitos-manifest; } \
  && pass "new toolkit file: installed via the batch and added to the manifest" \
  || fail "new toolkit file not installed / not in manifest (rc=$rc)"

# 10 — locally deleted (still in manifest): never recreated; --restore reinstalls it.
mktoolkit; mkproject t10; scaffold_project
rm scripts/a.sh
rc=$(runsync --yes)
{ [ "$rc" -eq 0 ] && [ ! -e scripts/a.sh ] && grep -qi "deleted locally" "$WORK/out" \
  && grep -q -- "--restore" "$WORK/out"; } \
  && pass "deleted-locally file: skipped with the --restore hint, not recreated" \
  || fail "deleted file was recreated or not reported (rc=$rc)"
rc=$(runsync --yes --restore scripts/a.sh)
{ [ "$rc" -eq 0 ] && cmp -s scripts/a.sh "$TOOLKIT/scripts/a.sh" \
  && grep -qF "$(sha scripts/a.sh)  scripts/a.sh" .claude/.jaimitos-manifest; } \
  && pass "--restore reinstalls the deleted file and refreshes its manifest entry" \
  || fail "--restore broken (rc=$rc)"

# 11 — --dry-run writes NOTHING: no content, no manifest change, no version stamp.
mktoolkit; mkproject t11; scaffold_project
cp .claude/.jaimitos-manifest "$WORK/t11-manifest"
printf '#!/usr/bin/env bash\necho toolkit-foo-v2\n' > "$TOOLKIT/scripts/foo.sh"
printf '#!/usr/bin/env bash\necho brand-new\n' > "$TOOLKIT/scripts/new-tool.sh"
rc=$(runsync --dry-run --yes)
{ [ "$rc" -eq 0 ] && ! cmp -s scripts/foo.sh "$TOOLKIT/scripts/foo.sh" && [ ! -e scripts/new-tool.sh ] \
  && cmp -s .claude/.jaimitos-manifest "$WORK/t11-manifest" && [ ! -f .claude/.jaimitos-os-version ] \
  && grep -q "would" "$WORK/out"; } \
  && pass "--dry-run previews the plan and writes nothing (content, manifest, version stamp)" \
  || fail "--dry-run mutated the project (rc=$rc)"

# 12 — paths with spaces survive enumerate/hash/update/manifest round-trips.
mktoolkit; mkproject t12; scaffold_project
printf 'notes v2 with a space\n' > "$WORK/src/skills/demo-skill/my notes.md"
rc=$(runsync --yes)
{ [ "$rc" -eq 0 ] && cmp -s ".claude/skills/demo-skill/my notes.md" "$WORK/src/skills/demo-skill/my notes.md" \
  && grep -qF "  .claude/skills/demo-skill/my notes.md" .claude/.jaimitos-manifest; } \
  && pass "a path containing a space updates and round-trips through the manifest" \
  || fail "space-in-path handling broken (rc=$rc)"

# 13 — never-scaffolded target (no settings.json) refused, points at install.sh.
mktoolkit; mkproject t13; rm -rf .claude
rc=$(runsync --dry-run)
{ [ "$rc" -ne 0 ] && grep -qi "install.sh" "$WORK/out"; } \
  && pass "never-scaffolded project refused with install.sh guidance" \
  || fail "unscaffolded target not refused (rc=$rc)"

# 14 — batch confirmation: an empty piped answer defaults to NO; nothing written.
mktoolkit; mkproject t14; scaffold_project
printf '#!/usr/bin/env bash\necho toolkit-foo-v2\n' > "$TOOLKIT/scripts/foo.sh"
printf '\n' | bash "$SYNC" --toolkit "$TOOLKIT" >"$WORK/out" 2>&1; rc=$?
{ [ "$rc" -eq 0 ] && ! cmp -s scripts/foo.sh "$TOOLKIT/scripts/foo.sh"; } \
  && pass "batch confirm: empty answer defaults to NO, file left unchanged" \
  || fail "empty answer wrongly applied the batch (rc=$rc)"

# 15 — exec bit restored when updating a mode-644 script/hook.
mktoolkit; mkproject t15; scaffold_project
printf '#!/usr/bin/env bash\necho toolkit-foo-v2\n'   > "$TOOLKIT/scripts/foo.sh"
printf '#!/usr/bin/env bash\necho toolkit-guard-v2\n' > "$TOOLKIT/.claude/hooks/guard.sh"
chmod 644 scripts/foo.sh .claude/hooks/guard.sh
rc=$(runsync --yes)
{ [ "$rc" -eq 0 ] && [ -x scripts/foo.sh ] && [ -x .claude/hooks/guard.sh ]; } \
  && pass "exec bit restored on updated scripts/hooks" \
  || fail "exec bit not restored (rc=$rc)"

# 16 — CI opt-in gate: .github/scripts/z.sh never ADDED without a .github/ dir; added with one.
mktoolkit; mkproject t16; scaffold_project
rc=$(runsync --yes)
{ [ "$rc" -eq 0 ] && [ ! -e .github/scripts/z.sh ] && grep -qi "CI not opted in" "$WORK/out"; } \
  && pass "CI gate: first .github/* file not added to a project with no .github/ dir" \
  || fail "CI gate failed to hold (rc=$rc)"
mkdir -p .github
rc=$(runsync --yes)
{ [ "$rc" -eq 0 ] && cmp -s .github/scripts/z.sh "$TOOLKIT/.github/scripts/z.sh"; } \
  && pass "CI gate counterpart: existing .github/ dir gets the add normally" \
  || fail "CI-opted-in add broken (rc=$rc)"

# 17 — version stamp written after a real run; _high-stakes.sh update refreshes the fingerprint.
mktoolkit; mkproject t17; scaffold_project
printf '#!/usr/bin/env bash\nHIGH_STAKES_RE=toolkit-default-v2\n' > "$TOOLKIT/.claude/lib/_high-stakes.sh"
rc=$(runsync --yes)
{ [ "$rc" -eq 0 ] && [ "$(cat .claude/.jaimitos-os-version)" = "9.9.9" ] \
  && grep -q "toolkit-default-v2" .claude/.high-stakes-default; } \
  && pass "real run stamps the toolkit VERSION and refreshes the high-stakes fingerprint" \
  || fail "version stamp / fingerprint refresh broken (rc=$rc)"

# 18 — a cp that genuinely fails → FAILED + nonzero exit + no version stamp bump.
# chmod 444 does not stop root's cp, so this fixture only proves anything as non-root (CI).
if [ "$(id -u)" -ne 0 ]; then
  mktoolkit; mkproject t18; scaffold_project
  printf '#!/usr/bin/env bash\necho toolkit-foo-v2\n' > "$TOOLKIT/scripts/foo.sh"
  printf '0.0.0\n' > .claude/.jaimitos-os-version
  chmod 444 scripts/foo.sh; chmod 555 scripts
  rc=$(runsync --yes)
  chmod 755 scripts; chmod 644 scripts/foo.sh
  { [ "$rc" -ne 0 ] && grep -qi "FAILED" "$WORK/out" \
    && [ "$(cat .claude/.jaimitos-os-version)" = "0.0.0" ]; } \
    && pass "failed copy: reported FAILED, nonzero exit, version stamp not bumped" \
    || fail "cp failure silently treated as success (rc=$rc)"
else
  skip "failed-copy fixture" "running as root — chmod cannot make the destination unwritable"
fi

# 19 — enumeration exclusions: toolkit-docs/, .github/workflows/, PLAN-*.md, .DS_Store,
# skills/README.md and setup-jaimitos-os/* are never offered.
mktoolkit; mkproject t19; scaffold_project
rc=$(runsync --dry-run)
{ [ "$rc" -eq 0 ] && ! grep -q "toolkit-docs" "$WORK/out" && ! grep -q "workflows" "$WORK/out" \
  && ! grep -q "PLAN-v0" "$WORK/out" && ! grep -q "DS_Store" "$WORK/out" \
  && ! grep -q "skills/README.md" "$WORK/out" && ! grep -q "setup-jaimitos-os" "$WORK/out"; } \
  && pass "enumeration mirrors install.sh's exclusions (docs/plans/cruft/meta-skill never offered)" \
  || fail "enumeration exclusions broken (rc=$rc)"

# 20 — a RESOLVED conflict does not recur. A modified file is skipped (diff shown); once the user
# aligns it to the toolkit version, the next sync reclassifies it "already current" and self-repairs
# its stale manifest entry (sync.sh's cmp -s branch), so a third sync is clean — no perpetual
# "manual merge" for a file the user already resolved.
mktoolkit; mkproject t20; scaffold_project
printf '#!/usr/bin/env bash\necho PROJECT-CUSTOM\n' > scripts/foo.sh            # local edit
printf '#!/usr/bin/env bash\necho toolkit-foo-v2\n' > "$TOOLKIT/scripts/foo.sh" # toolkit bump
rc=$(runsync --yes)
{ [ "$rc" -eq 0 ] && grep -qi "manual merge required" "$WORK/out" && grep -q PROJECT-CUSTOM scripts/foo.sh; } \
  && pass "precondition: the conflict is flagged 'manual merge required' and the file left untouched" \
  || fail "precondition broken: conflict not flagged (rc=$rc)"
cp "$TOOLKIT/scripts/foo.sh" scripts/foo.sh                                     # user resolves to toolkit
rc=$(runsync --yes)
{ [ "$rc" -eq 0 ] && ! grep -qi "manual merge required" "$WORK/out" \
  && grep -qF "$(sha scripts/foo.sh)  scripts/foo.sh" .claude/.jaimitos-manifest; } \
  && pass "after resolving to the toolkit version, re-sync is clean and self-repairs the manifest entry" \
  || fail "resolved conflict still flagged, or manifest not self-repaired (rc=$rc)"
rc=$(runsync --yes)
{ [ "$rc" -eq 0 ] && ! grep -qi "manual merge required" "$WORK/out"; } \
  && pass "a resolved conflict does not recur on a subsequent sync" \
  || fail "resolved conflict recurred (rc=$rc)"

# 21 — footprint gate (v2.16.0): the optional guard suite is UPDATE-where-present, never ADDED to a lean
# project (which would undo the install-time --with-tests gate by re-shipping ~27 files as "new").
# test-evidence.sh is always managed and IS offered; test-*.sh / run-guard-tests.sh are gated on local presence.
mktoolkit; mkproject t21; scaffold_project
printf '#!/usr/bin/env bash\necho tk-test-foo-v1\n'  > "$TOOLKIT/scripts/test-foo.sh"
printf '#!/usr/bin/env bash\necho tk-runguard-v1\n'  > "$TOOLKIT/scripts/run-guard-tests.sh"
printf '#!/usr/bin/env bash\necho tk-evidence-v1\n'  > "$TOOLKIT/scripts/test-evidence.sh"
rc=$(runsync --dry-run)
{ [ "$rc" -eq 0 ] && ! grep -qE 'test-foo\.sh|run-guard-tests\.sh' "$WORK/out"; } \
  && pass "lean project: the optional guard suite (test-*.sh / run-guard-tests.sh) is NOT re-added by sync" \
  || fail "footprint gate broken — sync offered the guard suite to a lean project (rc=$rc)"
grep -q 'test-evidence.sh' "$WORK/out" \
  && pass "always-managed test-evidence.sh IS still offered to a lean project" \
  || fail "always-managed test-evidence.sh was wrongly gated out (rc=$rc)"
# update-where-present: a FRESH project scaffolded WITH a guard-suite file (its manifest records it at
# adopt time) gets that file updated on a toolkit bump — the gate is update-where-present, not never-touch.
printf '#!/usr/bin/env bash\necho tk-test-foo-v1\n' > "$TOOLKIT/scripts/test-foo.sh"
mkproject t21b
mkdir -p scripts .claude
cp "$TOOLKIT/scripts/foo.sh" scripts/foo.sh
cp "$TOOLKIT/.claude/settings.json" .claude/settings.json
cp "$TOOLKIT/scripts/test-foo.sh" scripts/test-foo.sh                       # project HAS the guard-suite file
bash "$SYNC" --toolkit "$TOOLKIT" --adopt-manifest >/dev/null 2>&1          # FRESH adopt records test-foo.sh
printf '#!/usr/bin/env bash\necho tk-test-foo-v2\n' > "$TOOLKIT/scripts/test-foo.sh"
rc=$(runsync --yes)
{ [ "$rc" -eq 0 ] && grep -q 'tk-test-foo-v2' scripts/test-foo.sh; } \
  && pass "a guard-suite file already present IS updated on a toolkit bump (update-where-present)" \
  || fail "present guard-suite file not updated (rc=$rc)"

echo ""
echo "retired-file reconciliation (v2.17): a manifest entry the current toolkit no longer ships"

# Each retired test rebuilds a FRESH toolkit (mktoolkit) because retiring a file mutates $TOOLKIT.

# unchanged retired → REPORTED, not removed without --prune.
mktoolkit; mkproject tR1; scaffold_project
rm "$TOOLKIT/scripts/a.sh"            # RETIRE a.sh from the toolkit (still in the manifest + locally)
rc=$(runsync --yes)                  # note: NO --prune
{ [ "$rc" = 0 ] && [ -f scripts/a.sh ] && grep -q 'retired + unchanged (safe to remove): scripts/a.sh' "$WORK/out" && grep -q 'retired removable' "$WORK/out"; } \
  && pass "unchanged retired file is REPORTED, not removed without --prune" || fail "retired report wrong (rc=$rc)"

# --prune --yes → removes it AND drops the manifest entry.
rc=$(runsync --prune --yes)
{ [ "$rc" = 0 ] && [ ! -e scripts/a.sh ] && ! grep -qF '  scripts/a.sh' .claude/.jaimitos-manifest; } \
  && pass "--prune removes an unchanged retired file + drops its manifest entry" || fail "--prune did not remove/drop (rc=$rc)"

# locally MODIFIED retired → never auto-removed, even with --prune.
mktoolkit; mkproject tR2; scaffold_project
rm "$TOOLKIT/scripts/a.sh"; echo 'local customization' >> scripts/a.sh
rc=$(runsync --prune --yes)
{ [ "$rc" = 0 ] && [ -f scripts/a.sh ] && grep -q 'LOCALLY MODIFIED' "$WORK/out"; } \
  && pass "a locally-modified retired file is preserved (manual), never auto-removed" || fail "modified retired mishandled (rc=$rc)"

# locally DELETED retired → stale manifest entry dropped, nothing reinstalled.
mktoolkit; mkproject tR3; scaffold_project
rm "$TOOLKIT/scripts/a.sh"; rm scripts/a.sh
rc=$(runsync --yes)
{ [ "$rc" = 0 ] && [ ! -e scripts/a.sh ] && ! grep -qF '  scripts/a.sh' .claude/.jaimitos-manifest && grep -q 'dropping stale manifest entry: scripts/a.sh' "$WORK/out"; } \
  && pass "a locally-deleted retired file has its stale manifest entry dropped (not reinstalled)" || fail "deleted retired mishandled (rc=$rc)"

# path-safety: a `..` traversal manifest path is refused (report only, never acted on).
mktoolkit; mkproject tR4; scaffold_project
printf '%s  ../evil.sh\n' '0000000000000000000000000000000000000000000000000000000000000000' >> .claude/.jaimitos-manifest
rc=$(runsync --prune --yes)
{ [ "$rc" = 0 ] && grep -q 'unsafe/malformed manifest path' "$WORK/out" && [ ! -e "$WORK/evil.sh" ]; } \
  && pass "a .. traversal manifest path is refused (never removed/followed)" || fail "unsafe path not caught (rc=$rc)"

# symlink-escape safety: a retired path that is a symlink is never followed/removed.
mktoolkit; mkproject tR5; scaffold_project
rm "$TOOLKIT/scripts/a.sh"; rm scripts/a.sh; ln -s /etc/hosts scripts/a.sh 2>/dev/null
rc=$(runsync --prune --yes)
{ [ "$rc" = 0 ] && [ -L scripts/a.sh ] && grep -q 'unsafe/malformed manifest path' "$WORK/out"; } \
  && pass "a retired path that is a symlink is refused (no escape)" || fail "symlink retired mishandled (rc=$rc)"

# idempotent: a re-sync after pruning shows no retired files.
mktoolkit; mkproject tR6; scaffold_project
rm "$TOOLKIT/scripts/a.sh"; runsync --prune --yes >/dev/null
rc=$(runsync --yes)
{ [ "$rc" = 0 ] && ! grep -q 'retired toolkit files' "$WORK/out"; } \
  && pass "a second sync after prune is clean (idempotent)" || fail "retired reconciliation not idempotent (rc=$rc)"

echo ""
if [ "$FAILS" -eq 0 ]; then echo "All sync.sh tests passed."; exit 0
else echo "$FAILS sync test(s) FAILED."; echo "--- last output ---"; tail -n 25 "$WORK/out" 2>/dev/null; exit 1; fi
