#!/usr/bin/env bash
# doctor.sh — one-command health check for the jaimitos-os setup.
# Verifies the things autopilot.sh and the hooks silently depend on.
# Exit 0 = healthy, exit 1 = problems found.
#
# --fix applies SAFE, LOCAL, IDEMPOTENT repairs only: chmod +x hooks/scripts, create the
# docs/plans dir, create docs/FAILURES.md. It does NOT restore missing libs/hooks/scaffold
# (that needs ./install.sh --force) and never touches the high-stakes fingerprint.

set -uo pipefail

# Answer -h/--help BEFORE anything else (including the subdir check below and the git-root cd) so
# `doctor.sh --help` always prints usage and exits 0, regardless of where it's run from. (The arg loop
# further down also handles --help, e.g. after `--fix`.)
case "${1:-}" in
  -h|--help) echo "usage: doctor.sh [--fix]   (--fix applies safe, local, idempotent repairs)"; exit 0 ;;
esac

# H4: the operational scripts (this one included) resolve paths from `git rev-parse --show-toplevel`.
# If jaimitos-os was installed in a SUBDIRECTORY of a repo, that toplevel is the repo ROOT — not where
# .claude/ and docs/ actually live — so every check below would false-"missing". Detect the mismatch
# (this script's own scaffold dir vs the git root) and say so plainly instead of a wall of missing.
# Compare PHYSICAL paths (pwd -P): git prints the symlink-resolved toplevel (e.g. /private/var/… on
# macOS) while `cd && pwd` is logical (/var/…) — a raw string compare would false-trip on the symlink
# and refuse a perfectly-fine git-root install.
DOCTOR_SCAFFOLD="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
DOCTOR_GIT_TOP_RAW="$(git -C "$DOCTOR_SCAFFOLD" rev-parse --show-toplevel 2>/dev/null || true)"
if [ -n "$DOCTOR_GIT_TOP_RAW" ]; then
  DOCTOR_GIT_TOP="$(cd "$DOCTOR_GIT_TOP_RAW" && pwd -P)"
  if [ "$DOCTOR_GIT_TOP" != "$DOCTOR_SCAFFOLD" ]; then
    echo "jaimitos-os doctor"
    echo ""
    echo "  ✗ jaimitos-os is installed in a SUBDIRECTORY, not at the git root:"
    echo "      scaffold:  $DOCTOR_SCAFFOLD"
    echo "      git root:  $DOCTOR_GIT_TOP"
    echo "  The operational scripts resolve paths from the git root, so they look for .claude/ and docs/"
    echo "  in the wrong place. jaimitos-os assumes ONE repo per project. Reinstall at the git root"
    echo "  (bash install.sh \"$DOCTOR_GIT_TOP\"), or use a separate repo for this project."
    exit 1
  fi
fi

cd "$(git rev-parse --show-toplevel 2>/dev/null || echo .)" || exit 1

PROBLEMS=0
ok()    { printf '  ✓ %s\n' "$1"; }
bad()   { printf '  ✗ %s\n' "$1"; PROBLEMS=$((PROBLEMS+1)); }
warn()  { printf '  ! %s\n' "$1"; }
fixed() { printf '  ⚙ fixed: %s\n' "$1"; }

FIX=0
for a in "$@"; do
  case "$a" in
    --fix) FIX=1 ;;
    -h|--help) echo "usage: doctor.sh [--fix]   (--fix applies safe, local, idempotent repairs)"; exit 0 ;;
    *) echo "doctor: unknown argument '$a' (try --fix)" >&2; exit 2 ;;
  esac
done

# Load-bearing files that MUST exist. A manifest, not a bare glob: a glob of PRESENT files can flag a
# bad exec-bit or a syntax error, but it can never notice a DELETED file — so deleting tick.sh / sync.sh
# / _test-cmd.sh would otherwise slip past as "All good" (audit H3). Test suites aren't listed here —
# run-guard-tests.sh has its own drift guard for those.
REQUIRED_SCRIPTS="autopilot.sh tick.sh test-evidence.sh record-grade.sh models.sh sync.sh doctor.sh close-milestone.sh next-adr.sh lint-roadmap.sh run-guard-tests.sh"
REQUIRED_LIBS="_secret-scan _high-stakes _test-cmd"

echo "jaimitos-os doctor"
[ -f .claude/.jaimitos-os-version ] && echo "jaimitos-os version: $(cat .claude/.jaimitos-os-version)"
echo ""

echo "Tooling:"
command -v claude  >/dev/null 2>&1 && ok "claude CLI on PATH" || bad "claude CLI not found"
command -v jq      >/dev/null 2>&1 && ok "jq installed (hooks need it)" || bad "jq not found"
command -v git     >/dev/null 2>&1 && ok "git installed" || bad "git not found"
command -v ruff    >/dev/null 2>&1 && ok "ruff available (Python format/lint)" || warn "ruff not found (Python formatting skipped)"
command -v node    >/dev/null 2>&1 && ok "node available (JS/TS tooling)"       || warn "node not found (JS/TS formatting skipped)"
echo ""

echo "Repo:"
git rev-parse --is-inside-work-tree >/dev/null 2>&1 && ok "inside a git repo" || bad "not a git repo (run 'git init')"
echo ""

echo "Scaffold files:"
for f in .claude/settings.json docs/SPEC.md docs/ROADMAP.md docs/STATE.md CLAUDE.md; do
  [ -f "$f" ] && ok "$f" || bad "missing $f"
done
if [ -d docs/plans ]; then ok "docs/plans/ exists"
elif [ "$FIX" -eq 1 ]; then mkdir -p docs/plans && fixed "created docs/plans/"
else warn "docs/plans/ missing (/phase writes here)"; fi
if [ -f docs/FAILURES.md ]; then ok "docs/FAILURES.md exists"
elif [ "$FIX" -eq 1 ]; then
  printf '# Failure history\n\n_Resolved evaluator findings, appended by scripts/autopilot.sh on PASS._\n' > docs/FAILURES.md \
    && fixed "created docs/FAILURES.md"
else warn "docs/FAILURES.md missing (created on the first resolved finding, or run --fix)"; fi
echo ""

echo "Operational scripts (load-bearing — a missing one silently disables a gate/update/repair path):"
for s in $REQUIRED_SCRIPTS; do
  [ -f "scripts/$s" ] && ok "scripts/$s" || bad "missing scripts/$s"
done
echo ""

echo "Agents, commands, rules:"
for a in researcher planner executor evaluator; do
  [ -f ".claude/agents/$a.md" ] && ok ".claude/agents/$a.md" || bad "missing .claude/agents/$a.md"
done
for c in resume wrap phase autopilot autopilot-parallel models; do
  [ -f ".claude/commands/$c.md" ] && ok ".claude/commands/$c.md" || bad "missing .claude/commands/$c.md"
done
[ -f .claude/rules/high-stakes.md ] && ok ".claude/rules/high-stakes.md" || bad "missing .claude/rules/high-stakes.md"
echo ""

echo "Model configuration (which model each /phase stage uses; set via /models):"
if [ -f scripts/models.sh ]; then
  bash scripts/models.sh 2>/dev/null | sed 's/^/  /'
else
  bad "scripts/models.sh missing — /models cannot function"
fi
echo ""

echo "High-stakes gate customization:"
HS_LIB=".claude/lib/_high-stakes.sh"
if [ -f "$HS_LIB" ]; then
  HS_CUR=$(grep -E '^HIGH_STAKES_RE=' "$HS_LIB" 2>/dev/null)
  if [ ! -f .claude/.high-stakes-default ]; then
    warn "cannot verify high-stakes customization — fingerprint .claude/.high-stakes-default missing"
    warn "  (re-run install.sh to create it). Confirm HIGH_STAKES_RE in $HS_LIB matches your paths."
  elif [ "$HS_CUR" = "$(cat .claude/.high-stakes-default 2>/dev/null)" ]; then
    HS_DEFAULT=1
    warn "HIGH_STAKES_RE is still the shipped default — edit it in $HS_LIB to match THIS project's"
    warn "  sensitive paths. It's the ENFORCED gate; editing only rules/high-stakes.md does nothing."
  else
    ok "HIGH_STAKES_RE customized (no longer the shipped default)"
  fi
fi
echo ""

echo "High-stakes path allowlist (regex false-positive escapes for high_stakes_match — never hidden):"
HS_ALLOWLIST=".claude/high-stakes-path-allowlist"
if [ -f "$HS_ALLOWLIST" ]; then
  HS_ACTIVE=0
  while IFS= read -r hsline || [ -n "$hsline" ]; do
    case "$hsline" in ''|'#'*) continue ;; esac
    hs_reason="${hsline#*:}"
    case "$hsline" in
      *:*)
        case "$hs_reason" in
          *[![:space:]]*) HS_ACTIVE=$((HS_ACTIVE+1)); warn "suppressed: $hsline" ;;
          *) warn "listed but INACTIVE (no reason after colon — still flagged): $hsline" ;;
        esac
        ;;
      *) warn "listed but INACTIVE (no colon/reason — still flagged): $hsline" ;;
    esac
  done < "$HS_ALLOWLIST"
  [ "$HS_ACTIVE" -eq 0 ] && ok "allowlist file present, no active (reasoned) entries"
else
  ok "no high-stakes path allowlist file — no path-gate suppressions active"
fi
echo ""

echo "Hook files present:"
for h in session-start steer kill-switch format-on-edit test-gate commit-on-stop ownership-nudge; do
  [ -f ".claude/hooks/$h.sh" ] && ok ".claude/hooks/$h.sh" || bad "missing .claude/hooks/$h.sh"
done
echo ""
echo "Shared guard libraries (.claude/lib/):"
# Sourced by commit-on-stop.sh and autopilot.sh. If absent, the secret-scan and
# high-stakes gates silently disable, so treat as hard failures.
for lib in $REQUIRED_LIBS; do
  [ -f ".claude/lib/$lib.sh" ] && ok ".claude/lib/$lib.sh (shared guard lib)" || bad "missing .claude/lib/$lib.sh (secret/high-stakes/test-cmd gate disabled without it)"
done
echo ""

echo "settings.json:"
if [ -f .claude/settings.json ]; then
  # `jq empty` was observed to be a no-op on some bundled jq builds (audit M4). `jq -e 'type'` emits the
  # top-level type of ANY well-formed JSON (a truthy string → exit 0) and errors on a parse failure
  # (exit ≥2 → non-zero), so a corrupt settings.json is reliably caught. Matches the -e idiom used below.
  jq -e 'type' .claude/settings.json >/dev/null 2>&1 && ok "valid JSON" || bad "settings.json is not valid JSON"
  jq -e '.permissions.deny | length > 0' .claude/settings.json >/dev/null 2>&1 \
    && ok "permissions.deny present (secret-read protection)" \
    || warn "no permissions.deny — Claude can read .env/secrets. Add deny rules."
  # Kill-switch wiring: the AGENT_STOP brake must be a PreToolUse hook with a match-all
  # matcher so it fires before EVERY tool call. Per the Claude Code hooks docs, "*", ""
  # and an omitted matcher all mean "match all" — accept any of them; reject a narrowed
  # matcher (e.g. "Bash") that would let other tools slip past the brake.
  if jq -e '
        [ .hooks.PreToolUse[]?
          | select([.hooks[]?.command | select(test("kill-switch"))] | length > 0)
          | (.matcher // "*") ] as $ms
        | ($ms | length > 0) and ($ms | all(. == "" or . == "*"))
      ' .claude/settings.json >/dev/null 2>&1; then
    ok "kill-switch wired into PreToolUse with a match-all matcher"
  else
    bad "kill-switch.sh not wired into PreToolUse with a match-all matcher (* / \"\" / omitted) — the AGENT_STOP brake may not fire on every tool"
  fi
fi
echo ""

echo "Hooks executable:"
# Libraries under .claude/lib/ are SOURCED, not executed — they don't need the exec bit.
for h in .claude/hooks/*.sh scripts/*.sh; do
  [ -f "$h" ] || continue
  if [ -x "$h" ]; then ok "$h"
  elif [ "$FIX" -eq 1 ]; then chmod +x "$h" && fixed "chmod +x $h"
  else bad "$h not executable (run: chmod +x $h)"; fi
done
echo ""

echo "Hook shell syntax:"
for h in .claude/hooks/*.sh .claude/lib/*.sh scripts/*.sh; do
  [ -f "$h" ] || continue
  bash -n "$h" 2>/dev/null && ok "$h parses" || bad "$h has a syntax error"
done
echo ""

echo "CLAUDE.md placeholders:"
if [ -f CLAUDE.md ]; then
  # Any unresolved <...> token is a placeholder, not just the piped command form —
  # catches '<NAME>', '<pytest -q | npm test>', etc. Report the offending lines.
  PH_LINES=$(grep -nE '<[^>]+>' CLAUDE.md 2>/dev/null)
  if [ -n "$PH_LINES" ]; then
    warn "un-substituted <...> placeholder(s) in CLAUDE.md — fill them in with your real values:"
    printf '%s\n' "$PH_LINES" | sed 's/^/      /'
    UNCONFIGURED=1
  else
    ok "no <...> placeholders left in CLAUDE.md"
  fi
fi
echo ""

echo "Toolkit sync:"
if [ -f .claude/.jaimitos-os-version ]; then
  ok "scaffolded from jaimitos-os $(cat .claude/.jaimitos-os-version)"
  warn "run 'bash scripts/sync.sh --toolkit <path-to-jaimitos-os> --dry-run' to check for toolkit"
  warn "  updates and apply them without clobbering your customizations"
fi
echo ""

if [ "$PROBLEMS" -ne 0 ]; then
  echo "$PROBLEMS problem(s) found. Fix the ✗ items above before an unattended run."
  # Remediation hint on EVERY problem run (M11 — not only behind --fix). Missing scaffold/libs/hooks/
  # scripts are restored by install.sh --force; --fix only repairs chmod/dirs.
  if [ "$FIX" -eq 1 ]; then
    echo "(--fix repairs chmod/dirs only — it can't restore missing libs/hooks/scaffold; run ./install.sh --force for those.)"
  else
    echo "To restore missing scaffold/libs/hooks/scripts, run ./install.sh --force; for chmod/dirs, re-run with --fix."
  fi
  exit 1
elif [ "${UNCONFIGURED:-0}" = 1 ] || [ "${HS_DEFAULT:-0}" = 1 ]; then
  # Installed correctly but not yet customized — do NOT imply it's ready to run unattended.
  echo "Installed OK, but NOT yet configured for THIS project (see the ! warnings above):"
  [ "${UNCONFIGURED:-0}" = 1 ] && echo "  • fill the CLAUDE.md command placeholders"
  [ "${HS_DEFAULT:-0}" = 1 ]  && echo "  • point HIGH_STAKES_RE in .claude/lib/_high-stakes.sh at your sensitive paths"
  echo "Finish those before an unattended autopilot run."
  exit 0
else
  echo "All good. Setup looks healthy."
  exit 0
fi
