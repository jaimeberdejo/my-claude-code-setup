---
name: skill-creator
description: Maintainer-only. Decides whether a new skill in this toolkit is justified — then refuses, or generates it. Invoke by name.
disable-model-invocation: true
---

# Skill creator

Maintainer tooling for **this repo**. It exceeds the 30–80 line house range because it carries the
refusal criteria and the required report — a deliberate exception, for the creator skills only.

## Why it lives in repo-root `.claude/skills/`
`install.sh` reads exactly two source roots — `$SRC/jaimitos-os` and `$SRC/skills` (install.sh:31-32).
A repo-root `.claude/skills/` is reached by **no copy loop, no `--global-skills`, no `sync.sh`**: it is
*structurally* unshippable. Claude Code still auto-discovers it when a maintainer works in this repo.
**That is the safety guarantee** — a skill that creates skills must not be able to reach a user's
install. Do not move this directory into `skills/`; that ships it. `disable-model-invocation: true` is
the other half: no description in always-loaded context, no auto-fire, invoked by name only.

## Prefer improving an existing capability over creating one
Preference order, strongest first: **improve an existing component** → **deterministic script** (if a
regex or a test can check it, it is not a judgement call) → **rule or reference file** → **new skill** →
**new agent** (not this skill's business — that is `agent-creator`'s).

**The default answer is no new skill.**

## Required pre-creation analysis
Answer **all** of these before writing a line:
- What exact user problem does this solve? Is it recurring, or did it happen once?
- Is it already covered by an existing skill / command / agent / script / rule / plain doc?
- Should the existing capability be **improved** instead?
- User-invoked, model-invoked, or maintainer-only? Does it mutate state?
- Which artifact does it own — if any?
- Could its trigger collide with another model-invoked skill?
- Could it create a **second authority** over something already owned?
- Install scope: shipped (`skills/`) or maintainer-only (repo-root `.claude/skills/`)?
- What is its context cost? What evidence would show it is actually useful?

## Refuse when
**A refusal is a SUCCESS, not a failure.** Say so plainly and stop. Refuse when:
- An existing skill can absorb the behaviour · the responsibility is too broad · it duplicates a workflow.
- It would create a **second planner or executor**.
- It would create a **second authority** for ROADMAP / STATE / SPEC / GLOSSARY / ADRs / evaluation / completion.
- A command would be more appropriate · a deterministic script would be safer · a compact rule would suffice.
- It is only static documentation · it has no checkable output.
- Its trigger overlaps excessively with an existing model-invoked skill.
- It would add significant always-loaded context.
- **It exists only because an upstream project has it.**

## Invocation decision
- **Model-invoked** pays permanent context: its `name` + `description` sit in the window **every turn**.
  In exchange the agent reaches it autonomously, and other skills can reach it. The body loads only on
  invocation; a linked reference file loads only when its pointer fires.
- **User-invoked** (`disable-model-invocation: true`) costs **zero** always-loaded context — the
  description is stripped from the model's reach and becomes human-facing. It spends the maintainer's
  memory instead: *you* are the index.

**User-invoked is the DEFAULT. Model-invocation carries the burden of proof**, and the proof is not
an argument — it is a list.

### The consumer enumeration (mandatory; do this before you choose)
State plainly *who* is supposed to reach this skill, and *how*. Then check:

```bash
grep -rn "<skill-name>" skills/ jaimitos-os/.claude/
```

For **every** consumer, answer one question: **does it reach the skill autonomously, or does it name
the skill explicitly** (by path, or by invoking it by name)? A consumer that names it explicitly reads
the file directly and needs **no** description in the window.

**If no consumer relies on autonomous reach, the skill is user-invoked. Full stop** — regardless of
how natural a trigger phrase you can imagine for it. An imagined user question is not a consumer.

> This check exists because v2.10.0 shipped `module-design` model-invoked on exactly that reasoning —
> "five components must reach it" — when all five named it by path and none needed auto-fire. The
> independent review caught it and it was reverted in v2.11.0. The argument felt right; the grep would
> have settled it in ten seconds. **Run the grep.**

Beware the circular defence: *"a user might type a bare question about X, and only this skill answers
it."* A user who can phrase the question in the skill's own vocabulary has already read it. A user who
cannot phrases it in ordinary words — which fire some **other** skill's trigger. Check whether that
other skill already covers the case before you pay a description for it, every turn, forever.

## Description rules
- **Front-load the trigger** — the description does its invocation work in its first words.
- **One trigger per genuinely distinct branch.** Synonyms restating one branch are duplication; collapse them.
- **Never summarize the skill's workflow in the description.** Observed failure: a description that
  summarized the process became a shortcut the agent took **instead of** reading the body — upstream
  `writing-skills` records an agent running one review where the body specified two. The description
  says *when*; the body says *what*.
- **Keep it short.** Every byte is loaded every turn.

## Progressive disclosure
Steps and short reference stay **inline**. Heavy reference goes into a linked sibling `.md` reached by a
pointer, loaded only when the pointer fires. Never force-load.

## Required output when justified
Skill dir · `SKILL.md` with valid **current** frontmatter — only real fields (`name`, `description`,
`allowed-tools`, `disallowed-tools`, `disable-model-invocation`, `model`, `context`, `agent`, `paths`,
`argument-hint`; there is **no** `license` field and **no** `metadata` field — do not invent one) ·
invocation classification · allowed and prohibited tools · **explicit authority declaration** (which
artifact it owns — **"none" is a valid and common answer**) · inputs · outputs · failure behaviour ·
completion criteria · progressive-disclosure refs · catalog entry in `skills/README.md` · install scope ·
attribution + provenance if adapted · deterministic static tests.

## Prohibited
You may **not**: add the skill to always-loaded context automatically · create multiple skills when one
suffices · copy an upstream skill without adaptation **and** attribution · install globally without
explicit instruction · tick a phase · edit completion evidence or grades · modify completed roadmap
history · declare the generated skill production-ready without tests **and** a dogfood run · commit,
push, tag, or publish.

## Honesty
Static validation checks **shape, not judgement**. The linter proves frontmatter validity, naming,
catalog registration and context cost. It **cannot** prove the skill was justified. A skill can pass
every check and still be one that should never have existed.

## Before declaring done
Read **[checks.md](checks.md)** and run every check in it.

## Skill creation report
Emit this at the end, verbatim:
```md
### Skill creation report
- Problem solved:
- Why a new skill is justified:
- Existing overlap reviewed:
- Rejected alternatives:
- Invocation mode:                <!-- and the CONSUMER ENUMERATION that decided it -->
- Artifact authority:
- Tools:
- Files created or changed:
- Catalog/profile placement:
- Context cost:                   <!-- this skill's bytes AND the new always-loaded total -->
- Tests:
- Dogfood:
- Independent review:             <!-- WHO reviewed it — and it may not be you -->
- Provenance:
- Remaining risks:
```

**`Independent review:` may not name you.** A component's author cannot clear it — not "reviewed my
own work carefully", not a subagent you briefed and then graded. If nobody independent has looked at
it, write `NONE — not cleared for release` and mean it.

That field exists because it was skipped. v2.10.0's review of `module-design` was performed by the
same person who orchestrated its creation, and it approved a decision a genuinely independent
reviewer overturned one release later. The self-review found nothing because self-reviews rarely do.

<!-- Adapted from obra/superpowers (MIT) — https://github.com/obra/superpowers -->
<!-- Adapted from mattpocock/skills (MIT) — https://github.com/mattpocock/skills -->
