# Contributing

Thanks for considering a contribution. This is a small, opinionated, MIT-licensed project —
PRs and issues are welcome. Please match the existing voice (direct, practical, honest about
what enforces vs what merely advises) and keep changes lean.

## Project layout — know which part you're touching

There are three distinct things in this repo. Edits go to different places:

- **The toolkit repo itself** — `README.md`, `CHANGELOG.md`, `VERSION`, `install.sh`,
  and `.github/`. These document and ship the toolkit. **They are never copied into a
  target project.**
- **The `jaimitos-os/` scaffold** — the files that *do* get installed into a user's repo:
  `CLAUDE.md`, `SCAFFOLD.md`, `docs/`, `scripts/`, `.claude/` (hooks, commands, the
  `evaluator` agent, `rules/high-stakes.md`), and the opt-in `.github/workflows/jaimitos-os-ci.yml`.
- **`skills/`** — the 15 portable skills, each its own dir. `install.sh` copies them into a
  target's `.claude/skills/` (all except `setup-jaimitos-os`, which is global-only). Seven are
  adaptations of mattpocock/skills (MIT) — see `skills/README.md` § Adapted skills.

## The "ship by directory" boundary — don't break it

`install.sh` decides what ships from the scaffold by **directory**, not by a generated file list.
So:

- **Put toolkit-only docs at the repo root, not under `jaimitos-os/`.** A new doc dropped
  inside `jaimitos-os/` will start shipping into every install — usually not what you want.
- Anything a user's project genuinely needs goes in the scaffold proper. The scaffold's own
  note ships as `SCAFFOLD.md` (named so it can't clobber a user's `README.md`).
- The install **smoke test** (`.github/scripts/install-smoke.sh`) asserts no tool-doc
  pollution, no README clobber, idempotency, and `.gitignore` merge — keep it green.

## Adding a skill

A skill is a directory under `skills/<name>/` with a `SKILL.md`; support files (extra `.md`s, a
`scripts/` subdir) are optional. To add one:

1. **Frontmatter** exactly like the existing skills: `name:`, and a `description:` whose text
   contains the trigger phrases (that's what auto-invocation matches on). Report-only skills add
   `disallowed-tools: Edit, Write, NotebookEdit` (see `scope-guard` for the pattern,
   including `allowed-tools` for a read-only git surface). Keep SKILL.md ~30–80 lines.
2. **Register it everywhere the manifest lives** (all three, or CI catches you):
   `skills/README.md`'s table + count line, `REQUIRED_SKILLS` in `jaimitos-os/scripts/doctor.sh`,
   and the shipped-skill loop in `.github/scripts/install-smoke.sh`.
3. If it's adapted from someone else's work, add the one-line attribution comment at the bottom
   of SKILL.md and extend the "Adapted skills" notice in `skills/README.md`.
4. Artifacts go under `docs/` (SPEC/ROADMAP/STATE/decisions/GLOSSARY) — never introduce a second
   work queue or an external-tracker dependency.

## How synced files change (the manifest contract)

Every toolkit-owned file you edit ships to users through `scripts/sync.sh`, driven by
`.claude/.jaimitos-manifest` (sha256 of each file as shipped, written by `install.sh`). What that
means for a change:

- **Editing a shipped file** is cheap for users who never touched their copy: it lands in their
  next sync batch. Users who customized that file get a "manual merge required" diff instead —
  so keep user-tunable values (like `HIGH_STAKES_RE`) isolated on their own line, and prefer
  adding a NEW file over making an existing one more customization-prone.
- **Renaming/deleting a shipped file** leaves stale manifest entries pointing at the old path on
  users' machines; the old file shows up as "modified or deleted locally" forever. Avoid renames;
  when unavoidable, note the migration in the CHANGELOG.
- **Never list project-owned files** (docs/**, CLAUDE.md, SCAFFOLD.md, .gitignore, the
  high-stakes allowlist) in the manifest — the `project_owned()` case patterns in `install.sh`
  and `scripts/sync.sh` must stay identical.

## Local dev & running the checks

Shell-only project; no build step. Before opening a PR, run the checks CI runs plus the
behavior tests:

```bash
# Syntax — what CI enforces (every script, hook, and the installer)
for f in jaimitos-os/scripts/*.sh jaimitos-os/.claude/hooks/*.sh; do bash -n "$f"; done
bash -n install.sh
bash -n .github/scripts/install-smoke.sh
jq empty jaimitos-os/.claude/settings.json

# Install smoke test (CI runs this too)
bash .github/scripts/install-smoke.sh

# Behavior tests — run from inside jaimitos-os/
cd jaimitos-os
bash scripts/doctor.sh                 # health check
bash scripts/test-hooks.sh             # hook smoke tests (incl. secret-scan)
bash scripts/test-high-stakes.sh       # high-stakes path matcher
bash scripts/test-secret-scan.sh       # secret-scan filename + content regexes
bash scripts/test-autopilot-gates.sh   # autopilot gate logic
```

CI (`.github/workflows/ci.yml`) runs `bash -n` + **`shellcheck`** + **`actionlint`** over all
scaffold scripts/hooks/libs and the workflows, validates `settings.json`, runs the three
behavioral guard tests (`test-high-stakes.sh`, `test-secret-scan.sh`, `test-autopilot-gates.sh`),
and runs the install smoke test. **Run them locally before you push** anyway — especially for any
change to hooks, the secret-scan, the high-stakes gate, or `autopilot.sh`.

## Shell style

- Keep shell **POSIX-careful** and pass **`shellcheck -S warning`** clean (`shellcheck -S warning
  -e SC1090,SC1091 install.sh jaimitos-os/scripts/*.sh jaimitos-os/.claude/hooks/*.sh
  jaimitos-os/.claude/lib/*.sh`). Quote expansions, prefer `[ ]` tests, fail closed.
- Hooks and guards must **fail closed**: when in doubt, block/stop rather than wave a run
  through. That's the whole point of the deterministic layer.

## Safety changes need a matching test

Any change to enforcement behavior — the secret-scan, the high-stakes gate, verdict parsing,
the kill-switch, the evaluator-change cleanup, or `permissions.deny` — **must come with a test**
(extend the relevant `test-*.sh`) that fails before your change and passes after. Don't weaken
a guard silently; if you're relaxing one on purpose, say so in the PR and the CHANGELOG.

## Commit & PR conventions

- Small, single-purpose commits with imperative subjects (look at `git log` for the style).
- One logical change per PR. Describe **what** changed and **why**, and note any change to
  what ships into targets or to safety behavior.
- Update `CHANGELOG.md` (the `[Unreleased]`/next-version section) for anything user-visible,
  and bump `VERSION` only when cutting a release.
- Don't overstate guarantees in docs — match the honest tone in `SECURITY.md` and the README's
  "Enforcement reality" section.

By contributing you agree your work is licensed under the repo's [MIT License](LICENSE).
