---
name: setup-lean-stack
description: Installs the lean-stack scaffold into the current project and customizes it for the detected tech stack. Use when starting the lean-stack in a new repo — "set up the lean stack here", "scaffold this project", "install my claude setup". Runs the deterministic install.sh for the copy, then fills CLAUDE.md commands and high-stakes paths.
---

# Set up lean-stack

The COPY is deterministic — do not recreate files by hand. The CUSTOMIZE step is where
you (the model) add value: detect the stack and fill in what a blind copy can't.

## Step 1 — Copy the scaffold (deterministic; never hand-write the files)
Find the installer (the cloned `my-claude-code-setup` repo) and run it against the current
directory. Ask the user for the path if you can't find it:
```bash
bash /path/to/my-claude-code-setup/install.sh .
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
If you genuinely can't tell, ask — don't invent commands.

## Step 3 — Fill CLAUDE.md
Replace the `<...>` placeholders in `CLAUDE.md` with the real Test / Typecheck / Lint /
Run commands, and `<NAME>` with the project name. Keep CLAUDE.md lean (under ~200 lines).

## Step 4 — Point the high-stakes rule at real paths
Edit `.claude/rules/high-stakes.md` `paths:` to match THIS project's sensitive directories
(auth, migrations, payments, deletes, external-effect code). Remove the placeholder globs
that don't exist here. If the project has no high-stakes surface, say so and leave a minimal rule.

## Step 5 — Stub the spec and verify
- If `docs/SPEC.md` is still the template, offer to run the grilling/`roadmap` flow to fill it.
- Run `bash scripts/doctor.sh` and report the result. If not a git repo yet, suggest `git init`.
- Run `bash scripts/test-hooks.sh` to confirm the hooks work.

## Step 6 — Report
Tell the user: what commands you wired into CLAUDE.md, which high-stakes paths you set,
the doctor result, and the single next action (usually: write the SPEC, then run `roadmap`).

## Guardrails
- Deterministic copy via install.sh; intelligent customization by you. Never blur the two.
- Don't clobber an existing customized CLAUDE.md/docs without the user's say-so (install.sh
  skips existing files unless `--force`).
- Use the project's REAL commands (read package.json scripts / config), never placeholders.
