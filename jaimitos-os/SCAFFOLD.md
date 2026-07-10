# Jaimitos OS — the scaffold (SCAFFOLD.md)

> This file ships **with the scaffold** into your project. It is named `SCAFFOLD.md`
> (not `README.md`) on purpose, so it can never clobber or be mistaken for your own
> project's README. Delete it once you've read it — your repo's README is yours.

This is the self-contained quick-start for the lean Claude Code setup that was
installed into this repo. The full toolkit README is **not** copied into your
project (so it doesn't pollute it); read it on GitHub:

- <https://github.com/jaimeberdejo/jaimitos-claude-setup>

## What got installed here
- **CLAUDE.md** — lean constitution (edit the `<...>` placeholders). Includes the Ownership section.
- **.claude/** — hooks, commands (`/phase` `/autopilot` `/wrap` `/resume` `/models`), the four
  `/phase`-stage subagents (`researcher`, `planner`, `executor`, `evaluator`), the shared
  guard libs (`_secret-scan.sh`, `_high-stakes.sh`, `_test-cmd.sh`), and
  `.claude/.jaimitos-manifest` (the sha256 baseline `scripts/sync.sh` uses to update the
  scaffold without clobbering your customizations).
- **.claude/skills/** — 15 skills: think→spec→plan (grill, to-spec, roadmap, milestone, adr,
  glossary), engineering (design-twice, tdd, diagnose, merge-conflicts), review (scope-guard,
  unstick), ownership (teach-back, mapme, quizme). Catalog:
  `skills/README.md` in the toolkit repo.
- **docs/** — SPEC/ROADMAP/STATE/ARCHITECTURE templates + `decisions/` for ADRs.
- **scripts/** — `autopilot.sh` (guarded autonomous loop), `tick.sh` (the completion gate),
  `sync.sh` (manifest-driven updater), `doctor.sh`, `test-hooks.sh` and the guard-test suites.
- **sandbox/** — `Dockerfile.autopilot` + `run-autopilot-sandboxed.sh`, the supported way to run
  the headless loop unattended (no-credentials container; only the repo mounted, only
  `ANTHROPIC_API_KEY` passed).

Later toolkit fixes? `bash scripts/sync.sh --toolkit <path-to-your-local-jaimitos-os-checkout> --dry-run`
previews the plan; unchanged files batch-update, anything you modified is never overwritten
(you get the diff instead). Scaffolded before v2.5.0? Run once with `--adopt-manifest` first.

CI is **opt-in**: re-run the installer with `--with-ci` to also drop a
`.github/workflows/jaimitos-os-ci.yml` into your project.

## Quick start
The two required steps are `chmod` then `doctor.sh`:

    chmod +x .claude/hooks/*.sh scripts/*.sh
    # NOTE: don't blanket-set CLAUDE_CODE_SUBAGENT_MODEL=haiku — it OVERRIDES every /phase
    # stage's frontmatter model: (set via scripts/models.sh / /models), including the
    # evaluator's, and downgrades your grader. See the README setup notes.
    # ENABLE_TOOL_SEARCH is unverified against current docs — confirm before relying on it.
    bash scripts/doctor.sh        # verify tooling, scaffold, settings, hooks
    bash scripts/test-hooks.sh    # smoke-test the hooks

Existing project? Fill in CLAUDE.md's commands now. Starting from scratch? Skip that — describe
the project → `docs/SPEC.md` first, then run the `roadmap` skill → `docs/ROADMAP.md`; it fills
CLAUDE.md's commands from the SPEC as it runs.

### Optional companions (not required)
Handy extras, not part of setup — skip them and the stack still works. (Grilling, TDD discipline,
bug diagnosis, and merge-conflict skills are BUNDLED since v2.5.0 — adapted from
mattpocock/skills, MIT — so you no longer need an external pack for those.)

    npx skills@latest add mattpocock/skills          # Matt's originals (tracker-centric), if you want them too
    npm i -g @fission-ai/openspec && openspec init    # spec-of-record lifecycle, if you want it

## Safety note
`.claude/settings.json` ships with `permissions.deny` rules so Claude can't read
`.env`/secrets/keys (`.gitignore` alone does NOT prevent reads). Extend them per project.
The autopilot loop has preflight checks, STRICT evaluator-verdict parsing, a high-stakes
gate, a shared secret-scan before any commit/push, and a per-phase thrash cap — run
`doctor.sh` green before any unattended run. Note these are a deterministic best-effort
layer, **not** an OS sandbox; for truly unattended runs use a no-creds/sandboxed
environment (see the README's "Enforcement reality" section).
