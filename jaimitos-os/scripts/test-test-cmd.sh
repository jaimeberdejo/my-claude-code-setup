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
for tool in uv poetry pytest; do
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
  else
    printf "  ✗ %s -> got '%s', expected '%s'\n" "$desc" "$actual" "$expected"
    FAILS=$((FAILS+1))
  fi
}

expect_unresolved() {
  local desc="$1" actual
  actual=$(resolve_test_cmd 2>/dev/null || true)
  if [ -z "$actual" ]; then
    printf "  ✓ %s -> (unresolved, as expected)\n" "$desc"
  else
    printf "  ✗ %s -> got '%s', expected unresolved\n" "$desc" "$actual"
    FAILS=$((FAILS+1))
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
)

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
)

echo ""
echo "poetry-managed project: poetry.lock + tests/ + poetry on PATH -> poetry run pytest:"
(
  scenario_dir
  mkdir -p tests; : > poetry.lock
  unset LEAN_TEST_CMD
  PATH="$BIN:$PATH"
  export PATH
  expect_cmd "poetry.lock present, poetry on PATH" "poetry run pytest -q"
)

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
)

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
)

echo ""
echo "No lockfiles at all: existing baseline behavior preserved (tests/ + bare pytest):"
(
  scenario_dir
  mkdir -p tests
  unset LEAN_TEST_CMD
  PATH="$BIN:$PATH"
  export PATH
  expect_cmd "plain tests/ dir, no lockfile" "pytest -q"
)

echo ""
echo "test_*.py files (no tests/ dir) also still trigger detection:"
(
  scenario_dir
  : > test_example.py
  unset LEAN_TEST_CMD
  PATH="$BIN:$PATH"
  export PATH
  expect_cmd "bare test_*.py, no tests/ dir" "pytest -q"
)

echo ""
echo "package.json test script, no Python signals at all -> npm test:"
(
  scenario_dir
  printf '{"scripts":{"test":"vitest run"}}' > package.json
  unset LEAN_TEST_CMD
  PATH="$BIN:$PATH"
  export PATH
  expect_cmd "package.json with a test script" "npm test --silent"
)

echo ""
echo "Nothing resolvable at all:"
(
  scenario_dir
  unset LEAN_TEST_CMD
  PATH="/usr/bin:/bin"
  export PATH
  expect_unresolved "empty project, no tools on PATH"
)

echo ""
if [ "$FAILS" -eq 0 ]; then echo "All test-cmd resolver tests passed."; exit 0
else echo "$FAILS test-cmd resolver test(s) FAILED."; exit 1; fi
