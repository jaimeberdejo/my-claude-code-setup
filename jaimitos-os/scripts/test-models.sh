#!/usr/bin/env bash
# test-models.sh — behavioral tests for scripts/models.sh, the deterministic get/set for
# which model each /phase stage uses. Regression guard for the frontmatter-mutation contract:
# exact insert-vs-replace-vs-remove behavior, all=/explicit-override precedence, validation
# refuses BEFORE touching any file, and the body below frontmatter is never touched.

set -uo pipefail
SCAFFOLD="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MODELS="$SCAFFOLD/scripts/models.sh"
[ -f "$MODELS" ] || { echo "test: cannot find models.sh at $MODELS" >&2; exit 1; }
command -v git >/dev/null 2>&1 || { echo "test: git required"; exit 1; }

FAILS=0
pass() { printf '  ✓ %s\n' "$1"; }
fail() { printf '  ✗ %s\n' "$1"; FAILS=$((FAILS+1)); }

WORK="$(mktemp -d 2>/dev/null || mktemp -d -t leanstack-models)"
trap 'rm -rf "$WORK" 2>/dev/null' EXIT
REPO="$WORK/proj"; mkdir -p "$REPO/.claude/agents"
cd "$REPO" || exit 1
git init -q && git config user.email t@t.t && git config user.name t

all_bodies() {
  cat .claude/agents/researcher.md .claude/agents/planner.md .claude/agents/executor.md .claude/agents/evaluator.md 2>/dev/null
}

write_fixture() {
  cat > .claude/agents/researcher.md <<'EOF'
---
name: researcher
description: test fixture
tools: Read, Glob, Grep, WebFetch, WebSearch
---
body unchanged marker RESEARCHER
EOF
  cat > .claude/agents/planner.md <<'EOF'
---
name: planner
description: test fixture
tools: Read, Glob, Grep, Write
---
body unchanged marker PLANNER
EOF
  cat > .claude/agents/executor.md <<'EOF'
---
name: executor
description: test fixture
tools: Read, Write, Edit, Bash, Glob, Grep
---
body unchanged marker EXECUTOR
EOF
  cat > .claude/agents/evaluator.md <<'EOF'
---
name: evaluator
description: test fixture
tools: Read, Glob, Grep, Bash
model: sonnet
---
body unchanged marker EVALUATOR
EOF
  git add -A >/dev/null 2>&1 && git commit -q -m fixture --allow-empty
}

echo "models.sh tests"; echo ""

echo "Default show: research/plan/exec inherit, eval sonnet"
write_fixture
OUT=$(bash "$MODELS")
echo "$OUT" | grep -qE '^research: *\(inherits session model\)$' && pass "research inherits by default" || fail "research default wrong: $OUT"
echo "$OUT" | grep -qE '^plan: *\(inherits session model\)$'     && pass "plan inherits by default"     || fail "plan default wrong"
echo "$OUT" | grep -qE '^exec: *\(inherits session model\)$'     && pass "exec inherits by default"     || fail "exec default wrong"
echo "$OUT" | grep -qE '^eval: *sonnet$'                          && pass "eval defaults to sonnet"      || fail "eval default wrong"

echo ""
echo "exec=opus inserts exactly one model: line"
write_fixture
bash "$MODELS" exec=opus >/dev/null
[ "$(grep -c '^model:' .claude/agents/executor.md)" -eq 1 ] && pass "exactly one model: line after insert" || fail "wrong number of model: lines"
grep -q '^model: opus$' .claude/agents/executor.md && pass "model: opus present" || fail "model: opus not found"

echo ""
echo "Updating exec replaces the existing line, never duplicates it"
bash "$MODELS" exec=sonnet >/dev/null
[ "$(grep -c '^model:' .claude/agents/executor.md)" -eq 1 ] && pass "still exactly one model: line after update" || fail "update duplicated the model: line"
grep -q '^model: sonnet$' .claude/agents/executor.md && pass "model: line updated to sonnet" || fail "update did not take effect"

echo ""
echo "all=haiku exec=sonnet: exec ends up sonnet, the other three end up haiku"
write_fixture
bash "$MODELS" all=haiku exec=sonnet >/dev/null
grep -q '^model: sonnet$' .claude/agents/executor.md   && pass "exec (explicit) = sonnet"    || fail "exec did not win over all="
grep -q '^model: haiku$'  .claude/agents/researcher.md && pass "research (via all=) = haiku" || fail "research not set by all="
grep -q '^model: haiku$'  .claude/agents/planner.md    && pass "plan (via all=) = haiku"     || fail "plan not set by all="
grep -q '^model: haiku$'  .claude/agents/evaluator.md  && pass "eval (via all=) = haiku"     || fail "eval not set by all="

echo ""
echo "reset restores each role to ITS OWN shipped default (not the same value for all four)"
bash "$MODELS" reset >/dev/null
grep -qE '^model:' .claude/agents/researcher.md       && fail "researcher still has a model: line after reset" || pass "researcher reset to inherit"
grep -qE '^model:' .claude/agents/planner.md          && fail "planner still has a model: line after reset"    || pass "planner reset to inherit"
grep -qE '^model:' .claude/agents/executor.md         && fail "executor still has a model: line after reset"   || pass "executor reset to inherit"
grep -q '^model: sonnet$' .claude/agents/evaluator.md && pass "evaluator reset to its own default (sonnet)"    || fail "evaluator not reset to sonnet"

echo ""
echo "Invalid key refuses, touches nothing"
write_fixture
BEFORE=$(all_bodies)
bash "$MODELS" bogus=opus >/dev/null 2>&1 && fail "invalid key did not exit nonzero" || pass "invalid key exits nonzero"
AFTER=$(all_bodies)
[ "$BEFORE" = "$AFTER" ] && pass "invalid key left all 4 files untouched" || fail "invalid key modified a file"

echo ""
echo "Empty value refuses, touches nothing"
BEFORE=$(all_bodies)
bash "$MODELS" exec= >/dev/null 2>&1 && fail "empty value did not exit nonzero" || pass "empty value exits nonzero"
AFTER=$(all_bodies)
[ "$BEFORE" = "$AFTER" ] && pass "empty value left all 4 files untouched" || fail "empty value modified a file"

echo ""
echo "Malformed value (embedded ':') refuses without modifying files"
BEFORE=$(all_bodies)
bash "$MODELS" exec="bad:value" >/dev/null 2>&1 && fail "malformed value did not exit nonzero" || pass "malformed value exits nonzero"
AFTER=$(all_bodies)
[ "$BEFORE" = "$AFTER" ] && pass "malformed value left all 4 files untouched" || fail "malformed value modified a file"

echo ""
echo "Batch validation is atomic: one bad pair blocks the WHOLE batch, including the good pairs"
BEFORE=$(cat .claude/agents/planner.md)
bash "$MODELS" plan=opus exec="bad value" >/dev/null 2>&1
AFTER=$(cat .claude/agents/planner.md)
[ "$BEFORE" = "$AFTER" ] && pass "good pair in a bad batch was NOT applied" || fail "batch was partially applied"

echo ""
echo "Body below frontmatter, and other frontmatter fields, remain byte-identical after a set"
write_fixture
bash "$MODELS" exec=opus >/dev/null
grep -q "body unchanged marker EXECUTOR" .claude/agents/executor.md && pass "executor body untouched" || fail "executor body was altered"
grep -q "^name: executor$" .claude/agents/executor.md && pass "executor's other frontmatter fields untouched" || fail "other frontmatter fields altered"

echo ""
echo "settings.json is never touched, if present"
printf '{"permissions":{"deny":[]}}\n' > .claude/settings.json
BEFORE=$(cat .claude/settings.json)
bash "$MODELS" exec=opus >/dev/null
AFTER=$(cat .claude/settings.json)
[ "$BEFORE" = "$AFTER" ] && pass "settings.json byte-identical after a set" || fail "settings.json was modified"
rm -f .claude/settings.json

echo ""
echo "Duplicate pre-existing model: lines are refused, not silently picked from"
write_fixture
cat > .claude/agents/executor.md <<'EOF'
---
name: executor
description: corrupted fixture with two model: lines
tools: Read
model: opus
model: sonnet
---
body
EOF
bash "$MODELS" exec=haiku >/dev/null 2>&1 && fail "did not refuse a corrupted (duplicate model:) file" || pass "refuses when a role file already has duplicate model: lines"

echo ""
echo "Values containing sed/awk metacharacters round-trip byte-for-byte, update path (&, /, \\)"
write_fixture
bash "$MODELS" exec=opus >/dev/null   # give exec an existing model: line first (update path)
bash "$MODELS" 'exec=foo&bar' >/dev/null
grep -qx 'model: foo&bar' .claude/agents/executor.md && pass "'&' survives update path unmangled" || fail "'&' corrupted the model: line on update path"
grep -q "body unchanged marker EXECUTOR" .claude/agents/executor.md && pass "body untouched after '&' update" || fail "body altered after '&' update"
bash "$MODELS" 'exec=a/b' >/dev/null
grep -qx 'model: a/b' .claude/agents/executor.md && pass "'/' survives update path unmangled" || fail "'/' broke sed delimiter parsing on update path"
bash "$MODELS" 'exec=a\b' >/dev/null
[ "$(grep '^model:' .claude/agents/executor.md)" = 'model: a\b' ] && pass "'\\' survives update path unmangled" || fail "'\\' was mangled on update path"

echo ""
echo "Values containing awk -v escape sequences round-trip byte-for-byte, insert path (\\n, \\b)"
write_fixture
bash "$MODELS" 'research=foo\nbar' >/dev/null
[ "$(grep -c '^model:' .claude/agents/researcher.md)" -eq 1 ] && pass "'\\n' insert produced exactly one model: line (no stray injected line)" || fail "'\\n' injected an extra line into the frontmatter"
grep -qxF 'model: foo\nbar' .claude/agents/researcher.md && pass "literal backslash-n survives insert path unmangled" || fail "literal backslash-n was turned into a real newline"
write_fixture
bash "$MODELS" 'research=a\b' >/dev/null
[ "$(grep '^model:' .claude/agents/researcher.md)" = 'model: a\b' ] && pass "literal backslash-b survives insert path unmangled" || fail "literal backslash-b was turned into a control byte"

echo ""
echo "Malformed/missing frontmatter delimiters: refuses cleanly instead of silently no-op'ing or corrupting"
write_fixture
printf -- '---\nname: executor\ntools: Read\nbody, no closing delimiter\n' > .claude/agents/executor.md
BEFORE=$(cat .claude/agents/executor.md)
bash "$MODELS" exec=opus >/dev/null 2>&1 && fail "missing closing --- did not exit nonzero" || pass "missing closing --- exits nonzero"
AFTER=$(cat .claude/agents/executor.md)
[ "$BEFORE" = "$AFTER" ] && pass "missing closing --- left the file untouched" || fail "missing closing --- modified the file"

echo ""
echo "A deleted role file is refused with a clear error, not a silent stray .tmp file"
write_fixture
rm -f .claude/agents/researcher.md
bash "$MODELS" research=opus >/dev/null 2>&1 && fail "deleted role file did not exit nonzero" || pass "deleted role file exits nonzero"
[ -e .claude/agents/researcher.md.tmp ] && fail "a stray researcher.md.tmp was left behind" || pass "no stray .tmp file left behind"

echo ""
echo "chmod 444 on a role file survives a set on EITHER code path (insert and update)"
write_fixture
chmod 444 .claude/agents/executor.md
bash "$MODELS" exec=opus >/dev/null   # insert path (no pre-existing model: line)
PERM_AFTER_INSERT=$(ls -l .claude/agents/executor.md | cut -c1-10)
case "$PERM_AFTER_INSERT" in -r--r--r--*) pass "insert path preserves chmod 444" ;; *) fail "insert path reset permissions to $PERM_AFTER_INSERT" ;; esac
chmod 444 .claude/agents/executor.md
bash "$MODELS" exec=sonnet >/dev/null   # update path (model: line now exists)
PERM_AFTER_UPDATE=$(ls -l .claude/agents/executor.md | cut -c1-10)
case "$PERM_AFTER_UPDATE" in -r--r--r--*) pass "update path preserves chmod 444" ;; *) fail "update path reset permissions to $PERM_AFTER_UPDATE" ;; esac
chmod 644 .claude/agents/executor.md   # restore so later fixtures/cleanup aren't blocked by read-only perms

echo ""
echo "CLAUDE_CODE_SUBAGENT_MODEL warning appears in the no-arg report only when set"
write_fixture
OUT=$(CLAUDE_CODE_SUBAGENT_MODEL=haiku bash "$MODELS")
echo "$OUT" | grep -q "CLAUDE_CODE_SUBAGENT_MODEL=haiku" && pass "warns when CLAUDE_CODE_SUBAGENT_MODEL is set" || fail "no warning shown"
OUT2=$(bash "$MODELS")
echo "$OUT2" | grep -q "CLAUDE_CODE_SUBAGENT_MODEL" && fail "warns even when the env var is unset" || pass "no warning when the env var is unset"

echo ""
echo "H2: reset with a MISSING role file → non-zero exit and NO stray .tmp (was a silent false-success)"
write_fixture
rm -f .claude/agents/researcher.md
bash "$MODELS" reset >/dev/null 2>&1 && fail "reset with a missing role file exited 0 (false success)" || pass "reset with a missing role file exits nonzero"
[ -e .claude/agents/researcher.md.tmp ] && fail "reset left a stray researcher.md.tmp behind" || pass "reset left no stray .tmp behind"

echo ""
echo "H2: reset on a well-formed tree still restores each role's shipped default"
write_fixture
bash "$MODELS" all=opus >/dev/null
bash "$MODELS" reset >/dev/null
{ ! grep -qE '^model:' .claude/agents/researcher.md && ! grep -qE '^model:' .claude/agents/planner.md \
  && ! grep -qE '^model:' .claude/agents/executor.md && grep -q '^model: sonnet$' .claude/agents/evaluator.md; } \
  && pass "reset restores shipped defaults on a valid tree" || fail "reset did not restore defaults on a valid tree"

echo ""
echo "M3: a stray 'model:' line in the BODY (outside frontmatter) is never read, updated, or removed"
write_fixture
cat > .claude/agents/executor.md <<'EOF'
---
name: executor
description: test fixture
tools: Read
model: opus
---
body unchanged marker EXECUTOR
model: body-decoy-not-config
EOF
git add -A >/dev/null 2>&1; git commit -q -m m3fixture --allow-empty
OUT=$(bash "$MODELS")   # capture (never `models | grep -q`: SIGPIPE+pipefail flakes on an early match)
echo "$OUT" | grep -qE '^exec: *opus$' && pass "M3: current model read from frontmatter, body model: ignored" || fail "M3: body model: read as config (or dup-check refused)"
bash "$MODELS" exec=sonnet >/dev/null 2>&1
grep -q '^model: sonnet$' .claude/agents/executor.md && pass "M3: set updated the FRONTMATTER model:" || fail "M3: set did not update the frontmatter model:"
grep -q '^model: body-decoy-not-config$' .claude/agents/executor.md && pass "M3: body model: line untouched by set" || fail "M3: set rewrote the body model: line"
bash "$MODELS" reset >/dev/null 2>&1
grep -q '^model: body-decoy-not-config$' .claude/agents/executor.md && pass "M3: body model: line survives reset" || fail "M3: reset removed the body model: line"
[ "$(grep -c '^model:' .claude/agents/executor.md)" -eq 1 ] && pass "M3: after reset only the body decoy remains (frontmatter model: removed)" || fail "M3: reset frontmatter-scoping wrong"

echo ""
if [ "$FAILS" -eq 0 ]; then echo "All models.sh tests passed."; exit 0
else echo "$FAILS models.sh test(s) FAILED."; exit 1; fi
