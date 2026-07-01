# Security Policy

This is a personal, MIT-licensed open-source project. The guidance below is honest about
what it does and does not protect — read the **Scope** section before relying on any guard.

## Supported versions

Only the **latest release** is supported. The current version is in
[`VERSION`](VERSION) (and stamped into installed projects as
`.claude/.lean-stack-version`). Fixes land on the newest release; older tags get nothing.
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
- **The high-stakes gate only protects paths YOU point it at.** Out of the box,
  `HIGH_STAKES_RE` in `_high-stakes.sh` and `paths:` in `high-stakes.md` are generic
  examples. If you don't edit them to match your real auth/migration/money/delete dirs, a
  loop can auto-tick and commit those paths. Editing only the advisory rule (not the enforced
  regex) silently disables enforcement — `doctor.sh` warns when the default is untouched.
- **Autopilot is for low-stakes, reversible code only.** Worktree isolation and the kill-switch
  reduce blast radius; they do not make irreversible actions safe. Set a hard budget cap as the
  outer backstop.

In short: the guards here make mistakes *visible and bounded*. Containment is on you.
