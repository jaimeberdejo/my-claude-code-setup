# my-claude-code-setup

A lean, **project-neutral operating system for Claude Code**: an evidence-gated, auto-ticked
roadmap with auto-written state, deterministic hooks, an independent grader, two autonomous
loops (one you can watch, one for overnight), path-scoped rules, and a pack of portable
skills — at a fraction of the token cost of heavyweight planning frameworks.

It reproduces what big multi-agent frameworks automate — spec, roadmap, persistent state,
decision log, phase execution, independent verification — with **one context at a time, no
research fan-out**, so you keep full visibility and a 1-experienced-dev token budget.

> **The one idea:** `CLAUDE.md` advises · **hooks enforce** · **docs hold knowledge**.
> Never ask one to do another's job. And **match ceremony to stakes**: tiny/reversible →
> just prompt; medium → supervised; big/mechanical/low-stakes → autopilot; high-stakes →
> human-on-the-loop.

---

## Quickstart

```bash
git clone https://github.com/jaimeberdejo/my-claude-code-setup.git ~/my-claude-code-setup
cd /path/to/your-project
git init                                           # first, so the post-install doctor is clean
bash ~/my-claude-code-setup/install.sh .           # drops the scaffold + skills in (auto-runs doctor)
# then: fill CLAUDE.md placeholders + point HIGH_STAKES_RE in .claude/lib/_high-stakes.sh at your paths
```

Then: edit `CLAUDE.md` (your test/lint/run commands) → point `HIGH_STAKES_RE` in
`.claude/lib/_high-stakes.sh` at your sensitive paths → write `docs/SPEC.md` → run the
`roadmap` skill → build with `/phase`. New to it all? Work through `PRACTICE-PROJECT.md` first.

> **Two parts, how they relate:** the **`lean-stack/` scaffold** (hooks, commands, docs layout,
> autopilot) and the **`skills/` pack** (11 skills; 10 are copied per-project). Skills work standalone, but several
> (`roadmap`, `ship-check`, `adr`, …) assume the scaffold's `docs/` layout — install both for the
> full experience.

---

## Repository layout

```
my-claude-code-setup/
├── README.md              ← you are here (the master guide)
├── install.sh             ← one-command installer (deterministic copy + doctor)
├── PRACTICE-PROJECT.md    ← standalone hands-on tutorial (delete after you've learned the stack)
├── CHANGELOG.md · VERSION · LICENSE · .editorconfig
├── lean-stack/            ← the scaffold you drop into a repo
│   ├── CLAUDE.md                    # lean constitution (edit placeholders per project)   [installed]
│   ├── SCAFFOLD.md                  # scaffold quick-start (ships as SCAFFOLD.md, never clobbers README) [installed]
│   ├── docs/                        # SPEC · ROADMAP · STATE · ARCHITECTURE · decisions/ · plans/
│   ├── scripts/                     # autopilot.sh · tick.sh (the completion gate) · doctor.sh · test-hooks.sh
│   ├── .github/workflows/lean-stack-ci.yml   # OPT-IN CI (install.sh --with-ci)
│   └── .claude/
│       ├── settings.json            # hooks → events + permissions.deny
│       ├── commands/                # /resume /wrap /phase /autopilot
│       ├── agents/evaluator.md      # independent grader
│       ├── rules/high-stakes.md     # path-scoped extra care
│       └── hooks/                   # 7 deterministic shell hooks + 3 shared libs (_secret-scan, _high-stakes, _test-cmd)
└── skills/                ← 11 skills (10 portable + setup-lean-stack installer)
```

> The repo-root `README.md` documents the **toolkit**, so `install.sh` never copies it into your
> project. Only `SCAFFOLD.md` — a short, clearly-named quick-start — ships alongside the working files.

There are **two parts**: the **`lean-stack/` scaffold** (drop its contents into any repo)
and the **`skills/` pack** (copy any skill into `.claude/skills/` per-project, or
`~/.claude/skills/` globally). They're designed to work together but each stands alone.

---

## Install

### Prerequisites

Install these before running `install.sh` or any unattended loop:

| Tool | Required? | Install | Why |
|---|---|---|---|
| `git` | **required** | preinstalled / `brew install git` / `apt-get install git` | hooks, `commit-on-stop`, and autopilot all assume a git repo |
| `jq` | **required** | `brew install jq` / `apt-get install jq` | the hooks and `autopilot.sh` parse JSON with it — **autopilot's preflight hard-fails without `jq`** |
| `claude` CLI | **required** | see [Claude Code docs](https://docs.claude.com/en/docs/claude-code) | runs the loops, subagents, and the headless `autopilot.sh` |
| `gh` | optional | `brew install gh` / `apt-get install gh` | only needed for `autopilot.sh --pr` (opening a PR) |

`bash scripts/doctor.sh` checks for these and reports anything missing.

First, clone this repo somewhere stable:

```bash
git clone https://github.com/jaimeberdejo/my-claude-code-setup ~/my-claude-code-setup
```

Then pick one of three ways to get it into a project, from most to least automated:

### Option A — one command (recommended)
```bash
bash ~/my-claude-code-setup/install.sh /path/to/your-repo
```
`install.sh` does the **deterministic** part: copies the scaffold, copies all skills into
`.claude/skills/`, `chmod +x`s the hooks/scripts, and runs `doctor.sh`. It's **idempotent** —
re-running skips files that already exist, so it never clobbers a `CLAUDE.md` you've
customized. It does **not** copy the toolkit README into your project. Flags: `--force`
(overwrite existing files), `--global-skills` (also install the
skills into `~/.claude/skills/` for all projects), `--with-ci` (also drop the opt-in
`lean-stack-ci.yml` CI workflow).

### Option B — the `setup-lean-stack` skill (install **and** customize)
Install the skills globally once (`install.sh --global-skills`, or copy `skills/*` into
`~/.claude/skills/`), then in any project just say *"set up the lean stack here."* The
`setup-lean-stack` skill runs `install.sh` for the copy, then does the **intelligent** part a
blind copy can't: detects your stack, fills `CLAUDE.md`'s test/lint/run commands, points
`high-stakes.md` at your real sensitive dirs, and runs the health checks.

### Option C — manual copy
```bash
cp -r ~/my-claude-code-setup/lean-stack/. /path/to/your-repo/
mkdir -p /path/to/your-repo/.claude/skills && cp -r ~/my-claude-code-setup/skills/*/ /path/to/your-repo/.claude/skills/
cd /path/to/your-repo && chmod +x .claude/hooks/*.sh scripts/*.sh && bash scripts/doctor.sh
```

After any option: edit `CLAUDE.md`'s placeholders (your real commands) if the skill didn't,
then describe the project → `docs/SPEC.md`, run the `roadmap` skill → `docs/ROADMAP.md`, and loop.

> **Why a script and not an "init" skill that writes the files?** Copying static files must
> be deterministic — having a model regenerate the scaffold's files risks drift, costs tokens, and is
> the exact bug this setup avoids elsewhere. So `install.sh` owns the copy; the skill only
> owns the judgment (filling placeholders). Deterministic work stays deterministic.

> **Model note:** don't blanket-set `CLAUDE_CODE_SUBAGENT_MODEL=haiku` — it *overrides*
> the evaluator's `model: sonnet` and would downgrade your grader (the one place you want
> the strong model).

---

## The core loop

```
SPEC once  →  ROADMAP once  →  [ /resume → /phase → review → teach-back → /wrap → /clear ] × N  →  ship
```

- **SPEC once** — describe the project; write `docs/SPEC.md` with a *measurable* success criterion.
- **ROADMAP once** — the `roadmap` skill breaks the spec into phases, each with a checklist
  and a machine-checkable `Done when:` line.
- **The bracket, per phase** — orient, build one phase (research → plan → TDD → independent
  grade), capture ownership + decisions, update docs, clear context.
- **Ship** — full test pass, README, tag.

You drive each arrow manually for stakes that warrant it, or hand the bracket to an autopilot.

---

## Commands

| Command | What it does |
|---|---|
| `/resume` | Reads SPEC+ROADMAP+STATE, states the single next action, then waits. Orientation only. |
| `/phase` | Builds one roadmap phase: research-if-needed → plan → TDD → evaluator self-check. **Does not tick the roadmap** (that's gated on an independent grade). |
| `/autopilot N` | **Watchable** in-session loop: runs N phases in your terminal, grading each via the evaluator subagent. Accepts `N`, `3-5`, or `all`. |
| `/wrap` | Session close-out: update STATE, tick ROADMAP through the shared `scripts/tick.sh` gate (evaluator PASS + fresh green tests + clean secret scan + no high-stakes), append an ADR. Never flips checkboxes by hand. |

## Agent & rules

| File | Role |
|---|---|
| `agents/evaluator.md` | Independent grader — fresh context, **no edit tools**, default-FAIL contract. Grades only; never ticks. The sole *programmatic* gate on "done" in the headless loop. |
| `rules/high-stakes.md` | Native `.claude/rules/` file scoped to auth/migrations/money/etc. paths. Path-scoped loading is currently unreliable in Claude Code, so the **same constraints are also kept in `CLAUDE.md`** (which loads every turn) — don't rely on the rule auto-loading. Point its `paths:` at *your* sensitive dirs. |

## Hooks (deterministic shell — not all enforce; see Enforcement reality)

Seven deterministic shell hooks plus three shared libs:

| Hook | Event | Role |
|---|---|---|
| `session-start.sh` | start/resume/clear/compact | Injects capped state: `STATE`, open roadmap tasks, findings pointer, architecture overview, recent commits. |
| `steer.sh` | prompt/tool | If `STEER.md` exists, injects it once as additional context and removes it. |
| `kill-switch.sh` | every tool call | Blocks tools when `AGENT_STOP` exists. |
| `format-on-edit.sh` | after edits | Best-effort format-only pass for touched Python/JS/TS files. |
| `test-gate.sh` | stop | Optional green-suite gate via `LEAN_TEST_GATE=warn|block`; default is off. |
| `commit-on-stop.sh` | stop | Auto-checkpoint dirty work after a staged secret scan. |
| `ownership-nudge.sh` | stop | Reminds you to ADR / teach-back / map architecture after code changes. |

`_secret-scan.sh`, `_high-stakes.sh`, and `_test-cmd.sh` are sourced libraries, not hooks.

## Skills (`skills/`)

Seven workflow skills (roadmap, milestone, adr, ship-check, scope-guard, explain-diff, unstick),
three ownership skills (teach-back, mapme, quizme), and the `setup-lean-stack` meta-skill. The three
review skills are **report-only** (`disallowed-tools: Edit, Write, …`); a clean pre-commit chain
is **`scope-guard → explain-diff → ship-check`**.

**The full skills catalog lives in [`skills/README.md`](skills/README.md)** (workflow + ownership,
including the [Ownership](skills/README.md#ownership) writeup) — single source, so this list never
drifts from it.

---

## Autonomy

Three ways to run, in order of trust:

| Mode | How | When |
|---|---|---|
| Manual | `/phase`, you review each diff | medium stakes, your daily default |
| Watchable loop | `/autopilot N` (in-session) | a few phases you want to *see* run |
| Headless loop | `bash scripts/autopilot.sh N [--no-worktree] [--pr] [--allow-dirty]` | long/overnight, low-stakes, reversible |

`scripts/autopilot.sh` accepts `N` (up to N), `N-M` (aim for N, cap M), or `all` (malformed
counts are rejected, not ignored). **Worktree isolation is the default** — a bad run can't touch
your checkout; `--no-worktree` opts out (runs in-place, warned loudly). `--pr` opens a PR at the
end and never touches main (secret-scanned before any push); `--allow-dirty` skips the clean-tree
preflight (use sparingly — it removes a safety check).

**The guardrails:** verifiable signal · bounded stop · bounded retries (3-strike thrash cap) ·
blast-radius limit · independent verifier before roadmap ticking · the single `scripts/tick.sh`
completion gate · evaluator-change cleanup in the headless script · high-stakes gate
(auth/money/migrations → supervised stop, never auto-ticked) · secret-scan before commit/push ·
kill-switch · budget cap.

**One shared completion gate.** All ticking — `/wrap`, `/autopilot`, and `scripts/autopilot.sh` —
routes through `scripts/tick.sh`. Nothing marks a phase done without it: it requires a recorded
evaluator PASS, fresh green test evidence bound to the exact commit, a clean secret scan, and no
high-stakes changes, then flips the checkbox and updates the STATE auto-block. It **fails closed** —
on any refusal `docs/ROADMAP.md` is left byte-identical. So the secret-scan, high-stakes, and
evidence checks apply in the *in-session* modes too, not only the headless script.

**What the headless script adds on top of that shared gate is isolation:** a fresh Claude process
per phase (so context never rots), snapshot-and-discard of any change the evaluator makes, and
throwaway-worktree isolation (a bad run can't touch your checkout; a high-stakes branch is never
pushed, even with `--pr`). The in-session `/autopilot` and `/phase`+`/wrap` modes share the tick
gate but not that isolation — you (the watcher) are that guardrail. Use the headless script for
unattended runs; use the in-session modes when you want to watch.

---

## Security

**Enforcement reality — know which tier you're trusting:** the **deterministic** layer
(shell hooks + `autopilot.sh` control flow — kill-switch, strict verdict parsing,
secret-scan, high-stakes gate, evaluator-change cleanup) actually enforces and fails closed;
the **advisory** layer (`CLAUDE.md`, `rules/`, the evaluator prompt) only asks a model to comply.

- `.gitignore` stops *committing* `.env`; it does **not** stop *reading* it. `settings.json`
  ships a `permissions.deny` block for `.env*`, `secrets/**`, `*.pem`, `*.key`, credentials.
- The `Read(...)` denies are a **real boundary**. The `Bash(...)` denies are a **best-effort
  speed-bump** (bypassable via `less`, `source`, `python -c …`), not containment — the real shell
  boundary is a sandbox/no-creds container + `permission_mode: default` for sensitive work.
- High-stakes code (auth/authentication/oauth, migrations, money/payments/refunds, deletes,
  external effects like deploy/email/webhook): supervised only, smallest phases, audit trail. The
  `high-stakes.md` rule advises it, and the **headless** `autopilot.sh` high-stakes gate enforces it
  — a graded phase whose diff touches those paths is never auto-ticked/committed, and the branch is
  **never pushed, even with `--pr`** (it stays local for review). The enforced match list is
  `HIGH_STAKES_RE` in `_high-stakes.sh`; **customize it per project** (run `doctor.sh` — it warns if
  it's still the shipped default). The in-session `/autopilot` and `/phase` modes do **not** apply
  this gate programmatically; keep high-stakes work out of those loops.

---

## Health & maintenance

- `bash scripts/doctor.sh` — one-command health check (run before any unattended run).
- `bash scripts/test-hooks.sh` — hook smoke tests (incl. the secret-scan guard).
- **Repo CI** `.github/workflows/ci.yml` — on push/PR, runs shell-syntax + `settings.json`
  validation against `lean-stack/`, shellcheck + actionlint, lints `install.sh`, runs the
  **behavioral guard suite** (`scripts/run-guard-tests.sh` — the single test list both this
  workflow and the scaffold's own `lean-stack-ci.yml` call, so the two never drift), and the
  **install smoke test** (`.github/scripts/install-smoke.sh`: no tool-doc pollution, no README
  clobber, idempotent, `.gitignore` merge). `lean-stack-ci.yml` is opt-in for installed projects.

## Loop engineering notes

Autonomy is useful only when the loop has an external signal. Prefer phases with a command,
test, eval threshold, or observable output that a fresh reviewer can verify. If a phase cannot
be checked mechanically, mark it `Mode: supervised` and do it by hand.

`Mode: supervised` is enforced by `scripts/tick.sh`: a phase can still be built and graded, but
the shared completion gate refuses to auto-tick it and exits for human review. This complements
the high-stakes path/content gate in `_high-stakes.sh`; it does not replace careful path tuning.

Use the lightest mode that fits the risk:

| Work | Mode |
|---|---|
| tiny, reversible, obvious | Just prompt Claude directly. |
| normal feature work | `/phase`, review, then `/wrap`. |
| a few low-risk phases you want to watch | `/autopilot N`. |
| long low-risk mechanical work | `scripts/autopilot.sh N` in a clean, no-credentials environment. |
| auth, money, migrations, deletes, deploy/email/webhook effects | Supervised only, `permission_mode: default`, no unattended loop. |

---

## Troubleshooting

| Symptom | One-line fix |
|---|---|
| `doctor.sh` prints a ✗ | It names the missing piece — run the matching install step (e.g. `brew install jq`, install the `claude` CLI) and re-run `doctor.sh`. |
| Hooks not firing | `chmod +x .claude/hooks/*.sh scripts/*.sh`, and confirm they're wired in `.claude/settings.json`. |
| `format-on-edit` silently skips a file | Expected — there's no project-local formatter for that file type. Install/configure one (ruff, prettier+eslint) if you want formatting. |
| Evaluator verdict "unrecognized" | By design the loop stops rather than guess — read the evaluator's output and fix the phase (or the criteria) so it emits a clean PASS/FAIL. |
| Leftover autopilot worktree | `git worktree remove <path>` (add `--force` if it refuses); `git worktree list` shows them. |
| `autopilot.sh` preflight aborts | Most often missing `jq` (hard-fail) or a dirty tree — install `jq`, commit/stash, or pass `--allow-dirty` knowingly. |

---

## Where to read more

- **`PRACTICE-PROJECT.md`** — a standalone, throwaway tutorial to learn the whole stack hands-on,
  then delete. Lives at the repo root so `install.sh` never copies it into your real projects.

## License

[MIT](LICENSE) © 2026 Jaime Berdejo ([@jaimeberdejo](https://github.com/jaimeberdejo)).
