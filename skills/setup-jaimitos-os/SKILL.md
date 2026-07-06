---
name: setup-jaimitos-os
description: Installs the jaimitos-os scaffold into the current project and customizes it for the detected tech stack. Use when starting jaimitos-os in a new repo — "set up jaimitos-os here", "scaffold this project", "install my claude setup". Runs the deterministic install.sh for the copy, then fills CLAUDE.md commands and high-stakes paths.
---

# Set up jaimitos-os

The COPY is deterministic — do not recreate files by hand. The CUSTOMIZE step is where
you (the model) add value: detect the stack and fill in what a blind copy can't.

## Step 1 — Copy the scaffold (deterministic; never hand-write the files)
Find the installer (the cloned `jaimitos-claude-setup` repo) and run it against the current
directory. Ask the user for the path if you can't find it:
```bash
bash /path/to/jaimitos-claude-setup/install.sh .
```
If files already exist and the user wants them replaced, re-run with `--force`. Do NOT
recreate any scaffold file by writing it out — if install.sh isn't reachable, ask the user
to clone/locate the repo rather than regenerating files from memory (that causes drift).

## Step 2 — Detect the stack
Look at the repo to determine the real commands:
- Python: `pyproject.toml` / `requirements.txt` / `pytest.ini` → likely `pytest -q`,
  `mypy .` / `ruff check .`, `ruff format .`.
- Node/TS: `package.json` → read its `scripts` for the actual `test`, `typecheck`/`tsc`,
  `lint`, `dev`/`build` names. Use what's really there, not guesses.
- Other stacks: find the test runner, linter, type checker, and run command from config files.

**Branch on what you find:**
- **Stack detected (brownfield — an existing project)** → continue to Step 3 now; you have
  everything you need to fill CLAUDE.md immediately.
- **No stack detected (greenfield — an empty/near-empty project)** → there's nothing real to
  fill yet. **Skip Step 3 for now.** CLAUDE.md's placeholders will be filled automatically by
  the `roadmap` skill once `docs/SPEC.md` exists and pins the stack — don't guess commands
  here, and don't ask the user to remember to fill them later by hand. Go straight to Step 5.

## Step 3 — Fill CLAUDE.md (brownfield only — skip if greenfield, see Step 2)
Replace the `<...>` placeholders in `CLAUDE.md` with the real Test / Typecheck / Lint /
Run commands, and `<NAME>` with the project name. Keep CLAUDE.md lean (under ~200 lines).

## Step 4 — Point the high-stakes gate at real paths (brownfield only — skip if greenfield, see Step 2)
The high-stakes gate has two pieces and you MUST update the enforced one:

1. **`.claude/lib/_high-stakes.sh` → `HIGH_STAKES_RE`** — this is what `scripts/autopilot.sh`
   actually enforces (it refuses to tick/commit/push, and never pushes, a phase whose diff
   touches a matching path). Edit this regex to THIS project's sensitive paths. **If you only
   edit the rule file below and not this regex, the enforced gate stays at its shipped default
   and silently won't fire for your real directories.**
2. **`.claude/rules/high-stakes.md` `paths:`** — the human-readable mirror. Update it to match,
   and remove placeholder globs that don't exist here.

Keep the two in sync. If the project genuinely has no high-stakes surface, say so and leave a
minimal regex/rule. After editing, `scripts/doctor.sh` will confirm the regex is no longer the
shipped default.

## Step 5 — Configure per-stage models (optional; applies to both brownfield and greenfield)
`/phase` delegates its four stages (research, plan, execute, verify) to four subagents —
`.claude/agents/researcher.md`, `planner.md`, `executor.md`, `evaluator.md`. By default the
first three inherit whatever model is running the session, and `evaluator.md` ships pinned to
`sonnet`. Ask the user once, briefly: "Do you want to pin any of research / plan / execute /
verify to a specific model, or leave the defaults?" If they name any, run
`bash scripts/models.sh <role>=<value> ...` (the same deterministic script `/models` wraps —
never edit the frontmatter by hand). If they say "leave it," do nothing and move on without
asking again during this setup — `/models` (or `scripts/models.sh` directly) is always
available later.

## Step 6 — Stub the spec and verify
- If `docs/SPEC.md` is still the template, offer to run the grilling/`roadmap` flow to fill it.
- Run `bash scripts/doctor.sh` and report the result. If not a git repo yet, suggest `git init`.
- Run `bash scripts/test-hooks.sh` to confirm the hooks work.

## Step 7 — Report
- **Brownfield:** tell the user what commands you wired into CLAUDE.md, which high-stakes
  paths you set, what (if anything) you configured in Step 5, the doctor result, and the single
  next action (usually: write the SPEC, then run `roadmap`).
- **Greenfield:** tell the user CLAUDE.md and the high-stakes gate are intentionally left as
  shipped defaults for now — they'll be filled automatically (CLAUDE.md) or flagged as a
  reminder (high-stakes paths) by the `roadmap` skill once `docs/SPEC.md` exists. Mention what
  (if anything) you configured in Step 5. Report the doctor result (expect its `!` warnings
  about placeholders — that's expected pre-SPEC, not a problem) and the single next action:
  write the SPEC (grill first if useful), then run `roadmap`.

## Guardrails
- Deterministic copy via install.sh; intelligent customization by you. Never blur the two.
- Don't clobber an existing customized CLAUDE.md/docs without the user's say-so (install.sh
  skips existing files unless `--force`).
- Use the project's REAL commands (read package.json scripts / config), never placeholders.
