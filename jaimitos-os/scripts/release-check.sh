#!/usr/bin/env bash
# release-check.sh — pre-release consistency check for VERSION ↔ CHANGELOG ↔ git tags (audit 6.10).
# Creates NO tags and pushes nothing — it only REPORTS. Run it before cutting a release.
#
# Checks:
#   1. VERSION equals the newest non-[Unreleased] heading in CHANGELOG.md.
#   2. A tag v$VERSION exists (WARN if not — the release isn't tagged yet).
#   3. Every released CHANGELOG heading newer than the latest tag has a matching tag. Historical
#      misses BEFORE the grandfather floor (2.8.0) are a WARNING, not a failure — v2.5.0/2.6.0/2.7.0
#      shipped untagged and we don't retro-tag them. From 2.8.0 on, a missing tag is an ERROR.
#   4. [Unreleased] is empty/absent at release time (its content must be promoted to the version).
#
# Exit 0 = consistent (warnings allowed); 1 = a blocking inconsistency.
set -uo pipefail
cd "$(git rev-parse --show-toplevel 2>/dev/null || echo .)" || exit 1
# The toolkit's VERSION + CHANGELOG live at the repo ROOT (a sibling of jaimitos-os/).
ROOT="."
[ -f VERSION ] || ROOT=".."
VER_FILE="$ROOT/VERSION"; CHANGELOG="$ROOT/CHANGELOG.md"
GRANDFATHER_FLOOR="2.8.0"   # releases below this may be untagged (historical) without failing

case "${1:-}" in -h|--help) echo "usage: release-check.sh   (reports VERSION/CHANGELOG/tag consistency; creates nothing)"; exit 0 ;; esac

WARN=0; ERR=0
warn() { echo "release-check: ! $1" >&2; WARN=$((WARN+1)); }
err()  { echo "release-check: ⛔ $1" >&2; ERR=$((ERR+1)); }
ok()   { echo "release-check: ✓ $1"; }

[ -f "$VER_FILE" ]  || { err "no VERSION file"; exit 1; }
[ -f "$CHANGELOG" ] || { err "no CHANGELOG.md"; exit 1; }
VERSION=$(tr -d '[:space:]' < "$VER_FILE")
[ -n "$VERSION" ] || { err "VERSION is empty"; exit 1; }

# ver_lt A B : 0 (true) if A < B by dotted numeric compare (bash 3.2 / BSD safe, no sort -V).
ver_lt() {
  local a="$1" b="$2" IFS=.
  # shellcheck disable=SC2206
  local ax=($a) bx=($b) i
  for i in 0 1 2; do
    local an=${ax[i]:-0} bn=${bx[i]:-0}
    [ "$an" -lt "$bn" ] 2>/dev/null && return 0
    [ "$an" -gt "$bn" ] 2>/dev/null && return 1
  done
  return 1
}

# Newest released (non-[Unreleased]) heading, e.g. "## [2.8.0] — ...".
NEWEST=$(grep -E '^## \[[0-9]+\.[0-9]+\.[0-9]+\]' "$CHANGELOG" | head -1 | sed -E 's/^## \[([0-9.]+)\].*/\1/')
if [ "$NEWEST" = "$VERSION" ]; then ok "VERSION ($VERSION) == newest CHANGELOG release"
else err "VERSION ($VERSION) != newest CHANGELOG release ($NEWEST)"; fi

# [Unreleased] should be empty at release time.
UNREL=$(awk '/^## \[Unreleased\]/{f=1;next} /^## \[/{f=0} f' "$CHANGELOG" | grep -vE '^[[:space:]]*(_.*_)?[[:space:]]*$' | grep -c .)
if [ "${UNREL:-0}" -gt 0 ]; then warn "[Unreleased] section is non-empty ($UNREL lines) — promote it into the version heading before tagging"
else ok "[Unreleased] is empty (or a placeholder)"; fi

# Tag for the current VERSION.
if git rev-parse -q --verify "refs/tags/v$VERSION" >/dev/null 2>&1; then ok "tag v$VERSION exists"
else warn "tag v$VERSION does not exist yet (create it at release time, with human approval)"; fi

# Every released heading >= floor must have a tag; below floor → warn (grandfathered).
MISS_ERR=""; MISS_WARN=""
while IFS= read -r v; do
  [ -n "$v" ] || continue
  git rev-parse -q --verify "refs/tags/v$v" >/dev/null 2>&1 && continue
  if ver_lt "$v" "$GRANDFATHER_FLOOR"; then MISS_WARN="$MISS_WARN v$v"; else MISS_ERR="$MISS_ERR v$v"; fi
done < <(grep -E '^## \[[0-9]+\.[0-9]+\.[0-9]+\]' "$CHANGELOG" | sed -E 's/^## \[([0-9.]+)\].*/\1/')
[ -n "$MISS_WARN" ] && warn "untagged historical releases (grandfathered, will not retro-tag):$MISS_WARN"
[ -n "$MISS_ERR" ]  && err  "untagged releases at/after $GRANDFATHER_FLOOR (must be tagged):$MISS_ERR"
[ -z "$MISS_ERR" ] && ok "no untagged releases at/after the $GRANDFATHER_FLOOR floor"

echo "release-check: $WARN warning(s), $ERR error(s)."
[ "$ERR" -eq 0 ] || exit 1
exit 0
