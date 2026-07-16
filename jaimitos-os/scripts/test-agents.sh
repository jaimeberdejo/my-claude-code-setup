#!/usr/bin/env bash
# test-agents.sh — objective, mechanical checks on subagent definitions (.claude/agents/*.md).
# Shape only, never judgement: this suite can prove an agent's frontmatter is valid, its model value
# is real, its tool boundary is safe, it declares an output contract, and that it is covered by the
# gate-integrity list. It CANNOT prove the agent was justified — every agent definition is a
# control-plane change and needs human review (see docs/dev/AUTHORING.md).
#
#   1. frontmatter: name present, name == filename, description present, no duplicate names
#   2. NO hyphenated skill-style keys — in a SUBAGENT, allowed-tools / disallowed-tools /
#      permission-mode are silently-ignored no-ops, so a restriction you think you set doesn't exist
#   3. model: a real current alias (sonnet|opus|haiku|fable|inherit) or a full model id — never a
#      hardcoded obsolete name
#   4. every agent declares an output contract (the orchestrator has to be able to verify it ran)
#   5. graders are edit-disabled: an evaluator/reviewer must not hold Write or Edit
#   6. gate integrity: every agent file is listed in autopilot.sh's GATE_CONTROL_FILES, or a tampered
#      prompt could rubber-stamp a phase without the orchestrator noticing
#   7. the rules above actually fire — each is exercised against a bad fixture, not just asserted
#
# NOTE ON name == filename: this is a JAIMITOS CONVENTION (it keeps the catalog and the
# GATE_CONTROL_FILES list trivially derivable from the filename). Claude Code itself permits the
# agent's `name:` and its filename to differ.
set -uo pipefail
SCAFFOLD="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
AGENTS_DIR="$SCAFFOLD/.claude/agents"
AUTOPILOT="$SCAFFOLD/scripts/autopilot.sh"

FAILS=0
pass() { printf '  ✓ %s\n' "$1"; }
fail() { printf '  ✗ %s\n' "$1"; FAILS=$((FAILS+1)); }

WORK="$(mktemp -d 2>/dev/null || mktemp -d -t jaimitos-agents)"
trap 'rm -rf "$WORK" 2>/dev/null' EXIT

echo "agent-definition checks"; echo ""

[ -d "$AGENTS_DIR" ] || { echo "  ✗ no .claude/agents/ directory"; exit 1; }

fm() {
  awk -v k="$2" '
    /^---[[:space:]]*$/ { fence++; if (fence == 2) exit; next }
    fence == 1 && index($0, k ":") == 1 { sub("^" k ":[[:space:]]*", ""); print; exit }
  ' "$1"
}

# validate_agent <file> — echoes one violation per line; empty output == valid.
# This is the whole policy, in one place, so it can be run against fixtures as well as the real four.
validate_agent() {
  local f="$1" base name desc model tools
  base="$(basename "$f" .md)"
  name="$(fm "$f" name)"; desc="$(fm "$f" description)"
  model="$(fm "$f" model)"; tools="$(fm "$f" tools)"

  [ -n "$name" ] || echo "no name:"
  [ -n "$desc" ] || echo "no description:"
  [ -z "$name" ] || [ "$name" = "$base" ] || echo "name:'$name' != filename '$base' (Jaimitos convention)"

  # Hyphenated skill/command fields are silent no-ops inside a subagent.
  awk '/^---[[:space:]]*$/ { fence++; if (fence == 2) exit; next }
       fence == 1 && /^(allowed-tools|disallowed-tools|permission-mode):/ { print "hyphenated key is a silent no-op in a subagent: " $0 }' "$f"

  # Aliases are drift-proof; a pinned full id silently goes obsolete. We cannot know which ids are
  # current without a hardcoded list that would itself rot — so: alias = fine, pinned id = warn,
  # anything else = a real error.
  if [ -n "$model" ]; then
    case "$model" in
      sonnet|opus|haiku|fable|inherit) ;;
      claude-*) echo "warn: model '$model' is a pinned id — prefer an alias (sonnet/opus/haiku/fable/inherit), which cannot go obsolete" ;;
      *) echo "unsupported model value: '$model'" ;;
    esac
  fi

  # An output contract is whatever tells the orchestrator what it is getting back: an ## Output
  # section, a ## Verdict section (the evaluator's contract), or an explicit closing instruction.
  grep -qE '^## Output|^## Verdict|End with:|End your response|must END with' "$f" \
    || echo "no output contract (the orchestrator cannot verify what it produced)"

  # A grader that can edit the tree it grades is not a grader.
  case "$base" in
    evaluator|*review*)
      case "$tools" in *Write*|*Edit*) echo "grader '$base' holds Write/Edit — must be edit-disabled" ;; esac ;;
  esac
}

# --- 1-5 — the real four ------------------------------------------------------------------------
NAMES=""; DUPES=""
for f in "$AGENTS_DIR"/*.md; do
  [ -f "$f" ] || continue
  base="$(basename "$f" .md)"
  out="$(validate_agent "$f")"
  viol="$(printf '%s' "$out" | grep -v '^warn: ' || true)"
  advi="$(printf '%s' "$out" | grep    '^warn: ' || true)"
  [ -z "$viol" ] && pass "agent '$base' is well-formed (frontmatter, model, output contract, tool boundary)" \
                 || { fail "agent '$base' violations:"; printf '      %s\n' "$viol"; }
  [ -n "$advi" ] && printf '  ! %s\n' "${advi#warn: }"
  case " $NAMES " in *" $base "*) DUPES="$DUPES $base" ;; esac
  NAMES="$NAMES $base"
done
[ -z "$DUPES" ] && pass "no duplicate agent names" || fail "duplicate agent names:$DUPES"

# --- 6 — gate-integrity coverage ----------------------------------------------------------------
# autopilot.sh byte-compares each GATE_CONTROL_FILES entry against the launch commit. The evaluator
# prompt IS the grading contract, so an agent definition outside that list is an unguarded hole.
if [ -f "$AUTOPILOT" ]; then
  GCF="$(grep -E '^GATE_CONTROL_FILES=' "$AUTOPILOT" | head -1)"
  MISSING=""
  for f in "$AGENTS_DIR"/*.md; do
    [ -f "$f" ] || continue
    rel=".claude/agents/$(basename "$f")"
    case "$GCF" in *"$rel"*) ;; *) MISSING="$MISSING $rel" ;; esac
  done
  { [ -n "$GCF" ] && [ -z "$MISSING" ]; } \
    && pass "every agent definition is covered by autopilot.sh GATE_CONTROL_FILES" \
    || fail "agent definition(s) NOT gate-integrity protected:$MISSING"
else
  fail "autopilot.sh not found — cannot verify gate-integrity coverage"
fi

# --- 7 — the rules actually fire (fixtures) -----------------------------------------------------
# A linter nobody has ever seen fail is a linter that doesn't work.
echo ""
mkfix() { printf '%s' "$2" > "$WORK/$1.md"; }

mkfix good '---
name: good
description: A narrow specialist that returns one structured verdict.
tools: Read, Grep
model: sonnet
---
Do the narrow thing.

## Output
End with: a one-line verdict.
'
[ -z "$(validate_agent "$WORK/good.md")" ] \
  && pass "fixture: a valid narrow agent passes validation" \
  || fail "fixture: a valid narrow agent was rejected"

mkfix nocontract '---
name: nocontract
description: Does something vague.
tools: Read
---
Do stuff.
'
validate_agent "$WORK/nocontract.md" | grep -q "no output contract" \
  && pass "fixture: an agent with no output contract is rejected" \
  || fail "fixture: a vague-output agent slipped through"

mkfix hyphenated '---
name: hyphenated
description: Thinks it is sandboxed, is not.
tools: Read
disallowed-tools: Edit, Write
---
## Output
End with: a verdict.
'
validate_agent "$WORK/hyphenated.md" | grep -q "silent no-op" \
  && pass "fixture: a hyphenated (silently-ignored) tool restriction is rejected" \
  || fail "fixture: an unsafe hyphenated tool boundary slipped through"

mkfix badmodel '---
name: badmodel
description: Pinned to a model this harness does not have.
tools: Read
model: gpt-4o
---
## Output
End with: a verdict.
'
validate_agent "$WORK/badmodel.md" | grep -q "unsupported model value" \
  && pass "fixture: an unsupported model value is rejected" \
  || fail "fixture: a bad model value slipped through"

mkfix pinnedmodel '---
name: pinnedmodel
description: Pins a full model id instead of an alias.
tools: Read
model: claude-3-opus-20240229
---
## Output
End with: a verdict.
'
out="$(validate_agent "$WORK/pinnedmodel.md")"
{ printf '%s' "$out" | grep -q "^warn: model .* pinned id" \
  && [ -z "$(printf '%s' "$out" | grep -v '^warn: ')" ]; } \
  && pass "fixture: a pinned model id warns (can go obsolete) but does not fail the build" \
  || fail "fixture: pinned-model-id handling is wrong (should warn, not fail)"

mkfix evaluator-fixture '---
name: evaluator-fixture
description: A grader that can edit what it grades.
tools: Read, Write, Edit, Bash
---
## Output
End with: PASS
'
mv "$WORK/evaluator-fixture.md" "$WORK/evaluator.md"
validate_agent "$WORK/evaluator.md" | grep -q "must be edit-disabled" \
  && pass "fixture: an evaluator holding Write/Edit is rejected" \
  || fail "fixture: a write-enabled grader slipped through"

mkfix mismatched '---
name: something-else
description: Its name does not match its filename.
tools: Read
---
## Output
End with: a verdict.
'
validate_agent "$WORK/mismatched.md" | grep -q "!= filename" \
  && pass "fixture: name/filename mismatch is rejected (Jaimitos convention)" \
  || fail "fixture: a name/filename mismatch slipped through"

echo ""
echo "Always-loaded description budget (v2.15.0)"
# An agent's `description:` sits in the window EVERY TURN, exactly like a model-invoked skill's — but
# only skills were capped (test-skills.sh: 500 B each / 6000 B total). So AUTHORING.md's row
# "Always-loaded context stays inside budget | Deterministic" claimed a CATEGORY its mechanism only
# half covered, and the evaluator's description grew 160 -> 434 B in v2.14.0 (the single largest
# always-loaded increase in that release) with nothing to notice. Same discipline, both halves.
A_DESC_CAP=500     # per agent description, bytes
A_TOTAL_CAP=2000   # sum of all agent descriptions, bytes
A_SUM=0
for f in "$SCAFFOLD"/.claude/agents/*.md; do
  [ -e "$f" ] || continue
  base=$(basename "$f" .md)
  # Measured EXACTLY like test-skills.sh's description budget: awk's print appends \n, so wc -c
  # counts one trailing byte per description. Matching the idiom matters more than the byte: two
  # always-loaded budgets measured two ways produce two "true" totals that disagree, and an
  # independent reader lands N bytes low and reports the doc as wrong (it isn't).
  d=$(awk '/^description:/{sub(/^description: */,""); print; exit}' "$f")
  n=$(printf '%s\n' "$d" | wc -c | tr -d ' ')
  A_SUM=$((A_SUM + n))
  if [ "$n" -gt "$A_DESC_CAP" ]; then
    fail "agent '$base' description is ${n}B > ${A_DESC_CAP}B — trim the trigger text, don't summarize the prompt"
  else
    pass "agent '$base' description within cap (${n}B / ${A_DESC_CAP}B)"
  fi
done
if [ "$A_SUM" -gt "$A_TOTAL_CAP" ]; then
  fail "agent description budget blown: ${A_SUM}B > ${A_TOTAL_CAP}B (loaded every turn) — report the NEW TOTAL, not the marginal cost"
else
  pass "agent description budget: ${A_SUM}B / ${A_TOTAL_CAP}B (~$((A_SUM / 4)) tokens, loaded every turn)"
fi

echo ""
if [ "$FAILS" -eq 0 ]; then echo "All agent-definition checks passed."; exit 0
else echo "$FAILS agent-definition check(s) FAILED."; exit 1; fi
