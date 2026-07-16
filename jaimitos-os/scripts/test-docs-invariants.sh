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

# Requirement traceability (v2.12.0) — a CONDITIONAL Axis-A criterion that fires only when a phase
# declares a Requirements: line, written for ANY external requirements source (a PRD, a ticket, an
# imported spec). It must NOT name a specific external tool: the moment it does, it stops being a
# core capability and becomes a bridge to one product. The roadmap skill documents the producing
# side (the optional Requirements:/Sources: block); the evaluator is the consuming side. Both are
# pinned so the convention can't drift apart across the two homes.
assert_has ".claude/agents/evaluator.md" "only when the active phase declares" \
           "evaluator's requirement-traceability section is CONDITIONAL, not an unconditional new axis"
assert_has ".claude/agents/evaluator.md" "Requirement traceability" \
           "evaluator names the requirement-traceability criterion"
assert_absent ".claude/agents/evaluator.md" "speckit" \
           "the evaluator names no external tool (tool-agnostic, or it does not belong in core)"
assert_absent ".claude/agents/evaluator.md" "spec kit" \
           "the evaluator names no external tool (spelled-out form)"
assert_has "../skills/roadmap/SKILL.md" "Requirements:" \
           "roadmap skill documents the optional Requirements: block (the producing side)"
assert_has "../skills/roadmap/SKILL.md" "Sources:" \
           "roadmap skill documents the optional Sources: line that pairs with Requirements:"
assert_absent "../skills/roadmap/SKILL.md" "speckit" \
           "roadmap skill's requirement-id guidance names no external tool"

# Progressive specification depth (v2.14.0) — ONE spec template, tier-scaled. TINY stays compact,
# STANDARD uses native REQ/AC, DEEP adds the risk/architecture fields; a spec with no tier: line is
# unchanged/legacy. The tier is content-derived-readiness-neutral (never a gate). Pinned so the single
# template can't fork into competing per-tier formats, and so the blocking-clarification rule survives.
assert_has "docs/SPEC.md" "TINY | STANDARD | DEEP" \
           "SPEC frontmatter names the three tiers (tier: field, informational + overridable)"
assert_has "docs/SPEC.md" "DEPTH BY TIER" \
           "SPEC documents how depth scales with tier (one template, not three formats)"
assert_has "docs/SPEC.md" "## Deep design (DEEP tier only" \
           "SPEC carries the DEEP-tier deep-design section (deletable for TINY/STANDARD)"
assert_has "docs/SPEC.md" "BLOCKING clarification" \
           "SPEC distinguishes blocking [NEEDS CLARIFICATION] from a non-blocking deferred question"
assert_absent "docs/SPEC.md" "speckit" \
           "SPEC tier guidance names no external tool"
assert_has "../skills/to-spec/SKILL.md" "Match depth to the spec's" \
           "to-spec matches close depth to the spec tier (sole id owner, unchanged)"
assert_has "../skills/grill/SKILL.md" "Match interview depth to the spec's" \
           "grill matches interview depth to the spec tier (discovers, does not mint ids)"

# Grill's stopping condition (v2.15.0) — the interview terminates on an evidence condition (every
# MATERIAL decision settled or recorded as an honest gap), not on exhaustion or on the tier label.
# Pinned because an interview with no stopping rule invents requirements, and because deep discovery
# stays a branch of THIS skill: no --deep flag, no discovery artifact, no second spec authority.
assert_has "../skills/grill/SKILL.md" "unresolved material decision" \
           "grill earns a deep branch from an unresolved decision, not from the tier label"
assert_has "../skills/grill/SKILL.md" "Stop when the spec can be written honestly" \
           "grill has an explicit stopping condition (stop once the spec is honestly writable)"
assert_absent "../skills/grill/SKILL.md" "grill --deep" \
           "no --deep flag — depth is a derived condition, not a user-typed mode (ADR: discovery stays in grill)"

# Mapme brownfield/ownership/refresh modes (v2.14.0) — ALL mapping lives in the one mapme skill; no
# separate brownfield/ownership/architecture skill. Maps stay GENERATED VIEW (never canonical), facts vs
# inferences vs unknowns stay distinct, stated-vs-actual is honest, staleness is visible, flag-never-fix holds.
assert_has "../skills/mapme/SKILL.md" "mapme --brownfield" \
           "mapme owns a brownfield onboarding mode (not a separate skill)"
assert_has "../skills/mapme/SKILL.md" "mapme --ownership" \
           "mapme owns an ownership mapping mode (not a separate skill)"
assert_has "../skills/mapme/SKILL.md" "mapme --refresh" \
           "mapme owns a bounded refresh mode"
assert_has "../skills/mapme/SKILL.md" "Evidence classification" \
           "mapme classifies every material claim (VERIFIED/INFERRED/UNKNOWN/STALE/CONTRADICTION)"
assert_has "../skills/mapme/SKILL.md" "ARCHITECTURAL DEBT" \
           "mapme distinguishes architectural debt (stated-vs-actual) from documentation drift"
assert_has "../skills/mapme/SKILL.md" "DOCUMENTATION DRIFT" \
           "mapme names documentation drift as distinct from debt"
assert_has "../skills/mapme/SKILL.md" "Do not automatically convert the current structure" \
           "mapme refuses to promote current structure into desired architecture (no blessing drift)"
assert_has "../skills/mapme/SKILL.md" "POSSIBLY STALE" \
           "mapme surfaces staleness instead of pretending a map is current"
assert_has "../skills/mapme/SKILL.md" "GENERATED VIEW" \
           "mapme output is a generated view, never canonical state"
assert_has "../skills/mapme/SKILL.md" "flag it, never fix it" \
           "mapme keeps the flag-never-fix stance across all modes"
assert_absent "../skills/mapme/SKILL.md" "speckit" \
           "mapme names no external tool"

# Ownership model (v2.14.0) — three DISTINCT concepts: human-review (CODEOWNERS), logical component
# (docs/OWNERSHIP.md), per-phase execution (planner). None grants implementation permission or completes
# work. Overlapping writes stay sequential unless disjointness is proven; the evaluator checks actual scope.
assert_has ".claude/agents/planner.md" "## Change ownership" \
           "planner declares per-phase execution ownership (planned writes / shared / out of scope / reviewers)"
assert_has ".claude/agents/planner.md" "run SEQUENTIALLY" \
           "planner keeps execution sequential when disjoint write scopes cannot be proven"
assert_has ".claude/agents/planner.md" "a grant to implement" \
           "planner: CODEOWNERS is a review authority, not implementation permission"
assert_has ".claude/agents/evaluator.md" "Ownership compliance" \
           "evaluator reviews actual diff scope against the plan's ownership block"
assert_has ".claude/agents/evaluator.md" "Unexpected files modified" \
           "evaluator reports unexpected/unexplained diff scope (high-stakes drift blocks PASS)"
assert_has ".claude/agents/evaluator.md" "implementation permission" \
           "evaluator: a CODEOWNERS approval is a review signal, never implementation permission or completion"
assert_has "../skills/mapme/SKILL.md" "operational (logical) ownership" \
           "mapme keeps operational (OWNERSHIP.md) ownership distinct from CODEOWNERS and execution ownership"
assert_has "../skills/mapme/SKILL.md" "OWNED | SHARED | UNOWNED" \
           "mapme ownership component classifications present"

# Enforcement + UAT ledgers REMOVED in v2.15.0 (see the removal ADR). v2.14.0 shipped two validators
# with no producer, no template and no caller — reachable only from their own fixtures — while the docs
# labelled them DETERMINISTIC and "blocks a release". ADR-007's own standard ("revisited only when a real
# consumer demonstrates the need") plus three real consumer repos showing zero uptake made deletion, not
# wiring, the consistent answer. These pin the removal: speculative infrastructure does not creep back
# without a fresh decision, and no doc may claim a gate that no longer exists.
for gone in scripts/lint-enforcement.sh scripts/check-uat.sh scripts/test-enforcement.sh scripts/test-uat.sh; do
  if [ -e "$ROOT/$gone" ]; then
    bad "$gone was removed in v2.15.0 but exists again — reinstating it needs a fresh ADR, not a revert"
  else
    ok "$gone stays removed (no producer, no caller — ADR-007 standard)"
  fi
done
assert_absent "../README.md" "check-uat" \
           "README claims no UAT release gate (the validator is gone)"
assert_absent "../docs/dev/AUTHORING.md" "lint-enforcement.sh" \
           "the guarantee table claims no enforcement-ledger gate (the validator is gone)"

# Evaluator PLAN_CHECK + pre-mortem (v2.14.0) — the SAME independent evaluator gains a second mode. No new
# agent, no second evaluator. IMPLEMENTATION_REVIEW keeps the two-axis PASS/NEEDS_WORK contract that
# record-grade.sh gates on; PLAN_CHECK is a fresh, read-only plan review with its OWN verdict triple, on a
# separate channel that record-grade.sh never reads. /phase runs PLAN_CHECK after planning, before execution.
assert_has ".claude/agents/evaluator.md" "IMPLEMENTATION_REVIEW" \
           "evaluator names the implementation-review mode (the existing two-axis grade)"
assert_has ".claude/agents/evaluator.md" "PLAN_CHECK" \
           "evaluator gains a fresh read-only PLAN_CHECK mode"
assert_has ".claude/agents/evaluator.md" "PASS_WITH_WARNINGS" \
           "PLAN_CHECK has its own three-value verdict (distinct from the tick-gate PASS/NEEDS_WORK)"
assert_has ".claude/agents/evaluator.md" "implemented exactly as written and still failed" \
           "PLAN_CHECK runs the integrated pre-mortem"
assert_has ".claude/agents/evaluator.md" "never the input to \`record-grade.sh\`" \
           "PLAN_CHECK is a separate channel — its verdict never reaches record-grade.sh"
assert_has ".claude/agents/evaluator.md" "cannot approve a plan you authored" \
           "evaluator PLAN_CHECK stays independent (it authors nothing; the planner cannot self-approve)"
assert_has ".claude/commands/phase.md" "do NOT execute a failed plan" \
           "/phase dispatches PLAN_CHECK after planning and blocks execution on FAIL (skipped for TINY)"

# Stale-plan revalidation (v2.14.0) — plans decay as the repo moves. The planner records the baseline and
# a revalidation section; check-plan-freshness.sh gives the deterministic signals. An invalidated plan may
# not keep a prior PASS. Semantic validity stays evaluator-reviewed.
assert_has ".claude/agents/planner.md" "## Assumption revalidation" \
           "planner records assumption revalidation (baseline + still-valid/changed/stale fields)"
assert_has ".claude/agents/planner.md" "may not keep a prior PASS" \
           "an invalidated plan may not retain a prior PASS"
assert_has "scripts/check-plan-freshness.sh" "no longer an ancestor of HEAD" \
           "plan-freshness check detects a baseline that diverged from HEAD"
assert_has "scripts/check-plan-freshness.sh" "no longer resolves in" \
           "plan-freshness check detects a cited requirement/enforcement id that was removed"

# Native requirement ids (v2.13.0) — the spec + plan sides that pair with v2.12.0's roadmap +
# evaluator half. All OPTIONAL and inert by default; to-spec is the SOLE id owner; grill only
# discovers candidates; the planner maps tasks; and none of it names an external tool.
assert_has "docs/SPEC.md" "Requirements (optional" \
           "SPEC template carries an OPTIONAL Requirements (REQ/AC) section"
assert_has "docs/SPEC.md" "tiny/local work" \
           "SPEC template exempts tiny/local work from ids (they are not forced)"
assert_absent "docs/SPEC.md" "speckit" \
           "SPEC template names no external tool"
assert_has "../skills/to-spec/SKILL.md" "sole id owner" \
           "to-spec is the sole owner of native id assignment and preservation"
assert_has "../skills/to-spec/SKILL.md" "never renumber" \
           "to-spec preserves approved ids (no renumber on reorder)"
assert_absent "../skills/to-spec/SKILL.md" "speckit" \
           "to-spec's id guidance names no external tool"
assert_has "../skills/grill/SKILL.md" "do not mint canonical" \
           "grill discovers requirement candidates but does not mint canonical ids"
assert_absent "../skills/grill/SKILL.md" "speckit" \
           "grill's requirement guidance names no external tool"
assert_has ".claude/agents/planner.md" "no id ceremony" \
           "planner maps tasks to ids only when a phase declares them; tiny work skips it"
assert_absent ".claude/agents/planner.md" "speckit" \
           "planner's requirement mapping names no external tool"

# Extended traceability (v2.14.0) — R3 wired _requirements.sh (refs→defs); R4 adds the reverse coverage
# check (orphan detection: an approved requirement no phase plans) and a traceability REPORT generated from
# the canonical artifacts, never a hand-maintained spreadsheet. Orphans are advisory; structure stays hard.
assert_has ".claude/lib/_requirements.sh" "requirements_orphans" \
           "requirements lib gains orphan/coverage detection (approved requirement with no planned work)"
assert_has "scripts/trace-requirements.sh" "never a hand-maintained spreadsheet" \
           "traceability is a report generated from SPEC + ROADMAP, not a manual spreadsheet"
assert_absent "scripts/trace-requirements.sh" "speckit" \
           "the traceability report names no external tool"

# Evidence schema_version 2 (v2.14.0) — the producer keeps every v1 field (so tick.sh's reads are
# unchanged) and ADDS richer fields; tick.sh gates on the version (absent=v1, unknown=fail-closed). A
# bounded, secret-redacted summary can never override the exit-derived `passed`.
assert_has "scripts/test-evidence.sh" "schema_version 2" \
           "evidence producer emits schema_version 2 (v1 fields kept verbatim for tick.sh)"
assert_has "scripts/tick.sh" "evidence schema gate" \
           "tick.sh gates on the evidence schema_version (accept 1-2, reject unknown fail-closed)"
assert_has "scripts/test-evidence.sh" "cannot override" \
           "a redacted, bounded summary can never override the real exit status"

# Gap planning (v2.14.0, retained) — the UAT ledger it once cited is gone (v2.15.0), but bounded
# correction planning stands on its own: a phase still fails downstream via missing evidence, an
# evaluator NEEDS_WORK, an ownership violation, or an invalidated stale plan.
assert_has ".claude/agents/planner.md" "Gap planning" \
           "planner produces bounded gap/correction plans"
assert_has ".claude/agents/planner.md" "smallest coherent correction" \
           "a gap plan proposes the smallest correction (no rewriting unrelated requirements)"
assert_has ".claude/agents/planner.md" "Never defer failed REQUIRED work" \
           "a gap plan never defers failed required work merely to complete a release"

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
