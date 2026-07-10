# jaimitos-claude-setup

A lean, **project-neutral operating system for Claude Code**: an evidence-gated, auto-ticked
roadmap with auto-written state, deterministic hooks, an independent grader, two autonomous
loops (one you can watch, one for overnight), path-scoped rules, and a pack of portable
skills — at a fraction of the token cost of heavyweight planning frameworks.

It reproduces what big multi-agent frameworks automate — spec, roadmap, persistent state,
decision log, phase execution, independent verification — with **each phase run strictly
sequentially (research → plan → execute → verify, one subagent at a time), never a parallel
research/planning swarm**, so you keep full visibility and a 1-experienced-dev token budget.

> **The one idea:** `CLAUDE.md` advises · **hooks enforce** · **docs hold knowledge**.
> Never ask one to do another's job. And **match ceremony to stakes**: tiny/reversible →
> just prompt; medium → supervised; big/mechanical/low-stakes → autopilot; high-stakes →
> human-on-the-loop.

---

## Quickstart

```bash
git clone https://github.com/jaimeberdejo/jaimitos-claude-setup.git ~/jaimitos-claude-setup
cd /path/to/your-project
git init                                           # first, so the post-install doctor is clean
bash ~/jaimitos-claude-setup/install.sh .           # drops the scaffold + skills in (auto-runs doctor)
```

Then it branches on whether there's an existing stack to detect:
- **Adopting into an existing repo?** Fill `CLAUDE.md`'s commands + point `HIGH_STAKES_RE` in
  `.claude/lib/_high-stakes.sh` at your sensitive paths now (the `setup-jaimitos-os` skill can
  auto-detect and do this for you) — then write `docs/SPEC.md` → run the `roadmap` skill → build.
- **Starting from scratch?** There's no stack to fill CLAUDE.md with yet — write `docs/SPEC.md`
  first (grill the idea until it has a *measurable* success criterion). Then run the `roadmap`
  skill: it fills `CLAUDE.md`'s test/lint/run commands from the SPEC automatically as it writes
  `docs/ROADMAP.md`, and reminds you to point `HIGH_STAKES_RE` at any sensitive paths — no manual
  CLAUDE.md edit needed. Then build with `/phase`.

New to it all? Work through `PRACTICE-PROJECT.md` first.

> **Two parts, how they relate:** the **`jaimitos-os/` scaffold** (hooks, commands, docs layout,
> autopilot) and the **`skills/` pack** (16 skills; 15 are copied per-project — see
> [`skills/README.md`](skills/README.md) for the authoritative count and catalog). Skills work
> standalone, but several (`roadmap`, `scope-guard`, `adr`, …) assume the scaffold's `docs/`
> layout — install both for the full experience.

---

## Repository layout

```
jaimitos-claude-setup/
├── README.md              ← you are here (the master guide)
├── install.sh             ← one-command installer (deterministic copy + doctor)
├── PRACTICE-PROJECT.md    ← standalone hands-on tutorial (delete after you've learned the stack)
├── CHANGELOG.md · VERSION · LICENSE · .editorconfig
├── jaimitos-os/            ← the scaffold you drop into a repo
│   ├── CLAUDE.md                    # lean constitution (edit placeholders per project)   [installed]
│   ├── SCAFFOLD.md                  # scaffold quick-start (ships as SCAFFOLD.md, never clobbers README) [installed]
│   ├── docs/                        # SPEC · ROADMAP · STATE · ARCHITECTURE · decisions/ · plans/
│   ├── scripts/                     # autopilot.sh · tick.sh (the completion gate) · sync.sh (toolkit updater) · doctor.sh · models.sh
│   ├── .github/workflows/jaimitos-os-ci.yml   # OPT-IN CI (install.sh --with-ci)
│   └── .claude/
│       ├── settings.json            # hooks → events + permissions.deny
│       ├── commands/                # /resume /wrap /phase /autopilot /models
│       ├── agents/                  # researcher, planner, executor, evaluator — one per /phase stage
│       ├── rules/high-stakes.md     # path-scoped extra care
│       └── hooks/                   # 7 deterministic shell hooks + 4 shared libs (_secret-scan, _high-stakes, _test-cmd, _eval-isolation)
└── skills/                ← 16 skills (15 portable + setup-jaimitos-os installer) — see skills/README.md
```

> The repo-root `README.md` documents the **toolkit**, so `install.sh` never copies it into your
> project. Only `SCAFFOLD.md` — a short, clearly-named quick-start — ships alongside the working files.

There are **two parts**: the **`jaimitos-os/` scaffold** (drop its contents into any repo)
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
git clone https://github.com/jaimeberdejo/jaimitos-claude-setup ~/jaimitos-claude-setup
```

Then pick one of three ways to get it into a project, from most to least automated:

### Option A — one command (recommended)
```bash
bash ~/jaimitos-claude-setup/install.sh /path/to/your-repo
```
`install.sh` does the **deterministic** part: copies the scaffold, copies all skills into
`.claude/skills/`, `chmod +x`s the hooks/scripts, and runs `doctor.sh`. It's **idempotent** —
re-running skips files that already exist, so it never clobbers a `CLAUDE.md` you've
customized. It does **not** copy the toolkit README into your project. Flags: `--force`
(overwrite existing files), `--global-skills` (also install the
skills into `~/.claude/skills/` for all projects), `--with-ci` (also drop the opt-in
`jaimitos-os-ci.yml` CI workflow).

### Option B — the `setup-jaimitos-os` skill (install **and** customize)
Install the skills globally once (`install.sh --global-skills`, or copy `skills/*` into
`~/.claude/skills/`), then in any project just say *"set up jaimitos-os here."* The
`setup-jaimitos-os` skill runs `install.sh` for the copy, then does the **intelligent** part a
blind copy can't: detects your stack, fills `CLAUDE.md`'s test/lint/run commands, points
`high-stakes.md` at your real sensitive dirs, and runs the health checks.

### Option C — manual copy
```bash
cp -r ~/jaimitos-claude-setup/jaimitos-os/. /path/to/your-repo/
mkdir -p /path/to/your-repo/.claude/skills && cp -r ~/jaimitos-claude-setup/skills/*/ /path/to/your-repo/.claude/skills/
cd /path/to/your-repo && chmod +x .claude/hooks/*.sh scripts/*.sh && bash scripts/doctor.sh
```

After any option: if there was an existing stack to detect, `CLAUDE.md`'s placeholders are
already filled with your real commands (via `setup-jaimitos-os`, or edit them yourself). Starting
from an empty project instead? Leave them — describe the project → `docs/SPEC.md`, then run the
`roadmap` skill → `docs/ROADMAP.md`; it fills `CLAUDE.md`'s commands from the SPEC as it runs.
Then loop.

> **Why a script and not an "init" skill that writes the files?** Copying static files must
> be deterministic — having a model regenerate the scaffold's files risks drift, costs tokens, and is
> the exact bug this setup avoids elsewhere. So `install.sh` owns the copy; the skill only
> owns the judgment (filling placeholders). Deterministic work stays deterministic.

> **Model note:** each `/phase` stage can be pinned to its own model via `scripts/models.sh` /
> `/models` (persisted in that role's agent frontmatter). Don't blanket-set
> `CLAUDE_CODE_SUBAGENT_MODEL=haiku` — it *overrides* every subagent's frontmatter `model:`
> uniformly, including the evaluator's, silently downgrading whatever you configured.

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
| `/models` | Thin wrapper around `scripts/models.sh` — shows or sets which model each `/phase` stage (research/plan/execute/verify) uses, persisted per-project in that stage's agent frontmatter. `all=X` sets all four; `reset` restores shipped defaults. |

## Agent & rules

| File | Role |
|---|---|
| `agents/researcher.md` | Read-only investigator for `/phase` step 3 (research) — no Write/Edit, findings-only. |
| `agents/planner.md` | Writes `docs/plans/<phase>.md` for `/phase` step 4 (plan) — Write scoped by convention to that one file. |
| `agents/executor.md` | Full build permissions for `/phase` step 5 (execute) — the TDD loop. |
| `agents/evaluator.md` | Independent grader for `/phase` step 6 (verify) — fresh context, **no edit tools**, default-FAIL contract. Grades only; never ticks. The sole *programmatic* gate on "done" in the headless loop. |
| `rules/high-stakes.md` | Native `.claude/rules/` file scoped to auth/migrations/money/etc. paths. Path-scoped loading is currently unreliable in Claude Code, so the **same constraints are also kept in `CLAUDE.md`** (which loads every turn) — don't rely on the rule auto-loading. Point its `paths:` at *your* sensitive dirs. |

## Hooks (deterministic shell — not all enforce; see Enforcement reality)

Seven deterministic shell hooks plus four shared libs:

| Hook | Event | Role |
|---|---|---|
| `session-start.sh` | start/resume/clear/compact | Injects capped state: `STATE`, open roadmap tasks, findings pointer, architecture overview, recent commits. |
| `steer.sh` | prompt/tool | If `STEER.md` exists, injects it once as additional context and removes it. |
| `kill-switch.sh` | every tool call | Blocks tools when `AGENT_STOP` exists (in-session). Headless `scripts/autopilot.sh` also parent-polls `AGENT_STOP` *during* each child run and kills the child tree, so a wedged child can't ignore it. |
| `format-on-edit.sh` | after edits | Best-effort format-only pass for touched Python/JS/TS files. |
| `test-gate.sh` | stop | Optional green-suite gate via `LEAN_TEST_GATE=warn|block`; default is off. |
| `commit-on-stop.sh` | stop | Auto-checkpoint dirty work after a staged secret scan. |
| `ownership-nudge.sh` | stop | Reminds you to ADR / teach-back / map architecture after code changes. Also flags when a change happened outside an active phase, so `docs/STATE.md` doesn't silently go stale. |

`_secret-scan.sh`, `_high-stakes.sh`, `_test-cmd.sh`, and `_eval-isolation.sh` are sourced
libraries, not hooks.

## Skills (`skills/`)

Sixteen skills — ◆ marks the seven adapted from [mattpocock/skills](https://github.com/mattpocock/skills) (MIT):

**Workflow (8)**
- **grill** ◆ — relentless one-question-per-turn stress-test of a plan, each question with a recommendation
- **to-spec** ◆ — synthesize the design conversation into docs/SPEC.md (seams confirmed, measurable criterion required)
- **roadmap** — SPEC → phased docs/ROADMAP.md with measurable "Done when:" lines
- **milestone** — add phases mid-project / archive a finished roadmap
- **adr** — 4-line decision records in docs/decisions/
- **glossary** ◆ — docs/GLOSSARY.md: one-line domain definitions + rejected terms
- **scope-guard** — flags out-of-scope edits, drive-by refactors, and a stale paper trail (report-only)
- **unstick** — breaks a circular-debugging loop by naming the shared failing assumption

**Engineering (4)**
- **design-twice** ◆ — two genuinely different designs before non-trivial code, ADR records the loser
- **tdd** ◆ — the red→green loop with pre-agreed seams and the evaluator's own anti-pattern list
- **diagnose** ◆ — hard-bug discipline: a tight red-capable feedback loop before any hypothesis
- **merge-conflicts** ◆ — resolve from both sides' intent; runs the project checks, finishes the merge

**Ownership (3):** **teach-back** (explain + quiz after a phase) · **mapme** (regenerate
docs/ARCHITECTURE.md) · **quizme** (cold-open understanding check) — plus the
**setup-jaimitos-os** installer meta-skill (global-only).

A clean pre-commit chain is **`scope-guard` → `/code-review` → `/security-review`** (or `/verify`).
Claude Code's native commands **supersede** the retired `explain-diff` (≈ `/code-review`) and
`ship-check` (≈ `/security-review` + `/verify`) skills, dropped in v2.7.0; `scope-guard` stays
because "did this change stay on task, and is its paper trail current?" is scaffold-specific and
nothing native answers it. **The authoritative catalog (descriptions, triggers, the MIT attribution
notice) is [`skills/README.md`](skills/README.md)** — counts live there so they can't drift here.

---

## Autonomy

Three ways to run, in order of trust:

| Mode | How | When |
|---|---|---|
| Manual | `/phase`, you review each diff | medium stakes, your daily default |
| Watchable loop | `/autopilot N` (in-session) | a few phases you want to *see* run |
| Headless loop | `bash scripts/autopilot.sh N [--no-worktree] [--pr] [--allow-dirty] [--dangerously-skip-permissions]` | long/overnight, low-stakes, reversible |
| **Sandboxed headless (recommended for unattended)** | `bash sandbox/run-autopilot-sandboxed.sh N [--pr ...]` | the supported way to run truly unattended — builds a no-credentials container, mounts only the repo, passes only `ANTHROPIC_API_KEY`, runs the headless loop with `--dangerously-skip-permissions` inside |

`scripts/autopilot.sh` accepts `N` (up to N), `N-M` (aim for N, cap M), or `all` (malformed
counts are rejected, not ignored). **Worktree isolation is the default** — a bad run can't touch
your checkout; `--no-worktree` opts out (runs in-place, warned loudly). `--pr` opens a PR at the
end and never touches main (secret-scanned before any push); `--allow-dirty` skips the clean-tree
preflight (use sparingly — it removes a safety check).

That pre-push scan reads the **net** `BASE..HEAD` diff, so a secret added in one commit and deleted
in a later one **within the same phase** nets to zero and is missed — while `--pr` still pushes the
commit that contains it. For any run that pushes, set **`LEAN_SECRET_SCANNER=gitleaks`** (or
`trufflehog`): it scans the range commit by commit, and is fail-closed if the tool isn't installed.

**`--dangerously-skip-permissions`** — without a TTY, the default `--permission-mode acceptEdits`
cannot approve writes to `.claude/` (the phase-tracking markers `/phase` needs) or Bash commands
like the test suite, so a truly unattended run needs this flag to complete even one phase — pass
it ONLY in a sandboxed container with no production credentials. The script detects a blocked
builder deterministically (a missing `.claude/.phase-ready` after it exits) and stops with this
exact guidance rather than silently burning a grading pass on a phase that was never attempted.
Each builder/evaluator child now runs under a watchdog (a per-child wall-clock timeout plus a
parent-polled `AGENT_STOP` that kills the whole child tree), so a wedged headless `claude` subtree
is contained instead of spawning a runaway — but that is a *liveness* fix, not a *security* one:
under bypass the child can still run anything your OS user can, which is why sandbox-only stands.

**The guardrails:** verifiable signal · bounded stop · bounded retries (3-strike thrash cap) ·
blast-radius limit · independent verifier before roadmap ticking · the single `scripts/tick.sh`
completion gate · evaluator-change cleanup in the headless script · per-child watchdog (wall-clock
timeout + parent-polled `AGENT_STOP`, so a wedged builder/evaluator subtree is contained, not left
to run away) · high-stakes gate (auth/money/migrations → supervised stop, never auto-ticked) ·
secret-scan before commit/push · kill-switch · budget cap *(operator-set in your Claude/gateway
config — the one guardrail the stack can't enforce for you)*.

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

**Two tiers.** The **deterministic** layer (shell hooks, `tick.sh`, `autopilot.sh` control flow)
enforces and fails closed; the **advisory** layer (`CLAUDE.md`, `rules/`, agent prompts) only asks
a model to comply. `Read(...)` denies are a real boundary; `Bash(...)` denies are a bypassable
speed-bump — and there are deliberately **no `curl`/`wget` denies**, because a bash glob is not an
egress boundary. The real boundary for unattended runs is a **no-credentials sandbox**, and one
ships with the scaffold: `sandbox/run-autopilot-sandboxed.sh` (see Autonomy above).

Enforced by `tick.sh` + `_high-stakes.sh` + `_secret-scan.sh`: high-stakes paths/content are
never auto-ticked or pushed (supervised review instead); the gate's own config can't be edited by
the phase it gates; under headless autopilot the scan window and every gate-control file are
orchestrator-trusted (re-derived in a trusted shell + byte-integrity-checked); the manual `/wrap`
path is the weaker, human-supervised one — run it from a clean tree. Customize `HIGH_STAKES_RE`
per project (`doctor.sh` warns while it's the shipped default). The built-in secret scan is a
prefix-matcher; opt into a real one with **`LEAN_SECRET_SCANNER=gitleaks`** (or `trufflehog`) —
same gate, fail-closed if the tool is missing.

**The full security narrative lives in [GUIDE.md Parts 4–5](jaimitos-os/toolkit-docs/GUIDE.md#part-4--the-per-phase-cycle-hooks--the-completion-gate)
(single source — enforcement reality, gate integrity, the scan window), plus the policy in [SECURITY.md](SECURITY.md).**

---

## Health & maintenance

- `bash scripts/doctor.sh` — one-command health check (run before any unattended run).
- `bash scripts/test-hooks.sh` — hook smoke tests (incl. the secret-scan guard).
- **Repo CI** `.github/workflows/ci.yml` — on push/PR, runs shell-syntax + `settings.json`
  validation against `jaimitos-os/`, shellcheck + actionlint, lints `install.sh`, runs the
  **behavioral guard suite** (`scripts/run-guard-tests.sh` — the single test list both this
  workflow and the scaffold's own `jaimitos-os-ci.yml` call, so the two never drift), and the
  **install smoke test** (`.github/scripts/install-smoke.sh`: no tool-doc pollution, no README
  clobber, idempotent, `.gitignore` merge). `jaimitos-os-ci.yml` is opt-in for installed projects.

### Keeping a project up to date — `scripts/sync.sh`

`install.sh` only scaffolds a **brand-new** project (it skips files that already exist). To pull
**later toolkit fixes** into a project you already scaffolded — without clobbering your customizations —
run `sync.sh` against a local jaimitos-os checkout:

```bash
bash scripts/sync.sh --toolkit /path/to/jaimitos-claude-setup/jaimitos-os --dry-run  # preview the plan
bash scripts/sync.sh --toolkit /path/to/jaimitos-claude-setup/jaimitos-os           # apply (one batch confirm)
```

- **The manifest is the primitive.** `install.sh` writes `.claude/.jaimitos-manifest` — one
  `sha256  path` line per toolkit-owned file, recording the bytes each file *shipped* with
  (`sha256sum -c`-compatible). Sync compares local vs manifest vs toolkit and acts per file:
  - **Unchanged locally** (local hash == manifest) and the toolkit has a newer version →
    batch-updated after ONE confirmation (`--yes` skips it).
  - **Modified locally** → **never written.** You get the toolkit↔local diff and a
    "manual merge required" listing; copy your line over in 20 seconds.
  - **Project-owned** (`docs/**`, `CLAUDE.md`, `SCAFFOLD.md`, `.gitignore`, the high-stakes
    allowlist) → never touched, never reported.
  - **Deleted locally** (in the manifest, absent on disk) → never recreated;
    `--restore <path>` reinstalls it deliberately. A file in *neither* place is a new toolkit
    addition and joins the update batch.

> **Upgrading a pre-2.5.0 project (one-time step):** projects scaffolded before the manifest
> existed must adopt one first — `bash scripts/sync.sh --toolkit <path> --adopt-manifest`
> records the **current local files** as the baseline (writes only the manifest, no content).
> Because adoption can't tell a pre-adoption customization from shipped bytes, review the first
> post-adoption sync with `--dry-run` before confirming the batch.

- `--dry-run` writes nothing (not even the manifest); a failed copy is reported and exits nonzero,
  never counted as success. Run sync on a clean working tree so you can `git diff` the result.
- Sync **refuses on a never-scaffolded project** (no `.claude/settings.json`) — run `install.sh` first.

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
| `autopilot.sh` stops immediately: "`.claude/.phase-ready` is missing after the builder exited" | Headless (no TTY) `claude` can't approve a permission prompt for writing `.claude/` or running the test suite via Bash — retry with `--dangerously-skip-permissions`, and only in a sandboxed container with no production credentials. |
| `/phase` (no argument) keeps re-selecting the same already-built phase | It's `Mode: supervised` — its checkboxes never auto-tick until a human runs `/wrap` (which correctly refuses to auto-tick it). Target the next phase explicitly: `/phase "## Phase N — ..."`. |

---

## Where to read more

- **`PRACTICE-PROJECT.md`** — a standalone, throwaway tutorial to learn the whole stack hands-on,
  then delete. Lives at the repo root so `install.sh` never copies it into your real projects.
- **[`jaimitos-os/toolkit-docs/GUIDE.md`](jaimitos-os/toolkit-docs/GUIDE.md)** — the comprehensive
  guide: every hook, command, script, and the completion gate explained in depth, plus the loop-
  engineering theory (what makes a phase safe to automate, guardrail design, failure modes).

## License

[MIT](LICENSE) © 2026 Jaime Berdejo ([@jaimeberdejo](https://github.com/jaimeberdejo)).
