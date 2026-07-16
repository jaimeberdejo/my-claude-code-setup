#!/usr/bin/env bash
# test-control-plane-security.sh — adversarial posture of the v2.14.0 control-plane validators
# (classify-work, lint-enforcement, check-plan-freshness, check-uat, trace-requirements). The
# per-feature suites cover correctness; this one proves they are SAFE under hostile input:
#   - fail closed / stay inert on a missing or directory path (never crash, never hang, never fail open),
#   - are strictly READ-ONLY (they never create or modify a file),
#   - never EVALUATE file content (a ledger/plan line with $(...) or backticks cannot run a command).
set -uo pipefail
SCAFFOLD="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CW="$SCAFFOLD/scripts/classify-work.sh"
ENF="$SCAFFOLD/scripts/lint-enforcement.sh"
FRESH="$SCAFFOLD/scripts/check-plan-freshness.sh"
UAT="$SCAFFOLD/scripts/check-uat.sh"
TRACE="$SCAFFOLD/scripts/trace-requirements.sh"
for f in "$CW" "$ENF" "$FRESH" "$UAT" "$TRACE"; do [ -f "$f" ] || { echo "test: missing $f" >&2; exit 1; }; done

FAILS=0
pass() { printf '  ✓ %s\n' "$1"; }
fail() { printf '  ✗ %s\n' "$1"; FAILS=$((FAILS+1)); }
# runs a command, captures its exit; PASS if it terminated with any code in 0/1/2 (i.e. did not crash/hang).
terminates() { local d="$1"; shift; "$@" >/dev/null 2>&1; local rc=$?; case "$rc" in 0|1|2) pass "$d (exit $rc)";; *) fail "$d (unexpected exit $rc)";; esac; }

WORK="$(mktemp -d 2>/dev/null || mktemp -d -t leanstack-cpsec)"
trap 'rm -rf "$WORK" 2>/dev/null' EXIT
cd "$WORK" || exit 1

echo "control-plane validator security tests"; echo ""

echo "A missing path is handled safely (inert or usage error — never a crash)"
terminates "lint-enforcement on a missing file"      bash "$ENF" "$WORK/nope.md"
terminates "check-uat on a missing file"             bash "$UAT" "$WORK/nope.md"
terminates "check-plan-freshness on a missing plan"  bash "$FRESH" "$WORK/nope.md"
terminates "trace-requirements on a missing roadmap" bash "$TRACE" --roadmap "$WORK/nope.md"
terminates "classify-work with an unknown flag"      bash "$CW" --definitely-not-a-flag

echo ""
echo "A directory given where a file is expected does not crash"
mkdir -p "$WORK/adir"
terminates "lint-enforcement on a directory"  bash "$ENF" "$WORK/adir"
terminates "check-uat on a directory"         bash "$UAT" "$WORK/adir"

echo ""
echo "The validators are strictly read-only (no file is created or modified)"
mkdir -p "$WORK/ro/docs"; cd "$WORK/ro" || exit 1
printf '# Enforcement Ledger\nBaseline commit: x\n| ID | Claim | Source | Enforcement | Strength | Status | Trigger |\n|---|---|---|---|---|---|---|\n| ENF-001 | c | s | e | ADVISORY | ACTIVE | t |\n' > docs/ENFORCEMENT.md
printf '# UAT\nBaseline commit: x\n- UAT-001\n  Status: PASSED\n  Blocking: NO\n' > docs/UAT.md
BEFORE=$(find . -type f | sort | while read -r f; do printf '%s:%s\n' "$f" "$(cksum "$f")"; done)
bash "$ENF" docs/ENFORCEMENT.md >/dev/null 2>&1
bash "$UAT" docs/UAT.md >/dev/null 2>&1
AFTER=$(find . -type f | sort | while read -r f; do printf '%s:%s\n' "$f" "$(cksum "$f")"; done)
[ "$BEFORE" = "$AFTER" ] && pass "no file created or modified by the validators" || { fail "a validator wrote to the tree"; diff <(printf '%s' "$BEFORE") <(printf '%s' "$AFTER"); }
cd "$WORK" || exit 1

echo ""
echo "File content is DATA, never code — a \$(...) / backtick payload cannot execute"
mkdir -p "$WORK/inj/docs"; cd "$WORK/inj" || exit 1
git init -q >/dev/null 2>&1; git config user.email t@t.t; git config user.name t
# ledger, uat, spec, roadmap, and a plan all carrying a command-injection payload in their text
printf '# Ledger\nBaseline commit: x\n| ID | Claim | Source | Enforcement | Strength | Status | Trigger |\n|---|---|---|---|---|---|---|\n| ENF-001 | $(touch pwned-enf) | `touch pwned-enf2` | e | ADVISORY | ACTIVE | t |\n' > docs/ENFORCEMENT.md
printf '# UAT\nBaseline commit: x\n- UAT-001\n  Status: PASSED\n  Expected: $(touch pwned-uat)\n  Blocking: NO\n' > docs/UAT.md
printf '# Spec\n## Requirements\n### REQ-001 — $(touch pwned-spec)\nStatus: Approved\n- AC-001: `touch pwned-ac`\n' > docs/SPEC.md
printf '## Phase 1 — x\n- [ ] t\nDone when: y\nMode: loopable\nRequirements:\n- REQ-001\n' > docs/ROADMAP.md
printf '# Plan\nPlan created at: %s\nmodify `docs/SPEC.md` for REQ-001 $(touch pwned-plan)\n' "$(git rev-parse --short HEAD 2>/dev/null || echo abc)" > docs/plans-p.md
git add -A >/dev/null 2>&1; git commit -qm base >/dev/null 2>&1
bash "$ENF" docs/ENFORCEMENT.md >/dev/null 2>&1
bash "$UAT" docs/UAT.md >/dev/null 2>&1
bash "$TRACE" --roadmap docs/ROADMAP.md --spec docs/SPEC.md >/dev/null 2>&1
bash "$FRESH" docs/plans-p.md >/dev/null 2>&1
if ls pwned-* >/dev/null 2>&1; then fail "an injection payload EXECUTED: $(ls pwned-* 2>/dev/null | tr '\n' ' ')"; else pass "no injection payload executed (content stays data)"; fi
cd "$WORK" || exit 1

echo ""
if [ "$FAILS" -eq 0 ]; then echo "All control-plane security checks passed."; exit 0
else echo "$FAILS control-plane security check(s) FAILED."; exit 1; fi
