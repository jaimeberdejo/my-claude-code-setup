#!/usr/bin/env bash
# test-control-plane-security.sh — adversarial posture of the control-plane validators
# (classify-work, check-plan-freshness, trace-requirements). The per-feature suites cover correctness;
# this one proves they are SAFE under hostile input:
#   - TERMINATE on a missing or directory path (never crash, never hang) — note this proves termination,
#     NOT that the exit code is right; each per-feature suite owns its own exit contract. Do not read
#     "exit 0" here as "fails closed": a stub that only ran `exit 0` would satisfy this check too.
#   - are strictly READ-ONLY — every validator runs INSIDE the checksum window, so this covers all of
#     them, not a sample. (v2.14.0 ran only two of five inside the window while printing a blanket pass;
#     a `touch` planted in check-plan-freshness survived it.)
#   - never EVALUATE file content (a spec/roadmap/plan line with $(...) or backticks cannot run a command).
set -uo pipefail
SCAFFOLD="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CW="$SCAFFOLD/scripts/classify-work.sh"
FRESH="$SCAFFOLD/scripts/check-plan-freshness.sh"
TRACE="$SCAFFOLD/scripts/trace-requirements.sh"
for f in "$CW" "$FRESH" "$TRACE"; do [ -f "$f" ] || { echo "test: missing $f" >&2; exit 1; }; done

FAILS=0
pass() { printf '  ✓ %s\n' "$1"; }
fail() { printf '  ✗ %s\n' "$1"; FAILS=$((FAILS+1)); }
# Runs a command; PASS if it terminated with any code in 0/1/2 (i.e. did not crash, hang, or die on a
# signal). 137/124 = killed by the watchdog = an infinite loop.
terminates() { local d="$1"; shift; "$@" >/dev/null 2>&1; local rc=$?; case "$rc" in 0|1|2) pass "$d (exit $rc)";; *) fail "$d (unexpected exit $rc)";; esac; }

WORK="$(mktemp -d 2>/dev/null || mktemp -d -t leanstack-cpsec)"
trap 'rm -rf "$WORK" 2>/dev/null' EXIT
cd "$WORK" || exit 1

echo "control-plane validator security tests"; echo ""

echo "A missing path is handled safely (terminates — inert or usage error, never a crash)"
terminates "check-plan-freshness on a missing plan"  bash "$FRESH" "$WORK/nope.md"
terminates "trace-requirements on a missing roadmap" bash "$TRACE" --roadmap "$WORK/nope.md"
terminates "classify-work with an unknown flag"      bash "$CW" --definitely-not-a-flag

echo ""
echo "A directory given where a file is expected does not crash"
mkdir -p "$WORK/adir"
terminates "check-plan-freshness on a directory"  bash "$FRESH" "$WORK/adir"
terminates "trace-requirements on a directory"    bash "$TRACE" --roadmap "$WORK/adir"

echo ""
echo "A value-taking flag with no value terminates (no shift-2 spin)"
# `shift 2` with one arg left is a POSIX no-op returning 1; without `set -e` the parse loop spins
# forever. A watchdog is mandatory here — an un-guarded hang would stall CI with no diagnostic.
watchdog() {  # watchdog <secs> <cmd...> ; echoes rc, or 137 if it had to be killed
  local secs="$1"; shift
  ( "$@" >/dev/null 2>&1 & p=$!
    ( sleep "$secs" >/dev/null 2>&1; kill -9 $p 2>/dev/null ) & w=$!
    wait $p 2>/dev/null; rc=$?; kill $w 2>/dev/null; exit $rc ) 2>/dev/null
  echo $?
}
for spec in "$FRESH:--base" "$TRACE:--roadmap" "$TRACE:--spec" "$CW:--reason" "$CW:--subject"; do
  s_bin="${spec%%:*}"; s_flag="${spec##*:}"
  rc=$(watchdog 5 bash "$s_bin" "$s_flag")
  case "$rc" in
    137|124) fail "$(basename "$s_bin") $s_flag with no value HUNG (rc=$rc)" ;;
    *)       pass "$(basename "$s_bin") $s_flag with no value terminates (exit $rc)" ;;
  esac
done

echo ""
echo "The validators are strictly read-only (no file created or modified) — ALL of them, in-window"
mkdir -p "$WORK/ro/docs" && cd "$WORK/ro" || exit 1
git init -q >/dev/null 2>&1; git config user.email t@t.t; git config user.name t
printf '# Spec\n## Requirements\n### REQ-001 — thing\nStatus: Approved\n- AC-001: it works\n' > docs/SPEC.md
printf '## Phase 1 — x\n- [ ] t\nDone when: y\nMode: loopable\nRequirements:\n- REQ-001\n' > docs/ROADMAP.md
printf '# Plan\nPlan created at: %s\nmodify `docs/SPEC.md` for REQ-001\n' abc > plan.md
git add -A >/dev/null 2>&1; git commit -qm base >/dev/null 2>&1
snapshot() { find . -path ./.git -prune -o -type f -print | sort | while read -r f; do printf '%s:%s\n' "$f" "$(cksum < "$f")"; done; }
BEFORE=$(snapshot)
# EVERY validator runs between the two snapshots. If one is added, add it here — a checksum window with
# nothing inside it always passes, which is how a read-only claim goes vacuous.
bash "$FRESH" --strict plan.md                                >/dev/null 2>&1
bash "$TRACE" --roadmap docs/ROADMAP.md --spec docs/SPEC.md   >/dev/null 2>&1
bash "$CW" --components 3 --select STANDARD --reason x        >/dev/null 2>&1
AFTER=$(snapshot)
if [ "$BEFORE" = "$AFTER" ]; then
  pass "no file created or modified by any of the 3 validators"
else
  fail "a validator wrote to the tree"
  diff <(printf '%s\n' "$BEFORE") <(printf '%s\n' "$AFTER") || true
fi
cd "$WORK" || exit 1

echo ""
echo "File content is DATA, never code — a \$(...) / backtick payload cannot execute"
mkdir -p "$WORK/inj/docs" && cd "$WORK/inj" || exit 1
git init -q >/dev/null 2>&1; git config user.email t@t.t; git config user.name t
# spec, roadmap and a plan all carrying a command-injection payload in their text
printf '# Spec\n## Requirements\n### REQ-001 — $(touch pwned-spec)\nStatus: Approved\n- AC-001: `touch pwned-ac`\n' > docs/SPEC.md
printf '## Phase 1 — x\n- [ ] t\nDone when: y\nMode: loopable\nRequirements:\n- REQ-001\n' > docs/ROADMAP.md
printf '# Plan\nPlan created at: %s\nmodify `docs/SPEC.md` for REQ-001 $(touch pwned-plan)\n' "$(git rev-parse --short HEAD 2>/dev/null || echo abc)" > docs/plans-p.md
git add -A >/dev/null 2>&1; git commit -qm base >/dev/null 2>&1
bash "$TRACE" --roadmap docs/ROADMAP.md --spec docs/SPEC.md >/dev/null 2>&1
bash "$FRESH" docs/plans-p.md >/dev/null 2>&1
bash "$CW" --subject '$(touch pwned-subject)' --reason '`touch pwned-reason`' >/dev/null 2>&1
# Canaries are checked in cwd AND in the parent: a payload that fired with a different cwd would
# otherwise land outside the search and read as clean.
if ls pwned-* ../pwned-* >/dev/null 2>&1; then
  fail "an injection payload EXECUTED: $(ls pwned-* ../pwned-* 2>/dev/null | tr '\n' ' ')"
else
  pass "no injection payload executed (content stays data)"
fi
cd "$WORK" || exit 1

echo ""
if [ "$FAILS" -eq 0 ]; then echo "All control-plane security checks passed."; exit 0
else echo "$FAILS control-plane security check(s) FAILED."; exit 1; fi
