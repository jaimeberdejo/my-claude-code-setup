#!/usr/bin/env bash
# _high-stakes.sh — SHARED high-stakes path list + matcher (sourced, not a hook).
# Single source of truth for which paths are "high-stakes" (auth / money /
# migrations / deletes / external side effects). Used by scripts/autopilot.sh to
# REFUSE to auto-commit/tick a phase whose diff touches these paths unattended,
# and kept in sync with .claude/rules/high-stakes.md.
#
# Matching is done with grep -E (NOT shell `case`) so it behaves identically
# whether this file is sourced under bash or zsh. Edit HIGH_STAKES_RE to match
# YOUR project's sensitive paths.
#
# Segment keywords match as a path segment ((^|/)kw(/|$)) — `auth[a-z]*` covers
# auth/authentication/authorization. The loose substrings (delete/email/deploy/…)
# match ANYWHERE in the path. The gate fails SAFE when over-broad (a false hit just
# forces supervised review), so this list is intentionally generous — better to stop
# on a benign `discharge.py` than to miss a real `refund` path. Edit it for YOUR repo.
HIGH_STAKES_RE='(^|/)(auth[a-z]*|oauth|login|sessions?|accounts?|payments|billing|transactions|migrations|compliance|suitability|secrets|kyc|wallet|ledger)(/|$)|migration|money|payment|credential|delete|deletion|destroy|email|deploy|refund|withdraw|charge|webhook'

# high_stakes_match <newline-separated-paths>
#   Echoes the matching paths; returns 0 if any matched, 1 if none.
high_stakes_match() {
  local matched
  matched=$(printf '%s\n' "$1" | grep -Ei "$HIGH_STAKES_RE" 2>/dev/null)
  if [ -n "$matched" ]; then printf '%s\n' "$matched"; return 0; fi
  return 1
}

return 0 2>/dev/null || exit 0
