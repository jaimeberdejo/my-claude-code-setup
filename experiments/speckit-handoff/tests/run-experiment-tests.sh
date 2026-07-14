#!/usr/bin/env bash
# run-experiment-tests.sh — the experiment's OWN test runner, with its OWN drift guard.
#
# Deliberately NOT part of jaimitos-os/scripts/run-guard-tests.sh:
#   - that runner's drift guard forces every scripts/test-*.sh into its list, and
#   - everything in jaimitos-os/scripts/ SHIPS into user projects.
# An experimental suite must not do either. Keeping them apart also means a red experiment reads as
# "the experiment is red", and a REJECT deletes this directory and its CI job together.
#
# TIERS
#   offline (default)  — fixtures only. No network, no Spec Kit install. This is what CI runs.
#   live               — installs the PINNED Spec Kit CLI and tests the preset against it.
#                        Opt-in: SPECKIT_LIVE=1. Skipped LOUDLY otherwise — never silently passed.
set -euo pipefail

case "${1:-}" in
  -h|--help)
    echo "usage: run-experiment-tests.sh   (offline tier; set SPECKIT_LIVE=1 to add the pinned-CLI tier)"
    exit 0 ;;
  "") : ;;
  *) echo "run-experiment-tests: unexpected argument '$1' — this script takes no arguments." >&2; exit 2 ;;
esac

cd "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

git config --global user.email >/dev/null 2>&1 || git config --global user.email ci@example.com
git config --global user.name  >/dev/null 2>&1 || git config --global user.name  ci
chmod +x bin/*.sh tests/*.sh tests/live/*.sh 2>/dev/null || true

TESTS=(
  test-speckit-gate.sh
  test-speckit-footprint.sh
)

# Drift guard: every tests/test-*.sh MUST be listed above, or a newly-added test would silently
# never run. Same failure mode, same fix, as jaimitos-os/scripts/run-guard-tests.sh.
for f in tests/test-*.sh; do
  [ -e "$f" ] || continue
  b="${f#tests/}"
  case " ${TESTS[*]} " in
    *" $b "*) ;;
    *) echo "run-experiment-tests: '$b' exists but is missing from TESTS[] — add it (or it never runs)."; exit 1 ;;
  esac
done

echo "=== offline tier (no network) ==="
for t in "${TESTS[@]}"; do
  echo "--- tests/$t ---"
  bash "tests/$t"
done

echo ""
if [ "${SPECKIT_LIVE:-0}" = "1" ]; then
  echo "=== live tier (pinned Spec Kit CLI — network required) ==="
  for t in tests/live/test-*.sh; do
    [ -e "$t" ] || continue
    echo "--- $t ---"
    bash "$t"
  done
else
  # Loud, not silent. A tier that "passes" by not running is how an unverified claim reaches a report.
  echo "=== live tier: SKIPPED (SPECKIT_LIVE != 1) ==="
  echo "    The preset is the most fragile artifact in this experiment, and source inspection of"
  echo "    preset.yml is NOT evidence that Spec Kit honours it. Run with SPECKIT_LIVE=1 before"
  echo "    trusting any claim about /speckit-implement being neutered."
fi

echo ""
echo "All experiment tests passed."
