# Authoring skills and agents (maintainer guide)

The authoritative guide for adding, changing, or **removing** a Jaimitos component.

This file is maintainer-only. It lives at the repo root under `docs/dev/`, which `install.sh` never
reads (its only source roots are `jaimitos-os/` and `skills/`), so it costs a user project exactly
zero bytes. Do not copy its content into `jaimitos-os/CLAUDE.md` — that file is loaded on every turn.

The tooling that applies this guide — `skill-creator` and `agent-creator` — lives in the repo-root
`.claude/skills/`, for the same structural reason.

---

## What this repo can and cannot guarantee

Read this before you write a line of a new component, and before you describe one in a release note.
The linters check **shape**. They do not check **judgement**, and pretending otherwise is how a
trust-focused toolkit quietly stops being trustworthy.

| Guarantee | Enforcement |
|---|---|
| Skill/agent frontmatter is valid; `name` matches its directory/filename | **Deterministic** — `test-skills.sh`, `test-agents.sh` |
| No duplicate skill/agent names; no skill↔command↔agent collision | **Deterministic** — `test-skills.sh` |
| Catalog ⇔ directory: every skill is listed, every listing is real | **Deterministic** — `test-skills.sh` |
| Maintainer-only components are excluded from every install path | **Deterministic** — `install-smoke.sh` (negative assertions) + source-root check |
| An agent declares an output contract; no silently-ignored hyphenated keys; the model value is real | **Deterministic** — `test-agents.sh` |
| Every agent definition is covered by `GATE_CONTROL_FILES` | **Deterministic** — `test-agents.sh` |
| Always-loaded context stays inside budget | **Deterministic** — `test-skills.sh` (model-invoked skill descriptions: 500 B each / 6000 B total) + `test-agents.sh` (agent descriptions: 500 B each / 2000 B total). `CLAUDE.md` itself is **not** byte-capped — that one is human-dependent. |
| Provenance schema is valid and its cited files exist | **Deterministic** — `test-skills.sh` |
| The discipline is *stated* in the skill (red-for-the-right-reason, no speculative loops, …) | **Deterministic** — `test-docs-invariants.sh` (greps the prose; proves the rule is written, **not** that it was obeyed) |
| Requirement ids are well-formed and unique (`AC` globally); a phase's `Requirements:` refs resolve to `docs/SPEC.md`; an `Approved` requirement carries no blocking `[NEEDS CLARIFICATION]` | **Deterministic** — `_requirements.sh` via `lint-roadmap.sh` (advisory; `--strict` fails). Structure only — never that a requirement is *satisfied* |
| Work-tier recommendation is reproducible from its signals | **Deterministic** — `classify-work.sh` (same flags → same tier; unknown flag / bad value → exit 2) |
| An override records WHY it differs from the recommendation | **Human-dependent** — `classify-work.sh` warns on a reasonless override but still exits 0, and nothing checks the reason reached `docs/SPEC.md`. The tier field itself is never validated against the classifier. |
| A REQ/OBJ defined and active in the spec that no phase plans is surfaced (orphan) | **Deterministic — advisory** — `requirements_orphans` via `trace-requirements.sh` |
| Plan freshness (HARD): baseline is a valid commit and still an ancestor of HEAD; every cited REQ/AC/OBJ id resolves in `docs/SPEC.md` (an absent SPEC fails closed) | **Deterministic** — `check-plan-freshness.sh --strict` exits 1 |
| Plan freshness (SOFT): a referenced file is missing or changed since the baseline | **Advisory** — surfaced for revalidation, never fails `--strict` (path roots vary; hard-flagging produced dozens of false positives in v2.14.0's own dogfood) |
| An invalidated plan does not keep a prior PLAN_CHECK PASS | **Model + human** — no PLAN_CHECK verdict is stored anywhere, so nothing can mechanically revoke one; running the check before execution, and honouring it, is the planner's and the operator's discipline |
| Evidence carries `schema_version 2` (v1 fields kept); an unknown version fails closed; a summary cannot override the exit-derived status | **Deterministic** — `test-evidence.sh` + `tick.sh` schema gate |
| A validator never executes its input and never mutates it | **Deterministic** — `test-control-plane-security.sh` |
| A map claim is VERIFIED vs INFERRED vs UNKNOWN; stated-vs-actual is honest; current structure is not blessed as intended | **Model-dependent** — `mapme` |
| A plan is coherent, covered, ordered, and owned (pre-mortem: seams, temporal, failure behavior) | **Model-dependent** — evaluator `PLAN_CHECK` (independent; a planner cannot self-approve) |
| Unexplained unrelated / high-stakes diff scope | **Model-dependent** — evaluator ownership-compliance, on the deterministic phase diff |
| A grader cannot edit the tree it grades | **Hook/gate enforced** — `_eval-isolation.sh` snapshot + restore |
| Completion evidence belongs to the current commit | **Hook/gate enforced** — `tick.sh` (`run_id == HEAD`) |
| A test actually failed *for the intended reason* | **Model-dependent** — reviewed as evidence by the evaluator |
| A declared requirement/`AC` is genuinely satisfied by the code and its tests | **Model-dependent** — traced by the evaluator only when a phase declares `Requirements:` |
| Debugging avoided a speculative-fix loop | **Model-dependent** — reviewed as evidence |
| A new skill or agent was genuinely *justified* | **Model-dependent + mandatory human review** (control-plane change) |
| Module architecture is proportionate; the architecture fits | **Model-dependent** |

**Never write a release note that implies a row in the bottom half is enforced.**

---

## Choosing the shape

In order. Stop at the first one that works.

1. **Improve an existing component.** Almost always the right answer. A new component is a new
   surface, a new trigger, a new thing to keep in sync, and a permanent tax.
2. **A deterministic script.** If the behaviour is mechanical, a script cannot be talked out of it
   by a persuasive prompt. Prefer this to any prose instruction.
3. **A rule or a reference file.** Loaded on demand; no trigger to collide.
4. **A skill.** A repeatable discipline the model must apply, with a checkable output.
5. **An agent.** Only when a genuinely *separate context* or genuine *independence* is required.
   The four-stage pipeline (research → plan → execute → independent evaluation) already covers
   research, planning, implementation and grading. `NO NEW AGENT JUSTIFIED` is a success.

| Use a… | when |
|---|---|
| **command** (`.claude/commands/`) | the user drives a multi-step orchestration by hand (`/phase`, `/wrap`) |
| **skill** (`skills/`) | a discipline the model applies while doing something else |
| **agent** (`.claude/agents/`) | the work needs its own context window, or must be independent of the builder |
| **script** (`scripts/`) | the rule must hold even when the model would rather it didn't |

---

## Skills

### Invocation is a budget decision
A **model-invoked** skill keeps its `description:` in the context window **on every turn, forever**.
That buys autonomous firing and reach from other skills. A **user-invoked** skill
(`disable-model-invocation: true`) costs **zero** always-loaded context — but you must remember it
exists.

**User-invoked is the default. Model-invocation carries the burden of proof — and the proof is a
list, not an argument.** Before choosing, enumerate the consumers:

```bash
grep -rn "<skill-name>" skills/ jaimitos-os/.claude/
```

For each one, ask: does it reach the skill **autonomously**, or does it **name the skill explicitly**
(by path, or by name)? A consumer that names it explicitly reads the file directly and needs no
description in the window. **If no consumer relies on autonomous reach, the skill is user-invoked.**

> **This rule is written in blood.** v2.10.0 shipped `module-design` model-invoked, reasoning that
> "five components must reach it". All five named it by path; none needed auto-fire. The argument
> felt right and the grep would have settled it in ten seconds. An independent review overturned it
> one release later, and v2.11.0 reverted it — reclaiming 295 B/turn. **Run the grep.**

Watch for the circular defence: *"a user might type a bare question only this skill answers."* A user
who can phrase the question in the skill's own vocabulary has already read it; one who cannot phrases
it in ordinary words, which fire some **other** skill's trigger. `module-design`, `prototype` and
`review-feedback` are all user-invoked — three of the last four skills added. That is not a
coincidence; it is what happens when the default is applied honestly.

`test-skills.sh` enforces a per-description cap and a total budget. Report the **new total**, not the
marginal cost: every single skill looks affordable on its own, which is exactly how a budget dies.
**Do not solve a context budget by making instructions vague.**

### Descriptions
Front-load the trigger. One trigger per genuinely distinct branch — synonyms restating one branch are
duplication you pay for every turn. **Do not summarize the skill's workflow in its description**: a
description that describes the process becomes a shortcut the model takes *instead of reading the
body*.

### Progressive disclosure
Keep the steps and the short reference inline. Push heavy reference into a sibling `.md` and link it
in one line (`tdd/tests.md`, `module-design/deepening.md`). It loads when the pointer fires, not before.

### One source of truth
Every artifact has exactly one owner: `docs/ROADMAP.md` → `roadmap`/`milestone`; `docs/GLOSSARY.md` →
`glossary`; `docs/decisions/` → `adr`; `docs/ARCHITECTURE.md` → `mapme`; completion → `scripts/tick.sh`
and nothing else. A second author for any of these is a defect, not a feature.

### Adding a skill
Create `skills/<name>/SKILL.md`, add its row to `skills/README.md` (**the authoritative catalog — the
only place a skill count lives**), and run the tests. That is the whole checklist: `doctor.sh` derives
its expected set from the install manifest and `install-smoke.sh` derives its set from the source root,
so **neither needs editing**. If you find yourself updating a count in more than one file, stop — you
are re-creating the drift this design removed.

---

## Agents

Every agent definition is a **control-plane change** and needs human review.

- **camelCase frontmatter**: `tools`, `disallowedTools`, `model`, `permissionMode`. The hyphenated
  forms (`allowed-tools`, `disallowed-tools`, `permission-mode`) are SKILL/command fields — in a
  subagent they are **silently-ignored no-ops**, so a restriction you *think* you set does not exist.
  This is the single most dangerous authoring mistake here; `test-agents.sh` fails on it.
- **Model**: prefer an alias (`sonnet`/`opus`/`haiku`/`fable`/`inherit`). A pinned full id silently
  goes obsolete — `test-agents.sh` warns on one.
- **Scope matters**: a *plugin* subagent ignores `permissionMode`, `hooks` and `mcpServers`; project
  and user agents honour them. Emit only the fields the target scope actually reads.
- **Output contract**: state exactly what the agent returns, so the orchestrator can verify it ran.
- **No-op detection**: say what the orchestrator does when the agent returns nothing, returns
  something irrelevant, or never called a tool. An agent with no defined empty-output path is a
  silent-failure generator.
- **Gate integrity**: every file in `.claude/agents/` **must** be listed in `autopilot.sh`'s
  `GATE_CONTROL_FILES` — the evaluator prompt *is* the grading contract, and a tampered prompt could
  rubber-stamp a phase. `test-agents.sh` fails if a definition is not covered.
- **Authority**: researchers are read-only; planners write only their plan artifact; the executor owns
  implementation; graders are edit-disabled. No agent may touch roadmap completion, evidence, grades,
  tick scripts, `.claude/lib/*`, or the high-stakes allowlist.

---

## Removal and consolidation

Adding feels safe and removing feels risky, so components accumulate as **sediment**. Push back.

- If two skills fire on the same situation, one of them is wrong — merge or delete.
- If a skill is only ever invoked by another skill, it is a reference file, not a skill.
- If a skill has no checkable output, it is documentation.
- If it exists only because an upstream project has it, delete it. (`v2.7.0` retired `ship-check` and
  `explain-diff` when Claude Code's native `/code-review` and `/security-review` covered them. That was
  correct. `v2.10.0` rejected `architecture-audit` for the same reason.)

Splitting a skill costs a trigger and a description. Do it only when a distinct trigger genuinely needs
independent reach.

---

## Provenance

Anything adapted from upstream carries a one-line attribution comment in the file itself, and an entry
in [`integrations/upstreams.lock.json`](../../integrations/upstreams.lock.json): the pinned SHA, the
license, the files consulted, the Jaimitos files influenced, and **every deliberate deviation** —
including what was rejected and why. `test-skills.sh` validates the schema and asserts the cited files
still exist.

There is no automatic updater, and there must not be one: fetch-and-overwrite is how a careful
adaptation silently reverts to someone else's opinions. See `integrations/README.md`.

---

## Before you call it done

```bash
bash jaimitos-os/scripts/test-skills.sh          # frontmatter, catalog, budget, provenance
bash jaimitos-os/scripts/test-agents.sh          # agent shape, tool boundary, gate coverage
bash jaimitos-os/scripts/run-guard-tests.sh      # everything (registration is enforced)
bash .github/scripts/install-smoke.sh            # proves maintainer-only stays unshipped
```

Then **dogfood it once on real work**, and have **someone who did not write it** review it. A
component that has never been used is a guess. Static validation proving a component is well-formed is
not evidence that it was worth adding.

**"Independent" means independent.** Not the author reviewing carefully. Not a subagent you briefed
and then graded. If nobody independent has looked at it, it is not cleared — say so rather than
quietly counting your own approval. v2.10.0's review of `module-design` was performed by the same
person who orchestrated its creation; it approved a decision a genuinely independent reviewer
overturned one release later. **Self-reviews find nothing, reliably.**
