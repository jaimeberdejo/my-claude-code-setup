# PLAN — v2.14.0: Progressive control plane, brownfield intelligence, ownership & enforced planning

> **Branch:** `release-4-progressive-control-plane` (from `release-3-native-traceability` @ `897d282`,
> `VERSION=2.12.0`). R4 builds on R3's native traceability; R3 is in-flight (its own v2.13.0 not yet
> tagged), so R4 pins this base and rebases onto final R3 / master later.
> **Target:** `VERSION=2.14.0` (v2.13.0 is owned by Release 3). **No push, no tag, no PR, no history
> rewrite, no destructive reset, no unattended autopilot on the control plane.** Bumping VERSION /
> tagging is its own operator checkpoint.
> **Plan artifact (tracked):** this file — committed as commit 0.
> **Baseline recorded on `897d282`:** `release-check --prepare` exit 0 (clean tree; expected
> "v2.12.0 tag exists" prepare-mode warning); guard suite + `install-smoke` recorded at setup.

---

## Context

Release 3 gave Jaimitos a **native requirement-traceability spine**:
`SPEC REQ/AC → ROADMAP phase → plan task → code/test evidence → evaluator → tick`. Release 4 **extends
that spine forward through tasks and evidence** and wraps it in a *proportionate* control plane so small
work stays cheap and risky/unfamiliar work gets depth — without adding a runtime, an agent, or a second
authority.

The problem R4 solves: today every change gets the same ceremony; there is no first-class way to
understand a brownfield repo, separate documented intent from actual structure, map ownership, prove that
an architectural claim is actually enforced, stress-test a plan before building, or notice a plan went
stale. R4 lands each of these **inside an existing owner** — the `mapme` skill, the Evaluator, the
Planner, the evidence system — or as a small inspectable script/doc that loads only when relevant.

**Invariant preserved:** the four conditional agents stay four; `scripts/tick.sh` stays the sole path
that flips `- [ ]` → `- [x]`; no Spec Kit / Yojana / Sutra runtime; offline, Git/file-native,
sequential-by-default, human-overridable, proportionate to risk. Always-loaded (`CLAUDE.md`, 53 lines /
3140 B) grows by at most a short pointer.

---

## Decisions taken (operator-confirmed)

| # | Decision | Consequence |
|---|---|---|
| 1 | **Base = R3 tip `897d282`, target v2.14.0** | R4 inherits R3's REQ/AC foundation; rebase onto final R3/master once R3 tags v2.13.0. v2.13.0 is taken. |
| 2 | **Execution = autonomous, review at end** | Subagents used liberally for research + independent authoring; control-plane edits (evaluator, `tick.sh`, agents, evidence producer) done deliberately with a test run before each commit — never via the toolkit's own unattended `autopilot.sh`. |
| 3 | **Tiers are a helper, not a skill/agent** | `scripts/classify-work.sh` recommends `TINY/STANDARD/DEEP`; the selected tier is recorded in `SPEC.md` frontmatter (`tier:`), overridable + visible. No opaque routing, no invisible model selection. |
| 4 | **One spec format, tier-conditional depth** | Extend the single `SPEC.md` template — no second spec hierarchy. R3's REQ/AC section is the STANDARD core; TINY is a compact block; DEEP adds risk/architecture fields referencing ADRs. |
| 5 | **Mapping lives in `mapme`** | Bounded modes (`--brownfield`, `--ownership`, `--refresh`) inside the one skill — no separate brownfield/ownership/architecture skills. |
| 6 | **Evaluator gains modes, not a twin** | `PLAN_CHECK` (fresh, read-only, pre-mortem, verdict `PASS|PASS_WITH_WARNINGS|FAIL` on its own channel) + the existing two-axis review named `IMPLEMENTATION_REVIEW` (+ ownership-compliance). No second evaluator. The last-line `PASS` contract `record-grade.sh` depends on is untouched. |
| 7 | **Ownership is three distinct concepts** | Human-review (`.github/CODEOWNERS`, when present) vs logical component (`docs/OWNERSHIP.md`, when justified) vs per-phase execution (Planner declaration). None grants implementation permission or completes work. |
| 8 | **Enforcement ledger is additive, never regenerated from the code graph** | `docs/ENFORCEMENT.md`, when justified: claims → mechanism or explicit advisory; deferred rows need a real trigger; the ledger never ticks, grants permission, or becomes a second roadmap. |
| 9 | **Wire in R3's `_requirements.sh`; add orphan detection** | R3 authored it but left it untracked/inert; R4 commits it, sources it from `lint-roadmap.sh`, adds it to `doctor` + `run-guard-tests`, and adds spec→roadmap coverage (orphan) checks. |
| 10 | **Evidence schema_version 2, backward-compatible** | Extend the `test-evidence.sh` producer + `tick.sh` reader; failed stays failed, wrong-commit/stale/missing-field fail closed, summary never overrides exit status. No ecosystem adapter registry. |
| 11 | **UAT + gap planning are lightweight** | One canonical `docs/UAT.md` (when needed); blocking UAT blocks release but never bypasses evaluator/evidence/tick. Gap planning is Planner behavior, not a new skill. |
| 12 | **`diagnose` = enforcement, not net-new** | It already covers loop-first, flaky, cleanup, bisection, hypotheses, seam-honesty in prose; R4 strengthens/pins and fills selective gaps only. |

---

## The chain and its authorities (R4 extends R3, adds no authority)

```
scripts/classify-work.sh  TINY|STANDARD|DEEP recommendation (+ override, recorded)   ← control-plane helper
      ↓ tier recorded in
docs/SPEC.md  tier: + REQ/AC/OBJ definitions (tier-conditional depth)                ← to-spec (sole id owner)
      ↓ referenced by
docs/ROADMAP.md  Sources: / Requirements:                                            ← roadmap skill (v2.12.0)
      ↓ planned by
phase plan  task→REQ/AC/OBJ + ## Change ownership + ## Assumption revalidation       ← planner
      ↓ pre-checked by
Evaluator PLAN_CHECK  coverage · seams · deps · temporal · failure · ownership       ← evaluator (fresh, read-only)
      ↓ implemented + tested
code + tests + EVIDENCE (schema_version 2, commit-bound, REQ refs)                   ← executor + test-evidence.sh
      ↓ reviewed by
Evaluator IMPLEMENTATION_REVIEW  Axis A / Axis B / ownership compliance              ← evaluator (edit-disabled, default-fail)
      ↓ optionally accepted by
docs/UAT.md  tier-dependent, blocking UAT blocks release                             ← human
      ↓ gated by
record-grade.sh → tick.sh  THE SOLE completion authority                             ← untouched spine
      ↺ on failure
Planner gap plan  cite failed REQ/AC/OBJ/ENF · classify cause · smallest correction  ← planner (bounded)
```

Supporting artifacts, each with a classification (never silently promoted to canonical state):
`docs/CODEBASE|ARCHITECTURE|DEPENDENCIES|TEST-MAP|RISK-MAP.md` = **GENERATED VIEW** (mapme);
`docs/OWNERSHIP.md`, `docs/ENFORCEMENT.md`, `docs/UAT.md` = **CANONICAL STATE** when promoted;
`.tick-evidence.json`, `.phase-grade`, PLAN_CHECK output = **TEMPORARY EVIDENCE**;
`.github/CODEOWNERS`, provenance = **EXTERNAL REFERENCE**; classifier answers = **LOCAL OPTIONAL DATA**.

---

## Phase-0 overlap audit (verdicts — do not duplicate)

Layout: shipped skills `skills/`; maintainer skills `.claude/skills/`; commands
`jaimitos-os/.claude/commands/`; agents `jaimitos-os/.claude/agents/`; shipped templates
`jaimitos-os/docs/`; dev plans `docs/dev/plans/`; ADRs `docs/decisions/` (via `next-adr.sh`).

| Capability | Verdict | Note |
|---|---|---|
| Tier classifier (TINY/STANDARD/DEEP) | ABSENT | only informal "ceremony-to-stakes" prose; no `/goal` command exists |
| Progressive spec depth | ABSENT (binary) | `SPEC.md` optional REQ/AC only |
| mapme architecture map | PRESENT | core job |
| mapme brownfield / ownership / test-map / refresh | ABSENT | single linear procedure |
| mapme dep/risk map, stated-vs-actual, staleness | PARTIAL | "External deps" + "Where the risk lives" + "Doc drift" + diff-before-clobber |
| mapme VERIFIED/INFERRED/UNKNOWN tags | ABSENT | uses Strong/Worth/Speculative for friction only |
| CODEOWNERS / OWNERSHIP.md / execution ownership | ABSENT | ownership = CLAUDE.md section + STATE "Ownership gaps" + `ownership-nudge.sh` |
| Enforcement ledger | ABSENT | guarantee narrative in `docs/dev/AUTHORING.md` |
| Evaluator PLAN_CHECK / pre-mortem / ownership-compliance | ABSENT (net-new) | two-axis only; `PASS`/`NEEDS_WORK`+`NO_TESTS_OK` |
| Evaluator IMPLEMENTATION_REVIEW name | it does this, unnamed | formalize |
| Stale-plan revalidation | ABSENT | planner has no freshness section |
| Traceability through tasks/evidence | PARTIAL | `_requirements.sh` untracked+unwired; no orphan detection; evidence has no REQ refs |
| Evidence schema_version + fields | ABSENT | `passed,command,exit,run_id,source,config_sha,note`; HEAD-binding, only hash `config_sha` |
| UAT / gap planning | ABSENT | — |
| diagnose 6 areas | PRESENT (prose) | R4 = enforcement/selective gaps |
| tick.sh spine | PRESENT | 10 gates + rollback-safe ROADMAP+STATE txn — slot for new gates |

**Guardrails to preserve/extend (not break):** `test-docs-invariants.sh` pins the evaluator vocabulary
(two axes / "A failure in EITHER axis is `NEEDS_WORK`" / last-line PASS / absence of "speckit"/"spec
kit"); `record-grade.sh` reads the last non-empty line (PLAN_CHECK verdict must be a separate channel);
`run-guard-tests.sh` drift-guard requires every `test-*.sh` be listed; shipped `jaimitos-os-ci.yml`
requires a non-empty `permissions.deny`; guard the `CLAUDE.md` byte budget.

---

## Upstream provenance

Release 4 adopts **concepts only** — never runtimes, dependencies, agents, task databases, or vendored
text. Nothing here is fetched at runtime; the toolkit stays offline and Git/file-native. Consistent with
`integrations/README.md`, **every R4 adoption is `concept-only`** (the idea was taken; no upstream text
was used), so **no new entry is added to `integrations/upstreams.lock.json`** — that file is reserved for
SHA-pinned, materially-consulted upstream *text*, and none of the R4 sources could be honestly SHA-pinned.

### Source availability (honest SHA/license status)

| Source | Local availability | Pinned SHA | License |
|---|---|---|---|
| **Vidhi** (`vidhi` + `vidhi-sutra-*`, incl. Sutra / Yojana) | Not vendored; no local clone found | Not pinned — concept-only (not fetchable here) | Unverified |
| **Open GSD** (`get-shit-done`) | Installed as local skills (`~/.claude/gsd-core` v1.6.1 + 69 `gsd-*` skills); readable, **not a git repo**, not vendored | Not pinned — concept-only (no commit SHA) | Unverified (no `LICENSE` in the install) |
| **GitHub Spec Kit** | Upstream not cloned; only a downstream consumer present; already rejected as a profile (ADR-001, v2.12.0) | Not pinned — historical reference only | Unverified |
| **BMAD** (`BMAD-METHOD`) | Not vendored; no local clone found | Not pinned — concept-only (not fetchable here) | Unverified |

Nothing copied or adapted verbatim. No file carries an upstream attribution comment, because no upstream
text was used — only ideas informed native design.

### Adoption matrix

**Vidhi** (+ `vidhi-sutra-*`) — *concept-only; no SHA pinned*

| Capability | Verdict | Where it lands |
|---|---|---|
| Plan pre-mortem ("shipped as written and still failed — why?") | CONCEPT → ADAPT | Evaluator `PLAN_CHECK` (C7): fresh, read-only, verdict on its own channel, never routed to `record-grade.sh` |
| Plan / diagnose disciplines | CONCEPT → MERGE | Planner checklist + existing `diagnose` (C12); no new authority |
| Enforcement-ledger (claims → enforcement) | CONCEPT → ADAPT | `docs/ENFORCEMENT.md` + `lint-enforcement.sh` (C6): additive, when-justified, never regenerated from the code graph |
| Stated-vs-actual architecture classification | CONCEPT → ADAPT | `mapme` `CONFIRMED/ARCHITECTURAL DEBT/DOCUMENTATION DRIFT/UNKNOWN` (C4) |
| Stale-task / stale-plan revalidation | CONCEPT → ADAPT | Planner `## Assumption revalidation` + `check-plan-freshness.sh` (C8) |
| Requirement coverage + integration-seam ownership + late-integration risk | CONCEPT → MERGE | R3 REQ/AC spine through tasks/evidence (C9) + Planner `## Change ownership` + `PLAN_CHECK` seam/dependency/temporal checks |
| Yojana task-state, Sutra runtime, issue-tracker authority, auto `done` | REJECT | Would add a second completion authority + a runtime; `tick.sh` stays the sole `[ ]→[x]` path |
| Ecosystem paths/DBs, mandatory Rust/Dart tooling | REJECT | R4 is offline, file-native, language-agnostic |

**Open GSD** (`get-shit-done`, local skills v1.6.1) — *concept-only; no SHA pinned; license unverified*

| Capability | Verdict | Where it lands |
|---|---|---|
| Brownfield onboarding + codebase mapping | CONCEPT → MERGE | `mapme --brownfield` (C4): bounded modes in the one skill; outputs are GENERATED VIEW |
| Context hygiene / minimal-orchestrator context | CONCEPT → ADAPT | Tier-conditional loading (C2/C3): TINY never loads DEEP guidance |
| Dependency ordering | CONCEPT → ADAPT | Planner integration order + `PLAN_CHECK` dependency check (C7); `docs/DEPENDENCIES.md` as GENERATED VIEW |
| Lightweight UAT persistence | CONCEPT → ADAPT | Single canonical `docs/UAT.md` (C11); blocking UAT blocks release but never bypasses evaluator/evidence/tick |
| Correction / gap planning | CONCEPT → ADAPT | Planner gap-plan behavior (C11): cite failed id, classify cause, smallest correction — not a new skill or autonomous loop |
| Recovery ideas | CONCEPT → MERGE | Fail-closed recovery notes folded into existing scripts; no general repair framework |
| Full command surface + full `.planning/` state hierarchy | REJECT | Would become a second roadmap+state authority; ROADMAP+STATE+tick stay the sole spine |
| Mandatory agent-per-stage; heavy ceremony for small changes | REJECT | The four conditional agents stay four; TINY keeps small work cheap |

**GitHub Spec Kit** — *historical reference only; no SHA pinned; already rejected as a profile (ADR-001, v2.12.0)*

| Capability | Verdict | Where it lands |
|---|---|---|
| Requirement structure + stable IDs | CONCEPT (prior art) → NATIVE | R3 native `REQ/AC/OBJ`; extended through tasks/evidence in R4 (C9) |
| Acceptance criteria | CONCEPT → NATIVE | `AC-###` under the single `SPEC.md` template (C3) |
| Clarification markers | CONCEPT → ADAPT | Blocking `[NEEDS CLARIFICATION]` prevents progression; non-blocking deferred records reason/owner/resolution/impact (C3) |
| Success criteria | CONCEPT → MERGE | Tier-conditional spec depth + evaluator coverage checks |
| Runtime, `/speckit-*` skills, presets, `.specify/`+`specs/`+`tasks.md`, second queue | REJECT (re-confirmed) | ADR-001; `test-docs-invariants.sh` still forbids "speckit"/"spec kit" strings |

**BMAD** (`BMAD-METHOD`) — *concept-only; no SHA pinned*

| Capability | Verdict | Where it lands |
|---|---|---|
| Project-size questions | CONCEPT → ADAPT | `classify-work.sh` complexity signals (C2) |
| Uncertainty questions | CONCEPT → ADAPT | `[NEEDS CLARIFICATION]` / DEEP research + architecture-alternatives fields (C3) |
| Risk classification | CONCEPT → ADAPT | Classifier escalation signals that block TINY unless override is explicit + recorded (C2); `docs/RISK-MAP.md` as GENERATED VIEW |
| Stakeholder-impact questions | CONCEPT → MERGE | Ownership concepts (CODEOWNERS / `OWNERSHIP.md` / Planner `## Change ownership`, C5); required reviewers, not personas |
| Personas, story hierarchies, party mode, role choreography | REJECT | Role theatre with no artifact authority; R4 keeps the single-orchestrator model |

**Verdict legend:** `ADAPT` idea reworked into a native surface · `MERGE` folded into an existing
capability (no new skill/agent) · `NATIVE` already re-implemented natively upstream of R4 · `REJECT`
deliberately not adopted, reason given. No text-`COPY` verdicts appear because no upstream text was
vendored.

---

## Design (per commit)

Each commit is small, self-contained, and leaves its targeted tests green. Full commit table below.

**C2 classifier** — `jaimitos-os/scripts/classify-work.sh` (Bash 3.2/BSD-safe). Signals → prints the
`## Work classification` block (Recommended/Selected/Override/Reasons/Risk/Complexity/Required
workflow/Skipped ceremony). Escalation signals normally block TINY (auth, authz, secrets, payments,
destructive migration, public-API change, high-stakes data, major dep upgrade, multi-service deploy,
irreversible behavior, unresolved architecture) — override explicit + recorded. `tier:` stored in
`SPEC.md` frontmatter (optional per-phase override); short CLAUDE.md pointer.

**C3 spec depth** — one `jaimitos-os/docs/SPEC.md`: TINY compact block (Objective/Current/Expected/
Scope/Likely files/Verification/Non-goals; native IDs optional); STANDARD = existing REQ/AC + scenarios/
constraints/migration/security/test-strategy/assumptions; DEEP adds research/architecture-alternatives/
data model/contracts/dep graph/rollback/failure modes/observability/threat/perf/compat/release/deferred
decisions/enforcement implications, *referencing ADRs*. Blocking `[NEEDS CLARIFICATION]` prevents
progression; non-blocking deferred records reason/owner/resolution/impact. `to-spec`/`grill` read tier;
`to-spec` stays sole ID owner.

**C4 mapme modes** — one `skills/mapme/SKILL.md`: default overview + `--brownfield` + `--ownership` +
`--refresh`. Every material claim tagged `VERIFIED|INFERRED|UNKNOWN|STALE DOCUMENTATION|CONTRADICTION`
citing paths/symbols/commands/config/tests/CODEOWNERS/pkg metadata. Stated-vs-actual →
`CONFIRMED|ARCHITECTURAL DEBT|DOCUMENTATION DRIFT|UNKNOWN` (never auto-convert current structure into
"desired"). Staleness baseline (commit/date/paths/manifests/entry points/test config/CODEOWNERS
checksum) → `POSSIBLY STALE — REVIEW REQUIRED`; `--refresh` regenerates only affected maps. Outputs only
when justified; small repos consolidate; keep "flag, never fix".

**C5 ownership** — (A) CODEOWNERS authority when present (validate patterns, flag uncovered sensitive
areas, never rewrite/permission/complete); (B) `docs/OWNERSHIP.md` when justified
(`OWNED|SHARED|UNOWNED|GENERATED|VENDORED|EXTERNAL|UNKNOWN`; Git-history inference never shown as
verified); (C) Planner `## Change ownership` (Planned writes/Required reads/Shared files/Out of
scope/Required reviewers/Integration order; TINY short form). Checks in Planner + Evaluator: overlapping
writes, non-disjoint parallel, shared-without-integration-owner, high-stakes-without-supervised,
generated/vendor-as-source, stale map. Disjointness unproven → sequential. Evaluator gains an
ownership-compliance section (unexpected files don't auto-fail; unexplained unrelated/high-stakes block
PASS).

**C6 enforcement ledger** — `docs/ENFORCEMENT.md` when justified (ID/Claim/Source/Enforcement/Strength/
Status/Trigger; strengths `DETERMINISTIC|HOOK-ENFORCED|CI-ENFORCED|MODEL-DEPENDENT|HUMAN-DEPENDENT|
ADVISORY|DEFERRED`). Validator `lint-enforcement.sh`/`_enforcement.sh`: source exists, referenced
test/script exists, deferred trigger references a real phase, staleness warnings. Additive; never
regenerated from the code graph; never ticks/permits/replaces tests/hooks/ADRs.

**C7 evaluator PLAN_CHECK + pre-mortem (CONTROL PLANE)** — extend `evaluator.md`: name the current
two-axis review `IMPLEMENTATION_REVIEW` (+ ownership-compliance section), add a fresh-context read-only
`PLAN_CHECK` mode with the full plan checklist + pre-mortem ("shipped as written and still failed —
why?": requirement coverage, integration seams, dependency graph, temporal risks in execution order,
failure behavior, verification, ownership+enforcement). Verdict `PASS|PASS_WITH_WARNINGS|FAIL` on its own
channel (`FAIL` blocks auto-execution; warnings persist) — never routed to `record-grade.sh`.
Applicability: TINY skip/light; STANDARD required unless explicitly waived; DEEP/high-stakes required.
Update `test-docs-invariants.sh` (add mode/verdict/pre-mortem pins; keep all existing pins green).

**C8 stale-plan** — Planner `## Assumption revalidation` (plan/current commit, still valid, changed
since, stale assumptions, adjustments, blocking contradictions). Deterministic `check-plan-freshness.sh`:
baseline no longer ancestor of HEAD, referenced files missing, phase closed/changed, requirement
removed/superseded, ownership map stale, enforcement mechanism missing. Invalidated plan loses prior
PASS; material change → new PLAN_CHECK; scope change → user approval; repeated shared staleness → one
bounded backlog correction.

**C9 traceability** — commit + wire `_requirements.sh` (source from `lint-roadmap.sh`, add to `doctor`
REQUIRED_LIBS, add `test-requirements.sh`, register in `run-guard-tests.sh`). Extend chain to
`PHASE→TASK→EVIDENCE→verdict`; `OBJ-###` for maintenance; `ENF-###` refs validated. Add spec→roadmap
**orphan detection** (requirement with no planned work) + task-without-req/objective/risk,
wrong-commit-evidence, stale verdict, completed-phase-with-open-blocking, release-claims-incomplete,
enforcement-ref-missing. Reports from canonical artifacts; scripts validate structure, evaluator meaning.

**C10 evidence schema_version 2 (CONTROL PLANE)** — `test-evidence.sh` emits `schema_version:2` +
evidence_id, requirement/phase/task refs, cwd, started/finished/duration, classification, warnings,
skipped, redacted, optional hash — atop existing fields. `tick.sh` `jq` reads accept v2, reject
malformed, stay byte-identical on failure; v1/absent handled or cleanly rejected. Failed stays failed,
missing required fields fail closed, output bounded, secrets redacted, summary never overrides exit.

**C11 UAT + gap planning** — one `docs/UAT.md` when needed (Requirement/Status/Expected/Actual/Evidence/
Blocking; `NOT_TESTED|PASSED|FAILED|BLOCKED|DEFERRED`, deferred needs reason/risk/resolution/impact).
Tier-dependent (TINY omit; STANDARD when acceptance differs from automated; DEEP/high-stakes when human
acceptance relevant). Blocking failed UAT blocks release, never bypasses evaluator/evidence/tick. Planner
gap plan: cite failed REQ/AC/OBJ/ENF, preserve scope, classify cause (implementation/specification/
environment/data/dependency/test-evidence/ownership/enforcement), smallest correction, fresh evidence +
fresh PLAN_CHECK when sequencing/ownership changes, never rewrite completed history, never defer failed
required work to close a release.

**C12 diagnose** — enforcement + selective gaps only: loop-first gate, improve-the-loop checklist, flaky
reproduction-rate recording, instrumentation cleanup in completion evidence, differential/bisection,
hypothesis ranking, honest seam-absence, completion checklist (original repro reruns; one passing run
insufficient for flaky). `test-diagnose.sh` static/fixture invariants (not a proof of debugging quality).

---

## Files changed (representative)

| Area | Files | Compat |
|---|---|---|
| Agents | `evaluator.md` (modes/pre-mortem/ownership), `planner.md` (exec ownership, revalidation, gap plan) | additive; inert when phase declares nothing |
| Skills | `skills/mapme` (modes), `skills/to-spec` + `skills/grill` (tier), `skills/diagnose` (gap-fill) | additive; desc ~unchanged |
| New scripts | `classify-work.sh`, `lint-enforcement.sh`, `check-plan-freshness.sh`, new `test-*.sh` | new; registered in run-guard |
| Edited scripts | `test-evidence.sh`, `tick.sh`, `lint-roadmap.sh`, `doctor.sh`, `run-guard-tests.sh`, `test-docs-invariants.sh` | backward-compatible; fail-closed preserved |
| New lib | `.claude/lib/_requirements.sh` (wired), maybe `_enforcement.sh` | runs only when a phase/ledger declares refs |
| Templates/docs | `jaimitos-os/docs/SPEC.md` (tiers); shipped `ENFORCEMENT.md`/`OWNERSHIP.md`/`UAT.md` templates (when-justified); control-plane guide; `docs/dev/AUTHORING.md` (guarantee table); README/GUIDE/SECURITY/CHANGELOG/VERSION; 6 ADRs | additive |
| Always-loaded | `CLAUDE.md` — short pointer only | byte budget guarded |

**Reuse, don't rebuild:** the `Sources:`/`Requirements:` roadmap block, the conditional evaluator
traceability bullet, the anchored `_roadmap.sh` regexes, `next-adr.sh`, the `ok/bad/assert_has/
assert_absent` test header, `run-guard-tests.sh` drift guard, the manifest derive-not-duplicate pattern,
the two-file ROADMAP+STATE transaction, HEAD-binding for evidence integrity.

---

## Deterministic vs semantic enforcement (guarantee table — to extend in AUTHORING.md)

| Guarantee | Enforcement |
|---|---|
| Tier recommendation reproducible; override recorded | DETERMINISTIC (`classify-work.sh`) + HUMAN (selection) |
| REQ/OBJ unique, AC globally unique, refs resolve, orphan detection, format valid | DETERMINISTIC (`_requirements.sh`) |
| Evidence commit-bound, failed-stays-failed, missing-field fail-closed, schema v2 valid | DETERMINISTIC (`test-evidence.sh` + `tick.sh`) |
| Plan freshness: baseline ancestor, referenced files/phases/reqs exist | DETERMINISTIC (`check-plan-freshness.sh`) |
| Enforcement source/mechanism/trigger references exist | DETERMINISTIC (`lint-enforcement.sh`) |
| Ledger strength honest (advisory ≠ deterministic) | HUMAN + MODEL (evaluator) |
| Map claim VERIFIED vs INFERRED vs UNKNOWN; stated-vs-actual honest | MODEL-DEPENDENT (mapme) |
| Plan quality / pre-mortem / requirement meaning / ownership judgement | MODEL-DEPENDENT (evaluator PLAN_CHECK + IMPLEMENTATION_REVIEW) |
| Blocking UAT blocks release | HUMAN + existing release checks |
| Phase completes | existing evaluator → `record-grade` → `tick.sh` (unchanged) |

**Do not exaggerate model-dependent guarantees.** Linters check shape; the evaluator + human check
judgement.

---

## Compatibility, migration, rollback

- Legacy specs/phases (no tier, no REQ/AC, no ownership/enforcement/UAT): behave exactly as today — every
  new capability is opt-in / when-justified / conditional.
- Evidence: a v1/absent-`schema_version` file is still handled or cleanly rejected fail-closed; tick.sh
  stays byte-identical on refusal.
- Recovery (fail-closed, preserve previous valid state, explain manual action, no destructive reset,
  idempotent): interrupted map generation, malformed spec migration, failed plan check, stale plan,
  invalid evidence, invalid enforcement reference, interrupted state transition. No general repair
  framework.
- Rollback: additive commits revert cleanly; optional blocks/docs removable; completed roadmap history
  never rewritten.

---

## Tests (each new suite registered in `run-guard-tests.sh`)

`test-classify-work.sh` (small→TINY, feature→STANDARD, high-stakes escalates, override recorded, skipped
ceremony explicit) · `test-mapme.sh` (claims cite evidence, inferences labeled, unknowns stay unknown,
stated-vs-actual distinct, stale warns, user docs not overwritten, refresh bounded) · `test-ownership.sh`
(CODEOWNERS stays human-review authority, operational distinct, inferred labeled, overlapping writes
fail, shared needs integration owner, stale warns, high-stakes needs supervised, evaluator reports diff
scope) · `test-enforcement.sh` (deterministic→real mechanism, advisory not labeled deterministic, missing
trigger fails/warns, missing source fails, deleted mechanism → staleness, ledger can't tick, no
regenerate-default) · `test-plan-check.sh` (missing coverage fails, orphan task reported, unowned seam
fails, hidden dependency reported, missing e2e reported, risky external failure reported, migration
w/o rollback fails, overlapping exec ownership fails, planner can't approve own plan, TINY avoids heavy
review, verdict contract stable) · `test-stale-plan.sh` (unchanged valid, missing file invalidates,
changed ADR revalidates, changed requirement invalidates PASS, stale ownership surfaced, material change
→ fresh PLAN_CHECK, old PASS not reused) · `test-requirements.sh` (unknown refs fail, orphan detected,
maintenance OBJ works, unresolved blocking blocks completion, wrong-commit evidence fails) ·
evidence-schema-v2 cases in `test-tick.sh`/`test-evidence.sh` (missing fields fail closed, redaction,
summary can't override exit, malformed legacy rejected) · `test-uat.sh` + `test-gap.sh` (blocking UAT
blocks release, deferred needs justification, gap cites failed item, correction needs fresh evidence,
material correction needs fresh PLAN_CHECK, gap can't rewrite history) · `test-diagnose.sh` (loop
required, flaky records repeated runs, instrumentation cleanup required, original repro rerun, seam
absence documentable without fake coverage, one passing run insufficient) · **security/recovery**
behavioral tests (path traversal, symlink escape, wrong worktree, evidence/approval/enforcement-ref
tampering, interrupted-migration recovery, stale-ownership, stale-plan fail-closed).

Prefer behavioral tests over source greps. Portability: full guard suite on macOS (Bash 3.2/BSD) **and**
non-root Linux (GNU + mawk) before claiming green.

---

## Context budget

Record before/after bytes + est. tokens for always-loaded (`CLAUDE.md`) vs invocation-only (classifier
guidance, spec templates, `mapme`, planner, evaluator, ledger guidance, evidence metadata, UAT guidance,
diagnose, session-start). Requirements: TINY does not load DEEP guidance; maps/ownership/PLAN_CHECK/UAT/
ledger load only when relevant; no new always-loaded agent; no duplicated full guidance. Classify LOW/
MEDIUM/HIGH/VERY_HIGH per: TINY, STANDARD, DEEP, brownfield mapping, PLAN_CHECK, UAT, difficult debugging.

---

## Verification (exact commands)

```bash
bash jaimitos-os/scripts/run-guard-tests.sh < /dev/null
bash .github/scripts/install-smoke.sh
bash jaimitos-os/scripts/test-docs-invariants.sh
bash jaimitos-os/scripts/release-check.sh --prepare
find . -name "*.sh" -not -path "./.git/*" -print0 | xargs -0 -n1 bash -n
bash .github/scripts/lint-shell.sh
actionlint .github/workflows/ci.yml jaimitos-os/.github/workflows/jaimitos-os-ci.yml
```
Plus every new dedicated suite. Run on macOS (Bash 3.2/BSD) **and** non-root Linux (GNU + mawk). Report
any check `NOT RUN — <reason>`. No check is claimed passed unless it ran.

---

## Commit structure (small; each leaves targeted tests green; no push/tag)

0. `docs(plan): scope progressive control-plane release (v2.14.0)` — this file
1. `docs(provenance): record selective Vidhi and upstream research`
2. `feat(classification): add tier recommendation and override`
3. `feat(spec): add tier-dependent native specification depth`
4. `feat(mapme): add brownfield, ownership and refresh modes`
5. `feat(ownership): add component and execution ownership`
6. `feat(enforcement): add compact enforcement ledger`
7. `feat(evaluator): add plan-check pre-mortem`
8. `feat(plan): add stale-assumption revalidation`
9. `feat(traceability): extend native links through tasks and evidence`
10. `feat(evidence): strengthen generic evidence schema`
11. `feat(uat): add lightweight acceptance and gap planning`
12. `feat(diagnose): strengthen deterministic feedback-loop discipline`
13. `test(control-plane): add compatibility and negative fixtures`
14. `docs(control-plane): document architecture and migration` (+ 6 ADRs, context budget)
15. `chore(release): dogfood fixes, version and changelog` (prepare only; tag/push is a separate operator checkpoint)

---

## Deliberately out of scope (report as DELIBERATELY REJECTED / DEFERRED)

New permanent agent; separate classify-work/brownfield-onboard/ownership-map/premortem/enforcement-ledger/
gap-planner skills; second evaluator/roadmap/state/evidence authority; issue-tracker execution queue;
database/daemon/service; mandatory parallel agents/telemetry/multi-model router/MCP registry; large
specialist or test-adapter catalog; completion-attestation subsystem; Spec Kit production profile or CLI;
Yojana task state; Sutra runtime; auto `done` transitions; a second spec format. **Deferred until a real
consumer demands them:** test-adapter registry, completion attestations, telemetry, multi-model routing,
MCP registry, live ticket sync.
