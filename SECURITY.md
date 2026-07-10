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
  Since v2.6.0 you can wire a real scanner IN as the backend: set `LEAN_SECRET_SCANNER=gitleaks`
  (or `trufflehog`) and it replaces the regex inside the same gate — same contract, and
  **fail-closed** if the tool isn't installed (the scan errors rather than silently degrading to
  the regex). `doctor.sh` hard-fails when a selected scanner is missing. Still opt-in, because it
  adds an external dependency.
- **A secret added and then removed inside the same phase slips past the default regex scan — and
  `--pr` still pushes the commit that contains it.** `secret_scan_diff` scans the NET two-endpoint
  diff `BASE..HEAD`, so a credential committed in one commit and `git rm`'d in a later one within
  the same phase nets to zero and is reported clean. The tick gate ticks, and the push gate — which
  scans that same net diff — lets `--pr` push the whole branch, intermediate commit included. This
  is a limit of the **default `regex` backend**, not of the gate: `LEAN_SECRET_SCANNER=gitleaks`
  (or `trufflehog`) scans the range **commit by commit** and catches it, and is fail-closed if the
  tool isn't installed. **Set a real backend for any run that pushes** (`--pr`), or rewrite the
  branch history before pushing.
- **`permissions.deny` is defense-in-depth, not a boundary.** The `Read(...)` denies are a
  real boundary; the `Bash(...)` denies are a bypassable speed-bump (`less`, `source`,
  `python -c …`). There are deliberately **no network denies** (v2.5.0 removed the old
  `Bash(curl *)`/`Bash(wget *)` entries): network exfiltration cannot be blocked with bash
  globs — curl is one of a thousand ways out (python, node, `nc`, a git push to a new
  remote) — and denying it only broke legitimate daily work while implying protection that
  didn't exist. The real boundary for unattended runs is the **environment**: a
  sandbox/container with **no production credentials** and constrained egress, plus
  `permission_mode: default`. This scaffold can't sandbox itself.
- **`scripts/autopilot.sh --dangerously-skip-permissions` removes the permission boundary
  entirely, for both the builder and evaluator processes.** It exists because, without a TTY,
  the default `acceptEdits` mode cannot approve writes to `.claude/` or Bash commands like the
  test suite — a real unattended run needs this flag to complete even one phase. That is exactly
  why it must be confined to a sandbox/container with **no production credentials**: with it on,
  neither `permissions.deny` nor any interactive prompt stands between the builder and anything
  your OS user can touch. Each builder/evaluator child does now run under a watchdog — a per-child
  wall-clock timeout plus a parent-polled `AGENT_STOP` that kills the whole child tree — so a
  wedged headless `claude` subtree is contained rather than spawning a runaway; but that is a
  *liveness/containment* fix, not a security boundary, and does nothing to relax the sandbox-only
  rule. **The supported mitigation ships with the scaffold: `sandbox/run-autopilot-sandboxed.sh`**
  builds a no-credentials container, mounts only the repo, passes only `ANTHROPIC_API_KEY`, and
  refuses fail-closed if secret-shaped files would ride into the mount — use it for every
  unattended run. Prefer `acceptEdits` (the default, no flag needed) whenever a human is at the
  terminal to approve prompts.
- **Claude Code's `auto` permission mode is an in-session *semantic complement*, not a replacement
  for the deterministic high-stakes gate.** `auto` asks a model to judge, per tool call, whether an
  action looks dangerous — genuinely useful, and it catches things a regex never will. It cannot be
  the mechanism here: it is **ignored for subagents** (the builder/evaluator do their work there)
  and **aborts under `-p`** (headless, which is exactly where nobody is watching). So it adds a
  second opinion when a human is at the terminal, while `HIGH_STAKES_RE` + `tick.sh` remain the
  thing that actually stops an unattended loop. Run both; rely on the gate.
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
- **Under headless autopilot, the gate's own code and scan window are orchestrator-trusted;
  the manual `/wrap` path is weaker by design.** `scripts/autopilot.sh` re-derives the phase base
  in its own trusted shell and byte-integrity-checks every gate-control file, so a builder can
  neither forge `.claude/.phase-base` to shrink the scan window nor neuter the gate in its
  worktree; `/wrap` trusts the session-written base and on-disk gate
  code and is human-supervised — run `/wrap` only from a clean working tree, and use headless
  autopilot (in the sandbox) for unattended operation. The full mechanism — trusted re-derivation,
  `TICK_BASE` ancestor validation, integrity checks, and their limits — is documented in
  [GUIDE.md Part 4, "Gate integrity & the scan window"](jaimitos-os/toolkit-docs/GUIDE.md), the
  single source for that narrative. It still assumes a sandboxed, no-credentials environment — a
  builder with arbitrary shell access can tamper with its own worktree or exfiltrate, and we do
  not claim otherwise.
- **Autopilot is for low-stakes, reversible code only.** Worktree isolation, the kill-switch (now
  parent-polled *during* each child run, not just between iterations), and the per-child watchdog
  timeout reduce blast radius; they do not make irreversible actions safe. Set a hard budget cap as
  the outer backstop.

In short: the guards here make mistakes *visible and bounded*. Containment is on you.
