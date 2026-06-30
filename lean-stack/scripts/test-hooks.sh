#!/usr/bin/env bash
# test-hooks.sh — feed each hook the kind of JSON Claude Code sends on stdin
# and confirm it runs without error. This is a smoke test, not a behavior spec:
# it catches the "hook crashes / aborts early" class of bug (the kind that
# silently broke ownership-nudge and session-start before).
#
# Run from the repo root: bash scripts/test-hooks.sh

set -uo pipefail
cd "$(git rev-parse --show-toplevel 2>/dev/null || echo .)" || exit 1
export CLAUDE_PROJECT_DIR="$PWD"

FAILS=0
run() {
  local name="$1" script="$2" json="$3"
  if printf '%s' "$json" | bash "$script" >/dev/null 2>&1; then
    printf '  ✓ %s\n' "$name"
  else
    printf '  ✗ %s (exit %d)\n' "$name" "$?"
    FAILS=$((FAILS+1))
  fi
}

echo "hook smoke tests"
echo ""

run "SessionStart"            .claude/hooks/session-start.sh   '{"hook_event_name":"SessionStart","source":"startup"}'
run "UserPromptSubmit/steer"  .claude/hooks/steer.sh           '{"hook_event_name":"UserPromptSubmit","prompt":"hi"}'
run "PreToolUse/steer"        .claude/hooks/steer.sh           '{"hook_event_name":"PreToolUse","tool_name":"Edit"}'
run "PreToolUse/kill-switch"  .claude/hooks/kill-switch.sh     '{"hook_event_name":"PreToolUse","tool_name":"Bash"}'
run "PostToolUse/format"      .claude/hooks/format-on-edit.sh  '{"hook_event_name":"PostToolUse","tool_input":{"file_path":"/nonexistent.py"}}'
run "Stop/test-gate(off)"     .claude/hooks/test-gate.sh       '{"hook_event_name":"Stop","stop_hook_active":false}'
run "Stop/commit"             .claude/hooks/commit-on-stop.sh  '{"hook_event_name":"Stop","stop_hook_active":true}'
run "Stop/ownership"          .claude/hooks/ownership-nudge.sh '{"hook_event_name":"Stop","stop_hook_active":true}'

echo ""
# Verify kill-switch actually blocks (exit 2) when AGENT_STOP exists.
touch AGENT_STOP
if printf '%s' '{"hook_event_name":"PreToolUse"}' | bash .claude/hooks/kill-switch.sh >/dev/null 2>&1; then
  printf '  ✗ kill-switch did NOT block with AGENT_STOP present\n'; FAILS=$((FAILS+1))
else
  printf '  ✓ kill-switch blocks (exit 2) when AGENT_STOP present\n'
fi
rm -f AGENT_STOP

# Verify kill-switch FAILS CLOSED even when CLAUDE_PROJECT_DIR is unset.
# Under `set -u`, an unset var must NOT abort the hook before the AGENT_STOP check.
(
  unset CLAUDE_PROJECT_DIR
  touch AGENT_STOP
  printf '%s' '{"hook_event_name":"PreToolUse"}' | bash .claude/hooks/kill-switch.sh >/dev/null 2>&1
  rc=$?
  rm -f AGENT_STOP
  exit "$rc"
)
if [ "$?" -eq 2 ]; then
  printf '  ✓ kill-switch fails closed (exit 2) when CLAUDE_PROJECT_DIR unset\n'
else
  printf '  ✗ kill-switch did NOT fail closed with CLAUDE_PROJECT_DIR unset\n'; FAILS=$((FAILS+1))
fi

# Harder case: env var unset AND invoked from a SUBDIRECTORY. The brake must still fire
# (resolve the repo root via `git rev-parse --show-toplevel`), not fail open.
mkdir -p .ks-subdir-test
(
  unset CLAUDE_PROJECT_DIR
  touch AGENT_STOP
  cd .ks-subdir-test || exit 99
  printf '%s' '{"hook_event_name":"PreToolUse"}' | bash "$PWD/../.claude/hooks/kill-switch.sh" >/dev/null 2>&1
  rc=$?
  rm -f ../AGENT_STOP
  exit "$rc"
)
ks_sub_rc=$?
rmdir .ks-subdir-test 2>/dev/null || true
if [ "$ks_sub_rc" -eq 2 ]; then
  printf '  ✓ kill-switch fails closed from a subdir with CLAUDE_PROJECT_DIR unset\n'
else
  printf '  ✗ kill-switch FAILED OPEN from a subdir (rc=%s)\n' "$ks_sub_rc"; FAILS=$((FAILS+1))
fi

# Wiring assertion: the brake is only effective if settings.json actually dispatches
# kill-switch.sh on EVERY tool call. Per the Claude Code hooks docs, "*", "" and an
# omitted matcher all mean match-all; a narrowed matcher (e.g. "Bash") would fail open.
# (Unit-asserts the wiring shape; live harness dispatch can only be confirmed at runtime.)
if jq -e '
      [ .hooks.PreToolUse[]?
        | select([.hooks[]?.command | select(test("kill-switch"))] | length > 0)
        | (.matcher // "*") ] as $ms
      | ($ms | length > 0) and ($ms | all(. == "" or . == "*"))
    ' .claude/settings.json >/dev/null 2>&1; then
  printf '  ✓ kill-switch wired into PreToolUse with a match-all matcher\n'
else
  printf '  ✗ kill-switch NOT wired match-all in PreToolUse (brake may not fire on every tool)\n'; FAILS=$((FAILS+1))
fi

echo ""
# Verify the SHARED secret-scan library blocks a planted credential and does NOT
# false-positive on a clean file. Runs in an ISOLATED temp git repo so we never
# stage a secret into this repo.
SCAN_LIB="$PWD/.claude/lib/_secret-scan.sh"
if [ -f "$SCAN_LIB" ]; then
  (
    set -uo pipefail
    tmp=$(mktemp -d) || exit 20
    trap 'rm -rf "$tmp"' EXIT
    cd "$tmp" || exit 21
    git init -q . && git config user.email t@t.t && git config user.name t || exit 22
    . "$SCAN_LIB"
    # 1) a high-confidence token in an ordinary file MUST be flagged (rc 1).
    printf 'aws_key = "AKIA1234567890ABCDEF"\n' > config.py
    git add config.py
    secret_scan_staged >/dev/null 2>&1; src=$?
    [ "$src" -eq 1 ] || exit 11
    # 2) a clean staged file MUST pass (rc 0).
    git reset -q
    printf 'x = 1\n' > ok.py
    git add ok.py
    secret_scan_staged >/dev/null 2>&1; src=$?
    [ "$src" -eq 0 ] || exit 12
    exit 0
  )
  rc=$?
  case "$rc" in
    0)  printf '  ✓ secret-scan blocks a planted AWS key and passes a clean file\n' ;;
    11) printf '  ✗ secret-scan did NOT flag a planted AWS key\n'; FAILS=$((FAILS+1)) ;;
    12) printf '  ✗ secret-scan false-positived on a clean file\n'; FAILS=$((FAILS+1)) ;;
    *)  printf '  ✗ secret-scan test harness errored (rc=%d)\n' "$rc"; FAILS=$((FAILS+1)) ;;
  esac
else
  printf '  ✗ missing .claude/lib/_secret-scan.sh (shared secret-scan lib)\n'; FAILS=$((FAILS+1))
fi

echo ""
if [ "$FAILS" -eq 0 ]; then echo "All hook smoke tests passed."; exit 0
else echo "$FAILS hook test(s) failed."; exit 1; fi
