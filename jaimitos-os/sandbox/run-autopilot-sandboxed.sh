#!/usr/bin/env bash
# run-autopilot-sandboxed.sh — the SUPPORTED way to run the headless autopilot unattended.
#
# The docs have always said "run --dangerously-skip-permissions only in a sandboxed container
# with no production credentials"; this wrapper IS that container. It:
#   • builds the sandbox image (sandbox/Dockerfile.autopilot) if it doesn't exist yet;
#   • mounts ONLY the current repo (-v "$PWD":/work) — never $HOME, ~/.aws, ~/.ssh, or any
#     credential store;
#   • passes exactly ONE credential into the container: ANTHROPIC_API_KEY (env var). That is
#     the single allowed credential, by design — the loop needs it to call the API and nothing
#     else;
#   • runs `scripts/autopilot.sh "$@" --dangerously-skip-permissions` inside.
#
# Refusals (fail-closed, before any container starts):
#   • docker missing                        → exit 2 with install guidance
#   • ANTHROPIC_API_KEY unset               → exit 2
#   • secret-shaped files INSIDE the repo   → exit 3. The repo is the one thing we do mount, so
#     a tracked/unignored .env, secrets/, *.pem, … would ride straight into the container.
#     Detection reuses _secret-scan.sh's filename rules over tracked + untracked-unignored files.
#
# Usage: bash sandbox/run-autopilot-sandboxed.sh <autopilot.sh args>
#        e.g. bash sandbox/run-autopilot-sandboxed.sh 3 --pr
set -uo pipefail
cd "$(git rev-parse --show-toplevel 2>/dev/null || echo .)" || exit 1
SANDBOX_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
IMAGE="${JAIMITOS_SANDBOX_IMAGE:-jaimitos-autopilot}"

case "${1:-}" in
  -h|--help)
    echo "usage: run-autopilot-sandboxed.sh <autopilot.sh args>   (e.g. ... 3 --pr)"
    echo "  Builds the sandbox image if missing, mounts ONLY this repo, passes ONLY"
    echo "  ANTHROPIC_API_KEY, and runs scripts/autopilot.sh <args> --dangerously-skip-permissions"
    echo "  inside the container. Refuses if docker is missing, the key is unset, or the repo"
    echo "  contains secret-shaped files that would be mounted in."
    exit 0 ;;
esac

command -v docker >/dev/null 2>&1 || {
  echo "sandbox: ⛔ docker is required — install Docker (or Podman with a docker alias) first." >&2
  echo "sandbox:   Unattended --dangerously-skip-permissions runs are ONLY supported inside this container." >&2
  exit 2
}
[ -n "${ANTHROPIC_API_KEY:-}" ] || {
  echo "sandbox: ⛔ ANTHROPIC_API_KEY is not set — it is the single credential the container receives." >&2
  exit 2
}
git rev-parse --is-inside-work-tree >/dev/null 2>&1 || {
  echo "sandbox: ⛔ not a git repo — autopilot needs one." >&2
  exit 2
}

# Secret-shaped files inside the repo would be mounted into the container. Fail closed if the
# scan lib is missing; refuse on any filename hit over tracked + untracked-but-not-ignored files.
SCAN_LIB=".claude/lib/_secret-scan.sh"
[ -f "$SCAN_LIB" ] || {
  echo "sandbox: ⛔ $SCAN_LIB missing — cannot scan the repo for secret-shaped files (fail-closed)." >&2
  echo "sandbox:   Restore it (re-run install.sh) and retry." >&2
  exit 2
}
# shellcheck disable=SC1090
. "$SCAN_LIB"
HITS=""
while IFS= read -r f; do
  [ -z "$f" ] && continue
  _secret_basename_match "$f" && HITS="${HITS}    $f"$'\n'
done < <( { git ls-files; git ls-files --others --exclude-standard; } 2>/dev/null | sort -u )
if [ -n "$HITS" ]; then
  echo "sandbox: ⛔ secret-shaped file(s) inside the repo would be mounted into the container:" >&2
  printf '%s' "$HITS" >&2
  echo "sandbox:   Remove them or add them to .gitignore (an ignored file still on disk is NOT" >&2
  echo "sandbox:   flagged only if git ignores it — the mount carries whatever is in the repo dir," >&2
  echo "sandbox:   so prefer removing real credentials entirely), then retry." >&2
  exit 3
fi

if ! docker image inspect "$IMAGE" >/dev/null 2>&1; then
  echo "sandbox: building image '$IMAGE' from $SANDBOX_DIR/Dockerfile.autopilot ..."
  docker build -f "$SANDBOX_DIR/Dockerfile.autopilot" -t "$IMAGE" "$SANDBOX_DIR" || {
    echo "sandbox: ⛔ image build failed." >&2
    exit 1
  }
fi

# -i always (stdin for the loop); -t only when we actually have a TTY.
TTY_FLAG=""
[ -t 0 ] && [ -t 1 ] && TTY_FLAG="-t"
echo "sandbox: repo → /work (only mount) · credential → ANTHROPIC_API_KEY (only one) · image → $IMAGE"
# shellcheck disable=SC2086  # TTY_FLAG is deliberately unquoted (empty → no flag)
exec docker run --rm -i $TTY_FLAG \
  -v "$PWD":/work -w /work \
  -e ANTHROPIC_API_KEY \
  -e JAIMITOS_SANDBOXED=1 \
  "$IMAGE" scripts/autopilot.sh "$@" --dangerously-skip-permissions
