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

if [ "$rc" -eq 0 ]; then
  echo "lint-roadmap: every phase has a valid schema (Done when:, >=1 task, one Mode:)."
  exit 0
fi
printf '%s\n' "$OUT"
if [ "$STRICT" -eq 1 ]; then echo "lint-roadmap: problems found (--strict)."; exit 1; fi
echo "lint-roadmap: warnings above (advisory; pass --strict to fail)."
exit 0
