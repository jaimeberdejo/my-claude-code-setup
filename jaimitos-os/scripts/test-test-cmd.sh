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

WORK="$(mktemp -d 2>/dev/null || mktemp -d -t leanstack)"
cleanup() { rm -rf "$WORK" 2>/dev/null; }
trap cleanup EXIT

# Stub `uv`/`poetry`/`pytest` on PATH — resolve_test_cmd only ever checks `command -v` for
# these, it never executes them, so trivial no-op stubs make the tests hermetic regardless of
# what's actually installed on the machine running them.
BIN="$WORK/bin"; mkdir -p "$BIN"
for tool in uv poetry pytest go cargo make mvn gradle; do
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
  unset LEAN_TEST_CMD; PATH="/usr/bin:/bin"; export PATH   # no go stub
  expect_loud_fallback "go.mod present but go absent from PATH"
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
if [ "$FAILS" -eq 0 ]; then echo "All test-cmd resolver tests passed."; exit 0
else echo "$FAILS test-cmd resolver test(s) FAILED."; exit 1; fi
