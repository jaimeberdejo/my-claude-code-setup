#!/usr/bin/env bash
# test-sandbox.sh — sandbox/run-autopilot-sandboxed.sh must fail CLOSED before any container
# starts: no docker → clear refusal; no ANTHROPIC_API_KEY → refusal; secret-shaped files that
# would ride into the mount → refusal (reusing _secret-scan.sh's filename rules); missing scan
# lib → refusal. On a clean repo it must invoke docker with ONLY the repo mounted, ONLY
# ANTHROPIC_API_KEY passed, and --dangerously-skip-permissions appended INSIDE the container.
# No real docker is ever used — a stub records the invocation. Also lints the Dockerfile
# (hadolint when available, structural checks otherwise).
set -uo pipefail
SCAFFOLD="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WRAPPER="$SCAFFOLD/sandbox/run-autopilot-sandboxed.sh"
DOCKERFILE="$SCAFFOLD/sandbox/Dockerfile.autopilot"
[ -f "$WRAPPER" ] || { echo "test: missing $WRAPPER" >&2; exit 1; }
command -v git >/dev/null 2>&1 || { echo "test: git required"; exit 1; }

FAILS=0
pass() { printf '  ✓ %s\n' "$1"; }
fail() { printf '  ✗ %s\n' "$1"; FAILS=$((FAILS+1)); }

WORK="$(mktemp -d 2>/dev/null || mktemp -d -t leanstack-sbx)"
trap 'rm -rf "$WORK" 2>/dev/null' EXIT

# Stub docker: records `docker run` args, honors an env switch for `image inspect`.
mkdir -p "$WORK/bin"
cat > "$WORK/bin/docker" <<'EOF'
#!/usr/bin/env bash
case "${1:-}" in
  image) [ "${STUB_IMAGE_EXISTS:-1}" = "1" ] && exit 0 || exit 1 ;;
  build) printf '%s\n' "$@" > "${STUB_LOG:-/dev/null}.build"; exit 0 ;;
  run)   shift; printf '%s\n' "$@" > "${STUB_LOG:-/dev/null}"; exit 0 ;;
  *)     exit 0 ;;
esac
EOF
chmod +x "$WORK/bin/docker"

# mkrepo: throwaway git repo with the scan lib in place; cd's the current shell into it.
mkrepo() {
  REPO="$WORK/$1"; rm -rf "$REPO"; mkdir -p "$REPO/.claude/lib" "$REPO/scripts"
  cp "$SCAFFOLD/.claude/lib/_secret-scan.sh" "$REPO/.claude/lib/_secret-scan.sh"
  printf '#!/usr/bin/env bash\necho fake autopilot\n' > "$REPO/scripts/autopilot.sh"
  ( cd "$REPO" && git init -q && git config user.email t@t.t && git config user.name t )
  cd "$REPO" || exit 1
}

run_wrapper() {  # run_wrapper [env VAR=..] -- <args...>; stub docker on PATH, output to $WORK/out
  PATH="$WORK/bin:$PATH" STUB_LOG="$WORK/docker-args" ANTHROPIC_API_KEY="${KEY_OVERRIDE-test-key}" \
    bash "$WRAPPER" "$@" >"$WORK/out" 2>&1
  echo $?
}

echo "sandbox wrapper tests"; echo ""

# 1 — no docker anywhere on PATH → refuses with guidance, exit 2, before touching anything.
# (bash resolved to an absolute path FIRST — the emptied PATH must starve the wrapper of
# docker, not starve this test of bash itself.)
mkrepo t1
BASH_BIN="$(command -v bash)"
PATH=/nonexistent-path-for-test "$BASH_BIN" "$WRAPPER" 1 >"$WORK/out" 2>&1; rc=$?
{ [ "$rc" -eq 2 ] && grep -qi "docker is required" "$WORK/out"; } \
  && pass "no docker on PATH → clean refusal (exit 2) with install guidance" \
  || fail "missing docker not refused cleanly (rc=$rc)"

# 2 — ANTHROPIC_API_KEY unset → refusal, exit 2.
mkrepo t2
rc=$(KEY_OVERRIDE="" run_wrapper 1)
{ [ "$rc" -eq 2 ] && grep -q "ANTHROPIC_API_KEY" "$WORK/out"; } \
  && pass "unset ANTHROPIC_API_KEY → refusal naming the missing credential" \
  || fail "missing API key not refused (rc=$rc)"

# 3 — a secret-shaped file that would ride into the mount (untracked, NOT gitignored) → exit 3,
# file named, docker run never invoked.
mkrepo t3
printf 'SECRET=1\n' > .env
rm -f "$WORK/docker-args"
rc=$(run_wrapper 1)
{ [ "$rc" -eq 3 ] && grep -qF ".env" "$WORK/out" && [ ! -f "$WORK/docker-args" ]; } \
  && pass "unignored .env in the repo → refusal (exit 3), file named, container never started" \
  || fail "secret-shaped file not refused (rc=$rc)"

# 3b — same for a secrets/ directory file.
mkrepo t3b
mkdir -p secrets && printf 'k\n' > secrets/prod.json
rc=$(run_wrapper 1)
[ "$rc" -eq 3 ] && pass "unignored secrets/ file → refusal (exit 3)" \
  || fail "secrets/ dir not refused (rc=$rc)"

# 4 — a GITIGNORED .env no longer blocks (documented residual risk: the mount still carries it,
# the wrapper's contract is tracked/unignored files) and docker run gets the right shape:
# repo→/work as the only mount, ANTHROPIC_API_KEY as the only -e, wrapper args forwarded, and
# --dangerously-skip-permissions appended as the LAST argument inside the container.
mkrepo t4
printf 'SECRET=1\n' > .env; printf '.env\n' > .gitignore
rm -f "$WORK/docker-args"
rc=$(run_wrapper 3 --pr)
ARGS="$(cat "$WORK/docker-args" 2>/dev/null || true)"
# The container receives exactly ONE volume (the repo) and TWO -e vars: the ANTHROPIC_API_KEY
# credential and the non-secret JAIMITOS_SANDBOXED=1 marker (so autopilot's in-container run knows
# it IS sandboxed). No other mount, no other credential.
{ [ "$rc" -eq 0 ] && [ -n "$ARGS" ] \
  && printf '%s\n' "$ARGS" | grep -qx -- "$REPO:/work" \
  && [ "$(printf '%s\n' "$ARGS" | grep -cx -- '-v')" -eq 1 ] \
  && printf '%s\n' "$ARGS" | grep -qx -- "ANTHROPIC_API_KEY" \
  && printf '%s\n' "$ARGS" | grep -qx -- "JAIMITOS_SANDBOXED=1" \
  && [ "$(printf '%s\n' "$ARGS" | grep -cx -- '-e')" -eq 2 ] \
  && printf '%s\n' "$ARGS" | grep -qx -- "scripts/autopilot.sh" \
  && printf '%s\n' "$ARGS" | grep -qx -- "3" \
  && printf '%s\n' "$ARGS" | grep -qx -- "--pr" \
  && [ "$(printf '%s\n' "$ARGS" | tail -1)" = "--dangerously-skip-permissions" ]; } \
  && pass "clean repo: docker run mounts ONLY the repo, passes ONLY ANTHROPIC_API_KEY + the JAIMITOS_SANDBOXED marker, forwards args, appends --dangerously-skip-permissions last" \
  || fail "docker run invocation malformed (rc=$rc): $ARGS"

# 4b — missing image → docker build invoked against sandbox/Dockerfile.autopilot before run.
mkrepo t4b
rm -f "$WORK/docker-args" "$WORK/docker-args.build"
rc=$(STUB_IMAGE_EXISTS=0 run_wrapper 1)
{ [ "$rc" -eq 0 ] && grep -q "Dockerfile.autopilot" "$WORK/docker-args.build" 2>/dev/null; } \
  && pass "missing image → wrapper builds from sandbox/Dockerfile.autopilot first" \
  || fail "image build path broken (rc=$rc)"

# 5 — missing _secret-scan.sh lib → fail-closed refusal (exit 2), container never started.
mkrepo t5
rm .claude/lib/_secret-scan.sh
rm -f "$WORK/docker-args"
rc=$(run_wrapper 1)
{ [ "$rc" -eq 2 ] && grep -qi "fail-closed" "$WORK/out" && [ ! -f "$WORK/docker-args" ]; } \
  && pass "missing scan lib → fail-closed refusal, container never started" \
  || fail "missing scan lib not fail-closed (rc=$rc)"

# 6 — --help exits 0 and mentions the contract.
bash "$WRAPPER" --help >"$WORK/out" 2>&1; rc=$?
{ [ "$rc" -eq 0 ] && grep -q "ANTHROPIC_API_KEY" "$WORK/out"; } \
  && pass "--help prints the contract and exits 0" || fail "--help broken (rc=$rc)"

# 7 — Dockerfile lint: hadolint when available; otherwise structural must-haves (slim base,
# a USER line that isn't root, /work as the workdir, no credential-path mentions).
echo ""
if command -v hadolint >/dev/null 2>&1; then
  if hadolint "$DOCKERFILE" >"$WORK/hado" 2>&1; then pass "hadolint: Dockerfile.autopilot is clean"
  else fail "hadolint reported issues: $(head -3 "$WORK/hado" | tr '\n' ';')"; fi
else
  { grep -qE '^FROM .*(slim|alpine)' "$DOCKERFILE" \
    && grep -qE '^USER ' "$DOCKERFILE" && ! grep -qE '^USER +root' "$DOCKERFILE" \
    && grep -qE '^WORKDIR /work' "$DOCKERFILE" \
    && ! grep -vE '^[[:space:]]*#' "$DOCKERFILE" | grep -qE '\.aws|\.ssh'; } \
    && pass "Dockerfile structural checks (slim base, non-root USER, /work, no credential paths) — hadolint not installed" \
    || fail "Dockerfile structural checks failed"
fi

# ============================================================================================
# autopilot.sh's OWN sandbox fail-closed brake (v2.6.0): --dangerously-skip-permissions on a bare
# host (no sandbox signal) is REFUSED unless --i-understand-no-sandbox is passed. The container
# indicator paths are overridable (JAIMITOS_DOCKERENV_PATH / JAIMITOS_CGROUP_PATH) so a test can
# simulate a bare host even when the test runner is itself a container.
# ============================================================================================
AUTOPILOT="$SCAFFOLD/scripts/autopilot.sh"

# mkautorepo: minimal scaffold sufficient for autopilot.sh to reach (or refuse before) the sandbox
# gate. cds the shell into it. No real `claude` — a run that gets past the gate simply fails the
# builder, which is fine: the gate's refusal/banner is emitted before the loop.
mkautorepo() {
  R="$WORK/$1"; rm -rf "$R"; mkdir -p "$R/.claude/lib" "$R/scripts" "$R/docs"
  cp "$AUTOPILOT" "$R/scripts/autopilot.sh"
  cp "$SCAFFOLD/.claude/lib/_eval-isolation.sh" "$R/.claude/lib/"     # required (fail-closed) lib
  printf '{"hooks":{}}\n' > "$R/.claude/settings.json"
  printf '# Roadmap\n## Phase 1 — x\n- [ ] a\nDone when: x\nMode: loopable\n' > "$R/docs/ROADMAP.md"
  printf '# State\n' > "$R/docs/STATE.md"
  ( cd "$R" && git init -q && git config user.email t@t.t && git config user.name t \
      && git add -A >/dev/null 2>&1 && git commit -qm init >/dev/null 2>&1 )
  cd "$R" || exit 1
}
# No-signal env: forge nothing, just point the container indicators at nonexistent paths.
NOSIG=(JAIMITOS_SANDBOXED= JAIMITOS_DOCKERENV_PATH=/nonexistent-xyz JAIMITOS_CGROUP_PATH=/nonexistent-xyz)

echo ""
# 8 — refusal: bypass + no sandbox signal + no ack → exit 1, names the wrapper, before any loop.
mkautorepo a8
env "${NOSIG[@]}" bash scripts/autopilot.sh 1 --no-worktree --allow-dirty --dangerously-skip-permissions >"$WORK/out" 2>&1; rc=$?
{ [ "$rc" -eq 1 ] && grep -qi "NO sandbox signal" "$WORK/out" && grep -q "run-autopilot-sandboxed.sh" "$WORK/out"; } \
  && pass "autopilot refuses --dangerously-skip-permissions with no sandbox signal (exit 1, points at the wrapper)" \
  || fail "autopilot did not refuse the no-sandbox bypass (rc=$rc)"

# 9 — override: same, plus --i-understand-no-sandbox → does NOT refuse; prints the banner and
# records it in autopilot.log. (It then fails the builder — no real claude — which is expected.)
mkautorepo a9
env "${NOSIG[@]}" bash scripts/autopilot.sh 1 --no-worktree --allow-dirty --dangerously-skip-permissions --i-understand-no-sandbox >"$WORK/out" 2>&1
{ ! grep -qi "NO sandbox signal detected" "$WORK/out" \
  && grep -q "OUTSIDE ANY DETECTED SANDBOX" "$WORK/out" \
  && grep -q "OUTSIDE ANY DETECTED SANDBOX" autopilot.log 2>/dev/null; } \
  && pass "--i-understand-no-sandbox proceeds past the gate, prints the banner, and records it in autopilot.log" \
  || fail "--i-understand-no-sandbox banner/logging broken"

# 10 — signal present (JAIMITOS_SANDBOXED=1) → no refusal, no bare-host banner (it IS 'sandboxed').
mkautorepo a10
env JAIMITOS_SANDBOXED=1 JAIMITOS_DOCKERENV_PATH=/nonexistent-xyz JAIMITOS_CGROUP_PATH=/nonexistent-xyz \
  bash scripts/autopilot.sh 1 --no-worktree --allow-dirty --dangerously-skip-permissions >"$WORK/out" 2>&1
{ ! grep -qi "NO sandbox signal" "$WORK/out" && ! grep -q "OUTSIDE ANY DETECTED SANDBOX" "$WORK/out"; } \
  && pass "JAIMITOS_SANDBOXED=1 → no refusal and no bare-host banner (the wrapper's normal path)" \
  || fail "sandbox-signal path wrongly refused or bannered"

# 11 — the brake is inert without --dangerously-skip-permissions (no behavior change there).
mkautorepo a11
env "${NOSIG[@]}" bash scripts/autopilot.sh 1 --no-worktree --allow-dirty >"$WORK/out" 2>&1
grep -qi "NO sandbox signal" "$WORK/out" \
  && fail "sandbox gate wrongly fired without --dangerously-skip-permissions" \
  || pass "sandbox gate is inert when --dangerously-skip-permissions is absent"

echo ""
if [ "$FAILS" -eq 0 ]; then echo "All sandbox tests passed."; exit 0
else echo "$FAILS sandbox test(s) FAILED."; echo "--- last output ---"; tail -n 15 "$WORK/out" 2>/dev/null; exit 1; fi
