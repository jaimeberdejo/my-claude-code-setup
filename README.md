# my-claude-code-setup

A lean, **project-neutral operating system for Claude Code**: auto-maintained docs,
deterministic hooks, an independent grader, two autonomous loops (one you can watch, one
for overnight), path-scoped rules, and a pack of portable skills — at a fraction of the
token cost of heavyweight planning frameworks.

It reproduces what big multi-agent frameworks automate — spec, roadmap, persistent state,
decision log, phase execution, independent verification — with **one context at a time, no
research fan-out**, so you keep full visibility and a 1-experienced-dev token budget.

> **The one idea:** `CLAUDE.md` advises · **hooks enforce** · **docs hold knowledge**.
> Never ask one to do another's job. And **match ceremony to stakes**: tiny/reversible →
> just prompt; medium → supervised; big/mechanical/low-stakes → autopilot; high-stakes →
> human-on-the-loop.

---

## Repository layout

```
my-claude-code-setup/
├── README.md              ← you are here (the master guide)
├── install.sh             ← one-command installer (deterministic copy + doctor)
├── CHANGELOG.md · VERSION · LICENSE · .editorconfig
├── lean-stack/            ← the scaffold you drop into a repo
│   ├── CLAUDE.md                    # lean constitution (edit placeholders per project)
│   ├── GUIDE.md                     # the full manual + a hands-on practice project
│   ├── LOOP-ENGINEERING.md          # the theory of safe autonomous loops
│   ├── README.md                    # scaffold quick-start
│   ├── docs/                        # SPEC · ROADMAP · STATE · ARCHITECTURE · decisions/ · plans/
│   ├── scripts/                     # autopilot.sh · doctor.sh · test-hooks.sh
│   ├── .github/workflows/ci.yml     # regression CI for the hooks
│   └── .claude/
│       ├── settings.json            # hooks → events + permissions.deny
│       ├── commands/                # /resume /wrap /phase /autopilot
│       ├── agents/evaluator.md      # independent grader
│       ├── rules/high-stakes.md     # path-scoped extra care
│       └── hooks/                   # 7 deterministic shell hooks
└── skills/                ← 10 portable skills (9 workflow/ownership + setup-lean-stack)
```

There are **two parts**: the **`lean-stack/` scaffold** (drop its contents into any repo)
and the **`skills/` pack** (copy any skill into `.claude/skills/` per-project, or
`~/.claude/skills/` globally). They're designed to work together but each stands alone.

---

## Install

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
customized. Flags: `--force` (overwrite existing files), `--global-skills` (also install
the skills into `~/.claude/skills/` for all projects).

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
> be deterministic — having a model regenerate ~40 files risks drift, costs tokens, and is
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
| `/wrap` | Session close-out: update STATE, tick ROADMAP (only evaluator-confirmed items), append an ADR. |

## Agent & rules

| File | Role |
|---|---|
| `agents/evaluator.md` | Independent grader — fresh context, **no edit tools**, default-FAIL contract. Grades only; never ticks. The sole gate on "done." |
| `rules/high-stakes.md` | Path-scoped: auto-loads only when auth/migrations/money/etc. paths are touched; re-injected on compaction. Point its `paths:` at *your* sensitive dirs. |

## Hooks (deterministic enforcement)

| Hook | Fires on | Does |
|---|---|---|
| `session-start.sh` | session start/resume/clear/compact | Re-injects STATE + open roadmap + `NEXT_FINDINGS` + architecture overview + recent commits. The "never forget" mechanism. |
| `steer.sh` | prompt submit + before each tool call | Injects `STEER.md` (as JSON `additionalContext`) to redirect a running loop, then clears it. |
| `kill-switch.sh` | before each tool call | `touch AGENT_STOP` blocks the next tool call onward. Your seatbelt. |
| `format-on-edit.sh` | after Write/Edit | Auto-formats/lints the touched file (ruff / prettier+eslint). |
| `test-gate.sh` | turn end (opt-in) | `LEAN_TEST_GATE=warn\|block` runs the suite, writes `test-results.json`, and (block) refuses to end the turn on red. Makes "TDD always" enforceable. |
| `commit-on-stop.sh` | turn end | Honest git checkpoint (only claims success when a commit happened; survives untracked-only changes). |
| `ownership-nudge.sh` | turn end | Reminds you to ADR the decision, run teach-back, and `/mapme` after code changes. |

## Skills (`skills/`)

**Workflow**
| Skill | Use when | Does |
|---|---|---|
| `roadmap` | you have a spec | Turns SPEC into ROADMAP — adaptive phase count (recommends few/medium/many), measurable `Done when:`, loopable/supervised tag. |
| `adr` | a real decision is made | Writes a terse 4-line ADR (incl. the alternative rejected). |
| `ship-check` | before commit/PR | Runs the project's checks + scans for debug/secret/leftovers. READY / NOT READY. *Report-only.* |
| `scope-guard` | after a change | Flags out-of-scope edits, drive-by refactors, deletions. IN SCOPE / SCOPE CREEP. *Report-only.* |
| `explain-diff` | self-review | What changed and, mainly, where it might be wrong. *Report-only.* |
| `unstick` | going in circles | Names the shared failing assumption, proposes fresh hypotheses + the cheapest test. |

**Ownership** (understand what gets built — active recall, not passive reading)
| Skill | Use when | Does |
|---|---|---|
| `teach-back` | after a phase | Explains the build, then quizzes you one question at a time; weak answers → a reading list. |
| `mapme` | re-entering / after big changes | Regenerates `docs/ARCHITECTURE.md` from the real code. |
| `quizme` | periodically / before an interview | Cold-open quiz from the codebase, graded honestly. |

The three review skills set `disallowed-tools: Edit, Write, MultiEdit, NotebookEdit` — they
*cannot* modify code, only report. A clean pre-commit chain: **`scope-guard → explain-diff → ship-check`**.

**Meta** — `setup-lean-stack`: installs this scaffold into a project (via `install.sh`) and
then customizes it for the detected stack. See [Install → Option B](#install) above.

---

## Autonomy

Three ways to run, in order of trust:

| Mode | How | When |
|---|---|---|
| Manual | `/phase`, you review each diff | medium stakes, your daily default |
| Watchable loop | `/autopilot N` (in-session) | a few phases you want to *see* run |
| Headless loop | `bash scripts/autopilot.sh N [--worktree] [--pr]` | long/overnight, low-stakes, reversible |

`scripts/autopilot.sh` accepts `N` (up to N), `N-M` (aim for N, cap M), or `all`.
`--worktree` runs on an isolated branch; `--pr` opens a PR at the end and never touches main.

**The guardrails** (see `lean-stack/LOOP-ENGINEERING.md` for the full theory):
verifiable signal · bounded stop · bounded retries (3-strike thrash cap) · blast-radius
limit · **independent verifier as the sole roadmap-ticker** · kill-switch · budget cap.
The builder *never* marks its own work done — a fresh-context, no-edit-tools evaluator always gates the tick.

---

## Security

- `.gitignore` stops *committing* `.env`; it does **not** stop *reading* it. `settings.json`
  ships a `permissions.deny` block for `.env*`, `secrets/**`, `*.pem`, `*.key`, credentials.
- The `Read(...)` denies are a **real boundary**. The `Bash(...)` denies are **defense-in-depth**
  (bypassable via `less`, `source`, `python -c …`) — the real shell boundary is sandboxed bash +
  `sandbox.credentials` + `permission_mode: default` for sensitive work.
- High-stakes code (auth/migrations/money/deletes/external effects): supervised only, smallest
  phases, audit trail. The `high-stakes.md` rule encodes this.

---

## Health & maintenance

- `bash scripts/doctor.sh` — one-command health check (run before any unattended run).
- `bash scripts/test-hooks.sh` — hook smoke tests.
- `.github/workflows/ci.yml` — runs shell-syntax, settings validation, and the smoke tests on push/PR.

---

## Where to read more

- **`lean-stack/GUIDE.md`** — the full manual: setup, five worked use cases, tutorials, and a
  hands-on practice project to learn the whole stack end-to-end.
- **`lean-stack/LOOP-ENGINEERING.md`** — designing and running autonomous loops safely.

## License

[MIT](LICENSE) © 2026 Jaime Berdejo ([@jaimeberdejo](https://github.com/jaimeberdejo)).
