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

# doctor.sh counts a missing `claude` CLI as a hard problem (correct for a real operator's machine),
# but CI intentionally does NOT install `claude` (the workflow says so). Without a stub, every doctor
# run below that asserts exit 0 (the pristine-scaffold control + the team-warn advisory checks) would
# fail on that tooling check alone — not on any scaffold defect. Put a no-op `claude` on PATH so
# doctor's exit code reflects SCAFFOLD integrity (missing files / bad JSON), which is what these tests
# assert. jq + git stay real (present locally and in CI). doctor only does `command -v claude`.
STUB_BIN="$WORK/bin"; mkdir -p "$STUB_BIN"
printf '#!/usr/bin/env bash\nexit 0\n' > "$STUB_BIN/claude"; chmod +x "$STUB_BIN/claude"
export PATH="$STUB_BIN:$PATH"

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
echo "Skills manifest: doctor flags a dropped/renamed shipped skill (install-smoke owns the full check)"
echo ""
# The scaffold ($SC) does NOT contain .claude/skills/ — skills are a separate source root the installer
# pulls from the wrapper repo's skills/ dir. Simulate a real per-project install here so doctor's skills
# check has something to validate. If that source is absent (e.g. test-doctor.sh re-run from an installed
# project without the sibling skills/), skip — install-smoke covers the manifest in that context.
SKILLS_SRC="$SC/../skills"
if [ -d "$SKILLS_SRC" ]; then
  mkscaffold "$WORK/skills"
  mkdir -p "$WORK/skills/.claude/skills"
  for skdir in "$SKILLS_SRC"/*/; do
    sk="$(basename "$skdir")"
    [ "$sk" = "setup-jaimitos-os" ] && continue   # --global-skills only, never per-project
    cp -R "$skdir" "$WORK/skills/.claude/skills/$sk"
  done
  ( cd "$WORK/skills" && bash scripts/doctor.sh > "$WORK/skills.ok.out" 2>&1 )
  grep -q "✗ missing .claude/skills" "$WORK/skills.ok.out" \
    && fail "skills: doctor false-flags a complete shipped-skill set" \
    || pass "skills: a complete shipped-skill set passes doctor (no false missing)"
  # Drop one shipped skill → doctor must flag it by name and exit non-zero (not a silent 'All good').
  rm -rf "$WORK/skills/.claude/skills/adr"
  ( cd "$WORK/skills" && bash scripts/doctor.sh > "$WORK/skills.bad.out" 2>&1 ); skrc=$?
  { grep -q "missing .claude/skills/adr/SKILL.md" "$WORK/skills.bad.out" && [ "$skrc" -ne 0 ] && ! grep -q "All good" "$WORK/skills.bad.out"; } \
    && pass "skills: doctor flags a dropped skill (adr) by name and exits non-zero" \
    || fail "skills: a dropped skill was not detected (rc=$skrc)"
else
  pass "skills: SKIP doctor-side check ($SKILLS_SRC absent — install-smoke owns the manifest here)"
fi

echo ""
echo "Team repo warn: >1 contributor + LEAN_CHECKPOINT not off → warn; off (env or settings) → quiet"
echo ""
mkscaffold "$WORK/team"
( cd "$WORK/team" && git -c user.email=other@example.com -c user.name=Other commit -q --allow-empty -m "second author" )
( cd "$WORK/team" && LEAN_CHECKPOINT='' bash scripts/doctor.sh > "$WORK/team.out" 2>&1 ); teamrc=$?
grep -q "team repo detected" "$WORK/team.out" \
  && pass "team: 2 simulated authors + checkpoint on → 'team repo detected' warn" \
  || fail "team: 2-author repo did not warn about LEAN_CHECKPOINT"
[ "$teamrc" -eq 0 ] && pass "team: the warn is advisory (doctor still exits 0)" \
  || fail "team: the team warn wrongly made doctor exit non-zero (rc=$teamrc)"
( cd "$WORK/team" && LEAN_CHECKPOINT=off bash scripts/doctor.sh > "$WORK/team.off.out" 2>&1 )
grep -q "team repo detected" "$WORK/team.off.out" \
  && fail "team: LEAN_CHECKPOINT=off (env) still warned" \
  || pass "team: LEAN_CHECKPOINT=off in the env silences the warn"
# The settings.json env block is the persistent place to set it — doctor must honor it too.
( cd "$WORK/team" && jq '.env.LEAN_CHECKPOINT = "off"' .claude/settings.json > s.tmp && mv s.tmp .claude/settings.json )
( cd "$WORK/team" && LEAN_CHECKPOINT='' bash scripts/doctor.sh > "$WORK/team.set.out" 2>&1 )
grep -q "team repo detected" "$WORK/team.set.out" \
  && fail "team: settings.json env.LEAN_CHECKPOINT=off still warned" \
  || pass "team: LEAN_CHECKPOINT=off in settings.json's env block silences the warn"
# Single-contributor control: no warn.
mkscaffold "$WORK/solo"
( cd "$WORK/solo" && bash scripts/doctor.sh > "$WORK/solo.out" 2>&1 )
grep -q "team repo detected" "$WORK/solo.out" \
  && fail "team: single-contributor repo wrongly warned" \
  || pass "team: single-contributor repo does not warn"

echo ""
echo "Subagent frontmatter check (warn on hyphenated skill fields / malformed frontmatter; advisory)"
echo ""
# Clean control: a pristine scaffold's agents use camelCase fields → the OK line, no warn.
mkscaffold "$WORK/fmok"
( cd "$WORK/fmok" && bash scripts/doctor.sh > "$WORK/fmok.out" 2>&1 )
grep -q "all subagent frontmatter is well-formed" "$WORK/fmok.out" \
  && pass "fm: pristine agents pass the subagent-frontmatter check" \
  || fail "fm: pristine agents did not pass the frontmatter check"
# Hyphenated skill field in a subagent → warn (NOT a hard fail: doctor still exits 0 on an
# otherwise-configured tree), and it names the offending key.
mkscaffold "$WORK/fmhy"
# Insert a hyphenated denylist into the evaluator's frontmatter (after line 1's ---).
awk 'NR==1{print;print "disallowed-tools: Write";next}{print}' "$WORK/fmhy/.claude/agents/evaluator.md" > "$WORK/fmhy/.claude/agents/evaluator.md.tmp" \
  && mv "$WORK/fmhy/.claude/agents/evaluator.md.tmp" "$WORK/fmhy/.claude/agents/evaluator.md"
( cd "$WORK/fmhy" && bash scripts/doctor.sh > "$WORK/fmhy.out" 2>&1 )
{ grep -qi "hyphenated SKILL field in SUBAGENT" "$WORK/fmhy.out" \
  && grep -q "disallowed-tools" "$WORK/fmhy.out" \
  && ! grep -q "all subagent frontmatter is well-formed" "$WORK/fmhy.out"; } \
  && pass "fm: a hyphenated skill field in a subagent is warned and named" \
  || fail "fm: hyphenated subagent field not warned"
# Malformed frontmatter (no closing ---) → warn about empty metadata.
mkscaffold "$WORK/fmbad"
printf -- '---\nname: researcher\ntools: Read\n(no closing delimiter)\n' > "$WORK/fmbad/.claude/agents/researcher.md"
( cd "$WORK/fmbad" && bash scripts/doctor.sh > "$WORK/fmbad.out" 2>&1 )
grep -qi "no well-formed --- frontmatter" "$WORK/fmbad.out" \
  && pass "fm: malformed agent frontmatter (no closing ---) is warned" \
  || fail "fm: malformed agent frontmatter not warned"

echo ""
echo "F2: doctor lists active 'high-stakes-ok:' content suppressions (symmetry with the path allowlist)"
echo ""
# Control: a pristine scaffold declares no suppressions. The lib/rule-doc/guard-test mentions of the
# marker DEFINE or exercise it; if the exclusion filter or the content-regex pairing regressed, they
# would surface here as phantom suppressions on every healthy install.
mkscaffold "$WORK/hsok0"
( cd "$WORK/hsok0" && bash scripts/doctor.sh > "$WORK/hsok0.out" 2>&1 ); hs0rc=$?
grep -q "no active 'high-stakes-ok:' content suppressions" "$WORK/hsok0.out" \
  && pass "hs-ok: pristine scaffold reports no content suppressions (no phantom hits)" \
  || fail "hs-ok: pristine scaffold did not report a clean content-suppression set"
[ "$hs0rc" -eq 0 ] && pass "hs-ok: the clean report leaves doctor's exit code at 0" \
  || fail "hs-ok: clean content-suppression report wrongly made doctor exit non-zero (rc=$hs0rc)"

# Plant a REAL suppression: a line that the content scanner would flag (os.system + rm -rf), silenced
# by an inline marker with a reason. It must be TRACKED — `git grep` only sees tracked files.
mkscaffold "$WORK/hsok1"
mkdir -p "$WORK/hsok1/src"
printf 'os.system("rm -rf /tmp/build-cache")  # high-stakes-ok: regenerable local cache\n' \
  > "$WORK/hsok1/src/cleanup.py"
( cd "$WORK/hsok1" && git add src/cleanup.py >/dev/null 2>&1 )
( cd "$WORK/hsok1" && bash scripts/doctor.sh > "$WORK/hsok1.out" 2>&1 ); hs1rc=$?
{ grep -q "suppressed: src/cleanup.py:1" "$WORK/hsok1.out" \
  && grep -q "regenerable local cache" "$WORK/hsok1.out" \
  && grep -q "review every one" "$WORK/hsok1.out"; } \
  && pass "hs-ok: a planted marker is listed by path:line with its reason" \
  || fail "hs-ok: planted content suppression was not listed"
# Report-only: surfacing a suppression must never itself become a gate.
[ "$hs1rc" -eq 0 ] && pass "hs-ok: listing a suppression stays advisory (doctor still exits 0)" \
  || fail "hs-ok: a listed suppression wrongly made doctor exit non-zero (rc=$hs1rc)"

# A marker on a line the content scanner would NOT flag suppresses nothing, so it must not be listed.
mkscaffold "$WORK/hsok2"
mkdir -p "$WORK/hsok2/src"
printf 'x = 1  # high-stakes-ok: this suppresses nothing at all\n' > "$WORK/hsok2/src/inert.py"
( cd "$WORK/hsok2" && git add src/inert.py >/dev/null 2>&1 )
( cd "$WORK/hsok2" && bash scripts/doctor.sh > "$WORK/hsok2.out" 2>&1 )
grep -q "suppressed: src/inert.py" "$WORK/hsok2.out" \
  && fail "hs-ok: an inert marker (line the content gate never flags) was wrongly listed" \
  || pass "hs-ok: an inert marker on an unflagged line is not reported as a suppression"

echo ""
if [ "$FAILS" -eq 0 ]; then echo "All doctor --fix tests passed."; exit 0
else echo "$FAILS doctor test(s) FAILED."; tail -n 15 "$WORK/out" 2>/dev/null; exit 1; fi
