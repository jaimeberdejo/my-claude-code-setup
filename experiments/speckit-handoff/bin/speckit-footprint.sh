#!/usr/bin/env bash
# speckit-footprint.sh — ownership-aware check of what Spec Kit actually installed.
#
# The naive rule — "after `specify init`, nothing but speckit-* may change" — is wrong twice:
#   - `.claude/skills/speckit-*/` is SUPPOSED to appear. That is the integration working, not a
#     collision. A name-only check fires on the thing succeeding.
#   - The Claude integration is multi_install_safe and its documented footprint includes an
#     agent-context file (CLAUDE.md). Auto-rejecting it rejects correct, documented behavior.
#
# So this compares OWNERS, not names:
#     same path + same owner      → expected
#     same path + different owner → COLLISION
# Both toolkits publish a manifest. Spec Kit records what it wrote in
# .specify/integrations/speckit.manifest.json; install.sh records the sha256 of every toolkit-owned
# file in .claude/.jaimitos-manifest. We cross-check them, and fail closed if either is missing —
# "I could not verify ownership" must never read as "ownership is fine".
#
# Exit: 0 clean · 1 violation · 2 usage
set -uo pipefail

usage() {
  cat <<'EOF'
usage: speckit-footprint.sh --project <dir> --manifest <footprint.json> --snapshot <file>
       speckit-footprint.sh --project <dir> --manifest <footprint.json> --baseline <file>

  The check is DIFFERENTIAL, and it has to be: "forbidden" means Spec Kit must not WRITE
  docs/ROADMAP.md — not that docs/ROADMAP.md may not exist. It exists before Spec Kit ever runs.
  So: snapshot BEFORE `specify init`, check AFTER, and classify only what actually CHANGED.

    --snapshot <file>   record path + sha256 of every file (run before `specify init`)
    --baseline <file>   check against that snapshot (run after)

  Every ADDED or MODIFIED path is classified against the pinned footprint:
    expected_owned_patterns  must also be claimed by Spec Kit's own manifest
    conditionally_modified   reported for a human to classify, never auto-rejected
    forbidden                Jaimitos state — any write is a violation
    jaimitos-owned           sha256 must still match .claude/.jaimitos-manifest

  Also MEASURES the always-loaded context cost of Spec Kit's model-invoked skills (REJECT
  criterion R1) — a cost invisible to Jaimitos's own budget check.

exit: 0 clean · 1 violation · 2 usage
EOF
}

PROJECT=""; MANIFEST=""; SNAPSHOT=""; BASELINE=""
while [ $# -gt 0 ]; do
  case "$1" in
    --project)  PROJECT="${2:-}";  shift 2 || exit 2 ;;
    --manifest) MANIFEST="${2:-}"; shift 2 || exit 2 ;;
    --snapshot) SNAPSHOT="${2:-}"; shift 2 || exit 2 ;;
    --baseline) BASELINE="${2:-}"; shift 2 || exit 2 ;;
    -h|--help)  usage; exit 0 ;;
    *) echo "speckit-footprint: unknown argument '$1' (try --help)" >&2; exit 2 ;;
  esac
done
[ -n "$PROJECT" ] && [ -n "$MANIFEST" ] || { echo "speckit-footprint: --project and --manifest are required (try --help)" >&2; exit 2; }
[ -d "$PROJECT" ]  || { echo "speckit-footprint: no such project: $PROJECT" >&2; exit 2; }
[ -f "$MANIFEST" ] || { echo "speckit-footprint: no such footprint manifest: $MANIFEST" >&2; exit 2; }
command -v jq >/dev/null 2>&1 || { echo "speckit-footprint: jq is required" >&2; exit 2; }
[ -n "$SNAPSHOT" ] || [ -n "$BASELINE" ] || { echo "speckit-footprint: one of --snapshot or --baseline is required (try --help)" >&2; exit 2; }

hash_of() { shasum -a 256 "$1" 2>/dev/null | cut -d' ' -f1 || sha256sum "$1" 2>/dev/null | cut -d' ' -f1; }
walk()    { ( cd "$PROJECT" && find . -type f | sed 's|^\./||' | grep -vE '^(\.git/|\.speckit-handoff/)' | sort ); }

# --- snapshot mode: record the world as it was, then get out of the way ------------------------
if [ -n "$SNAPSHOT" ]; then
  : > "$SNAPSHOT" || { echo "speckit-footprint: cannot write $SNAPSHOT" >&2; exit 2; }
  while IFS= read -r rel; do
    [ -n "$rel" ] || continue
    printf '%s  %s\n' "$(hash_of "$PROJECT/$rel")" "$rel" >> "$SNAPSHOT"
  done < <(walk)
  echo "speckit-footprint: snapshot of $(wc -l < "$SNAPSHOT" | tr -d ' ') file(s) → $SNAPSHOT"
  echo "speckit-footprint: now run \`specify init\`, then re-run with --baseline $SNAPSHOT"
  exit 0
fi

[ -f "$BASELINE" ] || { echo "speckit-footprint: no such baseline: $BASELINE (take one with --snapshot BEFORE \`specify init\`)" >&2; exit 2; }

VIOLATIONS=0
violate() { echo "  ⛔ $1"; VIOLATIONS=$((VIOLATIONS+1)); }
note()    { echo "  · $1"; }

SK_MANIFEST_REL=$(jq -r '.spec_kit_manifest' "$MANIFEST")
JM_MANIFEST_REL=$(jq -r '.jaimitos_manifest' "$MANIFEST")
SK_MANIFEST="$PROJECT/$SK_MANIFEST_REL"
JM_MANIFEST="$PROJECT/$JM_MANIFEST_REL"

echo "speckit-footprint: $(jq -r '"spec-kit " + .spec_kit_version + " (" + .spec_kit_sha[0:12] + ") · integration=" + .integration' "$MANIFEST")"
echo ""

# ---- both manifests must exist. Fail CLOSED. --------------------------------------------------
echo "manifests:"
if [ -f "$SK_MANIFEST" ]; then
  note "spec-kit  → $SK_MANIFEST_REL"
else
  violate "spec-kit manifest MISSING ($SK_MANIFEST_REL) — ownership of every speckit-* path is unverifiable. Refusing to call that clean."
fi
if [ -f "$JM_MANIFEST" ]; then
  note "jaimitos  → $JM_MANIFEST_REL"
else
  violate "jaimitos manifest MISSING ($JM_MANIFEST_REL) — cannot prove our own files are intact. Refusing to call that clean."
fi
[ "$VIOLATIONS" -gt 0 ] && { echo ""; echo "speckit-footprint: REFUSED — $VIOLATIONS violation(s)."; exit 1; }

# What Spec Kit CLAIMS it wrote. Its schema is not contractual (upstream ships several releases a
# day), so we pull every path-like string out of the JSON rather than assuming a shape — and say so
# rather than pretending we know it.
#
# An UNPARSEABLE manifest must be its own error. Otherwise jq returns nothing, Spec Kit appears to
# claim nothing, and every one of its own files is reported as a collision — a confident, precise,
# entirely wrong answer.
if ! jq -e . "$SK_MANIFEST" >/dev/null 2>&1; then
  violate "spec-kit manifest is not valid JSON ($SK_MANIFEST_REL) — ownership is unverifiable. Refusing (this is NOT 'spec-kit claims nothing')."
  echo ""; echo "speckit-footprint: REFUSED — $VIOLATIONS violation(s)."; exit 1
fi
SK_OWNED=$(jq -r '.. | strings' "$SK_MANIFEST" 2>/dev/null | grep '/' | sort -u)

# ---- glob helpers (bash 3.2: `case` globbing, no extglob) -------------------------------------
matches_any() {   # matches_any <path> <newline-separated globs>
  local p="$1" g
  while IFS= read -r g; do
    [ -n "$g" ] || continue
    # shellcheck disable=SC2254
    case "$p" in $g|$g/*) return 0 ;; esac
  done <<EOF
$2
EOF
  return 1
}
OWNED_PATTERNS=$(jq -r '.expected_owned_patterns[]' "$MANIFEST")
FORBIDDEN=$(jq -r '.forbidden[]' "$MANIFEST")
CONDITIONAL=$(jq -r '.conditionally_modified[]' "$MANIFEST")

# ---- classify ONLY what changed ---------------------------------------------------------------
# Differential, deliberately. A file merely EXISTING says nothing: docs/ROADMAP.md is "forbidden"
# because Spec Kit must not WRITE it, not because it may not be there.
echo ""
echo "ownership (added or modified since the snapshot):"
SK_COUNT=0; UNCLAIMED=""; CHANGED=0
while IFS= read -r rel; do
  [ -n "$rel" ] || continue
  was=$(awk -v p="$rel" '$2 == p {print $1; exit}' "$BASELINE")
  now=$(hash_of "$PROJECT/$rel")
  [ "$was" = "$now" ] && continue        # untouched — not Spec Kit's doing, not our business
  CHANGED=$((CHANGED+1))

  # 1. A Jaimitos-owned file (per .jaimitos-manifest) that CHANGED. This is the hijack case.
  if awk -v p="$rel" '$2 == p {found=1} END {exit !found}' "$JM_MANIFEST" 2>/dev/null; then
    violate "MODIFIED a jaimitos-owned file: $rel  (sha256 no longer matches $JM_MANIFEST_REL)"
    continue
  fi

  # 2. Forbidden — Jaimitos state. A write here means Spec Kit has become a second orchestrator.
  if matches_any "$rel" "$FORBIDDEN"; then
    violate "wrote a FORBIDDEN path: $rel  (this is Jaimitos state — a REJECT, not a finding)"
    continue
  fi

  # 3. Conditionally modified — reported for a human, never auto-rejected. The Claude integration
  #    is multi_install_safe and documents an agent-context file; rejecting that rejects correct
  #    behavior. Reporting it silently would hide a real change to the file governing the project.
  if matches_any "$rel" "$CONDITIONAL"; then
    note "conditionally-modified — classify this diff by hand: $rel"
    continue
  fi

  # 4. Spec-Kit-owned? Must match the expected patterns AND be claimed by Spec Kit's own manifest.
  #    A speckit-*-looking file Spec Kit does NOT claim is the collision: same name, different owner.
  if matches_any "$rel" "$OWNED_PATTERNS"; then
    if printf '%s\n' "$SK_OWNED" | grep -qxF -- "$rel"; then
      SK_COUNT=$((SK_COUNT+1))
    else
      case "$rel" in
        specs/*|.specify/*) SK_COUNT=$((SK_COUNT+1)) ;;   # authored/derived content, not managed files
        *) UNCLAIMED="$UNCLAIMED $rel" ;;
      esac
    fi
    continue
  fi

  # 5. Unaccounted for.
  violate "unexpected new file, owned by nobody: $rel"
done < <(walk)

for u in $UNCLAIMED; do
  violate "looks Spec-Kit-owned but its manifest does NOT claim it: $u  (same name, different owner — the collision case)"
done
note "$CHANGED path(s) changed; spec-kit claims $SK_COUNT of them"

# Name the command surface it installed. A count is not a review — the whole point of pinning a
# footprint is that a human can see what actually landed and notice when the next release changes it.
SKILLS=""
for s in "$PROJECT"/.claude/skills/speckit-*/; do
  [ -d "$s" ] || continue
  SKILLS="$SKILLS $(basename "$s")"
done
[ -n "$SKILLS" ] && note "spec-kit command surface:$SKILLS"

# ---- R1 — the always-loaded context tax, MEASURED --------------------------------------------
# Spec Kit's Claude skills ship `disable-model-invocation: false`, so each description sits in the
# window every turn, forever, in the user's project. Jaimitos caps its OWN model-invoked
# descriptions at 6000 B — but that check iterates only the toolkit's skills/ and cannot see these.
echo ""
echo "always-loaded context (REJECT criterion R1 — measured, not estimated):"
SUM=0; N=0
for s in "$PROJECT"/.claude/skills/speckit-*/SKILL.md; do
  [ -f "$s" ] || continue
  grep -qE '^disable-model-invocation:[[:space:]]*true' "$s" && continue   # would cost zero
  # Take the first `description:` line, fenced or not. Depending on the --- fences being present
  # means a SKILL.md without them measures 0 B — silently, and in Spec Kit's favour.
  d=$(awk 'index($0,"description:")==1 {sub("^description:[[:space:]]*",""); print; exit}' "$s")
  b=$(printf '%s' "$d" | wc -c | tr -d ' ')
  SUM=$((SUM + b)); N=$((N + 1))
done
if [ "$N" -gt 0 ]; then
  note "$N model-invoked speckit-* skill(s): ${SUM}B of description, loaded EVERY TURN (~$((SUM / 4)) tokens)"
  note "invisible to jaimitos-os/scripts/test-skills.sh check 6 (it iterates only the toolkit's skills/)"
  note "there is no supported way to exclude a Spec Kit core command — this cost is not opt-out-able"
else
  note "no model-invoked speckit-* skills found (nothing always-loaded)"
fi

echo ""
if [ "$VIOLATIONS" -eq 0 ]; then echo "speckit-footprint: clean — Spec Kit stayed inside its own footprint."; exit 0
else echo "speckit-footprint: REFUSED — $VIOLATIONS violation(s)."; exit 1; fi
