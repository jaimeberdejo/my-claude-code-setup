#!/usr/bin/env bash
# test-doctor.sh — doctor.sh --fix must apply only SAFE, LOCAL, IDEMPOTENT repairs (chmod +x,
# docs/plans, docs/FAILURES.md), never touch the high-stakes fingerprint, and be a no-op on a
# second run. Installs the scaffold into a throwaway repo and breaks the fixable things.
# Also covers the informational "Model configuration:" report section, delegated to scripts/models.sh.
set -uo pipefail
SC="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
command -v git >/dev/null 2>&1 || { echo "test: git required"; exit 1; }

FAILS=0
pass() { printf '  ✓ %s\n' "$1"; }
fail() { printf '  ✗ %s\n' "$1"; FAILS=$((FAILS+1)); }

WORK="$(mktemp -d 2>/dev/null || mktemp -d -t leanstack-doc)"
trap 'rm -rf "$WORK" 2>/dev/null' EXIT
REPO="$WORK/proj"; mkdir -p "$REPO"
cp -R "$SC/." "$REPO/"
cd "$REPO" || exit 1
git init -q && git config user.email t@t.t && git config user.name t
chmod +x .claude/hooks/*.sh scripts/*.sh 2>/dev/null
git add -A >/dev/null 2>&1 && git commit -q -m init

echo "doctor --fix tests"; echo ""

# Break the fixable things; plant a fingerprint to confirm --fix never edits it.
chmod -x .claude/hooks/session-start.sh
rm -rf docs/plans docs/FAILURES.md
printf 'HIGH_STAKES_RE=SENTINEL_DO_NOT_TOUCH\n' > .claude/.high-stakes-default
fp_before=$(cat .claude/.high-stakes-default)

bash scripts/doctor.sh --fix > "$WORK/out" 2>&1 || true

[ -x .claude/hooks/session-start.sh ] && pass "--fix restores the executable bit on a hook" || fail "hook not made executable"
[ -d docs/plans ] && pass "--fix creates docs/plans/" || fail "docs/plans not created"
[ -f docs/FAILURES.md ] && pass "--fix creates docs/FAILURES.md" || fail "docs/FAILURES.md not created"
[ "$fp_before" = "$(cat .claude/.high-stakes-default)" ] && pass "--fix leaves the high-stakes fingerprint untouched" || fail "fingerprint was modified"
grep -q "fixed:" "$WORK/out" && pass "--fix reports what it repaired" || fail "--fix reported no repairs"

# Idempotent: a second --fix finds nothing left to repair.
bash scripts/doctor.sh --fix > "$WORK/out2" 2>&1 || true
grep -q "fixed:" "$WORK/out2" && fail "second --fix still repairs (not idempotent)" || pass "second --fix is a no-op (idempotent)"

# Plain doctor.sh stays report-only (does not create files).
rm -rf docs/plans
bash scripts/doctor.sh > /dev/null 2>&1 || true
[ ! -d docs/plans ] && pass "plain doctor.sh stays report-only (no repairs)" || fail "plain doctor.sh mutated the tree"

echo ""
echo "Model configuration reporting"
echo ""

bash scripts/doctor.sh > "$WORK/out3" 2>&1 || true
grep -q "research: *(inherits session model)" "$WORK/out3" \
  && pass "doctor reports researcher inherits session model by default" \
  || fail "doctor did not report researcher's default (inherit) state"
grep -q "eval: *sonnet" "$WORK/out3" \
  && pass "doctor reports evaluator's shipped model: sonnet" \
  || fail "doctor did not report evaluator's configured model"

bash scripts/models.sh exec=opus > /dev/null 2>&1
bash scripts/doctor.sh > "$WORK/out4" 2>&1 || true
grep -q "exec: *opus" "$WORK/out4" \
  && pass "doctor reflects a hand-set model on executor via models.sh" \
  || fail "doctor did not pick up executor's hand-set model"
bash scripts/models.sh reset > /dev/null 2>&1

echo ""
echo "H3/M4/M11: doctor DETECTS missing load-bearing files + invalid JSON, and prints remediation"
echo ""

# A fresh scaffold copy so the deletions below don't disturb the --fix repo above.
mkscaffold() {
  local d="$1"; rm -rf "$d"; mkdir -p "$d"; cp -R "$SC/." "$d/"
  ( cd "$d" && git init -q && git config user.email t@t.t && git config user.name t \
      && chmod +x .claude/hooks/*.sh scripts/*.sh 2>/dev/null && git add -A >/dev/null 2>&1 && git commit -q -m init )
}

# H3 — delete load-bearing files the OLD hardcoded lists missed. Report must flag each, exit non-zero,
# and NOT print "All good."
mkscaffold "$WORK/h3"
rm -f "$WORK/h3/scripts/tick.sh" "$WORK/h3/scripts/sync.sh" "$WORK/h3/.claude/lib/_test-cmd.sh"
( cd "$WORK/h3" && bash scripts/doctor.sh > "$WORK/h3.out" 2>&1 ); rc=$?
grep -q "missing scripts/tick.sh"          "$WORK/h3.out" && pass "H3: flags a deleted scripts/tick.sh"       || fail "H3: deleted tick.sh not reported"
grep -q "missing scripts/sync.sh"          "$WORK/h3.out" && pass "H3: flags a deleted scripts/sync.sh"       || fail "H3: deleted sync.sh not reported"
grep -q "missing .claude/lib/_test-cmd.sh" "$WORK/h3.out" && pass "H3: flags a deleted _test-cmd.sh lib"      || fail "H3: deleted _test-cmd.sh not reported"
{ [ "$rc" -ne 0 ] && ! grep -q "All good" "$WORK/h3.out"; } \
  && pass "H3: exits non-zero, no false 'All good' with load-bearing files deleted" || fail "H3: clean bill of health despite deletions (rc=$rc)"

# M11 — the remediation hint prints on a plain (no --fix) problem run, not only behind --fix.
grep -q "install.sh --force" "$WORK/h3.out" && pass "M11: remediation hint printed without --fix" || fail "M11: no remediation hint on a plain problem run"

# M4 — a corrupt settings.json is caught (jq empty is a no-op on some bundled jq; jq -e 'type' isn't).
mkscaffold "$WORK/m4"
printf '{ "permissions": { "deny": [ }\n' > "$WORK/m4/.claude/settings.json"
( cd "$WORK/m4" && bash scripts/doctor.sh > "$WORK/m4.out" 2>&1 )
grep -q "settings.json is not valid JSON" "$WORK/m4.out" && pass "M4: flags a corrupt settings.json as invalid" || fail "M4: corrupt settings.json reported valid (jq -e regression)"
grep -q "✓ valid JSON" "$WORK/m4.out" && fail "M4: doctor said '✓ valid JSON' for a corrupt file" || pass "M4: no false '✓ valid JSON' on a corrupt file"

# Control — a pristine scaffold is still a clean bill of health (no false positives from the manifest).
mkscaffold "$WORK/ok"
( cd "$WORK/ok" && bash scripts/doctor.sh > "$WORK/ok.out" 2>&1 ); okrc=$?
{ [ "$okrc" -eq 0 ] && ! grep -q "✗ missing" "$WORK/ok.out"; } \
  && pass "control: pristine scaffold reports no missing load-bearing files" || fail "control: manifest false-positived on a pristine scaffold (rc=$okrc)"

echo ""
echo "H4: jaimitos-os installed in a SUBDIRECTORY of a repo → doctor reports it clearly, not a wall of missing"
echo ""
# An OUTER git repo with the scaffold in a subdir (NOT at the git root). doctor resolves paths from the
# git root, so it must detect the mismatch and say so, not emit a wall of false 'missing'.
OUTER="$WORK/outer"; rm -rf "$OUTER"; mkdir -p "$OUTER/sub"
( cd "$OUTER" && git init -q && git config user.email t@t.t && git config user.name t )
cp -R "$SC/." "$OUTER/sub/"; chmod +x "$OUTER/sub/scripts/"*.sh 2>/dev/null
( cd "$OUTER/sub" && bash scripts/doctor.sh > "$WORK/h4.out" 2>&1 ); h4rc=$?
grep -q "SUBDIRECTORY" "$WORK/h4.out" && pass "H4: doctor reports a subdirectory install clearly" || fail "H4: subdir install not reported"
{ [ "$h4rc" -ne 0 ] && ! grep -q "All good" "$WORK/h4.out" && [ "$(grep -c '✗ missing' "$WORK/h4.out")" -eq 0 ]; } \
  && pass "H4: doctor exits non-zero with NO wall of false 'missing'" || fail "H4: subdir doctor gave misleading output (rc=$h4rc)"

echo ""
if [ "$FAILS" -eq 0 ]; then echo "All doctor --fix tests passed."; exit 0
else echo "$FAILS doctor test(s) FAILED."; tail -n 15 "$WORK/out" 2>/dev/null; exit 1; fi
