# Personal Skills — general-purpose dev workflow

> Part of **[jaimitos-claude-setup](../README.md)** — see the repo-root README for the full
> picture and how these pair with the jaimitos-os scaffold.

This is the **complete index of all 11 skills** — 7 workflow + 3 ownership + the installer
meta-skill. (The three ownership skills have a deeper writeup in the [Ownership](#ownership) section below.)

These are single-file each, no external dependencies. They encode workflows the base model
doesn't reliably do unprompted. They're largely portable and stack-agnostic — they read
your commands from CLAUDE.md/README rather than hardcoding a stack — but note the **caveat**
below: several assume the jaimitos-os `docs/` layout (SPEC/ROADMAP/STATE), so they're
scaffold-aware, not fully stack-neutral.

| Skill | Category | Fires when you... | What it does |
|---|---|---|---|
| **roadmap** | workflow | have a spec, need phases | Turns docs/SPEC.md into docs/ROADMAP.md — an adaptive number of phases (recommends few ~3–4 / medium ~5–7 / many ~8–12+; never hardcodes a count), each with a measurable "Done when:" and an advisory loopable/supervised tag |
| **milestone** | workflow | add phases / finish a roadmap | Mechanical roadmap lifecycle: add phase(s) mid-project (correct shape, unique heading, position=order), or archive a finished roadmap and start the next batch/milestone ("expand the scope", "the roadmap is done") |
| **adr** | workflow | make a real decision | Writes a terse 4-line ADR to docs/decisions/ |
| **ship-check** | workflow | are about to commit/PR | Runs the project's tests/lint/typecheck + scans for debug leftovers, secrets, missing docs. Verdict: READY / NOT READY (report-only; can't edit) |
| **scope-guard** | workflow | finish a change | Flags out-of-scope edits, drive-by refactors, unexpected deletions. Verdict: IN SCOPE / SCOPE CREEP (report-only; can't edit) |
| **explain-diff** | workflow | want a self-review | Summarizes what changed and, mainly, where it might be wrong (risks, assumptions, untested paths) (report-only; can't edit) |
| **unstick** | workflow | are going in circles | Stops the thrash: restates the goal, names the shared failing assumption, proposes fresh hypotheses + the cheapest next test |
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

## Install
**Easiest — the repo installer** copies all 10 portable skills per-project (and
`setup-jaimitos-os` only with `--global-skills`):
```bash
bash /path/to/jaimitos-claude-setup/install.sh .                 # per-project skills
bash /path/to/jaimitos-claude-setup/install.sh . --global-skills # also into ~/.claude/skills
```
**By hand** — the workflow + ownership skills (everything except the installer one):
```bash
mkdir -p .claude/skills
cp -r roadmap milestone adr ship-check scope-guard explain-diff unstick teach-back mapme quizme .claude/skills/
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
