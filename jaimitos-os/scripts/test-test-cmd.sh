#!/usr/bin/env bash
# test-test-cmd.sh — behavioral tests for the shared test-command resolver
# (.claude/lib/_test-cmd.sh). Regression guard for the uv/poetry lockfile-awareness gap:
# dogfooding found the bare-PATH `pytest` branch picking the wrong interpreter on a
# uv-managed project (system pytest ran against the wrong environment), needing a manual
# LEAN_TEST_CMD override that a correct resolver should never have required.

set -uo pipefail
SCAFFOLD="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LIB="$SCAFFOLD/.claude/lib/_test-cmd.sh"
[ -f "$LIB" ] || { echo "test: cannot find _test-cmd.sh at $LIB" >&2; exit 1; }
command -v jq >/dev/null 2>&1 || { echo "test: jq required"; exit 1; }
# shellcheck disable=SC1090
. "$LIB"

FAILS=0
# pass/fail for the subshell-wrapped tests below: fail RETURNS nonzero so the enclosing
# `( ... ) || FAILS=$((FAILS+1))` counts it (a subshell's own FAILS++ would be lost on exit).
pass() { printf '  ✓ %s\n' "$1"; return 0; }
fail() { printf '  ✗ %s\n' "$1"; return 1; }

WORK="$(mktemp -d 2>/dev/null || mktemp -d -t leanstack)"
cleanup() { rm -rf "$WORK" 2>/dev/null; }
trap cleanup EXIT

# Stub `uv`/`poetry`/`pytest` on PATH — resolve_test_cmd only ever checks `command -v` for
# these, it never executes them, so trivial no-op stubs make the tests hermetic regardless of
# what's actually installed on the machine running them.
BIN="$WORK/bin"; mkdir -p "$BIN"
for tool in uv poetry pytest go cargo make mvn gradle dbt; do
  printf '#!/usr/bin/env bash\nexit 0\n' > "$BIN/$tool"
  chmod +x "$BIN/$tool"
done

scenario_dir() {
  local d
  d=$(mktemp -d "$WORK/proj.XXXXXX")
  cd "$d" || exit 1
}

expect_cmd() {
  local desc="$1" expected="$2" actual
  actual=$(resolve_test_cmd 2>/dev/null || true)
  if [ "$actual" = "$expected" ]; then
    printf "  ✓ %s -> '%s'\n" "$desc" "$actual"
    return 0
  else
    printf "  ✗ %s -> got '%s', expected '%s'\n" "$desc" "$actual" "$expected"
    return 1
  fi
}

expect_unresolved() {
  local desc="$1" actual
  actual=$(resolve_test_cmd 2>/dev/null || true)
  if [ -z "$actual" ]; then
    printf "  ✓ %s -> (unresolved, as expected)\n" "$desc"
    return 0
  else
    printf "  ✗ %s -> got '%s', expected unresolved\n" "$desc" "$actual"
    return 1
  fi
}

# The "nothing matched" path (M2) must: exit non-zero, keep STDOUT empty (command-capturing callers
# get no noise), AND emit a LEAN_TEST_CMD instruction on STDERR (was a SILENT empty before the fix).
expect_loud_fallback() {
  local desc="$1" out rc errf="$WORK/lf.err"
  out=$(resolve_test_cmd 2>"$errf"); rc=$?
  if [ "$rc" -ne 0 ] && [ -z "$out" ] && grep -q 'LEAN_TEST_CMD' "$errf"; then
    printf "  ✓ %s -> nonzero, clean stdout, stderr names LEAN_TEST_CMD\n" "$desc"; return 0
  else
    printf "  ✗ %s -> rc=%s stdout='%s' (want nonzero + empty stdout + LEAN_TEST_CMD on stderr)\n" "$desc" "$rc" "$out"; return 1
  fi
}

echo "test-cmd resolver tests"
echo ""

echo "\$LEAN_TEST_CMD always wins, regardless of what's on disk or PATH:"
(
  scenario_dir
  mkdir -p tests; : > uv.lock
  LEAN_TEST_CMD="custom runner"
  PATH="$BIN:$PATH"
  export LEAN_TEST_CMD PATH
  expect_cmd "LEAN_TEST_CMD override" "custom runner"
) || FAILS=$((FAILS+1))

echo ""
echo "uv-managed project: uv.lock + tests/ + uv on PATH -> uv run pytest, NOT bare pytest,"
echo "even though a bare pytest is ALSO on PATH (the exact regression this guards):"
(
  scenario_dir
  mkdir -p tests; : > uv.lock
  unset LEAN_TEST_CMD
  PATH="$BIN:$PATH"
  export PATH
  expect_cmd "uv.lock present, uv on PATH" "uv run pytest -q"
) || FAILS=$((FAILS+1))

echo ""
echo "poetry-managed project: poetry.lock + tests/ + poetry on PATH -> poetry run pytest:"
(
  scenario_dir
  mkdir -p tests; : > poetry.lock
  unset LEAN_TEST_CMD
  PATH="$BIN:$PATH"
  export PATH
  expect_cmd "poetry.lock present, poetry on PATH" "poetry run pytest -q"
) || FAILS=$((FAILS+1))

echo ""
echo "uv.lock present but uv NOT on PATH -> degrades gracefully to bare pytest, doesn't fail:"
(
  scenario_dir
  mkdir -p tests; : > uv.lock
  unset LEAN_TEST_CMD
  NOUV="$WORK/nouv"; mkdir -p "$NOUV"
  cp "$BIN/pytest" "$NOUV/pytest"
  PATH="$NOUV:/usr/bin:/bin"
  export PATH
  expect_cmd "uv.lock present, uv absent, pytest present" "pytest -q"
) || FAILS=$((FAILS+1))

echo ""
echo "uv.lock present but no test_*.py/tests/ signal at all -> not routed through pytest"
echo "just because a lockfile happens to exist:"
(
  scenario_dir
  : > uv.lock
  unset LEAN_TEST_CMD
  PATH="$BIN:/usr/bin:/bin"
  export PATH
  expect_unresolved "uv.lock with no pytest-suite signal"
) || FAILS=$((FAILS+1))

echo ""
echo "No lockfiles at all: existing baseline behavior preserved (tests/ + bare pytest):"
(
  scenario_dir
  mkdir -p tests
  unset LEAN_TEST_CMD
  PATH="$BIN:$PATH"
  export PATH
  expect_cmd "plain tests/ dir, no lockfile" "pytest -q"
) || FAILS=$((FAILS+1))

echo ""
echo "test_*.py files (no tests/ dir) also still trigger detection:"
(
  scenario_dir
  : > test_example.py
  unset LEAN_TEST_CMD
  PATH="$BIN:$PATH"
  export PATH
  expect_cmd "bare test_*.py, no tests/ dir" "pytest -q"
) || FAILS=$((FAILS+1))

echo ""
echo "package.json test script, no Python signals at all -> npm test:"
(
  scenario_dir
  printf '{"scripts":{"test":"vitest run"}}' > package.json
  unset LEAN_TEST_CMD
  PATH="$BIN:$PATH"
  export PATH
  expect_cmd "package.json with a test script" "npm test --silent"
) || FAILS=$((FAILS+1))

echo ""
echo "Nothing resolvable at all:"
(
  scenario_dir
  unset LEAN_TEST_CMD
  PATH="/usr/bin:/bin"
  export PATH
  expect_unresolved "empty project, no tools on PATH"
) || FAILS=$((FAILS+1))

echo ""
echo "LEAN_TEST_CMD env var UNSET but .claude/settings.json env block sets it ->"
echo "resolver reads it from the file (env-propagation-failure fallback):"
(
  scenario_dir
  mkdir -p .claude
  printf '{"env":{"LEAN_TEST_CMD":"settings-json runner"}}' > .claude/settings.json
  unset LEAN_TEST_CMD
  PATH="$BIN:$PATH"
  export PATH
  expect_cmd "settings.json env.LEAN_TEST_CMD, no env var" "settings-json runner"
) || FAILS=$((FAILS+1))

echo ""
echo "LEAN_TEST_CMD env var SET still wins over a DIFFERING settings.json value"
echo "(explicit env override keeps precedence over the file fallback):"
(
  scenario_dir
  mkdir -p .claude
  printf '{"env":{"LEAN_TEST_CMD":"settings-json runner"}}' > .claude/settings.json
  LEAN_TEST_CMD="env var runner"
  PATH="$BIN:$PATH"
  export LEAN_TEST_CMD PATH
  expect_cmd "env var beats settings.json" "env var runner"
) || FAILS=$((FAILS+1))

echo ""
echo "No .claude/settings.json at all -> falls through to existing uv.lock/pytest behavior:"
(
  scenario_dir
  mkdir -p tests; : > uv.lock
  unset LEAN_TEST_CMD
  PATH="$BIN:$PATH"
  export PATH
  expect_cmd "no settings.json, uv.lock present" "uv run pytest -q"
) || FAILS=$((FAILS+1))

echo ""
echo "settings.json present but its env block has NO LEAN_TEST_CMD key -> existing"
echo "uv.lock/pytest behavior unchanged (jq yields empty, degrades silently):"
(
  scenario_dir
  mkdir -p tests .claude; : > uv.lock
  printf '{"env":{"OTHER_VAR":"x"}}' > .claude/settings.json
  unset LEAN_TEST_CMD
  PATH="$BIN:$PATH"
  export PATH
  expect_cmd "settings.json without LEAN_TEST_CMD key" "uv run pytest -q"
) || FAILS=$((FAILS+1))

echo ""
echo "settings.json present but malformed JSON -> degrades silently to existing behavior"
echo "(no jq error noise on stdout, no crash):"
(
  scenario_dir
  mkdir -p tests .claude; : > uv.lock
  printf '{not valid json' > .claude/settings.json
  unset LEAN_TEST_CMD
  PATH="$BIN:$PATH"
  export PATH
  expect_cmd "malformed settings.json" "uv run pytest -q"
) || FAILS=$((FAILS+1))

echo ""
echo "settings.json has no top-level env block at all -> jq's // empty yields nothing,"
echo "falls through unchanged:"
(
  scenario_dir
  mkdir -p tests .claude; : > uv.lock
  printf '{"hooks":{}}' > .claude/settings.json
  unset LEAN_TEST_CMD
  PATH="$BIN:$PATH"
  export PATH
  expect_cmd "settings.json with no env block" "uv run pytest -q"
) || FAILS=$((FAILS+1))

echo ""
echo "M2 — common non-Python/JS ecosystems (were a hard tick-gate deadlock before):"
(
  scenario_dir; : > go.mod
  unset LEAN_TEST_CMD; PATH="$BIN:/usr/bin:/bin"; export PATH
  expect_cmd "go.mod + go on PATH" "go test ./..."
) || FAILS=$((FAILS+1))
(
  scenario_dir; : > Cargo.toml
  unset LEAN_TEST_CMD; PATH="$BIN:/usr/bin:/bin"; export PATH
  expect_cmd "Cargo.toml + cargo on PATH" "cargo test"
) || FAILS=$((FAILS+1))
(
  scenario_dir; printf 'test:\n\techo hi\n' > Makefile
  unset LEAN_TEST_CMD; PATH="$BIN:/usr/bin:/bin"; export PATH
  expect_cmd "Makefile with a test: target + make" "make test"
) || FAILS=$((FAILS+1))
(
  scenario_dir; : > pom.xml
  unset LEAN_TEST_CMD; PATH="$BIN:/usr/bin:/bin"; export PATH
  expect_cmd "pom.xml + mvn on PATH" "mvn -q test"
) || FAILS=$((FAILS+1))
(
  scenario_dir; : > build.gradle
  unset LEAN_TEST_CMD; PATH="$BIN:/usr/bin:/bin"; export PATH
  expect_cmd "build.gradle + gradle on PATH" "gradle test"
) || FAILS=$((FAILS+1))
# dbt: `dbt build` (models AND their tests), not `dbt test` — the audit's day-one blocker for a
# data-engineering project, whose first phase could not produce tick evidence without it.
(
  scenario_dir; : > dbt_project.yml
  unset LEAN_TEST_CMD; PATH="$BIN:/usr/bin:/bin"; export PATH
  expect_cmd "dbt_project.yml + dbt on PATH" "dbt build"
) || FAILS=$((FAILS+1))

echo ""
echo "A Makefile WITHOUT a real test: target must NOT resolve to make (falls through to loud fallback):"
(
  scenario_dir; printf 'build:\n\techo hi\n' > Makefile
  unset LEAN_TEST_CMD; PATH="$BIN:/usr/bin:/bin"; export PATH
  expect_loud_fallback "Makefile without a test: target"
) || FAILS=$((FAILS+1))

echo ""
echo "Ecosystem manifest present but its runner NOT on PATH -> falls through (never emits a command"
echo "whose runner is missing):"
(
  scenario_dir; : > go.mod
  unset LEAN_TEST_CMD
  # "PATH=/usr/bin:/bin" does NOT reliably hide `go`: GitHub's ubuntu runner ships it in /usr/bin
  # (macOS keeps it in /opt/homebrew, which is why this only bit in CI). Build a PATH with the
  # coreutils the harness needs (grep) but provably NO ecosystem runner, so `command -v go` fails.
  norunner="$WORK/norunner"; mkdir -p "$norunner"
  for _t in grep sed awk cat; do _p=$(command -v "$_t" 2>/dev/null) && ln -sf "$_p" "$norunner/$_t"; done
  PATH="$norunner"; export PATH
  expect_loud_fallback "go.mod present but go absent from PATH"
) || FAILS=$((FAILS+1))
# Same for dbt: a dbt_project.yml with no `dbt` installed must fall through to the loud fallback, never
# emit a command that cannot run. Uses the runner-free PATH farm above, NOT "/usr/bin:/bin" — a CI
# runner may ship a tool in /usr/bin, which would silently make this case vacuous.
(
  scenario_dir; : > dbt_project.yml
  unset LEAN_TEST_CMD
  norunner="$WORK/norunner-dbt"; mkdir -p "$norunner"
  for _t in grep sed awk cat; do _p=$(command -v "$_t" 2>/dev/null) && ln -sf "$_p" "$norunner/$_t"; done
  PATH="$norunner"; export PATH
  expect_loud_fallback "dbt_project.yml present but dbt absent from PATH"
) || FAILS=$((FAILS+1))

echo ""
echo "Precedence unchanged: LEAN_TEST_CMD still wins over a present go.mod:"
(
  scenario_dir; : > go.mod
  LEAN_TEST_CMD="custom runner"; PATH="$BIN:$PATH"; export LEAN_TEST_CMD PATH
  expect_cmd "LEAN_TEST_CMD beats go.mod" "custom runner"
) || FAILS=$((FAILS+1))

echo ""
echo "Unknown ecosystem / nothing matched -> LOUD precise LEAN_TEST_CMD instruction on stderr, non-zero"
echo "exit, clean stdout (was a SILENT empty before M2 — the deadlock this fix removes):"
(
  scenario_dir
  unset LEAN_TEST_CMD; PATH="/usr/bin:/bin"; export PATH
  expect_loud_fallback "empty project, nothing detected"
) || FAILS=$((FAILS+1))

echo ""
echo "authorized_test_cmd — the GRADED path (H2). It reads ONLY the LEAN_TEST_CMD env and the"
echo "gate-controlled .claude/test-command; NEVER settings.json's env block or a mutable manifest:"
(
  scenario_dir
  # H2 vectors present but authorized_test_cmd must IGNORE them: a builder could edit either.
  mkdir -p .claude
  printf '{"env":{"LEAN_TEST_CMD":"true"}}\n' > .claude/settings.json      # builder-writable
  printf '{"scripts":{"test":"exit 0"}}\n' > package.json                   # builder-writable
  unset LEAN_TEST_CMD
  authorized_test_cmd >/dev/null 2>&1; rc=$?
  [ "$rc" = 3 ] && pass "settings.json/package.json are NOT graded — no file, no env → fail-closed rc 3" \
                || fail "authorized_test_cmd read a mutable manifest/settings (rc=$rc, expected 3)"
) || FAILS=$((FAILS+1))
(
  scenario_dir
  export LEAN_TEST_CMD="pytest -q"
  out=$(authorized_test_cmd); rc=$?
  { [ "$rc" = 0 ] && [ "$out" = "pytest -q" ]; } && pass "LEAN_TEST_CMD env → used verbatim (trusted launcher)" || fail "env override not honored (rc=$rc, out='$out')"
) || FAILS=$((FAILS+1))
(
  scenario_dir; mkdir -p .claude; unset LEAN_TEST_CMD
  printf 'pytest -q\n' > .claude/test-command
  out=$(authorized_test_cmd); rc=$?
  { [ "$rc" = 0 ] && [ "$out" = "pytest -q" ]; } && pass ".claude/test-command → used when no env" || fail "file command not read (rc=$rc, out='$out')"
) || FAILS=$((FAILS+1))
(
  scenario_dir; mkdir -p .claude; unset LEAN_TEST_CMD
  printf 'true\n' > .claude/test-command
  authorized_test_cmd >/dev/null 2>&1; rc=$?
  [ "$rc" = 2 ] && pass "a no-op ('true') in .claude/test-command → REJECTED (rc 2, never grades green)" || fail "no-op file command not rejected (rc=$rc)"
) || FAILS=$((FAILS+1))
# F3c — bounded, high-confidence WRAPPED / degenerate no-ops are also rejected (a builder cannot dodge
# the reject list by wrapping `true` in `sh -c`, or using an output-only echo/printf).
for nop in 'sh -c true' 'bash -c true' 'sh -c :' "bash -c 'exit 0'" 'exit 0' 'echo pass' 'printf ok' ': ; :' '  bash -c true  '; do
  (
    scenario_dir; mkdir -p .claude; unset LEAN_TEST_CMD
    printf '%s\n' "$nop" > .claude/test-command
    authorized_test_cmd >/dev/null 2>&1; rc=$?
    [ "$rc" = 2 ] && pass "wrapped/degenerate no-op rejected: '$nop' → rc 2" || fail "wrapped no-op NOT rejected: '$nop' (rc=$rc)"
  ) || FAILS=$((FAILS+1))
done
# ...but a REAL command must NOT be over-rejected — including a genuine pipeline that starts with echo.
for real in 'pytest -q' 'npm test --silent' 'go test ./...' 'echo hi | ./run-tests.sh'; do
  (
    scenario_dir; mkdir -p .claude; unset LEAN_TEST_CMD
    printf '%s\n' "$real" > .claude/test-command
    out=$(authorized_test_cmd); rc=$?
    { [ "$rc" = 0 ] && [ "$out" = "$real" ]; } && pass "real command accepted (not a no-op): '$real'" || fail "real command wrongly rejected: '$real' (rc=$rc)"
  ) || FAILS=$((FAILS+1))
done
(
  scenario_dir; mkdir -p .claude; unset LEAN_TEST_CMD
  printf 'none: this phase is docs-only, no tests\n' > .claude/test-command
  authorized_test_cmd >/dev/null 2>&1; rc=$?
  [ "$rc" = 1 ] && pass "'none: <reason>' sentinel → rc 1 (explicit no-tests, not a no-op reject)" || fail "none: sentinel mishandled (rc=$rc)"
) || FAILS=$((FAILS+1))

echo ""
echo "_seed_test_cmd — migration seeding reads PERSISTENT config only (settings.json + autodetect),"
echo "NEVER the transient LEAN_TEST_CMD process env (D1):"
(
  scenario_dir; mkdir -p .claude
  export LEAN_TEST_CMD="transient-should-not-persist"          # transient process env
  printf '{"env":{"LEAN_TEST_CMD":"pytest -q"}}\n' > .claude/settings.json   # persistent
  out=$(_seed_test_cmd); rc=$?
  { [ "$rc" = 0 ] && printf '%s' "$out" | grep -q 'pytest -q' && ! printf '%s' "$out" | grep -q 'transient'; } \
    && pass "seed uses settings.json (persistent), NOT the transient LEAN_TEST_CMD env" \
    || fail "seed leaked the transient env or missed persistent config (rc=$rc, out='$out')"
) || FAILS=$((FAILS+1))
(
  scenario_dir; unset LEAN_TEST_CMD
  # nothing persistent, autodetect finds nothing safe → seed refuses (leave the file absent)
  PATH="/usr/bin:/bin"; export PATH
  _seed_test_cmd >/dev/null 2>&1; rc=$?
  [ "$rc" = 1 ] && pass "no persistent config + no autodetect → seed returns nothing (file left absent, fail-closed)" || fail "seed produced something from nothing (rc=$rc)"
) || FAILS=$((FAILS+1))

echo ""
if [ "$FAILS" -eq 0 ]; then echo "All test-cmd resolver tests passed."; exit 0
else echo "$FAILS test-cmd resolver test(s) FAILED."; exit 1; fi
