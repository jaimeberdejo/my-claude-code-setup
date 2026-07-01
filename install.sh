#!/usr/bin/env bash
# install.sh — drop the lean-stack scaffold + skills into a target repo.
# Deterministic file copy ONLY. The intelligent part (filling CLAUDE.md placeholders,
# pointing high-stakes.md paths at your real dirs) is the `setup-lean-stack` skill's job —
# or do it by hand. This script never asks a model to do anything.
#
# Usage:
#   bash install.sh [TARGET_DIR] [--force] [--global-skills] [--with-ci]
#     TARGET_DIR       where to install (default: current directory)
#     --force          overwrite existing scaffold files (default: skip files that exist)
#     --global-skills  also install the skills into ~/.claude/skills (in addition to project)
#     --with-ci        also copy the CI workflow (.github/workflows/lean-stack-ci.yml).
#                      Off by default — most projects already have their own CI.
#
# Tool meta-docs live under lean-stack/toolkit-docs/ and are NEVER copied into a target —
# they document the toolkit, not your project. Exclusion is by DIRECTORY (not a hardcoded
# filename list), so a new toolkit doc can't accidentally start shipping. The scaffold's own
# note ships as SCAFFOLD.md (so it can't become/clobber your README).
#
# Idempotent: re-running is safe. Without --force it skips any file that already exists,
# so it never clobbers a CLAUDE.md you've customized.

set -uo pipefail

# Resolve this script's directory (the repo root) so it works from anywhere.
SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCAFFOLD="$SRC/lean-stack"
SKILLS_SRC="$SRC/skills"

TARGET="."
FORCE=0
GLOBAL_SKILLS=0
WITH_CI=0
for arg in "$@"; do
  case "$arg" in
    --force)         FORCE=1 ;;
    --global-skills) GLOBAL_SKILLS=1 ;;
    --with-ci)       WITH_CI=1 ;;
    -*)              echo "install: unknown flag '$arg'" >&2; exit 2 ;;
    *)               TARGET="$arg" ;;
  esac
done

[ -d "$SCAFFOLD" ]   || { echo "install: can't find lean-stack/ next to this script ($SCAFFOLD)" >&2; exit 1; }
[ -d "$SKILLS_SRC" ] || { echo "install: can't find skills/ next to this script ($SKILLS_SRC)" >&2; exit 1; }
mkdir -p "$TARGET" || { echo "install: can't create target '$TARGET'" >&2; exit 1; }
TARGET="$(cd "$TARGET" && pwd)" || { echo "install: can't enter target '$TARGET'" >&2; exit 1; }

VERSION="$(cat "$SRC/VERSION" 2>/dev/null || echo '?')"
echo "install: lean-stack v$VERSION  →  $TARGET  (force=$FORCE)"

COPIED=0; SKIPPED=0; FAILED=0

# Copy one file, honoring --force and creating parent dirs. Skips (and reports) if it
# exists and --force is off. A failed copy is reported and counted — never silently
# treated as success (a partial install must not look clean).
copy_file() {
  local rel="$1" srcfile="$2" dest="$TARGET/$1"
  if [ -e "$dest" ] && [ "$FORCE" -eq 0 ]; then
    echo "  skip (exists): $rel"; SKIPPED=$((SKIPPED+1)); return
  fi
  mkdir -p "$(dirname "$dest")"
  if cp "$srcfile" "$dest"; then
    COPIED=$((COPIED+1))
  else
    echo "  ✗ FAILED to copy: $rel" >&2; FAILED=$((FAILED+1))
  fi
}

# 1. Scaffold files (everything under lean-stack/, including dotfiles like .gitignore).
#    EXCLUSIONS (by DIRECTORY, so they can't silently drift):
#      - toolkit-docs/*  : tool meta-docs (GUIDE/LOOP-ENGINEERING) — never shipped
#      - .github/*       : CI workflow is opt-in (--with-ci)
#      - editor/OS cruft : .DS_Store / *.swp never copied into a target
while IFS= read -r srcfile; do
  rel="${srcfile#"$SCAFFOLD"/}"
  case "$rel" in
    toolkit-docs/*)
      continue ;;                                  # toolkit docs — don't pollute the target
    .github/*)
      [ "$WITH_CI" -eq 1 ] || continue ;;          # CI is opt-in
    *.DS_Store|*.swp)
      continue ;;                                  # editor/OS cruft
  esac
  copy_file "$rel" "$srcfile"
done < <(find "$SCAFFOLD" -type f)

# 2. Skills → <target>/.claude/skills/<skill>/
#    setup-lean-stack is the installer/meta skill — useless (and slightly misleading) once a
#    project is set up, so it is NOT copied per-project; it installs only via --global-skills.
while IFS= read -r srcfile; do
  skillrel="${srcfile#"$SKILLS_SRC"/}"
  case "$skillrel" in setup-lean-stack/*) continue ;; esac
  copy_file ".claude/skills/$skillrel" "$srcfile"
done < <(find "$SKILLS_SRC" -mindepth 2 -type f)   # mindepth 2 = inside skill dirs; skips top-level README/OWNERSHIP

# 3. Optional global skills install.
if [ "$GLOBAL_SKILLS" -eq 1 ]; then
  GDIR="$HOME/.claude/skills"
  echo "install: also copying skills → $GDIR"
  while IFS= read -r d; do
    name="$(basename "$d")"
    if [ -e "$GDIR/$name" ] && [ "$FORCE" -eq 0 ]; then echo "  skip global (exists): $name"; continue; fi
    mkdir -p "$GDIR" && cp -r "$d" "$GDIR/"
  done < <(find "$SKILLS_SRC" -mindepth 1 -maxdepth 1 -type d)
fi

# 3b. Merge scaffold .gitignore rules into a pre-existing target .gitignore.
# The generic copy loop skips files that already exist, so a repo that already
# has a .gitignore would never receive our control/secret ignore rules. Append
# any missing lines under a marked, idempotent block.
SCAFFOLD_GI="$SCAFFOLD/.gitignore"
TARGET_GI="$TARGET/.gitignore"
GI_MARK="# --- lean-stack control/secret ignores ---"
if [ -f "$SCAFFOLD_GI" ] && [ -f "$TARGET_GI" ]; then
  # Only act if our block isn't already present (idempotent on re-run).
  if ! grep -qF "$GI_MARK" "$TARGET_GI"; then
    MISSING=""
    while IFS= read -r line; do
      # Skip blank lines and comments from the scaffold.
      case "$line" in ""|\#*) continue ;; esac
      # Append only rules the target doesn't already have (exact-line match).
      grep -qxF "$line" "$TARGET_GI" || MISSING="$MISSING$line"$'\n'
    done < "$SCAFFOLD_GI"
    if [ -n "$MISSING" ]; then
      {
        printf '\n%s\n' "$GI_MARK"
        printf '%s' "$MISSING"
      } >> "$TARGET_GI"
      echo "  merged missing .gitignore rules into existing $TARGET_GI"
    fi
  fi
fi

# 3c. Stamp the installed version so `doctor.sh` can report what's installed.
mkdir -p "$TARGET/.claude" && printf '%s\n' "$VERSION" > "$TARGET/.claude/.lean-stack-version" 2>/dev/null || true

# 3d. Fingerprint the shipped HIGH_STAKES_RE so doctor.sh can warn when the ENFORCED gate
# was never pointed at the project's real paths (editing only the advisory rule is the
# common mistake that silently disables enforcement).
if [ -f "$TARGET/.claude/lib/_high-stakes.sh" ]; then
  grep -E '^HIGH_STAKES_RE=' "$TARGET/.claude/lib/_high-stakes.sh" > "$TARGET/.claude/.high-stakes-default" 2>/dev/null || true
fi

# 4. Make hooks/scripts executable.
chmod +x "$TARGET"/.claude/hooks/*.sh "$TARGET"/scripts/*.sh 2>/dev/null || true

echo ""
echo "install: copied $COPIED file(s), skipped $SKIPPED, failed $FAILED."
[ "$WITH_CI" -eq 0 ] && echo "install: CI workflow NOT copied (re-run with --with-ci to add lean-stack-ci.yml)."
if [ "$FAILED" -gt 0 ]; then
  echo "install: ⛔ $FAILED file(s) failed to copy — the install is INCOMPLETE. Fix the errors above and re-run." >&2
  exit 1
fi
echo ""
echo "Next:"
echo "  1. Edit CLAUDE.md placeholders (your test/lint/run commands) — or run the"
echo "     'setup-lean-stack' skill to auto-detect your stack and fill them."
echo "  2. Point .claude/rules/high-stakes.md 'paths:' at your sensitive dirs."
echo "  3. Describe the project → docs/SPEC.md, run the 'roadmap' skill → docs/ROADMAP.md."
echo ""

# 5. Health check. doctor.sh assumes a git repo (it verifies git-tracked guarantees), so only
#    run it when the target actually is one — otherwise "not a git repo yet" is expected, not a
#    problem, and shouldn't be reported as one.
if [ -x "$TARGET/scripts/doctor.sh" ]; then
  if ( cd "$TARGET" && git rev-parse --is-inside-work-tree >/dev/null 2>&1 ); then
    echo "install: running doctor.sh ..."
    ( cd "$TARGET" && bash scripts/doctor.sh ) || echo "install: doctor reported issues above — address them before an unattended run."
  else
    echo "install: complete. Skipping doctor because the target is not a git repo yet."
    echo "install:   run 'git init', then 'bash scripts/doctor.sh'."
  fi
fi
