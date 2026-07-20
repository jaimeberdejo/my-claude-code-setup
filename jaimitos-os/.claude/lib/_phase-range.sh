#!/usr/bin/env bash
# _phase-range.sh — SHARED, read-only phase-range resolver (sourced, not a hook).
#
# THE single precedence + validation for "which BASE..HEAD window is this phase". Before v2.17 the
# precedence lived inline in tick.sh while the manual evaluator diffed a DIFFERENT file
# (.claude/.phase-base), so the independent review, the evidence, the secret/high-stakes scan and the
# tick could each judge a different range. This resolver is the one implementation every consumer shares
# (scripts/tick.sh, scripts/phase-range.sh, record-grade.sh, test-evidence.sh, the evaluator, /wrap), so
# they all judge the SAME phase.
#
# Precedence (identical to tick.sh's historical logic):
#   • TICK_BASE env SET → the orchestrator (headless scripts/autopilot.sh) derived this base in its OWN
#     trusted shell, OUTSIDE the builder. Use it and NEVER fall back to the builder-writable file — a bad
#     trusted env must fail closed, not silently degrade to the untrusted .claude/.phase-base.
#   • .claude/.phase-anchor present → manual mode: the TRACKED, tamper-evident anchor authored by
#     scripts/start-phase.sh (its base= lives in committed history; advancing it is a visible commit).
#   • else → .claude/.phase-base (legacy gitignored manual floor).
# All sources are strict-ancestor-validated; the anchor path additionally requires the anchor-setting
# commit's parent to equal base= (the "naive narrowing is REFUSED" bar). This is NOT builder-PROOF for
# manual mode (a builder with arbitrary git can reset+re-anchor) — that is why HEADLESS derives the base
# outside the builder (TICK_BASE). Same honest scope as before; only the location changed.
#
# resolve_phase_range [heading]
#   Sets on success: PR_HEADING PR_BASE PR_BASE_SHA PR_HEAD PR_RANGE PR_SOURCE PR_ANCHOR_USED
#   Returns:  0 success
#             1 base cannot be resolved/validated — fail closed (PR_ERR carries the reason)
#             3 anchor base-integrity narrowing detected — supervised review (PR_ERR carries the reason)
#   Never calls exit and never prints — the CALLER decides severity (tick refuses / exits 3; the CLI
#   prints + exits; other consumers fail closed). Read-only: it inspects git + the anchor/base/roadmap,
#   and mutates nothing.
# shellcheck disable=SC2034  # PR_* are this resolver's OUTPUT contract — set here, read by callers.
resolve_phase_range() {
  PR_ERR=""; PR_ANCHOR_USED=0; PR_SOURCE=""; PR_BASE=""; PR_BASE_SHA=""; PR_RANGE=""; PR_HEADING="${1:-}"
  PR_HEAD=$(git rev-parse HEAD 2>/dev/null) || { PR_ERR="not a git repo / no HEAD (fail-closed)"; return 1; }

  # Heading (informational + the M4 binding key): explicit arg → anchor heading= → roadmap first-open.
  if [ -z "$PR_HEADING" ] && [ -f .claude/.phase-anchor ]; then
    PR_HEADING=$(grep -E '^heading=' .claude/.phase-anchor 2>/dev/null | head -1 | cut -d= -f2-)
  fi
  if [ -z "$PR_HEADING" ] && command -v roadmap_first_open_heading >/dev/null 2>&1; then
    PR_HEADING=$(roadmap_first_open_heading docs/ROADMAP.md 2>/dev/null || true)
  fi

  # Base precedence.
  if [ -n "${TICK_BASE+set}" ]; then
    PR_BASE="$TICK_BASE"; PR_SOURCE="TICK_BASE env (orchestrator-trusted)"
    [ -n "$PR_BASE" ] || { PR_ERR="TICK_BASE is set but empty — a trusted base must be a real commit (fail-closed)"; return 1; }
  elif [ -f .claude/.phase-anchor ]; then
    PR_ANCHOR_USED=1
    PR_BASE=$(grep -E '^base=' .claude/.phase-anchor 2>/dev/null | head -1 | cut -d= -f2-)
    PR_SOURCE=".claude/.phase-anchor (start-phase.sh)"
    [ -n "$PR_BASE" ] || { PR_ERR="no base= in .claude/.phase-anchor — re-run scripts/start-phase.sh (fail-closed)"; return 1; }
  else
    PR_BASE=$(cat .claude/.phase-base 2>/dev/null || true)
    PR_SOURCE=".claude/.phase-base"
    [ -n "$PR_BASE" ] || { PR_ERR="no phase start recorded — run scripts/start-phase.sh first (fail-closed)"; return 1; }
  fi

  # Strict-ancestor guard (ALL sources): resolve to a real commit, require it is NOT HEAD (empty window)
  # and IS a genuine ancestor of HEAD (not unrelated history). Any failure is fail-closed.
  PR_BASE_SHA=$(git rev-parse --verify --quiet "${PR_BASE}^{commit}" 2>/dev/null || true)
  [ -n "$PR_BASE_SHA" ] || { PR_ERR="phase base ($PR_SOURCE = '$PR_BASE') is not a resolvable commit (fail-closed)"; return 1; }
  [ "$PR_BASE_SHA" != "$PR_HEAD" ] || { PR_ERR="phase base ($PR_SOURCE) equals HEAD — the scan window would be empty (fail-closed)"; return 1; }
  git merge-base --is-ancestor "$PR_BASE_SHA" "$PR_HEAD" 2>/dev/null \
    || { PR_ERR="phase base ($PR_SOURCE = '$PR_BASE') is not an ancestor of HEAD (fail-closed)"; return 1; }
  PR_RANGE="${PR_BASE_SHA}..${PR_HEAD}"

  # Anchor base-integrity (F3b): the anchor is authored as a commit whose PARENT is exactly base=. A
  # naive base rewrite (base=<later ancestor> + an ordinary commit) then fails closed — that commit's
  # parent is the previous HEAD, not the new base — so the "narrowed scan window" is REFUSED.
  if [ "$PR_ANCHOR_USED" = 1 ]; then
    local a_commit a_parent
    a_commit=$(git log -1 --format=%H -- .claude/.phase-anchor 2>/dev/null || true)
    if [ -n "$a_commit" ]; then
      a_parent=$(git rev-parse --verify --quiet "${a_commit}^" 2>/dev/null || true)
      if [ -n "$a_parent" ] && [ "$a_parent" != "$PR_BASE_SHA" ]; then
        PR_ERR=".claude/.phase-anchor base=${PR_BASE_SHA:0:12} does not match the commit that set it (anchor-setting commit ${a_commit:0:12} has parent ${a_parent:0:12}) — the base was advanced (narrowed scan window). Re-run scripts/start-phase.sh from the true phase start."
        return 3
      fi
    fi
  fi
  return 0
}

return 0 2>/dev/null || exit 0
