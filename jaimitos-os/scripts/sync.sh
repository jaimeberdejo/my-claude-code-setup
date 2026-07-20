#!/usr/bin/env bash
# sync.sh — pull later jaimitos-os toolkit fixes into an already-scaffolded project, driven by
# the checksum manifest install.sh writes (.claude/.jaimitos-manifest). One primitive replaces
# the old four-tier classifier and its value-preserving merges: the manifest records the sha256
# each toolkit file SHIPPED with, so sync can tell "never touched" from "customized":
#
#   project-owned  docs/**, CLAUDE.md, SCAFFOLD.md, .gitignore,      → never touched or reported
#                  .claude/high-stakes-path-allowlist
#   unchanged      in manifest, local sha == manifest, toolkit newer → batch update (ONE confirm
#                                                                      for the whole lot; --yes
#                                                                      skips); manifest refreshed
#   modified       in manifest, local sha != manifest                → NEVER written; toolkit↔local
#                                                                      diff shown, listed as
#                                                                      "manual merge required"
#   deleted        in manifest, file absent locally                  → never recreated; listed with
#                                                                      the --restore hint
#   new            not in manifest, absent locally                   → toolkit ADDITION: joins the
#                                                                      batch, manifest entry added
#
# A project with NO manifest predates this model: sync refuses and points at --adopt-manifest,
# which records the CURRENT local files as the baseline (writes ONLY the manifest, no content).
# NOTE: adoption cannot tell a pre-adoption customization from shipped bytes, so the FIRST sync
# after adopting may offer to update files you customized before the baseline — review the batch
# with --dry-run before confirming.
#
# Usage: sync.sh --toolkit <path> [--dry-run] [--yes] [--adopt-manifest] [--restore <path>]
#   --toolkit <path>   REQUIRED. Local jaimitos-os checkout (the scaffold dir itself).
#   --dry-run          show the full plan; write NOTHING (not even the manifest).
#   --yes              skip the single batch confirmation (updates/adds only — modified files
#                      are never written regardless).
#   --adopt-manifest   pre-2.5.0 project: record current local files as the manifest baseline.
#   --restore <path>   reinstall ONE toolkit file you deleted locally (confirmed unless --yes).
# Exit: 0 clean · 1 a copy actually failed · 2 usage / unscaffolded / pre-manifest refusal.
# Run on a clean working tree so you can `git diff` the result before committing.
set -uo pipefail
cd "$(git rev-parse --show-toplevel 2>/dev/null || echo .)" || exit 1

MANIFEST=".claude/.jaimitos-manifest"
TOOLKIT=""; DRY_RUN=0; YES=0; ADOPT=0; RESTORE=""; PRUNE=0
while [ $# -gt 0 ]; do
  case "$1" in
    --toolkit) [ $# -ge 2 ] || { echo "sync: --toolkit requires a path argument" >&2; exit 2; }
               TOOLKIT="$2"; shift 2 ;;
    --dry-run) DRY_RUN=1; shift ;;
    --yes)     YES=1; shift ;;
    --prune)   PRUNE=1; shift ;;
    --adopt-manifest) ADOPT=1; shift ;;
    --restore) [ $# -ge 2 ] || { echo "sync: --restore requires a path argument" >&2; exit 2; }
               RESTORE="$2"; shift 2 ;;
    -h|--help)
      echo "usage: sync.sh --toolkit <path> [--dry-run] [--yes] [--prune] [--adopt-manifest] [--restore <path>]"
      echo "  Manifest-driven toolkit update for an ALREADY-scaffolded project. Unchanged files are"
      echo "  batch-updated after one confirmation; locally modified files are never written (diff"
      echo "  shown for manual merge); locally deleted files are never recreated (use --restore)."
      echo "  Retired files (in your manifest, no longer shipped) are REPORTED by default; --prune"
      echo "  removes the unchanged ones (after a confirmation, or --yes) — modified ones are never"
      echo "  auto-removed. Pre-2.5.0 projects: run once with --adopt-manifest to record the baseline."
      exit 0 ;;
    *) echo "sync: unknown argument '$1'" >&2; exit 2 ;;
  esac
done

[ -n "$TOOLKIT" ] || { echo "sync: --toolkit <path> is required (the local jaimitos-os checkout to sync from)" >&2; exit 2; }
[ -d "$TOOLKIT" ] && [ -r "$TOOLKIT" ] || { echo "sync: --toolkit path '$TOOLKIT' is not a readable directory" >&2; exit 2; }
if [ ! -d "$TOOLKIT/.claude" ] || [ ! -d "$TOOLKIT/scripts" ]; then
  echo "sync: --toolkit path '$TOOLKIT' doesn't look like a jaimitos-os checkout (expected .claude/ + scripts/)" >&2
  exit 2
fi
TOOLKIT="$(cd "$TOOLKIT" 2>/dev/null && pwd)" || { echo "sync: could not resolve --toolkit path" >&2; exit 2; }
# Second source root: repo-root skills/ is a SIBLING of jaimitos-os/ (mirrors install.sh).
SKILLS_SRC="$(cd "$TOOLKIT/.." 2>/dev/null && pwd)/skills"

# sync UPDATES an already-scaffolded project; it is not an installer (install.sh always writes
# settings.json, so its absence means the project was never scaffolded).
if [ ! -f .claude/settings.json ]; then
  echo "sync: ⛔ this project isn't scaffolded yet — .claude/settings.json is missing." >&2
  echo "sync:   Scaffold first:  bash install.sh .   — then re-run sync to pull updates." >&2
  exit 2
fi

# Portable sha256 (sha256sum on Linux, shasum -a 256 on macOS/Bash 3.2 hosts).
sha256_of() {
  if command -v sha256sum >/dev/null 2>&1; then sha256sum "$1" | awk '{print $1}'
  else shasum -a 256 "$1" | awk '{print $1}'; fi
}

# Project-owned content sync must never touch or report. Single fixed list (mirrored in
# install.sh's manifest writer — keep the two case patterns identical).
project_owned() {
  case "$1" in
    docs/*|CLAUDE.md|SCAFFOLD.md|.gitignore|.claude/high-stakes-path-allowlist|.claude/test-command|.claude/eval-fixture-paths) return 0 ;;
    *) return 1 ;;
  esac
}

# Shipped EXECUTABLES must stay executable after a copy (install.sh chmod +x's them on install).
# Sourced libraries under .claude/lib/ are NOT executed — install.sh chmods only hooks/scripts/sandbox,
# so sync must not add an exec bit they should not carry (v2.16.0: two libs had drifted to 755).
is_shipped_script() {
  case "$1" in
    scripts/*.sh|.claude/hooks/*.sh|.github/scripts/*.sh|sandbox/*.sh) return 0 ;;
    *) return 1 ;;
  esac
}

# CI opt-in gate: never ADD the project's first .github/* file — install.sh --with-ci owns that
# decision. Updating an existing .github file is unaffected (the dir exists by then).
ci_not_opted_in() { case "$1" in .github/*) [ ! -d .github ] ;; *) return 1 ;; esac; }

# Manifest lines are `<sha256><SP><SP><path>` (sha256sum -c compatible): sha = chars 1–64,
# path starts at char 67. Paths may contain spaces; substr() handles them where field-splitting
# would not. ENVIRON (not awk -v) so a path round-trips byte-for-byte.
manifest_sha() {
  [ -f "$MANIFEST" ] || return 0
  REL="$1" awk 'length($0) > 66 && substr($0, 67) == ENVIRON["REL"] { print substr($0, 1, 64); exit }' "$MANIFEST"
}

MANIFEST_UPDATES=""   # "sha  path" lines for files actually written/verified this run
MANIFEST_DROPS=""     # bare paths to REMOVE from the manifest (retired entries; v2.17)
record_entry() { MANIFEST_UPDATES="${MANIFEST_UPDATES}$1  $2"$'\n'; }
apply_manifest_updates() {
  [ -n "$MANIFEST_UPDATES$MANIFEST_DROPS" ] || return 0
  [ "$DRY_RUN" -eq 1 ] && return 0
  local tmp; tmp=$(mktemp 2>/dev/null || echo "$MANIFEST.tmp.$$")
  {
    if [ -f "$MANIFEST" ]; then
      # Drop set = paths being re-added (dedup) PLUS retired paths being removed. Both as bare paths.
      { printf '%s' "$MANIFEST_UPDATES" | awk 'length($0) > 66 { print substr($0, 67) }'
        printf '%s' "$MANIFEST_DROPS"; } > "$tmp.drop"
      awk 'NR==FNR { drop[$0]=1; next } !(substr($0, 67) in drop)' "$tmp.drop" "$MANIFEST"
    fi
    printf '%s' "$MANIFEST_UPDATES"
  } | LC_ALL=C sort | awk 'NF' > "$tmp"
  mkdir -p .claude && mv "$tmp" "$MANIFEST"
  rm -f "$tmp.drop" 2>/dev/null || true
}

# _retired_path_safe <manifest-path>: a retired path is safe to ACT on (remove / drop) only if it is a
# plain relative path inside a managed root and not a symlink — so a malformed/hostile manifest line can
# never make sync delete outside the project or follow a symlink out of it.
_retired_path_safe() {
  local p="$1"
  case "$p" in
    ''|/*) return 1 ;;                 # empty or absolute
    ..|../*|*/..|*/../*) return 1 ;;   # any .. traversal component
  esac
  case "$p" in
    scripts/*|.claude/*|sandbox/*|.github/*) : ;;   # the only roots the toolkit ships into
    *) return 1 ;;
  esac
  [ -L "$p" ] && return 1              # never follow / delete through a symlink
  return 0
}

# Enumerate both source roots exactly as install.sh ships them (sorted → deterministic order).
# Prints "<dest-rel>\t<abs-src>" lines; project-owned dests are dropped here (never reported).
toolkit_files() {
  local srcfile rel
  while IFS= read -r srcfile; do
    rel="${srcfile#"$TOOLKIT"/}"
    case "$rel" in
      toolkit-docs/*|.github/workflows/*|PLAN-*.md|*.DS_Store|*.swp) continue ;;
      scripts/test-evidence.sh|scripts/test-hooks.sh) ;;   # always-managed: shipped into every project
      scripts/run-guard-tests.sh|scripts/test-*.sh)
        # The optional guard suite ships only with install --with-tests. sync mirrors that: it UPDATES
        # the suite where a project already has it, but never ADDS it to a lean project (which would
        # undo the footprint gate by re-shipping ~27 files as "new").
        [ -f "$rel" ] || continue ;;
    esac
    project_owned "$rel" && continue
    printf '%s\t%s\n' "$rel" "$srcfile"
  done < <(find "$TOOLKIT" -type f | LC_ALL=C sort)
  [ -d "$SKILLS_SRC" ] || return 0
  while IFS= read -r srcfile; do
    rel="${srcfile#"$SKILLS_SRC"/}"
    case "$rel" in setup-jaimitos-os/*) continue ;; esac
    printf '%s\t%s\n' ".claude/skills/$rel" "$srcfile"
  done < <(find "$SKILLS_SRC" -mindepth 2 -type f | LC_ALL=C sort)
}

confirm() {
  local ans=""
  printf '%s [y/N] ' "$1"; read -r ans
  case "$ans" in y|Y|yes|Yes|YES) return 0 ;; *) return 1 ;; esac
}

# copy_one <rel> <src>: the single write path (mkdir, cp, exec bit, fingerprint, manifest entry).
FAILED=0; WROTE=0
copy_one() {
  local rel="$1" src="$2" cp_err
  mkdir -p "$(dirname "$rel")"
  if cp_err="$(cp "$src" "$rel" 2>&1 >/dev/null)"; then
    is_shipped_script "$rel" && chmod +x "$rel"
    # Keep doctor.sh's drift check honest: a new shipped _high-stakes.sh means a new default.
    [ "$rel" = ".claude/lib/_high-stakes.sh" ] \
      && { mkdir -p .claude; grep -E '^HIGH_STAKES_RE=' "$src" > .claude/.high-stakes-default 2>/dev/null || true; }
    record_entry "$(sha256_of "$rel")" "$rel"
    echo "  written: $rel"
    WROTE=$((WROTE+1))
  else
    echo "  FAILED: $rel${cp_err:+ ($cp_err)}" >&2
    FAILED=$((FAILED+1))
  fi
}

echo "jaimitos-os sync"
echo "  toolkit: $TOOLKIT"
[ "$DRY_RUN" -eq 1 ] && echo "  mode: dry-run (nothing will be written)"
echo ""

# --- --adopt-manifest: record the current local state as the baseline, write nothing else ------
if [ "$ADOPT" -eq 1 ]; then
  if [ -f "$MANIFEST" ]; then
    echo "sync: ⛔ $MANIFEST already exists — refusing to re-baseline over it (that would hide local drift)." >&2
    exit 2
  fi
  ADOPTED=0
  while IFS=$'\t' read -r rel src; do
    [ -f "$rel" ] || continue
    record_entry "$(sha256_of "$rel")" "$rel"
    ADOPTED=$((ADOPTED+1))
    [ "$DRY_RUN" -eq 1 ] && echo "  (dry-run) would record: $rel"
  done < <(toolkit_files)
  apply_manifest_updates
  echo "sync: recorded $ADOPTED toolkit-owned file(s) as the manifest baseline."
  [ "$DRY_RUN" -eq 0 ] && echo "sync: baseline written to $MANIFEST — no content files were modified. Re-run sync to pull updates."
  exit 0
fi

# --- pre-manifest refusal ------------------------------------------------------------------------
if [ ! -f "$MANIFEST" ]; then
  echo "sync: ⛔ this project predates the manifest sync model ($MANIFEST is missing)." >&2
  echo "sync:   Run \`scripts/sync.sh --toolkit <path> --adopt-manifest\` to record the current scaffold" >&2
  echo "sync:   as the baseline (writes only the manifest, never content). Then re-run sync." >&2
  exit 2
fi

# --- --restore <path>: reinstall one locally deleted toolkit file --------------------------------
if [ -n "$RESTORE" ]; then
  project_owned "$RESTORE" && { echo "sync: ⛔ '$RESTORE' is project-owned — sync never writes it." >&2; exit 2; }
  RSRC=$(toolkit_files | REL="$RESTORE" awk -F'\t' '$1 == ENVIRON["REL"] { print $2; exit }')
  [ -n "$RSRC" ] || { echo "sync: ⛔ '$RESTORE' is not a file this toolkit ships." >&2; exit 2; }
  if [ "$DRY_RUN" -eq 1 ]; then echo "  (dry-run) would restore: $RESTORE"
  elif [ "$YES" -eq 1 ] || confirm "Restore '$RESTORE' from the toolkit?"; then copy_one "$RESTORE" "$RSRC"
  else echo "  skipped (declined restore): $RESTORE"; fi
  apply_manifest_updates
  [ "$FAILED" -gt 0 ] && exit 1
  exit 0
fi

# --- classify every toolkit file (newline lists keep enumeration order) --------------------------
UPDATES=""; ADDS=""; MODIFIED=0; DELETED=0; CURRENT=0; SKIPPED_CI=0
while IFS=$'\t' read -r rel src; do
  msha=$(manifest_sha "$rel")
  if [ -f "$rel" ]; then
    if cmp -s "$rel" "$src"; then
      CURRENT=$((CURRENT+1))
      # Content already current — silently repair a missing/stale manifest entry.
      [ "$msha" = "$(sha256_of "$rel")" ] || record_entry "$(sha256_of "$rel")" "$rel"
      continue
    fi
    if [ -n "$msha" ] && [ "$(sha256_of "$rel")" = "$msha" ]; then
      UPDATES="${UPDATES}${rel}"$'\t'"${src}"$'\n'
    else
      # Locally modified (or unknown to the manifest and differing) — NEVER written.
      MODIFIED=$((MODIFIED+1))
      echo "--- manual merge required: $rel (modified locally — sync never overwrites it) ---"
      diff "$rel" "$src" || true
    fi
  else
    if [ -n "$msha" ]; then
      DELETED=$((DELETED+1))
      echo "  deleted locally — skipped (rerun with --restore '$rel' to reinstall): $rel"
    elif ci_not_opted_in "$rel"; then
      SKIPPED_CI=$((SKIPPED_CI+1))
      echo "  skipped (CI not opted in — run install.sh --with-ci, then re-sync): $rel"
    else
      ADDS="${ADDS}${rel}"$'\t'"${src}"$'\n'
    fi
  fi
done < <(toolkit_files)

# --- one batch confirmation for everything writable ----------------------------------------------
BATCH="${UPDATES}${ADDS}"
NBATCH=$(printf '%s' "$BATCH" | grep -c . || true)
if [ "$NBATCH" -gt 0 ]; then
  echo ""
  echo "toolkit updates/additions (unchanged locally or new — one confirmation for the lot):"
  printf '%s' "$UPDATES" | awk -F'\t' 'NF { print "  update: " $1 }'
  printf '%s' "$ADDS"    | awk -F'\t' 'NF { print "  add:    " $1 }'
  if [ "$DRY_RUN" -eq 1 ]; then
    echo "  (dry-run) $NBATCH file(s) would be written."
  elif [ "$YES" -eq 1 ] || confirm "Apply these $NBATCH update(s)/add(s) from the toolkit?"; then
    while IFS=$'\t' read -r rel src; do
      [ -n "$rel" ] && copy_one "$rel" "$src"
    done <<< "$BATCH"
  else
    echo "  skipped (declined batch)."
  fi
fi

# --- retired-file reconciliation (v2.17 OBJ-1704) ------------------------------------------------
# Manifest entries the CURRENT toolkit no longer ships. Before v2.17 sync classified only current
# toolkit files, so an upgrade left retired guard scripts/libs on disk AND stale manifest entries
# forever. Report-only by default; removing an UNCHANGED retired file needs --prune + a confirmation
# (or --yes) because deleting a user's file is destructive. A LOCALLY-MODIFIED retired file is NEVER
# auto-removed (reported for a manual decision); a LOCALLY-DELETED one just has its stale entry dropped.
RET_REMOVABLE=0; RET_MODIFIED=0; RET_DELETED=0; RET_REMOVED=0; RET_UNSAFE=0; RET_REMOVABLE_LIST=""
CUR_RELS=$(toolkit_files | cut -f1)
RET_LIST=""
while IFS= read -r mpath; do
  [ -n "$mpath" ] || continue
  printf '%s\n' "$CUR_RELS" | grep -qxF -- "$mpath" && continue   # still shipped → not retired
  project_owned "$mpath" && continue                              # defensive: install never records these
  RET_LIST="${RET_LIST}${mpath}"$'\n'
done < <(awk 'length($0) > 66 { print substr($0, 67) }' "$MANIFEST")
if [ -n "$(printf '%s' "$RET_LIST" | tr -d '[:space:]')" ]; then
  echo ""
  echo "retired toolkit files (in your manifest, no longer shipped by this toolkit):"
  while IFS= read -r rp; do
    [ -n "$rp" ] || continue
    if ! _retired_path_safe "$rp"; then
      RET_UNSAFE=$((RET_UNSAFE+1)); echo "  unsafe/malformed manifest path — NOT touching (report only): $rp" >&2; continue
    fi
    rsha=$(manifest_sha "$rp")
    if [ ! -e "$rp" ]; then
      RET_DELETED=$((RET_DELETED+1)); echo "  retired + already gone locally — dropping stale manifest entry: $rp"
      MANIFEST_DROPS="${MANIFEST_DROPS}${rp}"$'\n'
    elif [ -n "$rsha" ] && [ "$(sha256_of "$rp")" = "$rsha" ]; then
      RET_REMOVABLE=$((RET_REMOVABLE+1)); echo "  retired + unchanged (safe to remove): $rp"
      RET_REMOVABLE_LIST="${RET_REMOVABLE_LIST}${rp}"$'\n'
    else
      RET_MODIFIED=$((RET_MODIFIED+1)); echo "  retired but LOCALLY MODIFIED — manual decision required, NOT removed: $rp"
    fi
  done <<< "$RET_LIST"
  if [ "$RET_REMOVABLE" -gt 0 ]; then
    if [ "$PRUNE" -ne 1 ]; then
      echo "  ($RET_REMOVABLE removable — re-run with --prune to delete them; modified/unknown files are never auto-removed)"
    elif [ "$DRY_RUN" -eq 1 ]; then
      echo "  (dry-run) $RET_REMOVABLE retired file(s) would be removed."
    elif [ "$YES" -eq 1 ] || confirm "Remove $RET_REMOVABLE retired, unchanged toolkit file(s)?"; then
      while IFS= read -r rp; do
        [ -n "$rp" ] || continue
        if rm -f "$rp" 2>/dev/null; then echo "  removed: $rp"; RET_REMOVED=$((RET_REMOVED+1)); MANIFEST_DROPS="${MANIFEST_DROPS}${rp}"$'\n'
        else echo "  FAILED to remove: $rp" >&2; FAILED=$((FAILED+1)); fi
      done <<< "$RET_REMOVABLE_LIST"
    else
      echo "  skipped (declined retired-file removal)."
    fi
  fi
fi

apply_manifest_updates

echo ""
echo "sync summary:"
if [ "$DRY_RUN" -eq 1 ]; then echo "  would write:        $NBATCH"; else echo "  written:            $WROTE"; fi
echo "  manual merge:       $MODIFIED"
echo "  deleted locally:    $DELETED"
echo "  already current:    $CURRENT"
[ "$SKIPPED_CI" -gt 0 ] && echo "  CI not opted in:    $SKIPPED_CI"
[ "$RET_REMOVED"   -gt 0 ] && echo "  retired removed:    $RET_REMOVED"
[ "$RET_REMOVABLE" -gt 0 ] && [ "$RET_REMOVED" -eq 0 ] && echo "  retired removable:  $RET_REMOVABLE (use --prune)"
[ "$RET_MODIFIED"  -gt 0 ] && echo "  retired modified:   $RET_MODIFIED (manual)"
[ "$RET_DELETED"   -gt 0 ] && echo "  retired entries dropped: $RET_DELETED"
[ "$RET_UNSAFE"    -gt 0 ] && echo "  retired unsafe paths:    $RET_UNSAFE (skipped)"
echo "  failed:             $FAILED"

if [ "$FAILED" -gt 0 ]; then
  echo "" >&2
  echo "sync: ⛔ $FAILED file(s) failed to copy — see FAILED lines above." >&2
  exit 1
fi
# Migration (D1): seed .claude/test-command from PERSISTENT project config if it doesn't exist yet, so
# an existing install upgrading to the integrity-bound test-command gate (H2) keeps working without a
# manual step. Never overwrites; never reads the transient LEAN_TEST_CMD process env; leaves the file
# absent (fail-closed) if nothing safe can be derived. Best-effort — a seed failure never fails sync.
if [ "$DRY_RUN" -eq 0 ] && [ -f .claude/lib/_test-cmd.sh ]; then
  # shellcheck disable=SC1091
  . .claude/lib/_test-cmd.sh 2>/dev/null || true
  command -v seed_test_command_file >/dev/null 2>&1 && seed_test_command_file || true
fi

# Stamp the synced-to VERSION (mirrors install.sh) after a successful non-dry run.
if [ "$DRY_RUN" -eq 0 ]; then
  TOOLKIT_VERSION="$(cat "$TOOLKIT/../VERSION" 2>/dev/null || echo '?')"
  mkdir -p .claude && printf '%s\n' "$TOOLKIT_VERSION" > .claude/.jaimitos-os-version 2>/dev/null || true
fi
exit 0
