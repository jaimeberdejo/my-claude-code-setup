#!/usr/bin/env bash
# plan-review-route.sh — deterministic, inspectable routing for the /phase plan gate (v2.16.0).
#
# PURPOSE
#   Decide, deterministically and visibly, whether a phase's plan needs the full independent Evaluator
#   PLAN_CHECK, a lighter deterministic-only review, or none. Clear low-risk STANDARD work is not taxed
#   with a full agent review; RISKY work still gets it; DEEP and supervised always get it; and a
#   false / stale / invalid `tier:` can never silently buy less rigor. This script NEVER ticks, grades,
#   or edits, and emits NO gradeable token — its output is a routing decision, not a verdict on the
#   record-grade.sh channel. It does not recommend a tier or restate classify-work.sh's "Required
#   workflow" text: classify-work.sh owns tier->workflow at authoring time; this owns gate routing at 4b.
#
# CONTRACT
#   Usage: plan-review-route.sh --plan <plan-file> [--spec <spec-file>] [--heading <text>]
#                               [--tier <TINY|STANDARD|DEEP>] [--supervised]
#                               [--override <full|deterministic|skip>] [--reason <text>]
#   Reads the persisted tier from <spec-file> frontmatter (default docs/SPEC.md) unless --tier is given.
#   Composes the SHARED risk detectors — never reimplements them:
#     * .claude/lib/_high-stakes.sh  high_stakes_match   (path/keyword risk; rc 0 hit / 1 clean / 2 error)
#     * scripts/check-plan-freshness.sh --strict          (hard-stale plan -> exit 1)
#     * a grep for a BLOCKING [NEEDS CLARIFICATION] placeholder in the plan / spec
#   .claude/lib/_test-cmd.sh is consulted only as an ADVISORY "verification strategy exists" note inside
#   the deterministic path — it is a project-level config, NOT a per-phase routing-depth signal.
#   Prints a "## Plan review routing" block (Selected tier / Risk signals / Plan review / Reason /
#   Override / Supervised) and a final machine-readable line: ROUTE=<FULL_PLAN_CHECK|DETERMINISTIC_ONLY|SKIP>.
#   Exit codes:  10 = FULL_PLAN_CHECK required (caller MUST dispatch the evaluator in PLAN_CHECK mode)
#                 0 = SKIP or DETERMINISTIC_ONLY (no evaluator dispatch)
#                 2 = usage error
#
# ROUTE TABLE (fail-safe: when in doubt, FULL)
#   invalid tier value                    -> FULL   (never reward a bad tier with less review)
#   DEEP                                  -> FULL
#   supervised (--supervised)             -> FULL   (+ Supervised: YES)
#   any high-stakes path named in plan    -> FULL   (+ Supervised: YES)  — overrides a false/stale TINY
#   hard-stale plan (freshness --strict)  -> FULL
#   blocking [NEEDS CLARIFICATION]        -> FULL
#   STANDARD, none of the above           -> DETERMINISTIC_ONLY
#   TINY, none of the above               -> SKIP
#
# THE rc-2 TRAP (finding H4). high_stakes_match returns rc 2 when HIGH_STAKES_RE does not compile.
# `x=$(high_stakes_match ...)` in an `if` collapses rc 2 into the same falsy branch as rc 1 (clean) and
# would silently disable the gate. We read $? on its own line and treat rc 2 as a CLOSED failure -> FULL.
set -uo pipefail

usage() { sed -n '2,44p' "$0" | sed 's/^# \{0,1\}//'; }

PLAN=""; SPEC="docs/SPEC.md"; HEADING=""; TIER_OVERRIDE=""; SUPERVISED=0; OV=""; REASON=""
need_val() { [ "$2" -ge 2 ] || { echo "plan-review-route: $1 needs a value (see --help)" >&2; exit 2; }; }
while [ "$#" -gt 0 ]; do case "$1" in
  -h|--help)    usage; exit 0 ;;
  --plan)       need_val "$1" "$#"; PLAN="$2"; shift 2 ;;
  --spec)       need_val "$1" "$#"; SPEC="$2"; shift 2 ;;
  --heading)    need_val "$1" "$#"; HEADING="$2"; shift 2 ;;
  --tier)       need_val "$1" "$#"; TIER_OVERRIDE="$2"; shift 2 ;;
  --override)   need_val "$1" "$#"; OV="$2"; shift 2 ;;
  --reason)     need_val "$1" "$#"; REASON="$2"; shift 2 ;;
  --supervised) SUPERVISED=1; shift ;;
  -*) echo "plan-review-route: unknown flag: $1 (see --help)" >&2; exit 2 ;;
  *)  echo "plan-review-route: unexpected argument: $1 (see --help)" >&2; exit 2 ;;
esac; done

[ -n "$PLAN" ] || { echo "plan-review-route: --plan <plan-file> is required (see --help)." >&2; exit 2; }
[ -f "$PLAN" ] || { echo "plan-review-route: no such plan file: $PLAN" >&2; exit 2; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# --- persisted tier, validated fail-safe -----------------------------------
read_spec_tier() {
  [ -f "$SPEC" ] || { printf 'UNSET'; return 0; }
  local raw
  raw=$(grep -m1 -E '^[[:space:]]*tier:' "$SPEC" 2>/dev/null | sed -E 's/^[[:space:]]*tier:[[:space:]]*//; s/#.*$//')
  raw="${raw#"${raw%%[![:space:]]*}"}"; raw="${raw%"${raw##*[![:space:]]}"}"   # trim
  [ -n "$raw" ] && printf '%s' "$raw" || printf 'UNSET'
}
RAW_TIER="${TIER_OVERRIDE:-$(read_spec_tier)}"
TIER_VALID=1
case "$RAW_TIER" in
  TINY|STANDARD|DEEP) TIER="$RAW_TIER" ;;
  UNSET|'')           TIER="STANDARD" ;;                # documented default (SPEC template: "Empty = STANDARD")
  *)                  TIER="STANDARD"; TIER_VALID=0 ;;  # garbage -> fail-safe STANDARD + full review
esac

# --- high-stakes risk probe over the plan's declared paths -----------------
# Guarantee scope (kept honest, per the guarantee table): this is deterministic over the tier + the
# paths the plan DECLARES, not over the implementation (no code exists yet at 4b). Extracting paths from
# the whole plan is deliberately OVER-inclusive — high-stakes fails toward FULL, never toward SKIP.
HS_SIGNAL=0
if [ -f .claude/lib/_high-stakes.sh ] && . .claude/lib/_high-stakes.sh 2>/dev/null \
   && command -v high_stakes_match >/dev/null 2>&1; then
  PLAN_PATHS=$(grep -oE '[A-Za-z0-9_.-]+(/[A-Za-z0-9_.-]+)+|[A-Za-z0-9_-]+\.(py|ts|tsx|js|jsx|go|rs|rb|java|kt|c|cc|cpp|h|hpp|sql|sh|md|json|ya?ml|toml|env)' "$PLAN" 2>/dev/null | sort -u)
  if [ -n "$PLAN_PATHS" ]; then
    high_stakes_match "$PLAN_PATHS" >/dev/null; HS_RC=$?     # read rc on its own line — NOT inside an `if`
    case "$HS_RC" in
      0) HS_SIGNAL=1 ;;   # a declared path is high-stakes
      2) HS_SIGNAL=1 ;;   # HIGH_STAKES_RE does not compile -> fail CLOSED
      *) : ;;             # rc 1 -> clean
    esac
  fi
else
  HS_SIGNAL=1   # the high-stakes lib is unavailable -> cannot rule out risk -> fail CLOSED
fi

# --- plan freshness (hard-stale only) --------------------------------------
FRESH_SIGNAL=0
if [ -f "$SCRIPT_DIR/check-plan-freshness.sh" ]; then
  bash "$SCRIPT_DIR/check-plan-freshness.sh" --strict "$PLAN" >/dev/null 2>&1 || FRESH_SIGNAL=1
fi

# --- blocking clarification -------------------------------------------------
CLARIFY_SIGNAL=0
grep -qiE '\[NEEDS CLARIFICATION\]' "$PLAN" 2>/dev/null && CLARIFY_SIGNAL=1
[ -f "$SPEC" ] && grep -qiE '\[NEEDS CLARIFICATION\]' "$SPEC" 2>/dev/null && CLARIFY_SIGNAL=1

# --- assemble signals + base route -----------------------------------------
SIGNALS=""
add_sig() { SIGNALS="${SIGNALS:+$SIGNALS, }$1"; }
[ "$HS_SIGNAL" = 1 ]      && add_sig "high-stakes path"
[ "$FRESH_SIGNAL" = 1 ]   && add_sig "plan hard-stale"
[ "$CLARIFY_SIGNAL" = 1 ] && add_sig "blocking [NEEDS CLARIFICATION]"
[ "$TIER_VALID" = 0 ]     && add_sig "invalid tier value '$RAW_TIER'"
[ "$SUPERVISED" = 1 ]     && add_sig "supervised"

FORCE_FULL=0
[ "$HS_SIGNAL" = 1 ]      && FORCE_FULL=1
[ "$FRESH_SIGNAL" = 1 ]   && FORCE_FULL=1
[ "$CLARIFY_SIGNAL" = 1 ] && FORCE_FULL=1
[ "$TIER_VALID" = 0 ]     && FORCE_FULL=1
[ "$SUPERVISED" = 1 ]     && FORCE_FULL=1
[ "$TIER" = DEEP ]        && FORCE_FULL=1

if [ "$FORCE_FULL" = 1 ]; then ROUTE="FULL_PLAN_CHECK"
elif [ "$TIER" = TINY ];  then ROUTE="SKIP"
else                           ROUTE="DETERMINISTIC_ONLY"; fi

SUP_OUT="NO"; { [ "$SUPERVISED" = 1 ] || [ "$HS_SIGNAL" = 1 ]; } && SUP_OUT="YES"

# --- override (stronger always allowed; weaker never for high-stakes/supervised) ---
OVERRIDE_LINE="NO"
if [ -n "$OV" ]; then
  case "$OV" in
    full|FULL) ROUTE="FULL_PLAN_CHECK" ;;
    deterministic|DETERMINISTIC)
      if [ "$HS_SIGNAL" = 1 ] || [ "$SUPERVISED" = 1 ]; then
        OVERRIDE_LINE="YES — REFUSED: high-stakes/supervised work requires full independent review"; ROUTE="FULL_PLAN_CHECK"
      else ROUTE="DETERMINISTIC_ONLY"; fi ;;
    skip|SKIP)
      if [ "$HS_SIGNAL" = 1 ] || [ "$SUPERVISED" = 1 ]; then
        OVERRIDE_LINE="YES — REFUSED: high-stakes/supervised work requires full independent review"; ROUTE="FULL_PLAN_CHECK"
      else ROUTE="SKIP"; fi ;;
    *) echo "plan-review-route: --override must be full|deterministic|skip" >&2; exit 2 ;;
  esac
  if [ "$OVERRIDE_LINE" = NO ]; then
    if [ -n "$REASON" ]; then OVERRIDE_LINE="YES — reason: $REASON"; else OVERRIDE_LINE="YES — reason: MISSING"; fi
  fi
fi

# --- human-readable reason + review label ----------------------------------
case "$ROUTE" in
  FULL_PLAN_CHECK)
    REVIEW_TXT="full Evaluator PLAN_CHECK"
    if [ "$TIER" = DEEP ]; then RSN="DEEP tier always runs the independent plan review"
    elif [ -n "$SIGNALS" ]; then RSN="risk signal present: $SIGNALS"
    else RSN="override to stronger review"; fi ;;
  DETERMINISTIC_ONLY)
    REVIEW_TXT="deterministic checks only — independent PLAN_CHECK skipped"
    RSN="clear low-risk STANDARD: no high-stakes path, plan fresh, no blocking clarification" ;;
  SKIP)
    REVIEW_TXT="skipped (TINY, no risk signal)"
    RSN="TINY tier and no high-stakes / supervised signal" ;;
esac

# --- visible decision block ------------------------------------------------
echo "## Plan review routing"
[ -n "$HEADING" ] && echo "Phase: $HEADING"
if [ "$TIER_VALID" = 0 ]; then
  echo "Selected tier: $TIER  (declared '$RAW_TIER' is invalid -> STANDARD, full review)"
else
  echo "Selected tier: $TIER"
fi
echo "Risk signals: ${SIGNALS:-none}"
echo "Plan review: $REVIEW_TXT"
echo "Reason: $RSN"
echo "Override: $OVERRIDE_LINE"
echo "Supervised: $SUP_OUT"

if [ "$ROUTE" = DETERMINISTIC_ONLY ]; then
  echo ""
  echo "Deterministic checks (stand in for the independent review):"
  echo "  [ok] plan file exists"
  echo "  [ok] baseline valid, not hard-stale, cited ids resolve (check-plan-freshness --strict)"
  echo "  [ok] no high-stakes path declared in the plan"
  echo "  [ok] no blocking [NEEDS CLARIFICATION]"
  if [ -f .claude/lib/_test-cmd.sh ] && . .claude/lib/_test-cmd.sh 2>/dev/null \
     && command -v authorized_test_cmd >/dev/null 2>&1; then
    authorized_test_cmd >/dev/null 2>&1; TC_RC=$?
    case "$TC_RC" in
      0) echo "  [ok] verification strategy: a test command is configured" ;;
      1) echo "  [ok] verification strategy: phase explicitly declared test-less (none:)" ;;
      *) echo "  [warn] no authorized test command configured — set .claude/test-command so the light path has a real verifier" ;;
    esac
  fi
fi

echo ""
echo "ROUTE=$ROUTE"
case "$ROUTE" in
  FULL_PLAN_CHECK) exit 10 ;;
  *) exit 0 ;;
esac
