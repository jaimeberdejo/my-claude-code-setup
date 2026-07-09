#!/usr/bin/env bash
# install.sh — drop the jaimitos-os scaffold + skills into a target repo.
# Deterministic file copy ONLY. The intelligent part (filling CLAUDE.md placeholders,
# pointing high-stakes.md paths at your real dirs) is the `setup-jaimitos-os` skill's job —
# or do it by hand. This script never asks a model to do anything.
#
# Usage:
#   bash install.sh [TARGET_DIR] [--force] [--global-skills] [--with-ci]
#     TARGET_DIR       where to install (default: current directory)
#     --force          overwrite existing scaffold files (default: skip files that exist)
#     --global-skills  also install the skills into ~/.claude/skills (in addition to project)
#     --with-ci        also copy the CI workflow (.github/workflows/jaimitos-os-ci.yml).
#                      Off by default — most projects already have their own CI.
#     --allow-subdir   allow installing into a SUBDIRECTORY of an existing git repo. jaimitos-os
#                      assumes ONE repo per project — its operational scripts resolve every path from
#                      `git rev-parse --show-toplevel`, so a subdir install makes autopilot/tick/doctor
#                      look in the wrong place. Refused by default; pass this only if you accept that
#                      the scripts will misbehave (or you'll run them from the git root yourself).
#
# The repo README documents the toolkit and is NEVER copied into a target. The scaffold's own
# note ships as SCAFFOLD.md (so it can't become/clobber your README).
#
# Idempotent: re-running is safe. Without --force it skips any file that already exists,
# so it never clobbers a CLAUDE.md you've customized.

set -uo pipefail

# Resolve this script's directory (the repo root) so it works from anywhere.
SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCAFFOLD="$SRC/jaimitos-os"
SKILLS_SRC="$SRC/skills"

TARGET="."
FORCE=0
GLOBAL_SKILLS=0
WITH_CI=0
ALLOW_SUBDIR=0
for arg in "$@"; do
  case "$arg" in
    -h|--help)
      # Universal --help, matching the operational scripts (models.sh/sync.sh/tick.sh/…). A genuinely
      # unknown flag still fails closed (exit 2) via the catch-all below — help must not mask a typo.
      echo "usage: install.sh [TARGET_DIR] [--force] [--global-skills] [--with-ci] [--allow-subdir]"
      echo "  Drops the jaimitos-os scaffold + skills into TARGET_DIR (default: current dir)."
      echo "    --force          overwrite existing scaffold files (default: skip files that exist)"
      echo "    --global-skills  also install skills into ~/.claude/skills"
      echo "    --with-ci        also copy the CI workflow (.github/workflows/jaimitos-os-ci.yml)"
      echo "    --allow-subdir   allow installing into a SUBDIRECTORY of an existing git repo (scripts"
      echo "                     resolve paths from the git root, so expect them to misbehave)"
      echo "  The repo README is NEVER copied; the scaffold note ships as SCAFFOLD.md. Idempotent."
      exit 0 ;;
    --force)         FORCE=1 ;;
    --global-skills) GLOBAL_SKILLS=1 ;;
    --with-ci)       WITH_CI=1 ;;
    --allow-subdir)  ALLOW_SUBDIR=1 ;;
    -*)              echo "install: unknown flag '$arg'" >&2; exit 2 ;;
    *)               TARGET="$arg" ;;
  esac
done

[ -d "$SCAFFOLD" ]   || { echo "install: can't find jaimitos-os/ next to this script ($SCAFFOLD)" >&2; exit 1; }
[ -d "$SKILLS_SRC" ] || { echo "install: can't find skills/ next to this script ($SKILLS_SRC)" >&2; exit 1; }
mkdir -p "$TARGET" || { echo "install: can't create target '$TARGET'" >&2; exit 1; }
TARGET="$(cd "$TARGET" && pwd)" || { echo "install: can't enter target '$TARGET'" >&2; exit 1; }

# H4: jaimitos-os assumes ONE repo per project. Its operational scripts resolve every path from
# `git rev-parse --show-toplevel`, so installing into a SUBDIRECTORY of an existing git repo makes them
# read .claude/ and docs/ from the repo root, not this subdir (a wall of false "missing" from doctor,
# and autopilot/tick operating on the wrong tree). Refuse unless the user explicitly opts in. A target
# that is NOT yet a git repo (fresh project) resolves no toplevel and is allowed — that's the norm.
GIT_TOP_RAW="$(git -C "$TARGET" rev-parse --show-toplevel 2>/dev/null || true)"
if [ -n "$GIT_TOP_RAW" ]; then
  # Compare PHYSICAL paths: git prints the symlink-resolved toplevel (e.g. /private/var/… on macOS)
  # while `cd && pwd` for TARGET is logical (/var/…) — a raw string compare would false-trip on the
  # symlink and refuse a perfectly-fine git-root install.
  GIT_TOP="$(cd "$GIT_TOP_RAW" && pwd -P)"
  TARGET_PHYS="$(cd "$TARGET" && pwd -P)"
  if [ "$GIT_TOP" != "$TARGET_PHYS" ]; then
    if [ "$ALLOW_SUBDIR" -eq 1 ]; then
      echo "install: ⚠ installing into a SUBDIRECTORY of a git repo:" >&2
      echo "install:     target:   $TARGET" >&2
      echo "install:     git root: $GIT_TOP" >&2
      echo "install:   The operational scripts resolve paths from the git root, so they will NOT find this" >&2
      echo "install:   subdir's .claude/ and docs/. You passed --allow-subdir — proceeding; expect the" >&2
      echo "install:   scripts to misbehave unless you run them differently." >&2
    else
      echo "install: ⛔ refusing: target is a SUBDIRECTORY of a git repo, not its root." >&2
      echo "install:     target:   $TARGET" >&2
      echo "install:     git root: $GIT_TOP" >&2
      echo "install:   jaimitos-os assumes ONE repo per project — its scripts resolve every path from the" >&2
      echo "install:   git root, so a subdir install makes autopilot/tick/doctor look in the wrong place." >&2
      echo "install:   Install at the git root instead:  bash install.sh \"$GIT_TOP\"" >&2
      echo "install:   or use a separate repo for this project. To override anyway: --allow-subdir." >&2
      exit 1
    fi
  fi
fi

VERSION="$(cat "$SRC/VERSION" 2>/dev/null || echo '?')"
echo "install: jaimitos-os v$VERSION  →  $TARGET  (force=$FORCE)"

COPIED=0; SKIPPED=0; FAILED=0; SETTINGS_KEPT=0
WRITTEN_LIST=""   # newline-separated rel paths actually written this pass (feeds the manifest)

# Portable sha256 (sha256sum on Linux, shasum -a 256 on macOS).
sha256_of() {
  if command -v sha256sum >/dev/null 2>&1; then sha256sum "$1" | awk '{print $1}'
  else shasum -a 256 "$1" | awk '{print $1}'; fi
}

# Project-owned content: never listed in the sync manifest (sync never manages these files).
# Keep this case pattern identical to sync.sh's project_owned().
project_owned() {
  case "$1" in
    docs/*|CLAUDE.md|SCAFFOLD.md|.gitignore|.claude/high-stakes-path-allowlist) return 0 ;;
    *) return 1 ;;
  esac
}

# Copy one file, honoring --force and creating parent dirs. Skips (and reports) if it
# exists and --force is off. A failed copy is reported and counted — never silently
# treated as success (a partial install must not look clean).
copy_file() {
  local rel="$1" srcfile="$2" dest="$TARGET/$1"
  if [ -e "$dest" ] && [ "$FORCE" -eq 0 ]; then
    echo "  skip (exists): $rel"; SKIPPED=$((SKIPPED+1))
    # Brownfield safety: keeping the target's own settings.json means the jaimitos-os hooks +
    # permissions.deny were NOT merged, so the kill-switch / secret-guard won't fire. Flag it
    # loudly at the end (doctor also catches this, but only when the target is already a git repo).
    [ "$rel" = ".claude/settings.json" ] && SETTINGS_KEPT=1
    return
  fi
  mkdir -p "$(dirname "$dest")"
  if cp "$srcfile" "$dest"; then
    COPIED=$((COPIED+1))
    WRITTEN_LIST="${WRITTEN_LIST}${rel}"$'\n'
  else
    echo "  ✗ FAILED to copy: $rel" >&2; FAILED=$((FAILED+1))
  fi
}

# 1. Scaffold files (everything under jaimitos-os/, including dotfiles like .gitignore).
#    EXCLUSIONS (by directory or filename pattern, so they can't silently drift):
#      - toolkit-docs/*  : legacy toolkit docs — never shipped if present in old checkouts
#      - .github/*       : CI workflow is opt-in (--with-ci)
#      - PLAN-*.md       : defensive only since v2.5.0 — dev plans now live at repo-root
#                          docs/dev/plans/ (outside jaimitos-os/), so this should match nothing;
#                          kept so a stray plan dropped into the scaffold still never ships
#      - editor/OS cruft : .DS_Store / *.swp never copied into a target
while IFS= read -r srcfile; do
  rel="${srcfile#"$SCAFFOLD"/}"
  case "$rel" in
    toolkit-docs/*)
      continue ;;                                  # toolkit docs — don't pollute the target
    .github/*)
      [ "$WITH_CI" -eq 1 ] || continue ;;          # CI is opt-in
    PLAN-*.md)
      continue ;;                                  # toolkit dev/audit plans — never ship into a target
    *.DS_Store|*.swp)
      continue ;;                                  # editor/OS cruft
  esac
  copy_file "$rel" "$srcfile"
done < <(find "$SCAFFOLD" -type f)

# 2. Skills → <target>/.claude/skills/<skill>/
#    setup-jaimitos-os is the installer/meta skill — useless (and slightly misleading) once a
#    project is set up, so it is NOT copied per-project; it installs only via --global-skills.
while IFS= read -r srcfile; do
  skillrel="${srcfile#"$SKILLS_SRC"/}"
  case "$skillrel" in setup-jaimitos-os/*) continue ;; esac
  copy_file ".claude/skills/$skillrel" "$srcfile"
done < <(find "$SKILLS_SRC" -mindepth 2 -type f)   # mindepth 2 = inside skill dirs; skips the top-level skills/README.md

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
GI_MARK="# --- jaimitos-os control/secret ignores ---"
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
mkdir -p "$TARGET/.claude" && printf '%s\n' "$VERSION" > "$TARGET/.claude/.jaimitos-os-version" 2>/dev/null || true

# 3c-bis. Write/refresh the checksum manifest (.claude/.jaimitos-manifest): one
# `<sha256>  <rel-path>` line (sha256sum -c compatible) per toolkit-owned file ACTUALLY WRITTEN
# this pass, hashed as shipped. scripts/sync.sh reads it to tell a local customization from a
# stale shipped file. Merge semantics: entries for files skipped this pass are left as they were;
# project-owned files (docs/**, CLAUDE.md, SCAFFOLD.md, .gitignore, the high-stakes allowlist)
# are never listed — sync never manages them.
if [ -n "$WRITTEN_LIST" ]; then
  MANIFEST="$TARGET/.claude/.jaimitos-manifest"
  MF_TMP="$(mktemp 2>/dev/null || echo "$MANIFEST.tmp.$$")"
  {
    if [ -f "$MANIFEST" ]; then
      printf '%s' "$WRITTEN_LIST" > "$MF_TMP.drop"
      awk 'NR==FNR { drop[$0]=1; next } !(substr($0, 67) in drop)' "$MF_TMP.drop" "$MANIFEST"
    fi
    while IFS= read -r rel; do
      [ -n "$rel" ] || continue
      project_owned "$rel" && continue
      [ -f "$TARGET/$rel" ] && printf '%s  %s\n' "$(sha256_of "$TARGET/$rel")" "$rel"
    done <<< "$WRITTEN_LIST"
  } | LC_ALL=C sort > "$MF_TMP"
  mv "$MF_TMP" "$MANIFEST"
  rm -f "$MF_TMP.drop" 2>/dev/null || true
fi

# 3d. Fingerprint the shipped HIGH_STAKES_RE so doctor.sh can warn when the ENFORCED gate
# was never pointed at the project's real paths (editing only the advisory rule is the
# common mistake that silently disables enforcement).
if [ -f "$TARGET/.claude/lib/_high-stakes.sh" ]; then
  grep -E '^HIGH_STAKES_RE=' "$TARGET/.claude/lib/_high-stakes.sh" > "$TARGET/.claude/.high-stakes-default" 2>/dev/null || true
fi

# 4. Make hooks/scripts executable (incl. the sandbox wrapper).
chmod +x "$TARGET"/.claude/hooks/*.sh "$TARGET"/scripts/*.sh "$TARGET"/sandbox/*.sh 2>/dev/null || true

echo ""
echo "install: copied $COPIED file(s), skipped $SKIPPED, failed $FAILED."
[ "$WITH_CI" -eq 0 ] && echo "install: CI workflow NOT copied (re-run with --with-ci to add jaimitos-os-ci.yml)."
if [ "$FAILED" -gt 0 ]; then
  echo "install: ⛔ $FAILED file(s) failed to copy — the install is INCOMPLETE. Fix the errors above and re-run." >&2
  exit 1
fi
if [ "$SETTINGS_KEPT" -eq 1 ]; then
  echo "install: ⚠ kept your existing .claude/settings.json — the jaimitos-os HOOKS and permissions.deny were" >&2
  echo "install:   NOT merged, so the kill-switch, secret-guard, and other hooks will NOT fire until you" >&2
  echo "install:   merge them from $SCAFFOLD/.claude/settings.json (hooks + permissions blocks). Re-run" >&2
  echo "install:   with --force to overwrite instead. (This is the documented brownfield-adoption step.)" >&2
fi
echo ""
echo "Next:"
echo "  Existing project (a stack was already here)?"
echo "  1. Edit CLAUDE.md placeholders (your test/lint/run commands) — or run the"
echo "     'setup-jaimitos-os' skill to auto-detect your stack and fill them."
echo "  2. Point .claude/rules/high-stakes.md 'paths:' at your sensitive dirs."
echo "  3. Describe the project → docs/SPEC.md, run the 'roadmap' skill → docs/ROADMAP.md."
echo ""
echo "  Starting from scratch (empty project, no stack yet)?"
echo "  1. Describe the project → docs/SPEC.md (grill the idea first for a measurable criterion)."
echo "  2. Run the 'roadmap' skill → docs/ROADMAP.md. It fills CLAUDE.md's commands from the SPEC"
echo "     automatically, and reminds you to point high-stakes.md 'paths:' at real dirs."
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
