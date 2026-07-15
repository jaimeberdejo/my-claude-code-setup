#!/usr/bin/env bash
# lint-roadmap.sh — dependency-free check that every "## Phase" in docs/ROADMAP.md carries a
# a valid phase schema: a non-empty "Done when:", at least one task, and exactly one valid "Mode:".
# Advisory by default (exit 0, prints warnings); --strict exits 1 on any problem.
# Usage: bash scripts/lint-roadmap.sh [--strict] [path-to-roadmap]
set -uo pipefail
STRICT=0; FILE="docs/ROADMAP.md"
for a in "$@"; do case "$a" in
  -h|--help) echo "usage: lint-roadmap.sh [--strict] [path-to-roadmap]   (every ## Phase must carry a non-empty Done when: line)"; exit 0 ;;
  --strict) STRICT=1 ;;
  *) FILE="$a" ;;
esac; done
[ -f "$FILE" ] || { echo "lint-roadmap: no $FILE — nothing to lint."; exit 0; }

# Source the requirement-id validator (sibling lib). Resolved relative to THIS script so it works
# whether run from the project root or elsewhere; optional — absent means id validation is simply
# skipped. It is inert unless a phase declares a `Requirements:` line. (SC1090/1091 disabled
# repo-wide: this is a runtime-resolved source path by design.)
LINT_LIB="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")/../.claude/lib" 2>/dev/null && pwd)" || LINT_LIB=""
if [ -n "$LINT_LIB" ] && [ -f "$LINT_LIB/_requirements.sh" ]; then
  . "$LINT_LIB/_requirements.sh" 2>/dev/null || true
fi

OUT=$(awk '
  function flush() {
    if (!tracking) return
    if (!dw)          { printf "  ! missing \"Done when:\" — %s\n", h; miss++ }
    if (tasks == 0)   { printf "  ! phase has no task (- [ ] / - [x]) lines — %s\n", h; miss++ }
    if (modes == 0)   { printf "  ! missing \"Mode:\" line (loopable|supervised) — %s\n", h; miss++ }
    else if (modes > 1) { printf "  ! %d \"Mode:\" lines (exactly one required) — %s\n", modes, h; miss++ }
    else if (modeval !~ /^(loopable|supervised)$/) { printf "  ! invalid Mode \"%s\" (loopable|supervised) — %s\n", modeval, h; miss++ }
  }
  /^## Phase/ {
    flush()
    if (h != "" && seen[$0]) { printf "  ! duplicate phase heading — %s\n", $0; miss++ }
    seen[$0]=1
    h=$0; dw=0; tasks=0; modes=0; modeval=""; tracking=1; next
  }
  /^## / { flush(); tracking=0; next }
  /^[[:space:]]*Done when:/ && tracking {
    v=$0; sub(/^[[:space:]]*Done when:[[:space:]]*/, "", v)
    if (v == "") { printf "  ! empty \"Done when:\" — %s\n", h; miss++ } else dw=1
  }
  /^[[:space:]]*- \[[ xX]\] / && tracking { tasks++ }
  /^[[:space:]]*Mode:/ && tracking {
    modes++; mv=$0; sub(/^[[:space:]]*Mode:[[:space:]]*/, "", mv); sub(/[[:space:]]*$/, "", mv)
    modeval=tolower(mv)
  }
  END { flush(); exit (miss > 0 ? 1 : 0) }
' "$FILE")
rc=$?

# Requirement-id validation (inert unless a phase declares a `Requirements:` line). The helper owns
# REQ/AC/OBJ semantics so this linter stays the roadmap-schema checker; it derives docs/SPEC.md as a
# sibling of the roadmap file.
REQ_OUT=""; REQ_RC=0
if command -v requirements_lint >/dev/null 2>&1; then
  REQ_OUT=$(requirements_lint "$FILE"); REQ_RC=$?
fi

if [ "$rc" -eq 0 ] && [ "$REQ_RC" -eq 0 ]; then
  echo "lint-roadmap: every phase has a valid schema (Done when:, >=1 task, one Mode:)."
  exit 0
fi
[ "$rc" -ne 0 ] && printf '%s\n' "$OUT"
[ "$REQ_RC" -ne 0 ] && printf '%s\n' "$REQ_OUT"
if [ "$STRICT" -eq 1 ]; then echo "lint-roadmap: problems found (--strict)."; exit 1; fi
echo "lint-roadmap: warnings above (advisory; pass --strict to fail)."
exit 0
