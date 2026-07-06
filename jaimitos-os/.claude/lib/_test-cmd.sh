#!/usr/bin/env bash
# _test-cmd.sh — SHARED test-command resolver (sourced, not a hook).
# Single source of truth for "how do we run THIS project's tests", used by both the
# advisory Stop hook (.claude/hooks/test-gate.sh) and the authoritative tick-evidence
# producer (scripts/test-evidence.sh) so the resolution can never drift between them.
#
# resolve_test_cmd: echoes the test command to stdout; returns 0 if one was resolved,
# 1 if none. Order (first match wins):
#   1. $LEAN_TEST_CMD if set, OR (if unset) the same key read from .claude/settings.json's
#      `env` block — see _lean_test_cmd_from_settings() below
#   2. uv run pytest -q      (uv.lock present, `uv` on PATH, and a tests/ dir or test_*.py exists)
#   3. poetry run pytest -q  (poetry.lock present, `poetry` on PATH, and a tests/ dir or test_*.py exists)
#   4. pytest -q             (pytest on PATH AND a tests/ dir or test_*.py exists)
#   5. npm test --silent     (package.json has a "test" script; needs jq)
#
# Lockfile-managed Python envs (2 and 3) are checked BEFORE the bare-PATH pytest fallback (4):
# a project pinned to uv/poetry keeps its real dependencies in THAT tool's venv, not
# necessarily whatever `pytest` happens to resolve to first on PATH — dogfooding hit this on a
# uv-managed project (system pytest ran, but against the wrong/incomplete environment). Gated
# on the SAME pytest-suite signal as (4) (a tests/ dir or test_*.py) so a project that merely
# has a uv.lock for non-test reasons doesn't get routed through pytest it doesn't actually run.

# _lean_test_cmd_from_settings: echoes LEAN_TEST_CMD read from .claude/settings.json's `env`
# block, if any. Exists because settings.json's `env` block does NOT reliably reach a raw
# Bash-tool subprocess in every Claude Code invocation path — when that propagation fails,
# $LEAN_TEST_CMD is empty and resolve_test_cmd would otherwise fall through to a bare `pytest`
# (wrong/incomplete env on a uv/poetry-managed project). This reads the SAME value straight from
# the file so resolution never depends on env propagation. Silent no-op (empty stdout, no
# stderr noise) on any failure: no settings.json, no jq, malformed JSON, or an absent/null key.
_lean_test_cmd_from_settings() {
  [ -f .claude/settings.json ] || return 0
  command -v jq >/dev/null 2>&1 || return 0
  jq -r '.env.LEAN_TEST_CMD | select(type=="string") // empty' .claude/settings.json 2>/dev/null
  return 0
}

resolve_test_cmd() {
  if [ -n "${LEAN_TEST_CMD:-}" ]; then
    printf '%s' "$LEAN_TEST_CMD"; return 0
  fi
  local from_settings
  from_settings="$(_lean_test_cmd_from_settings)"
  if [ -n "$from_settings" ]; then
    printf '%s' "$from_settings"; return 0
  fi
  local has_pytest_suite=0
  { [ -d tests ] || ls test_*.py >/dev/null 2>&1; } && has_pytest_suite=1
  if [ "$has_pytest_suite" -eq 1 ] && [ -f uv.lock ] && command -v uv >/dev/null 2>&1; then
    printf '%s' "uv run pytest -q"; return 0
  fi
  if [ "$has_pytest_suite" -eq 1 ] && [ -f poetry.lock ] && command -v poetry >/dev/null 2>&1; then
    printf '%s' "poetry run pytest -q"; return 0
  fi
  if [ "$has_pytest_suite" -eq 1 ] && command -v pytest >/dev/null 2>&1; then
    printf '%s' "pytest -q"; return 0
  fi
  if [ -f package.json ] && command -v jq >/dev/null 2>&1 \
     && jq -e '.scripts.test' package.json >/dev/null 2>&1; then
    printf '%s' "npm test --silent"; return 0
  fi
  return 1
}

# Sourcing only defines the function; running this file directly is a harmless no-op.
return 0 2>/dev/null || exit 0
