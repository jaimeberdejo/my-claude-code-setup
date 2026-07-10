#!/usr/bin/env bash
# start-phase.sh — open a phase with a TRUSTED, tamper-EVIDENT start anchor (finding H1).
#
# The problem it solves: in manual mode tick.sh used to read the phase scan floor from the
# gitignored, builder-writable .claude/.phase-base. A builder could SILENTLY advance that file to a
# later ancestor, narrowing the secret/high-stakes scan window and hiding earlier in-phase commits —
# invisibly, because an ignored file leaves no trace in git. This script moves the floor into a
# TRACKED, committed anchor (.claude/.phase-anchor): now the floor is part of git history, so advancing
# it is a visible commit to a tracked file, not a silent rewrite. tick.sh derives the manual base from
# this anchor and prints the exact judged range for the human to vouch for.
#
# HONEST scope (do not overstate): this is NOT builder-PROOF. A bypass-mode builder that can run
# arbitrary `git` can still construct commits and rewrite the anchor; no purely-local, Git-native,
# crypto-free mechanism can prevent that — that is exactly why HEADLESS mode derives its base in the
# orchestrator's OWN shell (scripts/autopilot.sh, outside the builder) and is the trust-equivalent
# path. What this buys for MANUAL mode is: the floor is authored here (clean tree required, before the
# builder runs), it lives in tracked content, and any later change to it is a visible commit inside
# the very range tick.sh judges — tamper-EVIDENT and human-reviewed, not silent.
#
# What it does:
#   1. Requires a clean working tree (so the anchor is authored from a known state).
#   2. Resolves the first open roadmap phase (or verifies the heading you pass IS that phase).
#   3. Records .claude/.phase-anchor { heading, base=<HEAD>, test_command, anchored_at } and COMMITS
#      it as `chore(phase-start): <heading>` — the anchor commit's parent IS the recorded base.
#   4. Prints the anchor commit and the exact BASE..HEAD range the gate will judge.
# Idempotent: if the current open phase is ALREADY anchored at HEAD, it no-ops with a clear message
# rather than stacking a second anchor.
#
# Usage: bash scripts/start-phase.sh ["## Phase N — heading"]
set -uo pipefail
cd "$(git rev-parse --show-toplevel 2>/dev/null || echo .)" || exit 1
ROADMAP="docs/ROADMAP.md"
ANCHOR=".claude/.phase-anchor"

case "${1:-}" in
  -h|--help)
    echo "usage: start-phase.sh [\"## Phase N — heading\"]"
    echo "  Anchors the phase start in a TRACKED, committed .claude/.phase-anchor (tamper-evident base"
    echo "  for tick.sh's manual scan window). Requires a clean tree. Idempotent per open phase."
    exit 0 ;;
esac

fail() { echo "start-phase: ⛔ $1" >&2; exit 1; }

command -v git >/dev/null 2>&1 || fail "git is required."
[ -f "$ROADMAP" ] || fail "no $ROADMAP — create a roadmap first (run the 'roadmap' skill)."

# Shared, fail-closed roadmap parser (same one tick.sh / autopilot.sh use).
[ -f .claude/lib/_roadmap.sh ] && . .claude/lib/_roadmap.sh 2>/dev/null || true
command -v roadmap_first_open_heading >/dev/null 2>&1 || fail ".claude/lib/_roadmap.sh unavailable (fail-closed)."
[ -f .claude/lib/_test-cmd.sh ] && . .claude/lib/_test-cmd.sh 2>/dev/null || true

# Clean tree (excludes gitignored runtime artifacts, exactly like tick.sh's gate). The anchor must be
# authored from a known, committed state — a dirty tree means we can't say what the phase starts from.
DIRTY=$(git status --porcelain 2>/dev/null)
if [ -n "$DIRTY" ]; then
  echo "start-phase: ⛔ working tree not clean — commit or stash first so the phase start is well-defined:" >&2
  printf '%s\n' "$DIRTY" | sed 's/^/    /' >&2
  exit 1
fi

# Resolve the phase. With no arg, use the first open phase; with an arg, require it to BE that phase
# (you cannot anchor a phase that isn't next — that would let a start skip over open work).
FIRST_OPEN=$(roadmap_first_open_heading "$ROADMAP"); fo_rc=$?
[ "$fo_rc" = 0 ] || fail "could not resolve a single first-open phase (rc=$fo_rc; none open, or a duplicate/ambiguous heading)."
HEADING="${1:-$FIRST_OPEN}"
if [ "$HEADING" != "$FIRST_OPEN" ]; then
  fail "the first open phase is '$FIRST_OPEN', not '$HEADING' — anchor the first open phase (omit the argument to use it)."
fi

HEAD=$(git rev-parse HEAD 2>/dev/null) || fail "no HEAD (make an initial commit first)."

# Idempotency: if the anchor already names THIS heading and its committed base is HEAD's ancestor with
# no open phase having ticked since, treat as already-started. Concretely: the anchor file exists,
# tracked, names this heading, and the commit that last touched it is reachable and its recorded base
# is a strict ancestor of HEAD → re-running is a no-op.
if [ -f "$ANCHOR" ] && git ls-files --error-unmatch "$ANCHOR" >/dev/null 2>&1; then
  A_HEADING=$(grep -E '^heading=' "$ANCHOR" | head -1 | cut -d= -f2-)
  A_BASE=$(grep -E '^base=' "$ANCHOR" | head -1 | cut -d= -f2-)
  if [ "$A_HEADING" = "$HEADING" ] && [ -n "$A_BASE" ] \
     && git merge-base --is-ancestor "$A_BASE" HEAD 2>/dev/null; then
    echo "start-phase: '$HEADING' is already anchored (base ${A_BASE:0:12}). No new anchor created."
    echo "start-phase:   judged range at tick: ${A_BASE:0:12}..HEAD"
    exit 0
  fi
fi

# Author the anchor from the CURRENT clean HEAD (its parent IS the recorded base).
TEST_CMD=""
if command -v authorized_test_cmd >/dev/null 2>&1; then TEST_CMD=$(authorized_test_cmd 2>/dev/null || true); fi
STAMP=$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || echo unknown)
mkdir -p .claude
{
  echo "# .claude/.phase-anchor — TRUSTED phase-start anchor (tracked; authored by scripts/start-phase.sh)."
  echo "# tick.sh derives the manual scan floor from 'base=' below. Do NOT hand-edit mid-phase — every"
  echo "# change is a visible commit in the judged range (that is the point: tamper-evident, not silent)."
  echo "heading=$HEADING"
  echo "base=$HEAD"
  echo "test_command=$TEST_CMD"
  echo "anchored_at=$STAMP"
} > "$ANCHOR"

git add "$ANCHOR" || fail "could not stage $ANCHOR."
git commit -q -m "chore(phase-start): $HEADING" || fail "could not commit the phase anchor."
ANCHOR_SHA=$(git rev-parse HEAD)

echo "start-phase: ✓ anchored '$HEADING'"
echo "start-phase:   anchor commit: ${ANCHOR_SHA:0:12}  (base = ${HEAD:0:12})"
echo "start-phase:   the gate will judge the range:  ${HEAD:0:12}..HEAD"
echo "start-phase:   build the phase now; /wrap (scripts/tick.sh) will scan exactly that range."
exit 0
