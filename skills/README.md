# Personal Skills — general-purpose dev workflow

> Part of **[jaimitos-claude-setup](../README.md)** — see the repo-root README for the full
> picture and how these pair with the jaimitos-os scaffold.

This is the **complete index of all 18 skills** — 10 workflow + 4 engineering + 3 ownership +
the installer meta-skill; 17 install per-project (everything except the installer). (The three
ownership skills have a deeper writeup in the [Ownership](#ownership) section below; the seven
skills marked ◆ are adapted from mattpocock/skills — see [Adapted skills](#adapted-skills).)

These are small (a file or two each), no external dependencies. They encode workflows the base
model doesn't reliably do unprompted. They're largely portable and stack-agnostic — they read
your commands from CLAUDE.md/README rather than hardcoding a stack — but note the **caveat**
below: several assume the jaimitos-os `docs/` layout (SPEC/ROADMAP/STATE), so they're
scaffold-aware, not fully stack-neutral.

| Skill | Category | Fires when you... | What it does |
|---|---|---|---|
| **grill** ◆ | workflow | have a plan/idea to stress-test | Relentless interview, ONE question per turn, each with its own recommendation; facts looked up in the codebase, decisions put to you; hands off to `to-spec` |
| **to-spec** ◆ | workflow | finish a design conversation | Synthesizes the conversation into docs/SPEC.md (no interview): confirms the test seams first, demands a measurable success criterion, then suggests the `roadmap` skill |
| **roadmap** | workflow | have a spec, need phases | Turns docs/SPEC.md into docs/ROADMAP.md — an adaptive number of phases (recommends few ~3–4 / medium ~5–7 / many ~8–12+; never hardcodes a count), each with a measurable "Done when:" and an advisory loopable/supervised tag |
| **milestone** | workflow | add phases / finish a roadmap | Mechanical roadmap lifecycle: add phase(s) mid-project (correct shape, unique heading, position=order), or archive a finished roadmap and start the next batch/milestone ("expand the scope", "the roadmap is done") |
| **adr** | workflow | make a real decision | Writes a terse 4-line ADR to docs/decisions/ |
| **glossary** ◆ | workflow | settle domain vocabulary | Creates/updates docs/GLOSSARY.md (one-line definitions + rejected terms); never writes ADRs; injected capped into every session by the session-start hook |
| **ship-check** | workflow | are about to commit/PR | Runs the project's tests/lint/typecheck + scans for debug leftovers, secrets, missing docs. Verdict: READY / NOT READY (report-only; can't edit) |
| **scope-guard** | workflow | finish a change | Flags out-of-scope edits, drive-by refactors, unexpected deletions. Verdict: IN SCOPE / SCOPE CREEP (report-only; can't edit) |
| **explain-diff** | workflow | want a self-review | Summarizes what changed and, mainly, where it might be wrong (risks, assumptions, untested paths) (report-only; can't edit) |
| **unstick** | workflow | are going in circles | Stops the thrash: restates the goal, names the shared failing assumption, proposes fresh hypotheses + the cheapest next test (a bug to reproduce instead? → `diagnose`) |
| **design-twice** ◆ | engineering | structure a non-trivial module | Two genuinely different designs, trade-off comparison, a choice, and an ADR with the rejected alternative; the planner agent applies it to non-trivial phases |
| **tdd** ◆ | engineering | build test-first | The red→green loop plus what makes tests worth keeping: pre-agreed seams (from SPEC/plan), anti-patterns (the same list the evaluator grades against), mocking rules. The executor's TDD manual |
| **diagnose** ◆ | engineering | hit a hard bug / regression | Diagnosis discipline: build a tight red-capable feedback loop BEFORE hypothesizing (10 ordered ways), minimise, ranked falsifiable hypotheses, instrument, fix + regression test (3+ circular attempts instead? → `unstick`) |
| **merge-conflicts** ◆ | engineering | a merge/rebase stops on conflicts | Resolves from both sides' intent (never inventing behavior), runs the project checks, finishes the merge; covers the /autopilot-parallel worktree-integration case |
| **teach-back** | ownership | finish a non-trivial phase | Claude explains what it built and quizzes you; gaps go to docs/STATE.md "Ownership gaps" |
| **mapme** | ownership | made big structural changes | Refreshes docs/ARCHITECTURE.md from the actual code |
| **quizme** | ownership | want to test understanding | Cold-opens a quiz on the codebase to measure how well you know it |
| **setup-jaimitos-os** | installer | scaffold a new repo | Runs install.sh then fills CLAUDE.md commands + high-stakes paths. **Global/installer-only** — not copied into per-project `.claude/skills/` |

## Design principles
- **Report-only where it matters.** The three review skills (ship-check, scope-guard,
  explain-diff) set `disallowed-tools: Edit, Write, MultiEdit, NotebookEdit` in their frontmatter, so
  the direct file-editing tools are removed — they produce a verdict, not edits. They keep read-only
  shell access (to run `git diff`, tests, lint); scope-guard and explain-diff additionally declare an
  `allowed-tools` surface of read-only git and are instructed to use the shell for inspection only.
  Treat them as review tools held to a report-only contract, not a hard OS sandbox: don't route a
  mutation through them. Fixing is a separate, deliberate step.
- **Portable, with a caveat.** They read commands from your CLAUDE.md/README rather than
  hardcoding a stack, so the same skill works in a Python service and a Next.js app.
  But several (roadmap, and the ownership skills) assume the jaimitos-os `docs/` layout
  (`docs/SPEC.md`, `docs/ROADMAP.md`, `docs/STATE.md`, `docs/decisions/`) — so they're
  **scaffold-aware**, not fully stack-neutral. Drop the scaffold or adjust the paths to use them elsewhere.
- **Small.** One file each — low context cost, easy to read and adapt. Edit them; they're yours.

## Adapted skills
The seven skills marked ◆ (grill, to-spec, glossary, design-twice, tdd, diagnose,
merge-conflicts) are adaptations of skills from
[mattpocock/skills](https://github.com/mattpocock/skills), © Matt Pocock, MIT license — thank
you. They are rewritten, not copied: Matt's originals are tracker-centric (GitHub Issues,
`CONTEXT.md`, a work-queue subsystem of their own); these versions are docs-centric (`docs/SPEC.md`,
`docs/ROADMAP.md`, `docs/decisions/` with the 4-line ADR format, `docs/GLOSSARY.md`) and wire
into this scaffold's pipeline (executor↔tdd, planner↔design-twice, roadmap↔grill,
autopilot-parallel↔merge-conflicts). Each adapted SKILL.md carries a one-line attribution
comment; this paragraph is the full notice.

## Install
**Easiest — the repo installer** copies all 17 portable skills per-project (and
`setup-jaimitos-os` only with `--global-skills`):
```bash
bash /path/to/jaimitos-claude-setup/install.sh .                 # per-project skills
bash /path/to/jaimitos-claude-setup/install.sh . --global-skills # also into ~/.claude/skills
```
**By hand** — everything except the installer one:
```bash
mkdir -p .claude/skills
cp -r grill to-spec roadmap milestone adr glossary ship-check scope-guard explain-diff unstick \
      design-twice tdd diagnose merge-conflicts teach-back mapme quizme .claude/skills/
```
(Swap `.claude/skills` for `~/.claude/skills` to install globally for all projects.)

## Troubleshooting
| Symptom | Fix |
|---|---|
| A skill didn't auto-trigger | Invoke it by name (e.g. `ship-check`), or use a phrase from its `description:`. Auto-trigger is best-effort, not guaranteed. |
| Skill errors "can't find docs/SPEC.md" | You're using a scaffold-aware skill (roadmap/ownership) without the jaimitos-os `docs/` layout. Install the scaffold (`install.sh`) or adjust the skill's paths. |

## Use
They auto-trigger on the phrases in each skill's description, or invoke by name:
```
ship-check                 # before committing
scope-guard                # after a change, before commit
explain-diff               # self-review
unstick                    # when the same fix keeps failing
"log this decision: ..."   # adr
```

## A natural sequence
A clean end-of-task ritual chains three of them:
```
scope-guard   →   explain-diff   →   ship-check
(stayed on task)  (what's risky)     (verified + ready)
```
Run that before any commit and most of what slips through review gets caught first.

## The spec lifecycle (grill → to-spec → roadmap)
`grill` builds `docs/SPEC.md` live (one question per turn, each closed decision written into its
real section; vocabulary → the `glossary` skill in place). `to-spec` **closes** it: empties
`## Open questions`, distills the settled architectural notes into ADRs (`adr` skill), writes the
confirmed `## Test seams` (the `tdd` skill reads them), and flags a pivot if the success criterion
changed. `roadmap` then breaks it into phases.

**Three spec states, but only one is stored.** The frontmatter `status:` carries `draft` /
`grilling` / `ready`, yet **only `grilling` is load-bearing** — it's the one state that isn't
derivable from content (a paused interview and a draft look alike). `roadmap`'s gate *derives*
readiness from content (a measurable criterion + an empty Open questions), never trusting a
`ready` label blindly, so a stale label can't push a bad spec into planning. This is the same
"don't cache state that can lie" rule the manifest sync (§ Keeping a project up to date) follows.

**Roadmaps and milestones are amended, never regenerated.** Once `docs/ROADMAP.md` exists,
`roadmap` and `milestone` edit it in place; ticked (`- [x]`) phases are **immutable** and phase
numbers are **stable IDs** (like tracker issue numbers). The reason is *not* that `tick.sh` diffs
the roadmap against a stored copy — it doesn't; its "left byte-identical" only means it never
half-writes on refusal. The real reasons: a between-phases edit of a ticked phase is caught by
nothing (the evaluator's `phase-base..HEAD` criteria-integrity diff only sees the *active* phase),
so it silently becomes the new baseline and corrupts the audit trail; rewriting a ticked line can
regress a `- [x]` back to `- [ ]`; and `docs/STATE.md`'s "last ticked" pointer must keep resolving
to a heading that still exists verbatim. So `milestone` inserts-and-renumbers only when no ticked
phase sits below the insertion point, and otherwise appends at the end with
`Depends on: … Blocks: …`.

## Ownership
Three skills — **teach-back**, **mapme**, **quizme** — exist so you actually understand code
Claude helped build: enough to debug it, extend it, defend it in an interview, and (for regulated
code) be accountable for it.

**The principle: ownership comes from active recall, not passive reading.** A wall of generated
comments or a giant wiki is something you trust *instead of* understand — the opposite of ownership.
teach-back and quizme make *you* produce the explanation; that's what sticks.

**The ritual that protects ownership** (already wired into the jaimitos-os scaffold — the session-start
hook loads the ARCHITECTURE overview, and the ownership-nudge Stop hook reminds you to ADR + teach-back
after code changes):
```
build a SMALL phase  →  teach-back (explain + quiz)  →  adr (record why)  →  /wrap
...and every week or two:  quizme  (cold open, find the gaps)
```
Smaller phases + teach-back is the whole game: the less Claude builds before you engage, the more you keep.
