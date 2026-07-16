#!/usr/bin/env bash
# check-plan-freshness.sh — deterministic staleness signals for a phase plan, so a plan is never executed
# silently against a repository that has moved on since it was written. Structure/temporal facts only;
# whether a change MATTERS stays the planner's `## Assumption revalidation` section + a fresh PLAN_CHECK.
#
# It answers, deterministically: is the plan's baseline still an ancestor of HEAD? do the files the plan
# names still exist, and have any of them changed since the baseline? do the REQ/AC/OBJ/ENF ids the plan
# cites still resolve in docs/SPEC.md / docs/ENFORCEMENT.md? A "hard" staleness (baseline diverged, an
# invalid baseline, or a cited id vanished) fails under --strict — the plan may NOT keep a prior PASS.
# A "soft" signal (a referenced file missing or merely changed) is surfaced for revalidation but does not
# fail — path roots vary across plans and a moved file may be corrected in the plan with a note.
#
# Usage: bash scripts/check-plan-freshness.sh [--strict] [--base <commit>] <plan-file>
#   Baseline resolution: --base wins; else the plan's own "Plan created at: <sha>" / "Baseline: <sha>" line.
set -uo pipefail
STRICT=0; BASE=""; PLAN=""
while [ "$#" -gt 0 ]; do case "$1" in
  -h|--help) sed -n '2,14p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
  --strict) STRICT=1; shift ;;
  --base) BASE="${2:-}"; shift 2 ;;
  *) PLAN="$1"; shift ;;
esac; done
[ -n "$PLAN" ] || { echo "check-plan-freshness: no plan file given (see --help)." >&2; exit 2; }
[ -f "$PLAN" ] || { echo "check-plan-freshness: no such plan file: $PLAN" >&2; exit 2; }
git rev-parse --is-inside-work-tree >/dev/null 2>&1 || { echo "check-plan-freshness: not a git repo — freshness undetermined."; exit 0; }

miss=0; warn=0
bad()  { printf '  ! %s\n' "$1"; miss=$((miss+1)); }
soft() { printf '  ~ %s\n' "$1"; warn=$((warn+1)); }

# --- baseline ---------------------------------------------------------------
if [ -z "$BASE" ]; then
  BASE=$(grep -oiE '(plan created at|baseline)[^0-9a-f]*[0-9a-f]{7,40}' "$PLAN" 2>/dev/null \
         | grep -oiE '[0-9a-f]{7,40}' | head -1 || true)
fi
CHANGED=""
if [ -n "$BASE" ]; then
  if git rev-parse --verify --quiet "${BASE}^{commit}" >/dev/null 2>&1; then
    if git merge-base --is-ancestor "$BASE" HEAD 2>/dev/null; then
      CHANGED=$(git diff --name-only "$BASE" HEAD 2>/dev/null || true)
    else
      bad "baseline $BASE is no longer an ancestor of HEAD (rebased or diverged) — revalidate the plan"
    fi
  else
    bad "recorded baseline '$BASE' is not a valid commit in this repo"
  fi
else
  soft "no baseline recorded in the plan (add a 'Plan created at: <sha>' line) — freshness is undetermined"
fi

# --- referenced files (backtick-quoted, path-shaped) ------------------------
# Extract `path` tokens that look like real repo paths (contain a slash or a dotted extension).
FILES=$(grep -oE '`[A-Za-z0-9_.][A-Za-z0-9_./-]*`' "$PLAN" 2>/dev/null \
        | tr -d '`' \
        | grep -E '(/|\.[A-Za-z0-9]+$)' \
        | grep -vE '^(https?:|-)' \
        | sort -u || true)
if [ -n "$FILES" ]; then
  while IFS= read -r f; do
    [ -n "$f" ] || continue
    case "$f" in */) continue ;; esac                 # skip bare directories with trailing slash
    if [ ! -e "$f" ]; then
      # A missing referenced file is a SOFT signal only, and only for a PATH-shaped reference (contains a
      # "/"). A plan mentions many files it does not strictly depend on, and path roots vary (a plan may
      # cite `scripts/x.sh` relative to a subdir); the spec itself says a moved file may be corrected in
      # the plan with a note. So we surface it for revalidation but never block on it — the hard blockers
      # are baseline-ancestry, an invalid baseline, and a removed cited id.
      # (Dogfood finding v2.14.0: hard-flagging file existence produced dozens of false positives on a
      # real dev plan; demoted to soft.)
      case "$f" in
        */*) soft "referenced file not found (moved? path root differs?): $f — revalidate" ;;
      esac
    elif [ -n "$CHANGED" ] && printf '%s\n' "$CHANGED" | grep -qxF "$f"; then
      soft "referenced file changed since planning: $f — revalidate the assumptions that rest on it"
    fi
  done <<EOF
$FILES
EOF
fi

# --- referenced ids (REQ/AC/OBJ resolve in SPEC; ENF resolves in ENFORCEMENT) ---
IDS=$(grep -oE '\b(REQ|AC|OBJ|ENF)-[0-9]{3}\b' "$PLAN" 2>/dev/null | sort -u || true)
if [ -n "$IDS" ]; then
  while IFS= read -r id; do
    [ -n "$id" ] || continue
    case "$id" in
      ENF-*) tgt="docs/ENFORCEMENT.md" ;;
      *)     tgt="docs/SPEC.md" ;;
    esac
    if [ -f "$tgt" ]; then
      grep -qF "$id" "$tgt" || bad "plan cites $id but it no longer resolves in $tgt (removed or superseded)"
    fi
  done <<EOF
$IDS
EOF
fi

# --- report -----------------------------------------------------------------
if [ "$miss" -eq 0 ] && [ "$warn" -eq 0 ]; then
  echo "check-plan-freshness: no staleness signals — plan assumptions still hold deterministically."
  exit 0
fi
[ "$miss" -gt 0 ] && echo "check-plan-freshness: $miss hard staleness signal(s) above."
[ "$warn" -gt 0 ] && echo "check-plan-freshness: $warn soft signal(s) above (revalidate; not a hard fail)."
if [ "$STRICT" -eq 1 ] && [ "$miss" -gt 0 ]; then
  echo "check-plan-freshness: plan is stale (--strict) — it may not keep a prior PASS; return it to the planner."
  exit 1
fi
exit 0
