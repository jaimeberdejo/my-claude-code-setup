#!/usr/bin/env bash
# sync.sh — pull later jaimitos-os toolkit fixes into an already-scaffolded project from a LOCAL
# toolkit checkout, conservatively: never a blind two-way overwrite. install.sh only handles
# brand-new projects (skip-if-exists); this is the update path for one that's already scaffolded.
#
# Classifies every toolkit-shipped file into one of four tiers and applies each per its rule:
#   overwrite  toolkit-owned logic, no project values inside     → diff, confirm, copy over
#   never      project-owned (docs, CLAUDE.md, .gitignore)       → always skipped, never written
#   mixed      toolkit body + a project-customized value in it   → Phase 2 does the narrow
#                                                                   value-preserving merge; THIS
#                                                                   PHASE always routes it to the
#                                                                   manual-review bucket instead
#   unknown    unclassified (e.g. .claude/settings.json, JSON)   → always manual-review, never written
#
# Usage:
#   scripts/sync.sh --toolkit <path> [--dry-run] [--yes]
#     --toolkit <path>  REQUIRED. Local jaimitos-os checkout to sync FROM — the scaffold dir
#                       itself, e.g. --toolkit ~/projects/Claude_SETUP/jaimitos-os.
#     --dry-run         show the full per-tier plan; write NOTHING.
#     --yes             skip the per-file confirmation prompt for NON-MIXED tiers only.
#                       Mixed is never auto-applied in this phase, regardless of --yes.
#
# Exit 0 on a clean run — even if some files need manual review or a change was declined.
# Nonzero only on a real error: bad/missing args, or a --toolkit path that isn't a readable
# jaimitos-os checkout.

set -uo pipefail
cd "$(git rev-parse --show-toplevel 2>/dev/null || echo .)" || exit 1

TOOLKIT=""
DRY_RUN=0
YES=0
while [ $# -gt 0 ]; do
  case "$1" in
    --toolkit)
      [ $# -ge 2 ] || { echo "sync: --toolkit requires a path argument" >&2; exit 2; }
      TOOLKIT="$2"; shift 2 ;;
    --dry-run) DRY_RUN=1; shift ;;
    --yes)     YES=1; shift ;;
    *) echo "sync: unknown argument '$1'" >&2; exit 2 ;;
  esac
done

[ -n "$TOOLKIT" ] || { echo "sync: --toolkit <path> is required (the local jaimitos-os checkout to sync from)" >&2; exit 2; }
[ -d "$TOOLKIT" ] || { echo "sync: --toolkit path '$TOOLKIT' is not a directory" >&2; exit 2; }
[ -r "$TOOLKIT" ] || { echo "sync: --toolkit path '$TOOLKIT' is not readable" >&2; exit 2; }
if [ ! -f "$TOOLKIT/scripts/install.sh" ] && ! { [ -d "$TOOLKIT/.claude" ] && [ -d "$TOOLKIT/scripts" ]; }; then
  echo "sync: --toolkit path '$TOOLKIT' doesn't look like a jaimitos-os checkout (expected .claude/ + scripts/, or scripts/install.sh)" >&2
  exit 2
fi
TOOLKIT="$(cd "$TOOLKIT" 2>/dev/null && pwd)" || { echo "sync: could not resolve --toolkit path" >&2; exit 2; }

# --- enumeration -------------------------------------------------------------------------------
# Mirrors install.sh's find+case EXACTLY for toolkit-docs/* and *.DS_Store|*.swp. One deliberate
# difference from install.sh's DEFAULT (no --with-ci, which excludes ALL of .github/*): sync
# always considers .github/scripts/*.sh — plain toolkit-owned helper scripts, classified
# `overwrite` below like any other scripts/*.sh — but still never offers .github/workflows/*; a
# project's CI-workflow adoption is install.sh's separate, opt-in decision, not sync's to make.
toolkit_files() {
  local srcfile rel
  while IFS= read -r srcfile; do
    rel="${srcfile#"$TOOLKIT"/}"
    case "$rel" in
      toolkit-docs/*)         continue ;;
      .github/workflows/*)    continue ;;
      *.DS_Store|*.swp)       continue ;;
    esac
    printf '%s\n' "$rel"
  done < <(find "$TOOLKIT" -type f)
}

# classify_tier <rel-path> → overwrite | never | mixed | unknown. Order matters: the specific
# mixed files are matched BEFORE the broader overwrite globs (e.g. _high-stakes.sh lives under
# .claude/lib/*.sh but must classify mixed, not overwrite).
classify_tier() {
  case "$1" in
    .claude/lib/_high-stakes.sh|.claude/agents/*.md|.claude/rules/high-stakes.md)
      echo mixed ;;
    .claude/lib/*.sh|.claude/hooks/*.sh|scripts/*.sh|.claude/commands/*.md|.claude/skills/*|.github/scripts/*.sh)
      echo overwrite ;;
    docs/*|CLAUDE.md|SCAFFOLD.md|.gitignore)
      echo never ;;
    *)
      echo unknown ;;
  esac
}

# confirm <prompt>: read a yes/no answer from stdin (plain `read -r`, NOT `</dev/tty`, so tests
# can pipe answers). Empty or anything other than y/yes defaults to NO.
confirm() {
  local ans=""
  printf '%s [y/N] ' "$1"
  read -r ans
  case "$ans" in
    y|Y|yes|Yes|YES) return 0 ;;
    *) return 1 ;;
  esac
}

# should_apply <prompt>: --yes bypasses confirmation for the (non-mixed) tiers that call this.
should_apply() {
  [ "$YES" -eq 1 ] && return 0
  confirm "$1"
}

UPDATED=0
SKIPPED=0
MANUAL=0
UNCHANGED=0

echo "jaimitos-os sync"
echo "  toolkit: $TOOLKIT"
[ "$DRY_RUN" -eq 1 ] && echo "  mode: dry-run (nothing will be written)"
echo ""

# Materialize the enumerated file list into an array FIRST (a plain, non-piped loop below), so
# the main per-file loop's `read -r ans` prompts (via confirm) read from the script's OWN stdin —
# not from a process-substituted stream that a `while read < <(...)` around the whole loop would
# otherwise steal.
FILES=()
while IFS= read -r rel; do
  [ -n "$rel" ] && FILES+=("$rel")
done < <(toolkit_files)

# Bash 3.2 quirk: "${FILES[@]}" on a zero-element (but declared) array throws "unbound variable"
# under `set -u`. Guard with the count form first, which is always safe to expand.
[ "${#FILES[@]}" -gt 0 ] && for rel in "${FILES[@]}"; do
  tier="$(classify_tier "$rel")"
  toolkitfile="$TOOLKIT/$rel"

  if [ -f "$rel" ]; then
    if cmp -s "$rel" "$toolkitfile"; then
      UNCHANGED=$((UNCHANGED+1))
      [ "$DRY_RUN" -eq 1 ] && echo "  up to date: $rel"
      continue
    fi
    case "$tier" in
      overwrite)
        echo "--- diff: $rel ---"
        diff "$rel" "$toolkitfile" || true
        if [ "$DRY_RUN" -eq 1 ]; then
          echo "  (dry-run) would update: $rel"
          UPDATED=$((UPDATED+1))
        elif should_apply "Update '$rel' from the toolkit?"; then
          mkdir -p "$(dirname "$rel")"
          cp "$toolkitfile" "$rel"
          echo "  updated: $rel"
          UPDATED=$((UPDATED+1))
        else
          echo "  skipped (declined): $rel"
          SKIPPED=$((SKIPPED+1))
        fi
        ;;
      never)
        echo "  skipped (project-owned): $rel"
        SKIPPED=$((SKIPPED+1))
        ;;
      mixed)
        echo "  manual review needed (mixed file — value-preserving merge lands in a later step): $rel"
        MANUAL=$((MANUAL+1))
        ;;
      unknown)
        echo "  manual review needed (unclassified): $rel"
        MANUAL=$((MANUAL+1))
        ;;
    esac
  else
    case "$tier" in
      overwrite)
        if [ "$DRY_RUN" -eq 1 ]; then
          echo "  (dry-run) would add: $rel"
          UPDATED=$((UPDATED+1))
        elif should_apply "Add new file '$rel' from the toolkit?"; then
          mkdir -p "$(dirname "$rel")"
          cp "$toolkitfile" "$rel"
          echo "  added: $rel"
          UPDATED=$((UPDATED+1))
        else
          echo "  skipped (declined add): $rel"
          SKIPPED=$((SKIPPED+1))
        fi
        ;;
      never)
        echo "  skipped (project-owned, not present): $rel"
        SKIPPED=$((SKIPPED+1))
        ;;
      mixed)
        echo "  manual review needed (mixed file, not present — value-preserving merge lands in a later step): $rel"
        MANUAL=$((MANUAL+1))
        ;;
      unknown)
        echo "  manual review needed (unclassified, not present): $rel"
        MANUAL=$((MANUAL+1))
        ;;
    esac
  fi
done

echo ""
echo "sync summary:"
if [ "$DRY_RUN" -eq 1 ]; then
  echo "  would update/add: $UPDATED"
else
  echo "  updated/added:    $UPDATED"
fi
echo "  skipped:          $SKIPPED"
echo "  manual review:    $MANUAL"
echo "  already current:  $UNCHANGED"

# Stamp the synced-to VERSION (mirrors install.sh:139's write) after a successful non-dry run.
# VERSION lives at the repo root, next to the jaimitos-os/ scaffold dir (one level above
# --toolkit). Tolerate its absence, same as install.sh.
if [ "$DRY_RUN" -eq 0 ]; then
  TOOLKIT_VERSION="$(cat "$TOOLKIT/../VERSION" 2>/dev/null || echo '?')"
  mkdir -p .claude && printf '%s\n' "$TOOLKIT_VERSION" > .claude/.jaimitos-os-version 2>/dev/null || true
fi

exit 0
