# PLAN — v2.5.0: Audit fixes + Pocock skills adapted

> **Status:** APPROVED plan, executing in this session on branch `claude/new-session-7tbpgu`.
> **Source of the requirements:** the v2.5.0 execution prompt (audit fixes + adapted skills).
> **Reference repo:** `mattpocock/skills` (MIT), cloned read-only to a temp dir OUTSIDE this repo.
> This file lives in `docs/dev/plans/` (the new home Phase 1.5 creates for dev plans).

---

## 0. Hard rules (do not violate)

- Do NOT touch `scripts/tick.sh`, `.claude/lib/_high-stakes.sh`, or the evaluator's grading
  logic — except 2.4's explicit "add missing anti-patterns to the evaluator's fakery list".
- Do NOT import wayfinder, triage, to-tickets, code-review, handoff, research, implement,
  ask-matt, teach, prototype, git-guardrails, or the issue-tracker subsystem.
- Do NOT rewrite existing skills except the requested cross-references
  (roadmap→grill, unstick↔diagnose).
- Do NOT change the 4-line ADR format.
- Do NOT tag or close the milestone without an explicit human yes.
- All adapted skills are docs-centric (`docs/SPEC.md`, `docs/ROADMAP.md`, `docs/decisions/`,
  `docs/GLOSSARY.md`) — zero tracker dependencies, no second work queue.
- Nothing from mattpocock/skills is copied verbatim — adapted, with a one-line MIT attribution
  in each SKILL.md and a full note in `skills/README.md`.
- Bash 3.2-compatible shell only (no `declare -A`, `mapfile`, `${x^^}`, `wait -n`).
- Each phase: tests relevant to it green + one atomic commit.

---

## Parte 1 — Audit fixes

### Fase 1.1 — curl/wget contradiction
- Drop `"Bash(curl *)"` and `"Bash(wget *)"` from `jaimitos-os/.claude/settings.json` deny.
- Document in GUIDE.md ("Enforcement reality") + SECURITY.md: network exfiltration cannot be
  blocked with bash globs (python/node/nc are a thousand other paths); the real boundary is the
  no-credentials sandbox. Coherent with the existing "speed-bump" framing.
- No test asserts those two denies today (verified by grep); run the guard suite anyway.
- **Done when:** `jq '.permissions.deny'` has no curl/wget; `grep curl settings.json` empty;
  `bash scripts/run-guard-tests.sh` green.

### Fase 1.2 — sync.sh: 4 tiers → checksum manifest
- `install.sh` writes `.claude/.jaimitos-manifest`: `<sha256>  <project-relative-path>` per file
  actually written this pass (merge semantics: update/add written entries, keep the rest),
  `sha256sum -c`-compatible. Covers both source roots (scaffold + skills).
- Rewrite `scripts/sync.sh` — evaluation order:
  0. no manifest → explain + exit; `--adopt-manifest` records the CURRENT local files as
     baseline (writes only the manifest, never content).
  1. in manifest, local sha == manifest, toolkit differs → batch-updatable (one confirmation,
     `--yes` skips); manifest entries refreshed after write.
  2. in manifest, local sha != manifest → NEVER written; show toolkit↔local diff, list as
     "manual merge required". All value-preserving merge logic deleted.
  3. project-owned fixed list (`docs/**`, `CLAUDE.md`, `.gitignore`,
     `.claude/high-stakes-path-allowlist`, `SCAFFOLD.md`) → never touched or reported.
  4. toolkit file absent locally: (a) in manifest → deleted on purpose: skip, offer
     `--restore <path>`; (b) not in manifest → NEW toolkit file: treat as case 1 (batch add +
     manifest entry).
- Flags kept: `--dry-run`, `--toolkit <path>`, `--yes`, `--adopt-manifest`, `--restore <path>`,
  never-scaffolded refusal, clean-tree recommendation. Deleted: tiers, jq structural merge,
  HIGH_STAKES_RE/model:/paths: preservation, unknown classification.
  Keep: version stamp on success, exec-bit restore on shipped scripts, CI opt-in gate for
  `.github/*` adds, deterministic sorted enumeration.
- Rewrite `test-sync.sh` covering the 13 enumerated cases (manifest valid after install;
  sha256sum -c; clean update + manifest refresh; modified never overwritten + diff; project-owned
  untouched; pre-manifest refusal; --adopt-manifest baseline; post-adoption update; new toolkit
  file installed + manifest; local delete not recreated / --restore recreates; --dry-run writes
  nothing incl. manifest; paths with spaces; unscaffolded target refused).
- install-smoke: manifest exists + `sha256sum -c` passes after clean install.
- Docs: README "Keeping a project up to date" + GUIDE rewritten to the manifest model with the
  `--adopt-manifest` migration note; 4-tier explanation deleted.
- **Size target:** sync.sh ≤ 250 lines, test-sync.sh ≤ 350 — target, not dogma; any excess is
  justified here BEFORE proceeding.
- **Size justification (recorded before continuing):** the rewritten sync.sh lands at 292 lines
  (down from 575, −49%). The ~42-line excess over the target is documentation, not logic: the
  header block (~38 lines) spells out the five manifest cases, the adoption caveat (pre-adoption
  customizations look "unchanged" to the baseline), and the exit-code contract — exactly the
  fail-closed clarity the target says not to sacrifice. The executable body is ~230 lines.
  Stripping comments to hit 250 would trade away the contract documentation for a number.
- **Done when:** new suite green, install-smoke verifies the manifest, `grep -rn` of
  "mixed"/"value-preserving"/"unknown tier" clean in scripts and active docs, adoption path
  covered by test.

### Fase 1.3 — team-repo mode
- GUIDE.md "## Working in a team repo": `LEAN_CHECKPOINT=off` (session env or settings.json
  `env`), squash-before-PR convention, keep kill-switch/secret-scan vs disable checkpoint.
- `doctor.sh`: warn (not error) when `git shortlog -sn | wc -l` > 1 and `LEAN_CHECKPOINT` is not
  off (env or settings.json env).
- Checkpoint commit prefix: already stable (`checkpoint: N file(s) @ …` in commit-on-stop.sh) —
  verify + document, no change needed.
- test-doctor.sh covers the warn (2 simulated authors) and its absence with LEAN_CHECKPOINT=off.
- **Done when:** section exists, doctor warns in a 2-author test repo, test green.

### Fase 1.4 — executable sandbox for headless autopilot
- `jaimitos-os/sandbox/Dockerfile.autopilot`: debian-slim + git/jq/bash/node + claude CLI,
  non-root user, repo mounted as volume, no credential mounts.
- `jaimitos-os/sandbox/run-autopilot-sandboxed.sh`: builds image if missing, mounts ONLY the
  repo (`-v "$PWD":/work`), passes `-e ANTHROPIC_API_KEY` (the single allowed credential),
  runs `scripts/autopilot.sh "$@" --dangerously-skip-permissions` inside. Refuses to run when
  git-tracked secret-shaped files (`.env`, `secrets/`, per `_secret-scan.sh` filename rules)
  exist inside the mounted repo; refuses cleanly without docker.
- `scripts/test-sandbox.sh` (added to run-guard-tests TESTS): refusal cases + Dockerfile lint
  (hadolint if present, else basic checks) — no docker needed in CI.
- README (Autonomy) + GUIDE: sandbox is the supported path for unattended.
- install.sh copies `sandbox/` (it already copies everything not excluded — verify).
- **Done when:** wrapper fails clean without docker (tested), refusal tests green, Dockerfile
  passes lint when available.

### Fase 1.5 — structural cleanup
- `git mv` jaimitos-os/PLAN-v*.md + root PLAN-v2.2-toolkit-sync.md → `docs/dev/plans/`;
  `docs/audits/` → `docs/dev/audits/`.
- Fix all references (grep in *.md/*.sh incl. CI + install-smoke); simplify install.sh's
  `PLAN-*.md` exclusion comment (kept as defense, matches nothing now).
- **Done when:** `find jaimitos-os -name 'PLAN-*.md'` empty, guard tests + install-smoke green.

### Fase 1.6 — slim CLAUDE.md + dedupe security narrative
- CLAUDE.md "## Autonomy" ≤ 10 lines, only operational rules (tick via tick.sh; evaluator
  grades; AGENT_STOP; close-milestone needs explicit question). Architecture explanation →
  GUIDE if not already there.
- GUIDE Part 4/5 declared single source for the security narrative; README security ≤ 15 lines
  + link; CLAUDE.md behavioral rules only. Script comments untouched.
- **Done when:** `wc -l jaimitos-os/CLAUDE.md` ≤ 55; "scan window" explained in detail only in
  GUIDE.md (+ SECURITY.md keeps its own scope statement — it's a policy doc, README slims).

---

## Parte 2 — Adapted skills (7 new: to-spec, grill, diagnose, tdd, merge-conflicts, design-twice, glossary)

Global rules: live in `skills/<name>/SKILL.md`; frontmatter styled like scope-guard/adr
(name + description-with-triggers, `disallowed-tools` where applicable); 30–80 lines per
SKILL.md; English; attribution line
`<!-- Adapted from mattpocock/skills (MIT) — https://github.com/mattpocock/skills -->`;
artifacts go to `docs/`; ADRs stay 4-line in `docs/decisions/`.

- **2.1 to-spec** — synthesize the session's design conversation into `docs/SPEC.md` (existing
  template respected); propose test seams (fewest possible, ideal 1) and confirm BEFORE writing;
  measurable success criterion mandatory (the one allowed question); closes suggesting the
  `roadmap` skill. Triggers: "to spec", "congela esto en la spec", "vuelca la conversación en
  docs/SPEC.md".
- **2.2 grill** — grilling+grill-me fused: relentless one-question-per-turn interview with own
  recommendation each time; facts from the codebase, decisions from the user; offers `to-spec`
  at the end. Update `skills/roadmap/SKILL.md` "grill the spec first" → name the skill.
  Triggers: "grill me", "grill this plan", "estréssame este plan".
- **2.3 diagnose** — Phase 1 of diagnosing-bugs kept whole (tight feedback loop, ~10 ordered
  ways, tighten, non-deterministic); CONTEXT.md → `docs/ARCHITECTURE.md`, ADRs →
  `docs/decisions/`; ships `scripts/hitl-loop.template.sh` inside the skill; bridges: design
  decision → `adr`, bigger work → `milestone`; unstick↔diagnose boundary documented in both
  (unstick = 3+ circular attempts / process; diagnose = a bug to reproduce / technique).
  Triggers: "diagnose", "debug this", "hay un bug", "está roto", "va lento".
- **2.4 tdd** — skill + tests.md + mocking.md adapted to my docs; pre-agreed seams come from
  docs/SPEC.md or docs/plans/<fase>.md — if present, use them without re-asking.
  `executor.md` gains one line referencing the skill as ITS TDD manual. Verify anti-patterns
  (tautological, implementation-coupled, mocking the subject) exist in evaluator's fakery list —
  add any missing (teach/grade symmetry). Triggers: "tdd", "red-green", "test-first".
- **2.5 merge-conflicts** — near-direct adaptation of resolving-merge-conflicts + the
  `/autopilot-parallel` worktree-integration case; cross-reference added in
  `.claude/commands/autopilot-parallel.md`'s conflict step.
  Triggers: "merge conflict", "resuelve el conflicto", "el merge falla".
- **2.6 design-twice** — sketch TWO genuinely different designs before non-trivial
  implementation, compare trade-offs, choose, record via `adr` (rejected alternative included —
  my format already requires it). `planner.md`: non-trivial phases (>~3 tasks or new
  module/interface) apply design-it-twice, plan includes "Alternative considered: ...".
  DEEPENING.md assessed: bring only if it adds — decision recorded in the commit.
  Triggers: "design this", "diseña el módulo", "cómo estructuro esto".
- **2.7 glossary** — minimal domain-modeling: optional `docs/GLOSSARY.md` (term, one-line
  definition, rejected/renamed terms); NO ADRs (that's the `adr` skill).
  `session-start.sh` injects `docs/GLOSSARY.md` capped at 30 lines (same head+truncation-notice
  pattern as STATE.md). Triggers: "glossary", "define el término", "cómo llamamos a".
- **2.8 wiring** — skills/README table (18 total; 17 per-project), doctor REQUIRED_SKILLS,
  install-smoke skill list, CHANGELOG v2.5.0 entry (Audit fixes / New skills + MIT attribution),
  VERSION → 2.5.0. NO tag, NO milestone close.
- **Done when (parte 2):** `bash install.sh /tmp/test-target` installs 17 skills, doctor green
  on target, run-guard-tests green, `grep -rn "issue-tracker\|wayfinder\|setup-matt-pocock"
  skills/` empty.

---

## Parte 3 — Exhaustive documentation pass (after 1+2 are green)

- **3.1 obsolescence sweep** — grep all *.md for: mixed, value-preserving, unknown tier,
  four/4 tiers, curl/wget denies, "11 skills"/any count, old PLAN/audit paths, issue-tracker,
  manifest-less sync. Verify real counts by command; doc-debt list recorded below before fixing.
- **3.2 README** — 18-skill list by category (Pocock-adapted marked); "Keeping a project up to
  date" rewritten to manifest model with `--adopt-manifest` migration block; Security ≤15 lines
  + sandbox line; Autonomy names the sandbox wrapper; quickstart verified.
- **3.3 GUIDE** — new "Sync & the manifest" (format, 4 cases with real output, --adopt-manifest,
  --restore, upgrading pre-2.5.0); consolidated security single-source check; "Team repos"
  section; "The skills pack" flow (grill→to-spec→roadmap→/phase; tdd↔executor↔evaluator;
  design-twice↔planner; diagnose vs unstick) with a one-screen text/mermaid diagram; TOC
  regenerated.
- **3.4 scaffold docs** — SCAFFOLD.md reflects post-release tree (sandbox/, manifest, no
  PLAN-*.md); templates checked for dead flows; skills/README "Adapted skills" subsection with
  full MIT attribution once; frontmatter consistency pass across the 7 new SKILL.md.
- **3.5 CONTRIBUTING/SECURITY/CHANGELOG** — CONTRIBUTING: "how to add a skill" + "how synced
  files change" (manifest implications); SECURITY: deny update + sandbox as main unattended
  mitigation; CHANGELOG v2.5.0 structured (Breaking: sync model + --adopt-manifest required
  action; Added; Changed; Removed) + the dated autopilot.sh review TODO.
- **3.6 verification gate** — sweep grep clean (historical mentions only in CHANGELOG +
  docs/dev/); `scripts/test-docs.sh` (~40 lines): declared skill counts vs `ls skills/`,
  cited `\`path\`` existence in README/GUIDE; added to run-guard-tests.

### Doc debt (filled in during 3.1)

_To be recorded by Fase 3.1 before fixing._

---

## NOTA — autopilot.sh deliberately NOT simplified

`autopilot.sh` (683 lines) stays: its lines are guarantees (watchdogs, integrity checks,
worktrees), not fat. The lean decision on it is about USE, not code: if after ~2 months
(review ~2026-09-09) headless mode has been used fewer than 3 times, the right simplification
is deleting it entirely in favor of in-session `/autopilot`. A dated TODO goes in CHANGELOG.

## Execution order & verification

Parte 1 completa → Parte 2 → Parte 3. Each phase ends with its Done when verified + an atomic
commit. Final: `doctor.sh`, `run-guard-tests.sh`, install-smoke against a clean target, summary
of what changed / which tests cover each fix / what stayed out of scope and why.
