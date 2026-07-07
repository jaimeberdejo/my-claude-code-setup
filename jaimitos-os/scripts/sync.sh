#!/usr/bin/env bash
# sync.sh — pull later jaimitos-os toolkit fixes into an already-scaffolded project from a LOCAL
# toolkit checkout, conservatively: never a blind two-way overwrite. install.sh only handles
# brand-new projects (skip-if-exists); this is the update path for one that's already scaffolded.
#
# Classifies every toolkit-shipped file into one of four tiers and applies each per its rule:
#   overwrite  toolkit-owned logic, no project values inside     → diff, confirm, copy over
#   never      project-owned (docs, CLAUDE.md, .gitignore)       → always skipped, never written
#   mixed      toolkit body + a project-customized value in it   → value-preserving merge for the
#                                                                   three known shapes (the
#                                                                   HIGH_STAKES_RE= line, an
#                                                                   agent's model: frontmatter
#                                                                   line, or rules/high-stakes.md's
#                                                                   paths: block): toolkit body +
#                                                                   project value. ALWAYS prompts
#                                                                   (never bypassed by --yes); an
#                                                                   unrecognized/malformed shape in
#                                                                   EITHER copy still routes to the
#                                                                   manual-review bucket, untouched
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
# Nonzero on a real error: bad/missing args, a --toolkit path that isn't a readable jaimitos-os
# checkout, or one or more copies actually failing (see the FAILED tally in the summary — a
# `cp` failure, e.g. a read-only destination, is never silently reported as "updated").

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
    -h|--help)
      echo "usage: sync.sh --toolkit <path> [--dry-run] [--yes]"
      echo "  Pull later jaimitos-os toolkit fixes into an ALREADY-scaffolded project from a local toolkit"
      echo "  checkout, conservatively (four-tier classifier; mixed always prompts). See header for tiers."
      exit 0 ;;
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

# M7: sync is the UPDATE path for an ALREADY-scaffolded project, not an installer. A project with no
# .claude/settings.json was never scaffolded (install.sh always writes it), so running sync here would
# do a broken PSEUDO-install — adding toolkit scripts/hooks while skipping every project-owned file
# (CLAUDE.md, docs/, and settings.json itself). Refuse and point at install.sh instead of guessing.
if [ ! -f .claude/settings.json ]; then
  echo "sync: ⛔ this project isn't scaffolded yet — .claude/settings.json is missing." >&2
  echo "sync:   sync UPDATES an already-scaffolded project; it is not an installer. Running it here would" >&2
  echo "sync:   add toolkit scripts/hooks while skipping the project-owned files (CLAUDE.md, docs/," >&2
  echo "sync:   settings.json). Scaffold first:  bash install.sh .   — then re-run sync to pull updates." >&2
  exit 2
fi

# install.sh copies from TWO source roots (install.sh:73-98): the jaimitos-os/ scaffold itself,
# 1:1 onto the project root (--toolkit points here), AND a separate repo-root skills/ dir — a
# SIBLING of jaimitos-os/ — mapped onto the project's .claude/skills/<skill>/... . Skills are
# actively maintained just like jaimitos-os/ itself, so sync must see both roots or a scaffolded
# project could never receive a skill update. Tolerate its absence (e.g. a --toolkit checkout with
# no sibling skills/ dir): that's not an error, just nothing to enumerate from that root.
SKILLS_SRC="$(cd "$TOOLKIT/.." 2>/dev/null && pwd)/skills"

# --- enumeration -------------------------------------------------------------------------------
# Mirrors install.sh's find+case EXACTLY for toolkit-docs/* and *.DS_Store|*.swp. One deliberate
# difference from install.sh's DEFAULT (no --with-ci, which excludes ALL of .github/*): sync
# always considers .github/scripts/*.sh — plain toolkit-owned helper scripts, classified
# `overwrite` below like any other scripts/*.sh — but still never offers .github/workflows/*; a
# project's CI-workflow adoption is install.sh's separate, opt-in decision, not sync's to make.
# That opt-in gate is re-checked again at ADD-time (see ci_not_opted_in below): a project with no
# .github/ directory at all never ran install.sh --with-ci, so sync must not silently add its
# first .github file either — it still appears in the plan, just reported as skipped. UPDATING an
# existing .github/* file is unaffected (the directory necessarily already exists by then).
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
  done < <(find "$TOOLKIT" -type f | LC_ALL=C sort)   # sort → deterministic prompt order across machines/filesystems
}

# skills_files: enumerates the SKILLS_SRC root, mirroring install.sh's second copy loop
# (install.sh:94-98) EXACTLY — `find -mindepth 2 -type f` (files INSIDE a skill dir, which skips
# the top-level skills/README.md) and skips setup-jaimitos-os/* (the meta/installer skill;
# install.sh only ever ships it via --global-skills, never per-project, so sync must not offer it
# either). Prints the SOURCE path relative to SKILLS_SRC (e.g. "adr/SKILL.md") — the caller maps
# each onto its project-relative DEST path (.claude/skills/<that>) when building FILES/SRCS below,
# since (unlike jaimitos-os/, where source-relative IS project-relative) the two differ here.
skills_files() {
  local srcfile
  [ -d "$SKILLS_SRC" ] || return 0
  while IFS= read -r srcfile; do
    case "${srcfile#"$SKILLS_SRC"/}" in setup-jaimitos-os/*) continue ;; esac
    printf '%s\n' "${srcfile#"$SKILLS_SRC"/}"
  done < <(find "$SKILLS_SRC" -mindepth 2 -type f | LC_ALL=C sort)   # sort → deterministic order
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
    docs/*|CLAUDE.md|SCAFFOLD.md|.gitignore|.claude/high-stakes-path-allowlist)
      echo never ;;
    *)
      echo unknown ;;
  esac
}

# is_shipped_script <rel-path>: true if the destination is one of the toolkit's own shipped
# scripts/hooks — install.sh's final step (`chmod +x .../hooks/*.sh scripts/*.sh`) makes these
# executable on a fresh install, so sync must restore that bit after every copy too, or an
# overwrite of an existing non-executable destination would silently leave it non-executable
# (for .claude/hooks/*.sh this can defeat a guard hook without any error). Extended past
# install.sh's two globs to also cover .claude/lib/*.sh and .github/scripts/*.sh, which sync
# (unlike install.sh's default, CI-opt-out mode) does ship. Never matches non-script files
# (.claude/commands/*.md, .claude/skills/*) — those aren't meant to be executable.
is_shipped_script() {
  case "$1" in
    scripts/*.sh|.claude/hooks/*.sh|.claude/lib/*.sh|.github/scripts/*.sh) return 0 ;;
    *) return 1 ;;
  esac
}

# ci_not_opted_in <rel-path>: true only for a .github/* file that is about to be ADDED (caller
# already knows it's absent) to a project with NO .github/ directory at all — i.e. one that never
# ran install.sh --with-ci. Mirrors install.sh's own opt-in gate so sync can't accidentally do
# what install.sh explicitly refuses to do by default. Irrelevant to updates: if the file already
# exists, .github/ necessarily already exists too, so this is only ever consulted on the add path.
ci_not_opted_in() {
  case "$1" in
    .github/*) [ ! -d .github ] ;;
    *) return 1 ;;
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

# mixed_merge_prompt <rel> <kind>: the mixed-merge confirmation prompt. M5 — it NAMES the exact value
# preserved and states plainly that ONLY that value is kept; every OTHER local edit to the file
# (description, tools, prose body) is taken from the toolkit. The old generic "preserving your
# customized value?" implied the whole file's customizations survived, which they do not.
mixed_merge_prompt() {
  local rel="$1" what
  case "$2" in
    hs_lib)   what="your HIGH_STAKES_RE= line" ;;
    agent)    what="your model: frontmatter line (or its absence)" ;;
    rules_hs) what="your paths: block" ;;
    *)        what="your one customized value" ;;
  esac
  printf "Merge '%s'? Keeps the toolkit's updated version and preserves ONLY %s — any OTHER local edits to this file (description, tools, body) are REPLACED by the toolkit's." "$rel" "$what"
}

# --- mixed-file value-preserving merge (Phase 2) ------------------------------------------------
# Three known shapes get a narrow merge (toolkit body + project value) instead of a blind
# overwrite or a blanket manual-review punt. The overriding rule for all three: validate the
# shape of BOTH copies BEFORE touching anything; on any ambiguity, write NOTHING and route to
# manual review, leaving the project file byte-identical. Every merge is built into a TEMP file
# first and only `cp`'d over the project file after an explicit yes — there is no code path that
# writes a partial result to the real destination.
#
# Value substitution never uses `sed s/.../$value/`: HIGH_STAKES_RE values routinely contain
# regex metacharacters (|()[].*) that a sed REPLACEMENT string would reinterpret (mangling the
# value on write — the exact bug models.sh's own set_model() hardened against). Instead each
# merge prints the captured project line verbatim via awk's ENVIRON (not `awk -v`, which POSIX
# mandates backslash-escape processing on — see models.sh's own comment on this), or rebuilds the
# file by line-range selection (sed -n 'N,Mp', which only chooses which lines to print and never
# interprets their content), so values round-trip byte-for-byte regardless of what they contain.

# mixed_kind <rel-path> → hs_lib | agent | rules_hs, for the three known mixed shapes.
mixed_kind() {
  case "$1" in
    .claude/lib/_high-stakes.sh)  echo hs_lib ;;
    .claude/agents/*.md)          echo agent ;;
    .claude/rules/high-stakes.md) echo rules_hs ;;
    *) return 1 ;;
  esac
}

# --- shape 1: .claude/lib/_high-stakes.sh — the single ^HIGH_STAKES_RE= line is the value ------
hs_line_count() {
  local n
  n=$(grep -cE '^HIGH_STAKES_RE=' "$1" 2>/dev/null)
  printf '%s' "${n:-0}"
}

# merge_hs_lib <projfile> <toolkitfile> <outfile>: writes toolkit's body with the project's
# HIGH_STAKES_RE= line substituted in. Returns 1 (outfile untouched/empty, $MIXED_REASON set) if
# either copy doesn't have EXACTLY ONE such line.
merge_hs_lib() {
  local projfile="$1" toolkitfile="$2" outfile="$3" pn tn proj_line sq dq
  pn=$(hs_line_count "$projfile")
  if [ "$pn" -ne 1 ]; then
    MIXED_REASON="project copy has $pn HIGH_STAKES_RE= line(s) (expected exactly 1)"; return 1
  fi
  tn=$(hs_line_count "$toolkitfile")
  if [ "$tn" -ne 1 ]; then
    MIXED_REASON="toolkit copy has $tn HIGH_STAKES_RE= line(s) (expected exactly 1)"; return 1
  fi
  proj_line=$(grep -E '^HIGH_STAKES_RE=' "$projfile" | head -1)
  # C2 shape guard: the value must be self-contained on this ONE physical line. A trailing backslash
  # (line continuation) or an unbalanced quote means the real value spans further physical lines that
  # grep did not capture — substituting only the first line would silently TRUNCATE the safety regex.
  case "$proj_line" in *\\) MIXED_REASON="project HIGH_STAKES_RE= line ends with a backslash (multi-line continuation unsupported — merge by hand)"; return 1 ;; esac
  sq=$(printf '%s' "$proj_line" | tr -cd "'" | wc -c | tr -d ' ')
  dq=$(printf '%s' "$proj_line" | tr -cd '"' | wc -c | tr -d ' ')
  if [ $((sq % 2)) -ne 0 ] || [ $((dq % 2)) -ne 0 ]; then
    MIXED_REASON="project HIGH_STAKES_RE= line has an unbalanced quote (value likely spans multiple lines — merge by hand)"; return 1
  fi
  HS_PROJ_LINE="$proj_line" awk '
    /^HIGH_STAKES_RE=/ && !done { print ENVIRON["HS_PROJ_LINE"]; done=1; next }
    { print }
  ' "$toolkitfile" > "$outfile"
  # C2 syntax guard: never hand back a merged _high-stakes.sh that is not valid bash (a corrupted
  # value could leave an open quote that swallows the rest of the file). bash -n it before write.
  if ! bash -n "$outfile" 2>/dev/null; then
    MIXED_REASON="merged _high-stakes.sh failed a bash -n syntax check (refusing to write)"; return 1
  fi
}

# --- shape 2: .claude/agents/*.md — the ^model: frontmatter line (0 or 1; MAY be absent) -------
# has_wellformed_frontmatter <file>: true if line 1 is exactly "---" and a closing "---" exists.
has_wellformed_frontmatter() {
  [ "$(sed -n '1p' "$1")" = "---" ] || return 1
  [ "$(grep -c '^---$' "$1" 2>/dev/null)" -ge 2 ] || return 1
}

# fm_model_lines <file>: print ^model: lines that live INSIDE the frontmatter (between line 1's ---
# and the next ---). Scoping model: detection here stops a stray body `model:` line being mistaken
# for config (C3). Assumes has_wellformed_frontmatter already passed.
fm_model_lines() {
  awk 'NR==1 && $0=="---"{infm=1; next} infm && $0=="---"{exit} infm && /^model:/{print}' "$1"
}
fm_model_line_count() { fm_model_lines "$1" | grep -c . ; }

# merge_agent_model <projfile> <toolkitfile> <outfile>: preserves the PROJECT's model: state
# (its value, or its absence) onto the toolkit's body. Returns 1 (outfile untouched/empty,
# $MIXED_REASON set) if either copy has MORE THAN ONE model: line, or if inserting a model: line
# the toolkit lacks would require a frontmatter shape it doesn't have.
merge_agent_model() {
  local projfile="$1" toolkitfile="$2" outfile="$3" pn tn proj_line
  # C3: a model: line is only trustworthy INSIDE a well-formed --- frontmatter block. A stray model:
  # line in the markdown body, a frontmatter-less file, or unclosed frontmatter must never be treated
  # as config (that path replaced whole project files while reporting success). Require well-formed
  # frontmatter in BOTH copies and scope all model: detection to the frontmatter region.
  has_wellformed_frontmatter "$projfile"    || { MIXED_REASON="project agent file has no well-formed --- frontmatter block"; return 1; }
  has_wellformed_frontmatter "$toolkitfile" || { MIXED_REASON="toolkit agent file has no well-formed --- frontmatter block"; return 1; }
  pn=$(fm_model_line_count "$projfile")
  if [ "$pn" -gt 1 ]; then
    MIXED_REASON="project copy has $pn model: line(s) in frontmatter (expected 0 or 1)"; return 1
  fi
  tn=$(fm_model_line_count "$toolkitfile")
  if [ "$tn" -gt 1 ]; then
    MIXED_REASON="toolkit copy has $tn model: line(s) in frontmatter (expected 0 or 1)"; return 1
  fi
  if [ "$pn" -eq 1 ] && [ "$tn" -eq 1 ]; then
    proj_line=$(fm_model_lines "$projfile" | head -1)
    MODEL_LINE="$proj_line" awk '
      NR==1 && $0=="---"{infm=1; print; next}
      infm && $0=="---"{infm=0; print; next}
      infm && /^model:/ && !done { print ENVIRON["MODEL_LINE"]; done=1; next }
      { print }
    ' "$toolkitfile" > "$outfile"
  elif [ "$pn" -eq 1 ] && [ "$tn" -eq 0 ]; then
    proj_line=$(fm_model_lines "$projfile" | head -1)
    MODEL_LINE="$proj_line" awk '
      NR==1 { print; next }
      !done && /^---$/ { print ENVIRON["MODEL_LINE"]; print; done=1; next }
      { print }
    ' "$toolkitfile" > "$outfile"
  elif [ "$pn" -eq 0 ] && [ "$tn" -eq 1 ]; then
    awk '
      NR==1 && $0=="---"{infm=1; print; next}
      infm && $0=="---"{infm=0; print; next}
      infm && /^model:/ { next }
      { print }
    ' "$toolkitfile" > "$outfile"
  else
    cp "$toolkitfile" "$outfile"
  fi
}

# --- shape 3: .claude/rules/high-stakes.md — the ^paths: frontmatter BLOCK ----------------------
# paths_block_bounds <file>: on success sets globals PB_START/PB_END (1-indexed, inclusive line
# range of the paths: block: the "paths:" line itself plus every following indented line, up to
# the next top-level/unindented line or the closing ---) and returns 0. On any ambiguity — no
# opening/closing --- delimiter, or not EXACTLY ONE top-level paths: key — sets $MIXED_REASON and
# returns 1 without touching PB_START/PB_END. Called directly (never via `$(...)`) so these
# globals survive the call — a command-substitution-wrapped call would run in a subshell and
# lose them.
paths_block_bounds() {
  local f="$1" closing paths_lines paths_count ln line
  [ "$(sed -n '1p' "$f")" = "---" ] || { MIXED_REASON="has no opening --- frontmatter delimiter on line 1"; return 1; }
  closing=$(awk 'NR>1 && /^---$/ {print NR; exit}' "$f")
  [ -n "$closing" ] || { MIXED_REASON="frontmatter is never closed with a second ---"; return 1; }
  paths_lines=$(awk -v c="$closing" 'NR>1 && NR<c && /^paths:/ {print NR}' "$f")
  paths_count=$(printf '%s\n' "$paths_lines" | grep -c .)
  if [ "$paths_count" -ne 1 ]; then
    MIXED_REASON="has $paths_count top-level paths: key(s) in its frontmatter (expected exactly 1)"; return 1
  fi
  PB_START="$paths_lines"
  PB_END="$PB_START"
  ln=$((PB_START + 1))
  while [ "$ln" -lt "$closing" ]; do
    line=$(sed -n "${ln}p" "$f")
    case "$line" in
      ""|[[:space:]]*|'#'*) PB_END=$ln ;;   # blank, indented, OR a bare (unindented) comment stays in the block
      *:*) break ;;                          # a real top-level key (has a colon) ends the block
      *) MIXED_REASON="unexpected non-key line inside the paths: block (line $ln) — merge by hand"; return 1 ;;
    esac
    ln=$((ln + 1))
  done
  return 0
}

# merge_rules_hs <projfile> <toolkitfile> <outfile>: replaces the toolkit's paths: block with the
# project's (verbatim, including its own comments/indentation), keeping the rest of the
# toolkit's body. Returns 1 (outfile untouched/empty, $MIXED_REASON set) if either copy's
# paths: block can't be unambiguously delimited.
merge_rules_hs() {
  local projfile="$1" toolkitfile="$2" outfile="$3" proj_start proj_end tk_start tk_end
  paths_block_bounds "$projfile" || { MIXED_REASON="project copy $MIXED_REASON"; return 1; }
  proj_start="$PB_START"; proj_end="$PB_END"
  paths_block_bounds "$toolkitfile" || { MIXED_REASON="toolkit copy $MIXED_REASON"; return 1; }
  tk_start="$PB_START"; tk_end="$PB_END"
  {
    sed -n "1,$((tk_start - 1))p" "$toolkitfile"
    sed -n "${proj_start},${proj_end}p" "$projfile"
    sed -n "$((tk_end + 1)),\$p" "$toolkitfile"
  } > "$outfile"
}

# refresh_high_stakes_default <toolkitfile>: after a successful _high-stakes.sh merge, refresh
# the project's fingerprint to the TOOLKIT's (new) HIGH_STAKES_RE= line, mirroring install.sh's
# own write (install.sh:145) so doctor.sh's drift check keeps comparing against the CURRENT
# shipped default rather than a stale one.
refresh_high_stakes_default() {
  mkdir -p .claude
  grep -E '^HIGH_STAKES_RE=' "$1" > .claude/.high-stakes-default 2>/dev/null || true
}

UPDATED=0
SKIPPED=0
MANUAL=0
UNCHANGED=0
FAILED=0

echo "jaimitos-os sync"
echo "  toolkit: $TOOLKIT"
[ "$DRY_RUN" -eq 1 ] && echo "  mode: dry-run (nothing will be written)"
echo ""

# Materialize the enumerated file list into two PARALLEL arrays FIRST (a plain, non-piped loop
# below), so the main per-file loop's `read -r ans` prompts (via confirm) read from the script's
# OWN stdin — not from a process-substituted stream that a `while read < <(...)` around the whole
# loop would otherwise steal. FILES[i] is always the project-relative DEST path (what's checked
# on disk, classified, and written to); SRCS[i] is the matching absolute SOURCE path to diff/copy
# from. For jaimitos-os/ files the two are the same path; for skills/ files they differ (source
# "adr/SKILL.md" → dest ".claude/skills/adr/SKILL.md"), which is why one rel string can no longer
# serve both roles the way it used to when jaimitos-os/ was the only source root.
FILES=()
SRCS=()
while IFS= read -r rel; do
  [ -n "$rel" ] && { FILES+=("$rel"); SRCS+=("$TOOLKIT/$rel"); }
done < <(toolkit_files)
while IFS= read -r skillrel; do
  [ -n "$skillrel" ] && { FILES+=(".claude/skills/$skillrel"); SRCS+=("$SKILLS_SRC/$skillrel"); }
done < <(skills_files)

# Bash 3.2 quirk: "${FILES[@]}" (or "${!FILES[@]}") on a zero-element (but declared) array throws
# "unbound variable" under `set -u`. Guard with the count form first, which is always safe to
# expand. Indexed (not `for rel in`) so SRCS stays in lockstep with FILES.
[ "${#FILES[@]}" -gt 0 ] && for i in "${!FILES[@]}"; do
  rel="${FILES[$i]}"
  tier="$(classify_tier "$rel")"
  toolkitfile="${SRCS[$i]}"

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
          if cp_err="$(cp "$toolkitfile" "$rel" 2>&1 >/dev/null)"; then
            is_shipped_script "$rel" && chmod +x "$rel"
            echo "  updated: $rel"
            UPDATED=$((UPDATED+1))
          else
            echo "  FAILED: $rel${cp_err:+ ($cp_err)}" >&2
            FAILED=$((FAILED+1))
          fi
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
        kind="$(mixed_kind "$rel")"
        tmpfile="$(mktemp 2>/dev/null || mktemp -t jaimitos-os-sync)"
        MIXED_REASON=""
        mrc=0
        case "$kind" in
          hs_lib)   merge_hs_lib      "$rel" "$toolkitfile" "$tmpfile" || mrc=$? ;;
          agent)    merge_agent_model "$rel" "$toolkitfile" "$tmpfile" || mrc=$? ;;
          rules_hs) merge_rules_hs    "$rel" "$toolkitfile" "$tmpfile" || mrc=$? ;;
          *)        MIXED_REASON="unrecognized mixed-file kind"; mrc=1 ;;
        esac
        if [ "$mrc" -ne 0 ] || [ ! -s "$tmpfile" ]; then
          echo "  manual review needed (mixed file malformed — ${MIXED_REASON:-shape could not be validated}): $rel"
          MANUAL=$((MANUAL+1))
        else
          echo "--- diff: $rel (project vs proposed merge) ---"
          diff "$rel" "$tmpfile" || true
          if [ "$DRY_RUN" -eq 1 ]; then
            echo "  (dry-run) would merge: $rel"
            UPDATED=$((UPDATED+1))
          elif confirm "$(mixed_merge_prompt "$rel" "$kind")"; then
            mkdir -p "$(dirname "$rel")"
            if cp_err="$(cp "$tmpfile" "$rel" 2>&1 >/dev/null)"; then
              is_shipped_script "$rel" && chmod +x "$rel"
              [ "$kind" = "hs_lib" ] && refresh_high_stakes_default "$toolkitfile"
              echo "  merged: $rel"
              UPDATED=$((UPDATED+1))
            else
              echo "  FAILED: $rel${cp_err:+ ($cp_err)}" >&2
              FAILED=$((FAILED+1))
            fi
          else
            echo "  skipped (declined mixed merge): $rel"
            SKIPPED=$((SKIPPED+1))
          fi
        fi
        rm -f "$tmpfile"
        ;;
      unknown)
        # M6: an unclassified file (e.g. .claude/settings.json) is never written, but since we only
        # reach here when it DIFFERS from the toolkit's, SHOW the diff so the drift is visible for a
        # manual merge decision (informational only — nothing is written).
        echo "--- diff: $rel (project vs toolkit — informational only, never written) ---"
        diff "$rel" "$toolkitfile" || true
        echo "  manual review needed (unclassified): $rel"
        MANUAL=$((MANUAL+1))
        ;;
    esac
  else
    case "$tier" in
      overwrite)
        if ci_not_opted_in "$rel"; then
          echo "  skipped (CI not opted in — run install.sh --with-ci, then re-sync): $rel"
          SKIPPED=$((SKIPPED+1))
        elif [ "$DRY_RUN" -eq 1 ]; then
          echo "  (dry-run) would add: $rel"
          UPDATED=$((UPDATED+1))
        elif should_apply "Add new file '$rel' from the toolkit?"; then
          mkdir -p "$(dirname "$rel")"
          if cp_err="$(cp "$toolkitfile" "$rel" 2>&1 >/dev/null)"; then
            is_shipped_script "$rel" && chmod +x "$rel"
            echo "  added: $rel"
            UPDATED=$((UPDATED+1))
          else
            echo "  FAILED: $rel${cp_err:+ ($cp_err)}" >&2
            FAILED=$((FAILED+1))
          fi
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
        echo "  manual review needed (mixed file, not present in project — install or merge by hand): $rel"
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
echo "  failed:           $FAILED"

# A run with ANY FAILED copy must exit nonzero — checked BEFORE the version stamp below, so a
# failed run never bumps the stamp (that would claim the project is current with a toolkit
# version it demonstrably didn't fully receive). A clean run where everything was simply declined
# still stamps below: nothing failed, so the project's still-honestly-at-that-version.
if [ "$FAILED" -gt 0 ]; then
  echo "" >&2
  echo "sync: ⛔ $FAILED file(s) failed to copy — see FAILED lines above." >&2
  exit 1
fi

# Stamp the synced-to VERSION (mirrors install.sh:139's write) after a successful non-dry run.
# VERSION lives at the repo root, next to the jaimitos-os/ scaffold dir (one level above
# --toolkit). Tolerate its absence, same as install.sh.
if [ "$DRY_RUN" -eq 0 ]; then
  TOOLKIT_VERSION="$(cat "$TOOLKIT/../VERSION" 2>/dev/null || echo '?')"
  mkdir -p .claude && printf '%s\n' "$TOOLKIT_VERSION" > .claude/.jaimitos-os-version 2>/dev/null || true
fi

exit 0
