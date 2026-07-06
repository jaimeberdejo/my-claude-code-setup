#!/usr/bin/env bash
# test-sync.sh — scripts/sync.sh must pull toolkit fixes into an already-scaffolded project
# conservatively: never a blind two-way overwrite. Covers arg validation, enumeration parity
# with install.sh's find+exclusions, the four-tier classifier, and the three non-mixed tiers
# end-to-end (overwrite / never / unknown), plus the Phase-1 mixed-file stub.
#
# Phase 1 scope: a differing mixed file (e.g. .claude/lib/_high-stakes.sh) always routes to the
# safe "manual review" bucket and is NEVER overwritten — the value-preserving merge is Phase 2.
set -uo pipefail
SCAFFOLD="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SYNC="$SCAFFOLD/scripts/sync.sh"
[ -f "$SYNC" ] || { echo "test: missing $SYNC" >&2; exit 1; }
command -v git >/dev/null 2>&1 || { echo "test: git required"; exit 1; }

FAILS=0
pass() { printf '  ✓ %s\n' "$1"; }
fail() { printf '  ✗ %s\n' "$1"; FAILS=$((FAILS+1)); }

WORK="$(mktemp -d 2>/dev/null || mktemp -d -t leanstack-sync)"
trap 'rm -rf "$WORK" 2>/dev/null' EXIT

# mktoolkit: fresh fake jaimitos-os checkout with one file per tier, the enumeration-exclusion
# fixtures (toolkit-docs/, .github/workflows/, .DS_Store), and a repo-root VERSION next to it
# (sync.sh reads <toolkit>/../VERSION, mirroring install.sh's layout: VERSION next to the
# jaimitos-os/ scaffold dir). Sets the global $TOOLKIT to the scaffold dir path.
mktoolkit() {
  rm -rf "$WORK/src"
  TOOLKIT="$WORK/src/jaimitos-os"
  mkdir -p "$TOOLKIT/scripts" "$TOOLKIT/.github/scripts" "$TOOLKIT/.github/workflows" \
           "$TOOLKIT/.claude/lib" "$TOOLKIT/.claude/hooks" "$TOOLKIT/.claude/commands" \
           "$TOOLKIT/.claude/agents" "$TOOLKIT/.claude/rules" "$TOOLKIT/docs" \
           "$TOOLKIT/toolkit-docs"
  printf '9.9.9\n' > "$WORK/src/VERSION"

  printf '#!/usr/bin/env bash\necho toolkit-foo\n' > "$TOOLKIT/scripts/foo.sh"
  printf '#!/usr/bin/env bash\necho toolkit-a\n'   > "$TOOLKIT/scripts/a.sh"
  printf '#!/usr/bin/env bash\necho toolkit-z\n'   > "$TOOLKIT/.github/scripts/z.sh"
  printf 'name: ci\n'                              > "$TOOLKIT/.github/workflows/y"
  printf 'legacy toolkit doc\n'                     > "$TOOLKIT/toolkit-docs/x"
  : > "$TOOLKIT/.DS_Store"
  printf '#!/usr/bin/env bash\nHIGH_STAKES_RE=toolkit-default\n' > "$TOOLKIT/.claude/lib/_high-stakes.sh"
  printf '{"hooks":{}}\n'             > "$TOOLKIT/.claude/settings.json"
  printf '# Spec\ntoolkit copy\n'     > "$TOOLKIT/docs/SPEC.md"
  printf '# Project\ntoolkit copy\n'  > "$TOOLKIT/CLAUDE.md"
}

# mkproject <name>: fresh throwaway git repo, cd's the CURRENT shell into it (tests run
# sequentially, each starting a new project — mirrors mkrepo() in test-close-milestone.sh).
mkproject() {
  REPO="$WORK/$1"; rm -rf "$REPO"; mkdir -p "$REPO"
  ( cd "$REPO" && git init -q )
  cd "$REPO" || exit 1
}

# runsync [args...]: run the real sync.sh against $TOOLKIT with no stdin attached beyond what's
# already redirected; captures combined output to $WORK/out, echoes the exit code.
runsync() {
  bash "$SYNC" --toolkit "$TOOLKIT" "$@" >"$WORK/out" 2>&1
  echo $?
}

echo "sync.sh tests"; echo ""

# 1 — args: --toolkit missing / pointed at a nonexistent path.
mkproject t1-a
bash "$SYNC" >"$WORK/out" 2>&1; rc=$?
{ [ "$rc" -ne 0 ] && grep -qi toolkit "$WORK/out"; } \
  && pass "missing --toolkit → clear error, nonzero exit" \
  || fail "missing --toolkit mishandled (rc=$rc)"

mkproject t1-b
bash "$SYNC" --toolkit /nonexistent-toolkit-path-xyz >"$WORK/out" 2>&1; rc=$?
{ [ "$rc" -ne 0 ] && grep -qi toolkit "$WORK/out"; } \
  && pass "--toolkit /nonexistent → clear error, nonzero exit" \
  || fail "nonexistent --toolkit mishandled (rc=$rc)"

mkproject t1-c
bash "$SYNC" --toolkit "$REPO" --bogus-flag >"$WORK/out" 2>&1; rc=$?
[ "$rc" -ne 0 ] && pass "unknown argument → nonzero exit" || fail "unknown argument not rejected (rc=$rc)"

# 2 — enumeration parity: excluded dirs/files are never offered; .github/scripts/*.sh and
# scripts/*.sh ARE (proves sync does NOT blanket-exclude all of .github/*, only workflows/).
mktoolkit
mkproject t2
rc=$(runsync --dry-run)
{ [ "$rc" -eq 0 ] \
  && grep -q "scripts/a.sh" "$WORK/out" \
  && grep -q ".github/scripts/z.sh" "$WORK/out" \
  && ! grep -q "toolkit-docs" "$WORK/out" \
  && ! grep -q ".github/workflows" "$WORK/out" \
  && ! grep -q "DS_Store" "$WORK/out"; } \
  && pass "enumeration mirrors install.sh's exclusions (toolkit-docs/, .github/workflows/, .DS_Store never offered)" \
  || fail "enumeration parity broken"

# 3 — overwrite tier: --yes updates a differing project file to match the toolkit's bytes.
mktoolkit
mkproject t3
mkdir -p scripts
printf '#!/usr/bin/env bash\necho project-foo\n' > scripts/foo.sh
rc=$(runsync --yes)
{ [ "$rc" -eq 0 ] && cmp -s scripts/foo.sh "$TOOLKIT/scripts/foo.sh"; } \
  && pass "overwrite tier: --yes updates a differing file to the toolkit's bytes" \
  || fail "overwrite --yes did not update scripts/foo.sh (rc=$rc)"

# 3b — overwrite tier: a piped "n" answer (no --yes) leaves the file untouched.
mktoolkit
mkproject t3b
mkdir -p scripts
printf '#!/usr/bin/env bash\necho project-foo\n' > scripts/foo.sh
printf 'n\n' | bash "$SYNC" --toolkit "$TOOLKIT" >"$WORK/out" 2>&1; rc=$?
{ [ "$rc" -eq 0 ] && grep -q "project-foo" scripts/foo.sh && ! cmp -s scripts/foo.sh "$TOOLKIT/scripts/foo.sh"; } \
  && pass "overwrite tier: piped 'n' declines, file left unchanged" \
  || fail "declined overwrite ('n') still changed the file (rc=$rc)"

# 3c — overwrite tier: an empty answer defaults to NO (no --yes).
mktoolkit
mkproject t3c
mkdir -p scripts
printf '#!/usr/bin/env bash\necho project-foo\n' > scripts/foo.sh
printf '\n' | bash "$SYNC" --toolkit "$TOOLKIT" >"$WORK/out" 2>&1; rc=$?
{ [ "$rc" -eq 0 ] && grep -q "project-foo" scripts/foo.sh && ! cmp -s scripts/foo.sh "$TOOLKIT/scripts/foo.sh"; } \
  && pass "overwrite tier: empty answer defaults to NO, file left unchanged" \
  || fail "empty answer wrongly applied the overwrite (rc=$rc)"

# 4 — never tier: project docs/SPEC.md and CLAUDE.md stay byte-identical even with --yes.
mktoolkit
mkproject t4
mkdir -p docs
printf '# Spec\nproject customized\n'    > docs/SPEC.md
printf '# Project\nproject customized\n' > CLAUDE.md
rc=$(runsync --yes)
{ [ "$rc" -eq 0 ] && grep -q "project customized" docs/SPEC.md && grep -q "project customized" CLAUDE.md; } \
  && pass "never tier: docs/SPEC.md and CLAUDE.md untouched even with --yes" \
  || fail "never-tier file was overwritten (rc=$rc)"

# 5 — mixed tier (Phase-1 stub): a differing _high-stakes.sh is routed to manual review and
# left byte-identical (NOT overwritten) even with --yes — proves mixed isn't treated as overwrite.
mktoolkit
mkproject t5
mkdir -p .claude/lib
printf '#!/usr/bin/env bash\nHIGH_STAKES_RE=project-custom-regex\n' > .claude/lib/_high-stakes.sh
rc=$(runsync --yes)
{ [ "$rc" -eq 0 ] && grep -q "project-custom-regex" .claude/lib/_high-stakes.sh && grep -qi "manual review" "$WORK/out"; } \
  && pass "mixed tier (Phase-1 stub): differing _high-stakes.sh → manual review, untouched even with --yes" \
  || fail "mixed-tier file was overwritten or not reported as manual review (rc=$rc)"

# 6 — unknown tier: a differing .claude/settings.json is left byte-identical, reported manual.
mktoolkit
mkproject t6
mkdir -p .claude
printf '{"hooks":{},"env":{"CUSTOM":"1"}}\n' > .claude/settings.json
rc=$(runsync --yes)
{ [ "$rc" -eq 0 ] && grep -q "CUSTOM" .claude/settings.json && grep -qi "manual review" "$WORK/out"; } \
  && pass "unknown tier: differing .claude/settings.json untouched, reported as manual review" \
  || fail "unknown-tier file was overwritten or not reported (rc=$rc)"

# 7 — --dry-run: nothing is written for ANY tier, regardless of --yes.
mktoolkit
mkproject t7
mkdir -p scripts docs .claude/lib
printf 'project foo\n'          > scripts/foo.sh
printf 'project spec\n'         > docs/SPEC.md
printf 'project claude\n'       > CLAUDE.md
printf 'HIGH_STAKES_RE=project\n' > .claude/lib/_high-stakes.sh
printf '{"env":{"X":1}}\n'      > .claude/settings.json
rc=$(runsync --dry-run --yes)
{ [ "$rc" -eq 0 ] \
  && grep -q "project foo" scripts/foo.sh \
  && grep -q "project spec" docs/SPEC.md \
  && grep -q "project claude" CLAUDE.md \
  && grep -q "HIGH_STAKES_RE=project" .claude/lib/_high-stakes.sh \
  && grep -q '"X":1' .claude/settings.json \
  && [ ! -f .claude/.jaimitos-os-version ]; } \
  && pass "--dry-run writes nothing for any tier (all files byte-identical, no version stamp)" \
  || fail "--dry-run mutated the project tree (rc=$rc)"

# 8 — .claude/.jaimitos-os-version is written/updated to the toolkit VERSION after a real run;
# its prior absence doesn't error.
mktoolkit
mkproject t8
rc=$(runsync --yes)
{ [ "$rc" -eq 0 ] && [ -f .claude/.jaimitos-os-version ] && [ "$(cat .claude/.jaimitos-os-version)" = "9.9.9" ]; } \
  && pass ".claude/.jaimitos-os-version stamped with toolkit VERSION after a real run (prior absence didn't error)" \
  || fail "version stamp missing or wrong after a real run (rc=$rc)"

# 9 — a --toolkit checkout that enumerates to ZERO files (valid shape, but empty of shipped
# files) must not crash. Bash 3.2 regression guard: "${arr[@]}" on a declared-but-empty array
# throws "unbound variable" under `set -u` unless the loop is guarded by the count form first.
rm -rf "$WORK/empty-src"; TOOLKIT="$WORK/empty-src/jaimitos-os"
mkdir -p "$TOOLKIT/.claude" "$TOOLKIT/scripts"
mkproject t9
rc=$(runsync --dry-run)
[ "$rc" -eq 0 ] && pass "empty --toolkit enumeration (0 files) exits cleanly, no 'unbound variable' crash" \
  || fail "empty --toolkit enumeration crashed or errored (rc=$rc)"

echo ""
if [ "$FAILS" -eq 0 ]; then echo "All sync.sh tests passed."; exit 0
else echo "$FAILS sync test(s) FAILED."; echo "--- last output ---"; tail -n 20 "$WORK/out" 2>/dev/null; exit 1; fi
