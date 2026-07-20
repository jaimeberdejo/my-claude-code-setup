#!/usr/bin/env bash
# close-milestone.sh — archive a COMPLETED roadmap and scaffold the next one, but REFUSE to
# close while any work or unresolved finding remains. This is the deterministic replacement for
# the old milestone prose ("ask whether to proceed anyway") — there is NO bypass flag by design.
#
# Refuses (exit 1) when:
#   - docs/ROADMAP.md has any open "- [ ]" item, OR
#   - NEXT_FINDINGS.md exists (an unresolved evaluator finding), OR
#   - docs/ROADMAP.md has no phases at all (nothing to close — also makes re-runs safe).
# On success: git mv docs/ROADMAP.md -> docs/archive/ROADMAP-<label>.md (label = --name arg,
# else a VERSION file, else the latest git tag, else the UTC date), write a fresh empty
# docs/ROADMAP.md, and reset the docs/STATE.md auto-block to point at the next scope.
#
# Usage: bash scripts/close-milestone.sh [--name <label>]
set -uo pipefail
cd "$(git rev-parse --show-toplevel 2>/dev/null || echo .)" || exit 1
ROADMAP="docs/ROADMAP.md"
STATE="docs/STATE.md"

NAME=""; NAME_GIVEN=0
# need_val: a flag that takes a value must have one — a bare `--name` at end of args used to run
# `shift 2` on a single positional, a no-op under `set -uo pipefail` (no set -e) that left $1 == --name
# and spun the while-loop forever. Guard it (same fix trace-requirements.sh carries).
need_val() { [ "$2" -ge 2 ] || { echo "close-milestone: $1 requires a value" >&2; exit 2; }; }
while [ $# -gt 0 ]; do
  case "$1" in
    --name) need_val "$1" "$#"; NAME="$2"; NAME_GIVEN=1; shift 2 ;;
    -h|--help)
      echo "usage: close-milestone.sh [--name <label>]"
      echo "  Archive a COMPLETED roadmap and scaffold the next. Refuses while any open item or an"
      echo "  unresolved NEXT_FINDINGS.md remains — no bypass by design. --name must be a safe archive"
      echo "  label (no path separator, no '..', no control chars); unknown args exit 2."
      exit 0 ;;
    *) echo "close-milestone: unknown argument '$1'" >&2; exit 2 ;;
  esac
done

# Validate an explicit --name: it becomes the archive filename docs/archive/ROADMAP-<name>.md, so a path
# separator, a `..` traversal, control chars, or an all-whitespace value must be refused (exit 2) rather
# than flow into a path. A DERIVED label (VERSION/tag/date, below) is already safe.
if [ "$NAME_GIVEN" = 1 ]; then
  NAME=$(printf '%s' "$NAME" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')   # trim
  [ -n "$NAME" ] || { echo "close-milestone: --name is empty after trimming whitespace — give a real label" >&2; exit 2; }
  case "$NAME" in
    */*|*\\*) echo "close-milestone: --name must not contain a path separator: '$NAME'" >&2; exit 2 ;;
    *..*)     echo "close-milestone: --name must not contain '..': '$NAME'" >&2; exit 2 ;;
    *$'\n'*)  echo "close-milestone: --name must not contain a newline" >&2; exit 2 ;;
  esac
  # A grep for [[:cntrl:]] is LINE-oriented and never sees an embedded newline (handled by the case
  # above); this catches the remaining control chars (tab, etc.).
  printf '%s' "$NAME" | LC_ALL=C grep -q '[[:cntrl:]]' && { echo "close-milestone: --name must not contain control characters" >&2; exit 2; }
fi

refuse() { echo "close-milestone: REFUSED — $1" >&2; exit 1; }

# Shared roadmap parser — the SAME task definition, first-open-heading and Mode classification that
# tick.sh uses, via ONE library instead of a hand-copied awk block. Fail-closed, like tick.sh and
# autopilot.sh: without it we cannot tell an open phase from a closed one, and "I couldn't read the
# roadmap" must never degrade into "safe to close".
[ -f .claude/lib/_roadmap.sh ] && . .claude/lib/_roadmap.sh 2>/dev/null || true
command -v roadmap_open_total >/dev/null 2>&1 && command -v roadmap_first_open_heading >/dev/null 2>&1 \
  || refuse ".claude/lib/_roadmap.sh missing/unloadable — cannot read the roadmap (fail-closed)."

[ -f "$ROADMAP" ] || refuse "no $ROADMAP to close."
# $ROADMAP_TASK_RE / $ROADMAP_OPEN_RE are anchored to real list items (start of line, optional
# leading whitespace). A plain substring match also hits the roadmap skill's own legend line
# ("> `- [ ]` = todo, `- [x]` = done. ..."), which is permanently present at the top of every
# roadmap it generates and would otherwise ALWAYS false-positive as "open items remain."
grep -qE "$ROADMAP_TASK_RE" "$ROADMAP" 2>/dev/null || refuse "no phases in $ROADMAP — nothing to close."
# Open items remain → classify the FIRST open phase so the refusal is actionable, not a flat "open
# items remain". Three cases: (a) a supervised phase awaiting explicit human approval (name it +
# point at tick.sh --supervised-approved — the new v2.4.0 path so a supervised phase is no longer a
# dead end), (b) an unresolved evaluator finding (NEXT_FINDINGS.md) gating it, (c) plain unfinished
# work. The heading + Mode classification come from the shared _roadmap.sh parser.
if [ "$(roadmap_open_total "$ROADMAP")" -gt 0 ]; then
  first_open=$(roadmap_first_open_heading "$ROADMAP" 2>/dev/null || true)
  first_mode=$(roadmap_phase_mode "$ROADMAP" "$first_open" 2>/dev/null || true)
  case "$first_mode" in
    supervised)
      echo "close-milestone: the first open phase is SUPERVISED and awaiting human approval:" >&2
      echo "close-milestone:   ${first_open#\#\# }" >&2
      echo "close-milestone:   approve + tick it with:" >&2
      echo "close-milestone:     bash scripts/tick.sh --supervised-approved \"$first_open\" --note \"<why it's safe>\"" >&2
      refuse "a supervised phase is unticked — approve it (command above), then close." ;;
    *)
      if [ -f NEXT_FINDINGS.md ]; then
        echo "close-milestone: an unresolved evaluator finding (NEXT_FINDINGS.md) is blocking the first open phase:" >&2
        echo "close-milestone:   ${first_open#\#\# }" >&2
        refuse "resolve NEXT_FINDINGS.md and finish the open phase, then close."
      else
        echo "close-milestone: the first open phase still has unfinished work:" >&2
        echo "close-milestone:   ${first_open#\#\# }" >&2
        refuse "open items remain in $ROADMAP — finish or remove them first."
      fi ;;
  esac
fi
[ -f NEXT_FINDINGS.md ] && refuse "NEXT_FINDINGS.md exists (an unresolved evaluator finding) — resolve it first."

# Non-fatal notice: surface open '## Ownership gaps' entries in docs/STATE.md (skipped/incomplete
# teach-backs are recorded there) so they don't silently accumulate across milestones. This never
# blocks the close — plain echo to stderr, no exit — and section-absent is treated exactly like
# section-empty: the scaffold ships with no '## Ownership gaps' heading by default.
if [ -f "$STATE" ] && grep -qx '## Ownership gaps' "$STATE" 2>/dev/null; then
  open_gaps=$(awk '
    $0=="## Ownership gaps" { inphase=1; next }
    /^## / && inphase { inphase=0 }
    inphase && /^[[:space:]]*-[[:space:]]*[^[:space:]]/ { c++ }
    END { print c+0 }
  ' "$STATE")
  [ "${open_gaps:-0}" -gt 0 ] && echo "close-milestone: NOTE — docs/STATE.md has open '## Ownership gaps' entries; carrying them into the next milestone unresolved." >&2
fi

# Non-fatal notice: architectural drift across the milestone.
# Per-PHASE review structurally cannot see this. The evaluator grades a phase diff, so ten
# individually-clean phases can still compose into a pass-through layer, and nobody is looking at
# the whole. The milestone boundary is the only place that view exists — so surface it here.
# NEVER blocks the close (same contract as the Ownership-gaps notice above): a stale map is a
# prompt to run `mapme`, not a reason to trap a finished milestone.
#
# "This milestone" = since the previous close (the commit that created the newest
# docs/archive/ROADMAP-*.md). Scoping it that way means the notice fires when a WHOLE milestone was
# built without ever refreshing the map — not on every close, which would be noise nobody reads.
# Fail-open throughout: a shallow clone or an odd history yields no notice, never a false alarm.
ARCH="docs/ARCHITECTURE.md"
ms_start=$(git log -1 --format=%H -- docs/archive 2>/dev/null || true)
RANGE="${ms_start:+$ms_start..}HEAD"
# Code = anything outside docs/. A docs-only milestone has nothing to re-map.
code_commits=$(git log --oneline "$RANGE" -- . ':(exclude)docs' 2>/dev/null | wc -l | tr -d ' ')
if [ "${code_commits:-0}" -gt 0 ]; then
  if [ ! -f "$ARCH" ]; then
    echo "close-milestone: NOTE — no $ARCH, but $code_commits code commit(s) landed this milestone. Run the \`mapme\` skill (it also flags architectural friction: shallow modules, pass-through layers, leaky seams)." >&2
  else
    arch_touched=$(git log --oneline "$RANGE" -- "$ARCH" 2>/dev/null | wc -l | tr -d ' ')
    [ "${arch_touched:-0}" -eq 0 ] && \
      echo "close-milestone: NOTE — $ARCH was not refreshed during this milestone ($code_commits code commit(s) since the last close). Run the \`mapme\` skill; carry any Strong friction findings into the next roadmap." >&2
  fi
fi

# Pick the archive label.
if [ -z "$NAME" ]; then
  if [ -f VERSION ]; then
    NAME=$(tr -d '[:space:]' < VERSION)
  elif NAME=$(git describe --tags --abbrev=0 2>/dev/null) && [ -n "$NAME" ]; then
    :
  fi
fi
[ -z "$NAME" ] && NAME=$(date -u +%Y%m%d 2>/dev/null || echo milestone)

mkdir -p docs/archive || refuse "could not create docs/archive/."
DEST="docs/archive/ROADMAP-$NAME.md"
# Never clobber existing history — suffix if a same-named archive already exists.
[ -e "$DEST" ] && DEST="docs/archive/ROADMAP-$NAME-$(date -u +%H%M%S 2>/dev/null || echo dup).md"

# --- transactional close (v2.17 OBJ-1706) --------------------------------------------------------
# Archive-move + roadmap-recreate + STATE-reset were three separate LIVE in-place mutations with no
# rollback contract: a failure after the move left the roadmap archived with no fresh roadmap, and a
# failure in the STATE rewrite left ROADMAP already replaced. Now the fresh roadmap + reset STATE are
# built in temp files and validated FIRST, the originals are backed up byte-for-byte, and any failure
# during apply restores ROADMAP + STATE exactly and removes the half-written archive. (Plain `mv` — git
# detects the rename on the human's `git add -A`; this keeps rollback a simple file restore.)
R_BAK=$(mktemp 2>/dev/null || echo "$ROADMAP.close-bak.$$"); cp "$ROADMAP" "$R_BAK" || refuse "could not back up $ROADMAP (nothing changed)."
S_BAK=""; if [ -f "$STATE" ]; then S_BAK=$(mktemp 2>/dev/null || echo "$STATE.close-bak.$$"); cp "$STATE" "$S_BAK" || refuse "could not back up $STATE (nothing changed)."; fi
NEW_R=$(mktemp 2>/dev/null || echo "$ROADMAP.close-new.$$"); NEW_S=""

cm_cleanup()  { rm -f "$R_BAK" "$NEW_R" 2>/dev/null; [ -n "$S_BAK" ] && rm -f "$S_BAK" 2>/dev/null; [ -n "$NEW_S" ] && rm -f "$NEW_S" 2>/dev/null; return 0; }
cm_rollback() {
  cp "$R_BAK" "$ROADMAP" 2>/dev/null || true
  [ -n "$S_BAK" ] && { cp "$S_BAK" "$STATE" 2>/dev/null || true; }
  [ -e "$DEST" ] && rm -f "$DEST" 2>/dev/null || true
  cm_cleanup
  echo "close-milestone: ⛔ $1 — rolled back (ROADMAP + STATE restored byte-for-byte, no archive created)." >&2
  exit 1
}

# Prepare the fresh roadmap into a temp.
cat > "$NEW_R" <<'MD'
# Roadmap

<!--
Author phases here (use the `roadmap` skill, or the `milestone` skill Mode A). Each phase is:
a "## Phase N — <goal>" heading, one unchecked checkbox line per task, a "Done when:" line with
an observable/machine-checkable condition, and a "Mode: loopable | supervised" line.
See docs/archive/ for the previous milestone's phases as examples.
-->
MD
[ -s "$NEW_R" ] || cm_rollback "fresh roadmap generation produced empty output"

# Prepare the reset STATE into a temp (only when it carries the auto-block).
if [ -n "$S_BAK" ] && grep -qF '<!-- lean:auto:begin -->' "$STATE"; then
  NEW_S=$(mktemp 2>/dev/null || echo "$STATE.close-new.$$")
  awk -v d="$NAME" '
    /<!-- lean:auto:begin -->/ {
      print
      print "_Auto-generated by scripts/tick.sh on each roadmap tick — do not edit between these markers._"
      print ""
      print "- Milestone " d " closed. Author the next scope, then plan its first phase."
      skip=1; next
    }
    /<!-- lean:auto:end -->/ { print; skip=0; next }
    !skip { print }
  ' "$STATE" > "$NEW_S" || cm_rollback "STATE regeneration failed"
  [ -s "$NEW_S" ] || cm_rollback "STATE regeneration produced empty output"
fi

# Apply: archive-move → recreate → reset. Any failure restores both files and removes the archive.
mv "$ROADMAP" "$DEST"      || cm_rollback "could not archive $ROADMAP → $DEST"
cp "$NEW_R" "$ROADMAP"     || cm_rollback "could not write the fresh $ROADMAP"
if [ -n "$NEW_S" ]; then cp "$NEW_S" "$STATE" || cm_rollback "could not write the reset $STATE"; fi
{ [ -f "$DEST" ] && [ -f "$ROADMAP" ]; } || cm_rollback "post-close verification failed (archive or fresh roadmap missing)"
cm_cleanup

echo "close-milestone: ✓ archived $ROADMAP → $DEST; fresh roadmap created. Author the next scope (roadmap skill)."
