# Contributing

Thanks for considering a contribution. This is a small, opinionated, MIT-licensed project —
PRs and issues are welcome. Please match the existing voice (direct, practical, honest about
what enforces vs what merely advises) and keep changes lean.

## Project layout — know which part you're touching

There are three distinct things in this repo. Edits go to different places:

- **The toolkit repo itself** — `README.md`, `CHANGELOG.md`, `VERSION`, `install.sh`,
  and `.github/`. These document and ship the toolkit. **They are never copied into a
  target project.**
- **The `lean-stack/` scaffold** — the files that *do* get installed into a user's repo:
  `CLAUDE.md`, `SCAFFOLD.md`, `docs/`, `scripts/`, `.claude/` (hooks, commands, the
  `evaluator` agent, `rules/high-stakes.md`), and the opt-in `.github/workflows/lean-stack-ci.yml`.
- **`skills/`** — the 10 portable skills, each its own dir. `install.sh` copies them into a
  target's `.claude/skills/` (all except `setup-lean-stack`, which is global-only).

## The "ship by directory" boundary — don't break it

`install.sh` decides what ships from the scaffold by **directory**, not by a generated file list.
So:

- **Put toolkit-only docs at the repo root, not under `lean-stack/`.** A new doc dropped
  inside `lean-stack/` will start shipping into every install — usually not what you want.
- Anything a user's project genuinely needs goes in the scaffold proper. The scaffold's own
  note ships as `SCAFFOLD.md` (named so it can't clobber a user's `README.md`).
- The install **smoke test** (`.github/scripts/install-smoke.sh`) asserts no tool-doc
  pollution, no README clobber, idempotency, and `.gitignore` merge — keep it green.

## Local dev & running the checks

Shell-only project; no build step. Before opening a PR, run the checks CI runs plus the
behavior tests:

```bash
# Syntax — what CI enforces (every script, hook, and the installer)
for f in lean-stack/scripts/*.sh lean-stack/.claude/hooks/*.sh; do bash -n "$f"; done
bash -n install.sh
bash -n .github/scripts/install-smoke.sh
jq empty lean-stack/.claude/settings.json

# Install smoke test (CI runs this too)
bash .github/scripts/install-smoke.sh

# Behavior tests — run from inside lean-stack/
cd lean-stack
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
  -e SC1090,SC1091 install.sh lean-stack/scripts/*.sh lean-stack/.claude/hooks/*.sh
  lean-stack/.claude/lib/*.sh`). Quote expansions, prefer `[ ]` tests, fail closed.
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
