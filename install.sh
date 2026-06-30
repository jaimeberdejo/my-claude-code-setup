#!/usr/bin/env bash
# install.sh — drop the lean-stack scaffold + skills into a target repo.
# Deterministic file copy ONLY. The intelligent part (filling CLAUDE.md placeholders,
# pointing high-stakes.md paths at your real dirs) is the `setup-lean-stack` skill's job —
# or do it by hand. This script never asks a model to do anything.
#
# Usage:
#   bash install.sh [TARGET_DIR] [--force] [--global-skills]
#     TARGET_DIR       where to install (default: current directory)
#     --force          overwrite existing scaffold files (default: skip files that exist)
#     --global-skills  also install the skills into ~/.claude/skills (in addition to project)
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
for arg in "$@"; do
  case "$arg" in
    --force)         FORCE=1 ;;
    --global-skills) GLOBAL_SKILLS=1 ;;
    -*)              echo "install: unknown flag '$arg'" >&2; exit 2 ;;
    *)               TARGET="$arg" ;;
  esac
done

[ -d "$SCAFFOLD" ]   || { echo "install: can't find lean-stack/ next to this script ($SCAFFOLD)" >&2; exit 1; }
[ -d "$SKILLS_SRC" ] || { echo "install: can't find skills/ next to this script ($SKILLS_SRC)" >&2; exit 1; }
mkdir -p "$TARGET" || { echo "install: can't create target '$TARGET'" >&2; exit 1; }
TARGET="$(cd "$TARGET" && pwd)"

echo "install: scaffold → $TARGET  (force=$FORCE)"

COPIED=0; SKIPPED=0

# Copy one file, honoring --force and creating parent dirs. Skips (and reports) if it
# exists and --force is off.
copy_file() {
  local rel="$1" srcfile="$2" dest="$TARGET/$1"
  if [ -e "$dest" ] && [ "$FORCE" -eq 0 ]; then
    echo "  skip (exists): $rel"; SKIPPED=$((SKIPPED+1)); return
  fi
  mkdir -p "$(dirname "$dest")"
  cp "$srcfile" "$dest"
  COPIED=$((COPIED+1))
}

# 1. Scaffold files (everything under lean-stack/, including dotfiles like .github, .gitignore).
while IFS= read -r srcfile; do
  rel="${srcfile#"$SCAFFOLD"/}"
  copy_file "$rel" "$srcfile"
done < <(find "$SCAFFOLD" -type f)

# 2. Skills → <target>/.claude/skills/<skill>/
while IFS= read -r srcfile; do
  rel=".claude/skills/${srcfile#"$SKILLS_SRC"/}"
  copy_file "$rel" "$srcfile"
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

# 4. Make hooks/scripts executable.
chmod +x "$TARGET"/.claude/hooks/*.sh "$TARGET"/scripts/*.sh 2>/dev/null || true

echo ""
echo "install: copied $COPIED file(s), skipped $SKIPPED."
echo ""
echo "Next:"
echo "  1. Edit CLAUDE.md placeholders (your test/lint/run commands) — or run the"
echo "     'setup-lean-stack' skill to auto-detect your stack and fill them."
echo "  2. Point .claude/rules/high-stakes.md 'paths:' at your sensitive dirs."
echo "  3. Describe the project → docs/SPEC.md, run the 'roadmap' skill → docs/ROADMAP.md."
echo ""

# 5. Health check (don't fail the install if the target isn't a git repo yet).
if [ -x "$TARGET/scripts/doctor.sh" ]; then
  echo "install: running doctor.sh ..."
  ( cd "$TARGET" && bash scripts/doctor.sh ) || echo "install: doctor reported issues above (often just 'not a git repo yet' — run 'git init')."
fi
