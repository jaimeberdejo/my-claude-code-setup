---
name: mapme
description: Regenerates a one-page architecture map of the project from the actual current code, and in its bounded modes onboards a brownfield repo, maps ownership, or refreshes a stale map. Use when re-entering a project, onboarding, or after big changes — "map the project", "how does this fit together", "map this brownfield repo", "who owns what", "update the architecture doc". Reads code, does not trust stale docs. Modes: --brownfield, --ownership, --refresh.
---

# Map me

A one-page "how this fits together" doc is what lets you re-enter a project cold. This regenerates it
from the code as it actually is now — not from whatever the old doc claimed. Run it whenever the mental
map has gone fuzzy.

Every map this skill writes is a **GENERATED VIEW**, never canonical state. It supports planning; it does
not replace fresh inspection, and it never becomes the spec, the roadmap, or an authority. Reading the
system is the only time you see its seams at once — so note the friction, but **flag it, never fix it.**

## Modes (one skill, a mode flag — do NOT make new skills)
| Invocation | What it maps | Primary output |
|---|---|---|
| `mapme` (bare) | the architecture, top-down | `docs/ARCHITECTURE.md` |
| `mapme --brownfield` | an unfamiliar/legacy repo, end to end | `docs/CODEBASE.md` (+ others only when justified) |
| `mapme --ownership` | who owns what, and what is unowned | `docs/OWNERSHIP.md` |
| `mapme --refresh` | only the maps affected by recent change | the affected doc(s) only |

Small repos **consolidate** into one map — do not emit every file unconditionally. Only create a doc when
it earns its place. Keep every map compact; if one grows past a page, link out to detail rather than inline it.

## Evidence classification (every material claim, in every mode)
A map is only trustworthy if it says how it knows each thing. Tag every material claim:
- **VERIFIED** — confirmed by reading the code / running a command / a config or test file. Cite it.
- **INFERRED** — a reasonable deduction (naming, a manifest, git history) not directly confirmed. Say so.
- **UNKNOWN** — you could not determine it. Leave it UNKNOWN; do not guess and present the guess as fact.
- **STALE DOCUMENTATION** — an existing doc claims it, but the code no longer matches.
- **CONTRADICTION** — two sources disagree (a doc vs the code, two configs, a comment vs behavior).

Cite the basis: a path, a symbol, a command run, a config key, a test, a doc, `.github/CODEOWNERS`, or
package metadata. **Never present INFERRED as VERIFIED, and never copy large source excerpts** — cite the
location, don't paste the file.

## `mapme` (default) — the architecture map
1. **Survey the structure.** Top-level dirs, key files, entry points (main, app factory, CLI, server, the
   graph's compile/run for agent projects).
2. **Trace the main flows.** For the 1–3 primary use cases, follow execution from input to output using
   the real call graph — grep/read to confirm, don't assume.
3. **Identify the boundaries.** Modules and responsibilities, what depends on what, where the seams are
   (interfaces, adapters, external services, the DB).
4. **Write `docs/ARCHITECTURE.md`**, one page: One-paragraph overview · Entry points (file:line) · Module
   map (each module: one line + key files) · Main data flow (short numbered list or a simple text/mermaid
   diagram) · External dependencies (and what they're for) · Where the risk lives (the 2–3 most complex or
   consequential spots).

For graph/agent projects (e.g. LangGraph), also emit a mermaid diagram of the node/edge structure — the
graph IS the system. Read the graph definition; don't sketch from memory.

## `mapme --brownfield` — onboard an unfamiliar repo
You are meeting this codebase cold. Inspect, and classify each finding (VERIFIED/INFERRED/UNKNOWN):
languages · frameworks · entry points · services · data stores · build system · CI · deployment · public
interfaces · generated/vendored files · high-change areas (git churn) · security-sensitive areas · package
boundaries · conventions · existing documentation · known risks · contradictions.

Write `docs/CODEBASE.md` — a compact operational overview. Split out `docs/ARCHITECTURE.md`,
`docs/DEPENDENCIES.md`, `docs/TEST-MAP.md`, or `docs/RISK-MAP.md` **only when the repo is large enough
that one doc would exceed a page** — otherwise fold them into sections of `CODEBASE.md`. Record the
staleness baseline (below) so the map can announce when it has aged.

### Stated vs actual architecture (brownfield's most valuable output)
Compare the **human-authored intent** (READMEs, ADRs, an existing ARCHITECTURE.md, module docstrings)
against the **actual dependency and module structure** you traced. Classify each comparison:
- **CONFIRMED** — the code matches the stated intent.
- **ARCHITECTURAL DEBT** — the code violates a stated rule (e.g. "UI must not touch the DB" but it does).
- **DOCUMENTATION DRIFT** — the doc is simply out of date; the current code is fine, the doc is wrong.
- **UNKNOWN** — no stated intent to compare against, or you could not confirm.

**Do not automatically convert the current structure into the desired architecture.** A dependency that
is widespread today is not thereby proven desirable — a widespread `A → B` may be exactly the debt to
remove. Report the finding and let a human decide (an ADR, an enforcement-ledger row, or a doc fix);
never silently promote "what is" into "what should be."

## `mapme --ownership` — map who owns what
Discover, and keep the three ownership kinds distinct (see the ownership model in `docs/OWNERSHIP.md`):
- **Human-review ownership** — from `.github/CODEOWNERS` when present. It is the review authority; report
  it as-is, validate its patterns where practical, and flag sensitive areas it does NOT cover. Never
  rewrite it, and never read an approval as implementation permission or as completion.
- **Logical component boundaries** — components, their paths, associated tests, public interfaces, shared
  integration points, sensitive components.
- **Unowned / generated / vendored areas** — call them out explicitly.
- **Inferred maintainers** — from git history. Label them **INFERRED**; a Git-history guess is never
  presented as a verified owner. Where you cannot tell, say **UNKNOWN**.

Write `docs/OWNERSHIP.md` **only when the repo has enough real ownership structure to be worth
governing** (a small repo does not need one), using this component format — one block per component
(classifications `OWNED | SHARED | UNOWNED | GENERATED | VENDORED | EXTERNAL | UNKNOWN`):

```md
## Component: Authentication
Classification: OWNED
Risk: HIGH_STAKES
Paths:
- `src/auth/**`
Public interfaces:
- `src/auth/session.ts`
Primary tests:
- `tests/auth/**`
Verified review owner:        # from .github/CODEOWNERS — a fact, cite it
- Platform team
Inferred maintainer:          # from git history — INFERRED, never presented as verified
- UNKNOWN
Shared integration points:
- `src/routes.ts`
Evidence:
- `.github/CODEOWNERS`
Baseline:
- `<commit>`
```

`docs/OWNERSHIP.md` is operational (logical) ownership — kept **distinct** from `.github/CODEOWNERS`
(human-review authority) and from a plan's per-phase execution ownership. None of the three grants
permission to implement or marks work complete.

## `mapme --refresh` — bounded update
Refresh **only** the maps whose inputs actually changed — do not regenerate every map on every phase.
Diff the staleness baseline (below) against HEAD: if only tests moved, refresh `TEST-MAP.md`; if only
dependencies changed, refresh `DEPENDENCIES.md`. A map whose inputs are unchanged is left alone.

## Staleness (record at the bottom of every generated map)
Maps age. Record enough to know when: **baseline commit** (`git rev-parse HEAD`), **generation date**,
the **relevant path patterns**, the **dependency manifests**, the **key entry points**, the **test
configuration**, and — for `--ownership` — a **CODEOWNERS checksum** when present. When a later run sees
those inputs have changed, it reports `POSSIBLY STALE — REVIEW REQUIRED` at the top rather than pretending
the map is current. A stale map supports planning; it never stands in for fresh inspection.

## Architectural friction (all modes — flag, never fix)
Reading the whole system is the only time you see its seams at once. Vocabulary comes from
`module-design`; use those words exactly:
- **Shallow module** — interface nearly as complex as the implementation it hides.
- **Pass-through layer** — forwards calls, adds no abstraction.
- **Leaky seam** — callers must know the internals to use it correctly.
- **Poor locality** — one concept smeared across many files; a change means shotgun surgery.
- **Oversized interface** — many entry points, most of them barely used.
- **Hidden dependency** — reaching into global state, env, or another module's internals.
- **Premature abstraction** — an extension point with exactly one implementation.
- **Excessive fragmentation** — files so small the structure costs more than it saves.
- **Domain-language mismatch** — the code's nouns disagree with `docs/GLOSSARY.md`.
- **Doc drift** — the previous map claims something the code no longer does.

Apply the **deletion test** (defined once, in `module-design`) to anything you suspect is shallow.

Classify each friction finding **Strong** · **Worth exploring** · **Speculative** and report them with the
map. Keep the doc to one page — at most, the Strong ones inform "Where the risk lives". Then stop:
**flagging is the deliverable.** Anything worth acting on becomes a design session (`design-twice`), a
roadmap phase (`milestone`) — never an edit you make
while mapping.

## Guardrails
- Regenerate from code every time; never just reformat the existing doc.
- **Never refactor while mapping.** A map that changed the territory is not a map.
- **Don't silently clobber a hand-authored doc.** If the target doc already exists, diff your regenerated
  version against it and show the user what materially changed (sections added, removed, or altered)
  BEFORE you overwrite — then get their OK, or write to `<doc>.new.md` for them to compare and swap in.
  Regenerating from code is right; replacing edits they made without showing them first is not.
- Maps are **GENERATED VIEW**, not canonical state — they never silently become the spec/roadmap, and they
  never grant permission or complete work.
- One page each. If it's growing past that, link out to detail rather than inlining it.
- Flag anything you found that contradicts the previous map — drift is a signal, tagged CONTRADICTION.

<!-- Adapted from mattpocock/skills (MIT) — https://github.com/mattpocock/skills. Brownfield, ownership,
     refresh modes, evidence classification, stated-vs-actual, and staleness added in jaimitos-os v2.14.0. -->
