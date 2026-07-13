# skill-creator — mechanical checks

The **shape** checks. Run every one before declaring a skill done. Passing them all proves nothing
about whether the skill was justified — that is the refusal analysis in `SKILL.md`, and no check here
can stand in for it.

## Naming and collisions

- **Unique skill name** — no other directory under `skills/` or repo-root `.claude/skills/` uses it.
- **No collision with a command name** in `jaimitos-os/.claude/commands/` (`autopilot`, `models`,
  `phase`, `resume`, `wrap`). A name that reads like a slash command belongs to a command, not a skill.
- **No collision with an agent name** in `jaimitos-os/.claude/agents/` (`researcher`, `planner`,
  `executor`, `evaluator`).
- **`name:` equals the directory name**, exactly. Letters, numbers, hyphens only.

## Frontmatter

- **Only real fields.** `name`, `description`, `allowed-tools`, `disallowed-tools`,
  `disable-model-invocation`, `model`, `context`, `agent`, `paths`, `argument-hint`. There is **no**
  `license` field and **no** `metadata` field — an invented field is a silent no-op, not an error.
- **Description non-empty, specific, appropriately sized.** Model-invoked: front-loaded trigger
  phrases, no workflow summary. User-invoked / maintainer-only: one human-facing line.
- **Report-only skills** carry `disallowed-tools: Edit, Write, NotebookEdit` (pattern: `skills/scope-guard/SKILL.md`).
- **Maintainer-only skills** carry `disable-model-invocation: true`.

## Authority

- **No artifact-authority conflict.** ROADMAP, STATE, SPEC, GLOSSARY, ADRs, evaluation and completion
  each already have exactly one owner. A second writer is a refusal, not a check to negotiate.
- The skill's declared authority is stated explicitly in SKILL.md. **"None" is valid and common.**

## Registration

A shipped skill must be registered in **all three** manifests, or CI fails:

- `skills/README.md` — catalog row **and** the count line in the intro.
- `REQUIRED_SKILLS` in `jaimitos-os/scripts/doctor.sh` (line ~70).
- The shipped-skill loop in `.github/scripts/install-smoke.sh` (lines ~66-78).

If adapted from someone else's work: the one-line attribution comment at the bottom of SKILL.md
**and** an extension of the "Adapted skills" notice in `skills/README.md`.

## Install scope

- **Shipped skills live in `skills/<name>/`.** `install.sh` copies them into each project's
  `.claude/skills/`.
- **Maintainer-only skills live in repo-root `.claude/skills/<name>/`** — outside both of install.sh's
  source roots (`$SRC/jaimitos-os`, `$SRC/skills`; install.sh:31-32), so no install, sync, or
  `--global-skills` path can reach them. A maintainer-only skill must appear in **no** shipped list:
  not `skills/README.md`'s table, not `REQUIRED_SKILLS`, not `install-smoke.sh`. If it appears in one,
  it is in the wrong place or the wrong list — fix it before shipping.
- `setup-jaimitos-os` is the third case: it lives in `skills/` but is excluded from the per-project
  copy loop (install.sh:170) and ships only with `--global-skills`.

## Content

- **Measured context cost — this skill AND the total.** Model-invoked: count the bytes of `name` +
  `description`; that is what loads every turn. User-invoked: zero. Then report the **new
  always-loaded total**, not just the marginal cost — a per-skill number always looks affordable,
  which is how a budget dies by a thousand affordable increments:
  ```bash
  bash jaimitos-os/scripts/test-skills.sh | grep 'description budget'
  ```
- **No duplicate instructions** — one meaning, one home. A rule restated in two skills is a
  maintenance bug and inflates its apparent rank. If a component genuinely must restate a rule to
  stand alone (the `evaluator` restates the deletion test because a gate-checked grading contract
  cannot depend on reading a skill file), that exception is **documented at the canonical home**,
  not left to look like an accident.
- **No stale or no-op prose.** Test each sentence in isolation: does it change behaviour versus the
  model's default? If not, delete the sentence — do not trim words from it.
- SKILL.md within the house range of ~30–80 lines, unless it is maintainer tooling that says why it
  is longer.

## The deterministic gates

These police the result. Run all three:

```bash
bash jaimitos-os/scripts/test-skills.sh      # skill shape, frontmatter, catalog registration
bash jaimitos-os/scripts/run-guard-tests.sh  # the guard/hook suite
bash .github/scripts/install-smoke.sh        # post-install manifest gate (what actually ships)
```

A green run proves the skill is well-formed and correctly registered. It does not prove it should
exist.
