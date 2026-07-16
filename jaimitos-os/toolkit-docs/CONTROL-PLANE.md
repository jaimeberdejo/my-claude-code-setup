# Progressive control plane (v2.14.0)

Release 4 makes Jaimitos **proportionate to risk**: small work stays cheap, unfamiliar and high-stakes
work gets depth — while the deterministic completion spine (`scripts/tick.sh`) stays the sole authority,
the four conditional agents stay four, and no external runtime (Spec Kit / Yojana / Sutra) is required.
Every capability below lands inside an *existing* owner or as a small, inspectable, offline script that
loads only when relevant. Nothing here adds always-loaded context: `jaimitos-os/CLAUDE.md` is byte-for-byte
unchanged (3140 B).

This chain — R3's traceability spine, now complete in both directions — is what everything hangs off:

```
classify-work.sh  → SPEC tier + REQ/AC → ROADMAP phase → plan (ownership + revalidation)
                  → Evaluator PLAN_CHECK (pre-mortem) → implementation → evidence (schema 2)
                  → Evaluator IMPLEMENTATION_REVIEW → optional UAT → record-grade → tick.sh
                                                                      ↺ gap plan on failure
```

## 1. Workflow tiers — TINY / STANDARD / DEEP
`scripts/classify-work.sh` reads explicit risk + complexity signals (flags) and prints a
`## Work classification` block recommending a tier. It has **no side effects** — it never edits a spec,
never selects a model, never routes anything; a human records the selected tier in `docs/SPEC.md`
frontmatter (`tier:`) and may override the recommendation with a reason.

- **Escalation signals** (auth, authz, secrets, payments, destructive migration, public-API change,
  high-stakes data, major dep upgrade, multi-service deploy, irreversible behavior, unresolved
  architecture) normally **prevent TINY**; an override is allowed but printed loudly and must be recorded.
- Unknown flags / bad values **fail closed** (exit 2) so a typo can never silently misclassify.
- TINY = compact spec, diagnose+TDD, evidence, light evaluation. STANDARD = native REQ/AC, ownership-aware
  plan, PLAN_CHECK, IMPLEMENTATION_REVIEW. DEEP = + research, mapme brownfield/ownership, architecture,
  enforcement ledger, UAT.

## 2. Progressive specification depth
One `docs/SPEC.md` template, tier-scaled — **not** a second format. `tier:` frontmatter (informational,
overridable; readiness stays content-derived so a stale tier can't trick the gate). A "DEPTH BY TIER"
guide says what each tier fills; a deletable `## Deep design` section holds the DEEP fields (architecture
alternatives, data model, contracts, migration/rollback, failure modes, threat model, observability,
performance, compatibility — referencing ADRs, not duplicating them). A **blocking** `[NEEDS
CLARIFICATION]` prevents progression; a **non-blocking** deferred question records reason/owner/
resolution/impact. `to-spec` stays the sole id owner; `grill` and `to-spec` scale depth to the tier.

## 3. Brownfield & mapping — the `mapme` skill
All mapping is bounded modes of the one `mapme` skill (ADR-003): default architecture, `--brownfield`
(onboard an unfamiliar repo → `docs/CODEBASE.md`, splitting out ARCHITECTURE/DEPENDENCIES/TEST-MAP/RISK-MAP
only when a page won't hold it), `--ownership` (→ `docs/OWNERSHIP.md`), `--refresh` (only maps whose
inputs changed). Every material claim is tagged **VERIFIED | INFERRED | UNKNOWN | STALE DOCUMENTATION |
CONTRADICTION** with a cited basis. **Stated-vs-actual** architecture is classified **CONFIRMED |
ARCHITECTURAL DEBT | DOCUMENTATION DRIFT | UNKNOWN**, and current structure is never auto-promoted into
"desired" architecture. Every map records a staleness baseline and reports `POSSIBLY STALE — REVIEW
REQUIRED` when inputs change. Maps are GENERATED VIEW, never canonical state; flag-never-fix holds.

## 4. Ownership — three distinct concepts
None grants implementation permission or completes work.
- **Human-review**: `.github/CODEOWNERS` when present — a review authority, validated, never rewritten,
  never read as permission or completion.
- **Logical component**: `docs/OWNERSHIP.md` (via `mapme --ownership`, when justified) — components
  classified `OWNED | SHARED | UNOWNED | GENERATED | VENDORED | EXTERNAL | UNKNOWN`; git-history
  maintainers are labelled INFERRED, never verified.
- **Per-phase execution**: the planner's `## Change ownership` (planned writes / required reads / shared
  files with a named integration owner / out of scope / required reviewers / integration order). If
  disjoint write scopes can't be proven, tasks run **sequentially**. The evaluator's Axis-A
  ownership-compliance check diffs actual scope against the plan; unexplained unrelated/high-stakes
  modifications block PASS.

## 5. Evaluator PLAN_CHECK + pre-mortem
The same independent, edit-disabled evaluator gains a second mode (ADR-005). `IMPLEMENTATION_REVIEW` is the
existing two-axis grade (`PASS` / `NEEDS_WORK`, gated by `record-grade.sh`). `PLAN_CHECK` is a fresh,
read-only plan review before execution, with a checklist **plus a pre-mortem** ("imagine it shipped as
written and still failed — why?") over requirement coverage, integration seams, dependency graph, temporal
risks, failure behavior, verification, and ownership/enforcement. Verdict `PASS | PASS_WITH_WARNINGS |
FAIL` on a separate channel `record-grade.sh` never reads; `FAIL` returns the plan to the planner and
blocks execution. `/phase` runs it after planning for STANDARD/DEEP/supervised phases; TINY skips it.

## 6. Stale-plan revalidation
A STANDARD/DEEP plan records its baseline and a `## Assumption revalidation` section (ADR-006).
`scripts/check-plan-freshness.sh` gives deterministic signals: baseline still an ancestor of HEAD,
referenced files present/changed, cited REQ/AC/OBJ/ENF ids still resolve. Hard signals fail `--strict` —
an invalidated plan **may not keep a prior PASS**. A material change needs a fresh PLAN_CHECK; a scope
change needs user approval; a small path move may be corrected in-plan with a note.

## 7. Native traceability through tasks and evidence
R3 wired `_requirements.sh` (references resolve to definitions). R4 adds the reverse — `requirements_orphans`
(a REQ/OBJ defined and active in the spec that no phase plans) — and `scripts/trace-requirements.sh`, a
report GENERATED from the canonical SPEC + ROADMAP (never a hand-maintained spreadsheet). Structure is
deterministic; meaning stays evaluator-reviewed.

## 8. Generic evidence — schema_version 2
`test-evidence.sh` emits `schema_version 2`: every v1 field kept verbatim (so `tick.sh` is unchanged) plus
evidence_id, cwd, timestamps, duration, classification, requirement refs, warnings, skipped, a bounded +
secret-redacted summary, redacted flag, and an advisory recomputable `content_hash`. `passed` is always
exit-derived, so a summary can never override the real status. `tick.sh` gates on the version (absent = v1;
1–2 understood; unknown fails closed). No ecosystem adapter registry (ADR-007) — the generic runner stays
authoritative.

## 9. Strengthened `diagnose`
Already loop-first with ranked hypotheses, tagged+removed instrumentation, and bisection/differential
methods; R4 adds the flaky discipline — record the measured reproduction rate as a baseline, and one green
run is never resolution (re-run the loop many times post-fix and record the new rate).

---

## Security & guarantee classification
Guarantees are classified honestly — linters check *shape*, the evaluator + human check *judgement*. See
the table in `docs/dev/AUTHORING.md`. Deterministic: id/ledger/UAT/plan-freshness structure, evidence
commit-binding + schema gate, tier reproducibility. Hook/gate-enforced: evaluator edit-isolation, evidence
HEAD-binding. Model-dependent: map claim classification, plan pre-mortem, requirement satisfaction,
ownership judgement. Human-dependent: CODEOWNERS review, UAT acceptance, tier override, tag/release.
Advisory: enforcement-ledger rows labelled ADVISORY, orphan warnings, changed-file staleness.

**Adversarial posture** (`test-control-plane-security.sh`): every new validator fails closed / stays inert
on a missing or directory path, is strictly read-only, and never evaluates file content — a `$(...)` or
backtick payload in a ledger/plan/spec/UAT line cannot execute.

## Migration & rollback
Every capability is opt-in / when-justified / conditional, so **legacy projects are unaffected**: a spec
with no `tier:`, a repo with no ownership/enforcement/UAT docs, and a plan with no revalidation section all
behave exactly as before. Evidence: a v1/absent-`schema_version` file is still read (or cleanly rejected);
`tick.sh` stays byte-identical on refusal. **Recovery** is fail-closed: interrupted map generation,
malformed spec migration, a failed plan check, a stale plan, invalid evidence, an invalid enforcement
reference, and an interrupted state transition all preserve the previous valid state, explain the manual
action, avoid destructive resets, and stay idempotent — there is no general repair framework. Rollback:
additive commits revert cleanly; optional blocks/docs are removable; completed roadmap history is never
rewritten.

## Context cost
| Surface | Cost | Loads when |
|---|---|---|
| `CLAUDE.md` (always-loaded) | **UNCHANGED — 3140 B** | every turn |
| Skill descriptions (model-invoked) | 5173 B / 6000 B (+138 B, mapme only) | every turn |
| Classifier / spec-depth guidance | LOW | authoring a spec/roadmap |
| `mapme` modes | MEDIUM (brownfield/DEEP: HIGH) | invoking `mapme` |
| PLAN_CHECK + pre-mortem | MEDIUM | a STANDARD/DEEP plan check |
| UAT / enforcement-ledger detail | LOW | when the artifact exists |
| Difficult debugging (`diagnose`) | MEDIUM–HIGH | invoking `diagnose` |

TINY work never loads DEEP guidance; maps, ownership, PLAN_CHECK, UAT, and enforcement detail load only
when relevant. No new always-loaded agent; no Spec Kit / Yojana / Sutra context.

## Deliberately deferred (ADR-007)
test-adapter registry · completion attestations · telemetry · multi-model routing · MCP orchestration
registry · live ticket synchronization. Revisited only when a real consumer demonstrates the need.
