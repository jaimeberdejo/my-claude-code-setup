#!/usr/bin/env bash
# check-plan-freshness.sh — deterministic staleness signals for a phase plan, so a plan is never executed
# silently against a repository that has moved on since it was written. Structure/temporal facts only;
# whether a change MATTERS stays the planner's `## Assumption revalidation` section + a fresh PLAN_CHECK.
#
# It answers, deterministically: is the plan's baseline still an ancestor of HEAD? do the files the plan
# names still exist, and have any of them changed since the baseline? do the REQ/AC/OBJ ids the plan
# cites still resolve in docs/SPEC.md? A "hard" staleness (baseline diverged, an
# invalid baseline, or a cited id vanished) fails under --strict — the plan may NOT keep a prior PASS.
# A "soft" signal (a referenced file missing or merely changed) is surfaced for revalidation but does not
# fail — path roots vary across plans and a moved file may be corrected in the plan with a note.
#
# Usage: bash scripts/check-plan-freshness.sh [--strict] [--base <commit>] <plan-file>
#   Baseline resolution: --base wins; else the plan's own "Plan created at: <sha>" / "Baseline: <sha>" line.
set -uo pipefail
NL=$'\n'   # newline literal, for pipe-free membership tests (see the referenced-files loop)
STRICT=0; BASE=""; PLAN=""
# `shift 2` with one arg left is a POSIX no-op returning 1, and there is no `set -e` — `--base` with
# no value spun forever. An unknown -flag must not fall into the catch-all and be read as the plan path.
while [ "$#" -gt 0 ]; do case "$1" in
  -h|--help) sed -n '2,14p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
  --strict) STRICT=1; shift ;;
  --base) [ "$#" -ge 2 ] || { echo "check-plan-freshness: --base needs a value (see --help)" >&2; exit 2; }; BASE="$2"; shift 2 ;;
  -*) echo "check-plan-freshness: unknown flag: $1 (see --help)" >&2; exit 2 ;;
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
  # The label may be "Plan created at:", "Baseline:" or "Baseline commit:" — all three are used in
  # the wild. The old skip class [^0-9a-f]* could
  # not cross the "c" of "commit" (c is a hex digit), so "Baseline commit: <sha>" never matched and
  # freshness silently fell back to "undetermined" (a soft signal, exit 0). Allow any non-hex-or-space
  # run, then require a word-boundaried sha.
  BASE=$(grep -oiE '(plan created at|baseline( commit)?)[^0-9a-f]*[0-9a-f]{7,40}' "$PLAN" 2>/dev/null \
         | grep -oiE '[0-9a-f]{7,40}$' | head -1 || true)
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
    # Membership test WITHOUT a pipe. `printf "$CHANGED" | grep -qxF` looks equivalent and is not:
    # grep -q exits at the first match, printf then takes SIGPIPE once CHANGED exceeds the 64KB pipe
    # buffer, and `pipefail` promotes 141 over grep's 0 — so the condition reads FALSE and the file is
    # silently reported UNCHANGED. It fires exactly when the changed-set is large and the match sorts
    # early, i.e. on the big long-lived repos this check exists for. An interactive probe cannot see it
    # (interactive bash ignores SIGPIPE for builtins); in a real script it was 10/10 fail-open.
    elif [ -n "$CHANGED" ] && case "${NL}${CHANGED}${NL}" in *"${NL}${f}${NL}"*) true ;; *) false ;; esac; then
      soft "referenced file changed since planning: $f — revalidate the assumptions that rest on it"
    fi
  done <<EOF
$FILES
EOF
fi

# --- referenced ids (REQ/AC/OBJ resolve in SPEC) -----------------------------
# "A removed cited id" is one of the three HARD blockers, so this must fail CLOSED. Two ways it used
# to fail open: (1) `if [ -f "$tgt" ]` skipped the check entirely when the target was absent — so
# DELETING docs/SPEC.md, the most complete form of "the requirement was removed", produced a
# maximally confident all-clear; (2) $tgt was a CWD-relative literal, so the same plan passed from a
# subdirectory and failed from the root. Resolve from the repo root, and treat unverifiable as unverified.
# ENF-### ids are gone with the enforcement ledger (v2.15.0): that branch could never resolve, because
# docs/ENFORCEMENT.md had no producer in any repo — it was dead code that only ever skipped.
ROOT=$(git rev-parse --show-toplevel 2>/dev/null || printf '.')
IDS=$(grep -oE '\b(REQ|AC|OBJ)-[0-9]{3}\b' "$PLAN" 2>/dev/null | sort -u || true)
if [ -n "$IDS" ]; then
  while IFS= read -r id; do
    [ -n "$id" ] || continue
    rel="docs/SPEC.md"
    tgt="$ROOT/$rel"
    if [ -f "$tgt" ]; then
      grep -qF "$id" "$tgt" || bad "plan cites $id but it no longer resolves in $rel (removed or superseded)"
    else
      bad "plan cites $id but $rel does not exist — the id cannot be resolved (unverifiable is not verified)"
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
