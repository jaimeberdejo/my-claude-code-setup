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
#   6. go test ./...          (go.mod present AND `go` on PATH)
#   7. cargo test             (Cargo.toml present AND `cargo` on PATH)
#   8. make test              (Makefile/makefile with a real `^test:` target AND `make` on PATH)
#   9. mvn -q test            (pom.xml present AND `mvn` on PATH)
#  10. gradle test            (build.gradle or build.gradle.kts present AND `gradle` on PATH)
#  11. dbt build             (dbt_project.yml present AND `dbt` on PATH)
#
# Ecosystem detectors (6-11) each require BOTH the manifest file AND the runner on PATH — mirroring
# how uv/poetry/npm are gated — so resolve_test_cmd never emits a command whose runner is not
# installed; an unmatched manifest simply falls through to the next check.
#
# dbt (11) runs `dbt build`, which executes the models AND their tests in dependency order — `dbt test`
# alone would grade a warehouse the phase never rebuilt. It sits with the other manifests, i.e. AFTER
# the pytest checks (2-4): `dbt init` scaffolds a `tests/` dir, so a dbt project that ALSO has pytest
# installed resolves to pytest first. That is intentional — a repo with both usually does have Python
# tests to run — but if you want the dbt run to be the graded suite, set LEAN_TEST_CMD="dbt build".
#
# If NOTHING matches, resolve_test_cmd writes a precise "no known test runner detected — set
# LEAN_TEST_CMD" message to STDERR (stdout stays clean for command-capturing callers) and returns 1.
# LEAN_TEST_CMD (env, or .claude/settings.json `.env.LEAN_TEST_CMD`) is REQUIRED — not merely
# "optional" — for any stack outside this detected set (e.g. Ruby, or a non-standard runner):
# without it the tick gate records passed:null and can never mark the phase done.
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
  # Common non-Python/JS ecosystems. Each requires BOTH the manifest AND the runner on PATH
  # (mirrors uv/poetry/npm gating), so we never emit a command whose runner is not installed.
  if [ -f go.mod ] && command -v go >/dev/null 2>&1; then
    printf '%s' "go test ./..."; return 0
  fi
  if [ -f Cargo.toml ] && command -v cargo >/dev/null 2>&1; then
    printf '%s' "cargo test"; return 0
  fi
  if command -v make >/dev/null 2>&1 \
     && { { [ -f Makefile ] && grep -qE '^test:' Makefile; } \
          || { [ -f makefile ] && grep -qE '^test:' makefile; }; }; then
    printf '%s' "make test"; return 0
  fi
  if [ -f pom.xml ] && command -v mvn >/dev/null 2>&1; then
    printf '%s' "mvn -q test"; return 0
  fi
  if { [ -f build.gradle ] || [ -f build.gradle.kts ]; } && command -v gradle >/dev/null 2>&1; then
    printf '%s' "gradle test"; return 0
  fi
  if [ -f dbt_project.yml ] && command -v dbt >/dev/null 2>&1; then
    printf '%s' "dbt build"; return 0
  fi
  # Nothing matched. Loud, precise instruction to STDERR (never stdout — command-capturing callers
  # must stay unaffected) so a non-pytest/npm project cannot silently deadlock the tick gate.
  printf '%s\n' "resolve_test_cmd: no known test runner detected for this project (checked uv/poetry/pytest, npm, go, cargo, make, mvn, gradle, dbt). Set LEAN_TEST_CMD to the exact test command via the environment, or add .env.LEAN_TEST_CMD to .claude/settings.json, so the tick gate can record test evidence." >&2
  return 1
}

# ============================================================================================
# authorized_test_cmd — the GRADED path (finding H2). resolve_test_cmd() above is the PROPOSAL
# function: it autodetects from mutable, builder-writable files (settings.json's env block, package.json,
# Makefile, …) and is fine for the advisory Stop-hook nudge and for SEEDING .claude/test-command at
# setup time. But those same files are exactly what an implementation agent can rewrite MID-PHASE to
# swap the graded suite for a no-op — and they are NOT gate-controlled. So the command whose result the
# tick gate TRUSTS must come only from sources that are either not builder-controllable or are
# gate-controlled + project-owned:
#   1. $LEAN_TEST_CMD env — set by the operator / CI / the autopilot orchestrator in the PARENT shell;
#      a headless builder cannot set it there. This is also how the test suites and CI legitimately
#      stub a suite, so it is accepted as-is (a trusted launcher's explicit choice).
#   2. .claude/test-command — a one-line, project-owned (never sync-managed), gate-controlled file
#      (in autopilot.sh's GATE_CONTROL_FILES). A no-op here (empty / true / : / exit 0) is REJECTED —
#      that is the builder-writable surface, so it gets the strict check. A line `none: <reason>`
#      (or a bare `none`) is the explicit "this phase legitimately has no tests" sentinel.
# It deliberately does NOT read settings.json's env block or ecosystem manifests — those are the H2
# vectors. Contract:
#   rc 0 + <cmd>  — a real command to run
#   rc 1          — explicit no-tests sentinel (`none:`)
#   rc 2          — a configured command was REJECTED as a no-op (fail-closed; never grade green)
#   rc 3          — nothing configured (no env, no file) — fail-closed / unconfigured

# _tc_is_noop <command>: 0 if <command> is a HIGH-CONFIDENCE degenerate/no-op that runs no tests, 1
# otherwise. Bounded on purpose — this is NOT arbitrary program-equivalence (a real binary that happens
# to exit 0 is undetectable; documented residual). It strips one `sh -c`/`bash -c` wrapper and one layer
# of surrounding quotes, then matches the classic no-ops plus bare echo/printf (output-only). It refuses
# to classify anything containing a shell operator ( | & ; < > ` ) as output-only, so a real pipeline
# like `echo x | grader` is never wrongly rejected.
_tc_is_noop() {
  local c="$1"
  case "$c" in 'sh -c '*) c="${c#sh -c }" ;; 'bash -c '*) c="${c#bash -c }" ;; esac
  case "$c" in \'*\') c="${c#\'}"; c="${c%\'}" ;; \"*\") c="${c#\"}"; c="${c%\"}" ;; esac
  c="${c#"${c%%[![:space:]]*}"}"; c="${c%"${c##*[![:space:]]}"}"   # trim
  case "$c" in
    ''|true|':'|'exit 0'|'/bin/true'|'/usr/bin/true'|': ; :'|'true ; true'|'true; true') return 0 ;;
  esac
  case "$c" in *[\|\&\;\<\>\`]*) return 1 ;; esac   # has an operator → could be a real pipeline
  case "$c" in echo|echo\ *|printf|printf\ *) return 0 ;; esac
  return 1
}

authorized_test_cmd() {
  if [ -n "${LEAN_TEST_CMD:-}" ]; then printf '%s' "$LEAN_TEST_CMD"; return 0; fi
  local f=".claude/test-command" line
  if [ -f "$f" ]; then
    # first non-blank, non-comment line, trimmed
    line=$(grep -vE '^[[:space:]]*(#|$)' "$f" 2>/dev/null | head -1)
    line="${line#"${line%%[![:space:]]*}"}"; line="${line%"${line##*[![:space:]]}"}"
    case "$line" in
      none|none:*) return 1 ;;
    esac
    if _tc_is_noop "$line"; then
      echo "authorized_test_cmd: .claude/test-command is empty, a no-op, or output-only ('$line') — not a real test suite (fail-closed)." >&2
      return 2
    fi
    printf '%s' "$line"; return 0
  fi
  echo "authorized_test_cmd: no authorized test command. Set LEAN_TEST_CMD, or write the command to" >&2
  echo "  .claude/test-command (run 'bash scripts/doctor.sh --fix' or the setup skill to seed it from" >&2
  echo "  your project config), or put 'none: <reason>' there for a genuinely test-less phase." >&2
  return 3
}

# authorized_test_cmd_source — echoes a short label for WHERE authorized_test_cmd resolved from, so
# evidence can record provenance. Kept separate so authorized_test_cmd's stdout stays the bare command.
authorized_test_cmd_source() {
  if [ -n "${LEAN_TEST_CMD:-}" ]; then printf 'env:LEAN_TEST_CMD'; return 0; fi
  [ -f .claude/test-command ] && { printf 'file:.claude/test-command'; return 0; }
  printf 'none'; return 0
}

# authorized_test_cmd_config_sha — the IDENTITY of the config that authorizes the command (finding
# F3/M3), so a phase-start anchor and the tick gate can prove the graded command did not change
# mid-phase. For the file source it is the sha256 of .claude/test-command; for the env source, the
# sha256 of the literal LEAN_TEST_CMD value; empty otherwise. A mid-phase rewrite of the file (or a
# changed env) is then detectable even if the resolved command string happens to be unchanged.
authorized_test_cmd_config_sha() {
  local src; src="$(authorized_test_cmd_source)"
  case "$src" in
    file:.claude/test-command)
      [ -f .claude/test-command ] && { shasum -a 256 .claude/test-command 2>/dev/null || sha256sum .claude/test-command 2>/dev/null; } | cut -d' ' -f1 ;;
    env:LEAN_TEST_CMD)
      printf '%s' "${LEAN_TEST_CMD:-}" | { shasum -a 256 2>/dev/null || sha256sum 2>/dev/null; } | cut -d' ' -f1 ;;
  esac
}

# _seed_test_cmd — resolve a command to SEED into .claude/test-command at migration/setup time, from
# PERSISTENT repo config ONLY (D1): settings.json's env.LEAN_TEST_CMD, then ecosystem autodetect. It
# must NOT read the transient $LEAN_TEST_CMD process env (that would bake a one-off shell override into
# a committed file). Rejects no-ops. Echoes "<cmd>\t<source>" and returns 0, or returns 1 if nothing
# safe was found. Callers write the command (not the source) to the file.
_seed_test_cmd() {
  local cmd src
  cmd="$(_lean_test_cmd_from_settings)"
  if [ -n "$cmd" ]; then src="settings.json:env.LEAN_TEST_CMD"; else
    # autodetect WITHOUT the transient env (unset in a subshell so resolve_test_cmd skips source #1)
    cmd="$( unset LEAN_TEST_CMD; resolve_test_cmd 2>/dev/null || true )"
    src="autodetect"
  fi
  case "$cmd" in
    ''|true|':'|'exit 0'|'/bin/true'|'/usr/bin/true') return 1 ;;   # nothing safe to seed
    *) printf '%s\t%s' "$cmd" "$src"; return 0 ;;
  esac
}

# seed_test_command_file — migration/setup helper (D1). If .claude/test-command does NOT already exist,
# seed it from PERSISTENT config only (via _seed_test_cmd — settings.json + autodetect, never the
# transient env). NEVER overwrites an existing file. On success prints the exact command + source it
# wrote. If nothing safe can be seeded, leaves the file ABSENT (the graded path then stays fail-closed)
# and prints a precise remediation note. rc 0 = a file exists now (seeded or pre-existing); rc 1 = none.
seed_test_command_file() {
  local f=".claude/test-command" out cmd src
  [ -f "$f" ] && return 0            # never overwrite a project-owned file
  if ! out="$(_seed_test_cmd)"; then
    echo "test-command: could not derive a test command from project config (settings.json env.LEAN_TEST_CMD" >&2
    echo "  or a detected ecosystem manifest). Left .claude/test-command ABSENT — the tick gate fails closed" >&2
    echo "  until you write the exact command there (one line), or export LEAN_TEST_CMD. Use 'none: <reason>'" >&2
    echo "  for a genuinely test-less project." >&2
    return 1
  fi
  cmd="${out%%	*}"; src="${out#*	}"   # split on the literal TAB _seed_test_cmd emits
  mkdir -p .claude 2>/dev/null || true
  {
    echo "# .claude/test-command — the ONE authorized test command for this project (finding H2)."
    echo "# The tick gate grades ONLY this command (or the LEAN_TEST_CMD env), never settings.json or a"
    echo "# mutable manifest. Project-owned: sync never overwrites it. First non-comment line is the command."
    echo "# Use 'none: <reason>' if this project genuinely has no tests."
    echo "# Seeded from: $src"
    printf '%s\n' "$cmd"
  } > "$f" 2>/dev/null || { echo "test-command: failed to write $f" >&2; return 1; }
  echo "test-command: seeded .claude/test-command → '$cmd'  (source: $src)"
  return 0
}

# Sourcing only defines the function; running this file directly is a harmless no-op.
return 0 2>/dev/null || exit 0
