# Security Policy

This is a personal, MIT-licensed open-source project. The guidance below is honest about
what it does and does not protect — read the **Scope** section before relying on any guard.

## Supported versions

Only the **latest release** is supported. The current version is in
[`VERSION`](VERSION) (and stamped into installed projects as
`.claude/.jaimitos-os-version`). Fixes land on the newest release; older tags get nothing.
If you installed an older copy, re-run `install.sh --force` from a fresh clone to update.

## Reporting a vulnerability

Please **do not open a public issue for anything sensitive** (a way to exfiltrate secrets,
bypass the high-stakes gate, defeat the secret-scan, etc.). Instead:

- Open a **private GitHub security advisory** on the repo (Security → "Report a
  vulnerability"), **or**
- Open a private issue / email the maintainer ([@jaimeberdejo](https://github.com/jaimeberdejo))
  with enough detail to reproduce.

This is a side project: **no SLA, no bounty, best-effort response only.** Non-sensitive bugs
and hardening ideas are welcome as normal public issues or PRs (see
[`CONTRIBUTING.md`](CONTRIBUTING.md)). A matching test for any safety fix is appreciated.

## Scope

**What this project tries to do:** ship deterministic shell hooks, a headless-loop control
flow, and sensible defaults that make a *good* automated run likely and a *bad* one loud.
Read the README's "Enforcement reality" section — the deterministic layer (hooks +
`autopilot.sh`) fails closed; the advisory layer (`CLAUDE.md`, `rules/`, the evaluator
prompt) only *asks* a model to comply.

**What it explicitly does NOT guarantee — your responsibility:**

- **The secret-scan is a best-effort, prefix-matching commit-time guard — NOT a scanner, and it
  runs on the default-on auto-commit path.** It matches secret-y filenames plus ~20 fixed-prefix
  token shapes (AWS, Anthropic `sk-ant-`, OpenAI `sk-`/`sk-proj-`, Stripe, Google `AIza`/`GOCSPX-`,
  GitHub/GitLab/Slack/npm/SendGrid/Azure/DigitalOcean, JWTs, PEM/PGP blocks, `user:password` URLs).
  Because it matches PREFIXES, it **cannot catch secrets that have no fixed prefix** — bare-hex
  Twilio/Mailgun-style tokens, Django/Rails random `SECRET_KEY` values, and generic `password=` /
  high-entropy strings will pass through and be auto-committed with a normal "✓ checkpointed"
  message. Do NOT rely on it as a safety net: use a real scanner (gitleaks, trufflehog, GitHub
  secret scanning) + a pre-commit hook, and review your diffs. This guard only stops the obvious.
- **`permissions.deny` is defense-in-depth, not a boundary.** The `Read(...)` denies are a
  real boundary; the `Bash(...)` denies are a bypassable speed-bump (`less`, `source`,
  `python -c …`). The real boundary for unattended runs is the **environment**: a
  sandbox/container with **no production credentials** and constrained egress, plus
  `permission_mode: default`. This scaffold can't sandbox itself.
- **`scripts/autopilot.sh --dangerously-skip-permissions` removes the permission boundary
  entirely, for both the builder and evaluator processes.** It exists because, without a TTY,
  the default `acceptEdits` mode cannot approve writes to `.claude/` or Bash commands like the
  test suite — a real unattended run needs this flag to complete even one phase. That is exactly
  why it must be confined to a sandbox/container with **no production credentials**: with it on,
  neither `permissions.deny` nor any interactive prompt stands between the builder and anything
  your OS user can touch. Prefer `acceptEdits` (the default, no flag needed) whenever a human is
  at the terminal to approve prompts.
- **The high-stakes gate only protects paths YOU point it at.** Out of the box,
  `HIGH_STAKES_RE` in `_high-stakes.sh` and `paths:` in `high-stakes.md` are generic
  examples. If you don't edit them to match your real auth/migration/money/delete dirs, a
  loop can auto-tick and commit those paths. Editing only the advisory rule (not the enforced
  regex) silently disables enforcement — `doctor.sh` warns when the default is untouched.
- **The high-stakes path allowlist is an auditable escape hatch, not a bypass.**
  `.claude/high-stakes-path-allowlist` clears **exact-path false positives** in the path matcher
  (e.g. an ADR whose name merely contains "money") — git-tracked, one path per line, each requiring a
  non-empty reason. It is purely subtractive: the enforced `HIGH_STAKES_RE` and the content scanner are
  untouched, a bare/reasonless entry suppresses nothing, and `doctor.sh` lists every active suppression.
  A phase **cannot** self-exempt by adding its own allowlist entry: editing the allowlist — or
  `_high-stakes.sh` — inside a phase forces supervised review (`tick.sh` exit 3), regardless of the new
  contents. `tick.sh` **cannot** guard edits to `tick.sh` itself (a neutered gate would run its own
  neutered check); those are caught under headless autopilot by the gate-control byte-integrity check
  (next bullet), not by `tick.sh` exit 3.
- **Under headless autopilot, the gate's own code and scan window are orchestrator-trusted.**
  `tick.sh` and `_high-stakes.sh` run from the builder's worktree, and the scan runs over
  `${phase-base}..HEAD` where `.claude/.phase-base` is builder-written — both untrusted under
  `--dangerously-skip-permissions`. `scripts/autopilot.sh` closes that: it derives the phase base in its
  OWN trusted shell (overwriting the builder's file before the evaluator, strict-ancestor-validated by
  `tick.sh` via `TICK_BASE`), and byte-compares each gate-control file against the trusted launch
  checkout before running the gate — so a builder can neither forge `.phase-base` to hide a commit nor
  neuter `tick.sh`/`_high-stakes.sh` in its worktree and still get an auto-tick or push. This is enforced
  and tested; the executor's forbidden-writes rule is advisory on top of it. It still assumes a
  sandboxed, no-credentials environment — a builder with arbitrary shell access can tamper with its own
  worktree or exfiltrate, and we do not claim otherwise.
- **The manual `/wrap` path is weaker than headless autopilot — by design.** `/wrap` (and
  `/autopilot-parallel`) call `tick.sh` directly and do **not** yet have the trusted-base override or the
  gate-control byte-integrity check that `scripts/autopilot.sh` runs: they trust the session-written
  `.claude/.phase-base` and the on-disk gate code. Two consequences: (1) run `/wrap` only from a **clean
  working tree** — `tick.sh` scans `${phase-base}..HEAD`, so an **uncommitted** high-stakes/secret change
  is outside the window; (2) a forged/narrowed in-session `.phase-base` (a valid later ancestor) can shrink
  that window. Both are acceptable because `/wrap` is **human-supervised**; for **unattended** operation use
  **headless `scripts/autopilot.sh`**, which is the hardened path.
- **Autopilot is for low-stakes, reversible code only.** Worktree isolation and the kill-switch
  reduce blast radius; they do not make irreversible actions safe. Set a hard budget cap as the
  outer backstop.

In short: the guards here make mistakes *visible and bounded*. Containment is on you.
