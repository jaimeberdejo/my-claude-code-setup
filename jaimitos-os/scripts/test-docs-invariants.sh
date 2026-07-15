#!/usr/bin/env bash
# test-docs-invariants.sh — guard the "no prose ticking" contract in the shipped command docs.
# Completion marking must route through scripts/tick.sh; no command file may tell the model it
# can flip roadmap checkboxes by hand, and no doc may claim the in-session tick is ungated.
# Cheap grep assertions, no model needed — a regression guard for Phase 3.
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

FAILS=0
ok()  { printf '  ✓ %s\n' "$1"; }
bad() { printf '  ✗ %s\n' "$1"; FAILS=$((FAILS+1)); }
assert_has()    { if grep -qF  "$2" "$ROOT/$1"; then ok "$3"; else bad "$3 (expected '$2' in $1)"; fi; }
assert_absent() { if grep -qiF "$2" "$ROOT/$1"; then bad "$3 (forbidden '$2' present in $1)"; else ok "$3"; fi; }

echo "docs invariants — completion marking routes through scripts/tick.sh"
echo ""
assert_has    ".claude/commands/wrap.md"      "scripts/tick.sh"   "wrap.md routes ticking through scripts/tick.sh"
assert_has    ".claude/commands/wrap.md"      "may NOT flip"      "wrap.md forbids flipping checkboxes by hand"
assert_absent ".claude/commands/wrap.md"      "deliberately"      "wrap.md has no '(or you, deliberately)' tick bypass"
assert_has    ".claude/commands/autopilot.md" "scripts/tick.sh"   "/autopilot routes ticking through scripts/tick.sh"
assert_has    "CLAUDE.md"                      "scripts/tick.sh"   "CLAUDE.md documents the single tick gate"
assert_absent "CLAUDE.md"                      "the tick is not"  "CLAUDE.md no longer claims the in-session tick is ungated"
assert_has    ".claude/commands/autopilot.md" "Check the next phase's \`Mode:\` line BEFORE building it" \
              "/autopilot checks Mode: supervised BEFORE building, not just at tick time"
assert_has    ".claude/commands/phase.md" "if ZERO headings match at all, STOP" \
              "/phase <heading> handles zero-match arguments explicitly (no silent fall-through)"

echo ""
echo "roadmap-legend regression — prose must not use literal checkbox bracket syntax"
echo "(that syntax once made an unanchored grep in close-milestone.sh/autopilot.sh false-match"
echo " on every generated roadmap's own legend line; see commit 0d55d49)"
echo ""
assert_absent "../skills/roadmap/SKILL.md" '`- [ ]`' \
              "roadmap skill's legend prose does not use literal '- [ ]' bracket syntax"
assert_absent "../skills/roadmap/SKILL.md" '`- [x]`' \
              "roadmap skill's legend prose does not use literal '- [x]' bracket syntax"
assert_absent "docs/ROADMAP.md" '`- [ ]`' \
              "shipped ROADMAP.md scaffold's legend prose does not use literal '- [ ]' bracket syntax"
assert_absent "docs/ROADMAP.md" '`- [x]`' \
              "shipped ROADMAP.md scaffold's legend prose does not use literal '- [x]' bracket syntax"

echo ""
echo "shipped CLAUDE.md cites nothing the installed project cannot open"
echo "(CLAUDE.md ships verbatim into every project; install.sh deliberately excludes toolkit-docs/,"
echo " so a 'see the GUIDE' pointer there is a dead end for every user — found by dogfooding"
echo " the diagnose skill in v2.10.0)"
echo ""
assert_absent "CLAUDE.md" "toolkit-docs" \
              "shipped CLAUDE.md does not point users at toolkit-docs/ (never installed)"

echo ""
echo "engineering disciplines (v2.10.0) — the contracts the skills/agents are supposed to carry"
echo "(prose, so only greppable: these prove the RULE IS STATED, never that it was FOLLOWED —"
echo " see docs/dev/AUTHORING.md on deterministic vs model-dependent guarantees)"
echo ""
# TDD: a red that never happened, or happened for the wrong reason, is not TDD.
assert_has "../skills/tdd/SKILL.md" "The red must be meaningful" \
           "tdd requires the red to fail for the INTENDED reason (not just 'it failed')"
assert_has "../skills/tdd/SKILL.md" "the exception is explicit, never" \
           "tdd names an explicit exception path when production code must precede the test"
assert_has "../skills/tdd/SKILL.md" "Never claim TDD was followed if no meaningful red was ever observed" \
           "tdd forbids claiming TDD without an observed meaningful red"
assert_has "../skills/tdd/SKILL.md" "Then run the wider suite" \
           "tdd requires the wider suite after a targeted green"

# Debugging: hypothesis and evidence are different things, and guesses don't stack.
assert_has "../skills/diagnose/SKILL.md" "Never present a hypothesis as evidence" \
           "diagnose separates unverified hypothesis from confirmed evidence"
assert_has "../skills/diagnose/SKILL.md" "No speculative fix loops" \
           "diagnose discourages speculative fix loops"
assert_has "../skills/diagnose/SKILL.md" "Three failed fixes = stop fixing" \
           "diagnose escalates to the architecture after 3 failed fixes"

# Verification before completion — behavioral, on top of the mechanical tick gate.
assert_has ".claude/agents/executor.md" "Verify before you claim anything" \
           "executor requires fresh verification before any completion claim"
assert_has ".claude/agents/executor.md" "after your last edit" \
           "executor requires the verification run to POST-DATE the final edit"
assert_has ".claude/commands/phase.md" "Fresh verification" \
           "/phase re-verifies after the executor's final commit (the agent's report is a claim)"
assert_has ".claude/commands/wrap.md" "First, verify freshly" \
           "/wrap re-verifies before grading"

# Two-axis evaluation — and the gate contract it must not break.
assert_has ".claude/agents/evaluator.md" "## Axis A — Specification compliance" \
           "evaluator has the specification-compliance axis"
assert_has ".claude/agents/evaluator.md" "## Axis B — Engineering quality" \
           "evaluator has the engineering-quality axis"
assert_has ".claude/agents/evaluator.md" "A failure in EITHER axis is \`NEEDS_WORK\`" \
           "evaluator fails on EITHER axis (one may not excuse the other)"
assert_has ".claude/agents/evaluator.md" "records a grade only when it is exactly \`PASS\`" \
           "evaluator still documents the last-line PASS contract record-grade.sh depends on"
assert_absent ".claude/agents/evaluator.md" "End your response with exactly one line:
- \`PASS\` — every acceptance criterion is demonstrably met AND" \
           "evaluator's old single-axis verdict text is gone"
# Requirement traceability: CONDITIONAL (fires only when a phase declares Requirements:), and it must
# be written for ANY external requirements source — never naming a specific tool. If it cannot be
# written tool-agnostically, it does not belong in a shipped agent. (Release 2 experiment.)
assert_has    ".claude/agents/evaluator.md" "only when the active phase declares" \
              "evaluator's requirement-traceability section is CONDITIONAL, not an unconditional new axis"
assert_absent ".claude/agents/evaluator.md" "speckit" \
              "the shipped evaluator names no external tool (tool-agnostic, or it does not belong in core)"
assert_absent ".claude/agents/evaluator.md" "spec kit" \
              "the shipped evaluator names no external tool (spelled-out form)"

# Prototype — sanctioned, but never a route to a tick.
assert_has "../skills/prototype/SKILL.md" "**MAY NEVER** satisfy production implementation or release criteria" \
           "prototype output can never satisfy production/release criteria"
assert_has "../skills/prototype/SKILL.md" "**This skill never ticks a phase.**" \
           "prototype disclaims any completion authority"
assert_has "../skills/prototype/SKILL.md" "disable-model-invocation: true" \
           "prototype is user-invoked (zero always-loaded context; cannot auto-fire)"

# Review feedback — validated, not obeyed.
assert_has "../skills/review-feedback/SKILL.md" "Classify every item — exactly one label" \
           "review-feedback carries its comment classification taxonomy"
assert_has "../skills/review-feedback/SKILL.md" "**Misunderstanding**" \
           "review-feedback can classify a review comment as a misunderstanding"
assert_has "../skills/review-feedback/SKILL.md" "authority" \
           "review-feedback refuses to comply on reviewer authority alone"

# Single authorities survive the release.
assert_has "../skills/glossary/SKILL.md" "docs/GLOSSARY.md" \
           "glossary remains the sole docs/GLOSSARY.md authority"
assert_has "../skills/module-design/SKILL.md" "never ticks a phase" \
           "module-design explicitly disclaims completion authority"
assert_has "../skills/module-design/SKILL.md" "disable-model-invocation: true" \
           "module-design is user-invoked (every consumer reaches it by path; 0 B always-loaded)"

# The milestone boundary is the only place anyone sees the whole system at once (v2.11.0).
assert_has "scripts/close-milestone.sh" 'NOTE — $ARCH was not refreshed during this milestone' \
           "close-milestone surfaces an architecture map left stale across a whole milestone"
assert_has "scripts/close-milestone.sh" 'NOTE — no $ARCH, but' \
           "close-milestone surfaces a missing architecture map when code shipped"
assert_has "../skills/milestone/SKILL.md" "Dispatch \`mapme\` into a subagent" \
           "milestone Mode B runs the architecture pass in its own context before archiving"
assert_has "../skills/milestone/SKILL.md" "carry any **Strong** finding into the next roadmap" \
           "milestone Mode B schedules Strong architecture findings instead of rediscovering them"

echo ""
if [ "$FAILS" -eq 0 ]; then echo "All docs-invariant checks passed."; exit 0
else echo "$FAILS docs-invariant check(s) FAILED."; exit 1; fi
