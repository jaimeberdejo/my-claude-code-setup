---
description: Extra care for high-stakes or hard-to-reverse code — auth, data migrations, anything that moves money or can't be cleanly undone.
paths:
  # Faithful mirror of HIGH_STAKES_RE in ../lib/_high-stakes.sh (the ENFORCED list).
  # Segment categories:
  - "**/auth*/**"
  - "**/oauth*/**"
  - "**/login/**"
  - "**/session*/**"
  - "**/account*/**"
  - "**/payment*/**"
  - "**/billing/**"
  - "**/transaction*/**"
  - "**/migration*/**"
  - "**/compliance/**"
  - "**/suitability/**"
  - "**/secret*/**"
  - "**/kyc/**"
  - "**/wallet/**"
  - "**/ledger/**"
  # Substring categories (match anywhere in the path):
  - "**/*migrat*"
  - "**/*money*"
  - "**/*payment*"
  - "**/*credential*"
  - "**/*delet*"
  - "**/*destroy*"
  - "**/*email*"
  - "**/*deploy*"
  - "**/*refund*"
  - "**/*withdraw*"
  - "**/*charge*"
  - "**/*webhook*"
---

# High-stakes code

This is a native `.claude/rules/` file. **Path-scoped (`paths:`) triggering is
currently unreliable in Claude Code** — known bugs mean it can load globally
regardless of the `paths:` filter, or fail to load even on matching files. So do
NOT rely on the `paths:` filter for enforcement. For GUARANTEED enforcement, either
remove the `paths:` filter (the rule will then always load) or keep these same
constraints in CLAUDE.md as well.

Edit the `paths:` above to match wherever YOUR irreversible/consequential code lives —
auth, schema migrations, billing, deletion paths, external-effect calls, anything where
a bug costs more than a re-run.

**The single source of truth for enforcement is `.claude/lib/_high-stakes.sh`**
(`HIGH_STAKES_RE`): `scripts/autopilot.sh` sources it and REFUSES to auto-tick/commit/push
a phase whose diff touches those paths — it stops for supervised review (and never pushes,
even with `--pr`). The `paths:` globs above are a **human-readable mirror** of that regex,
not a second enforcement point. When you customize, **edit `HIGH_STAKES_RE` first** (that's
what's enforced), then update these globs to match. `scripts/doctor.sh` warns if you left the
regex at its shipped default (a sign the enforced gate was never pointed at your real paths).

- **No autopilot here.** This is human-on-the-loop work: a loop may *surface* a diff,
  but a human approves it before it lands. Keep `permission_mode: default`. Claude Code's `auto`
  mode is a useful *semantic complement* when you're at the terminal, but never the mechanism: it
  is ignored for subagents and aborts under `-p`, so it cannot guard a headless run. The enforced
  gate is `HIGH_STAKES_RE` + `scripts/tick.sh`.
- **Smallest possible phases.** One reviewable change at a time. No drive-by refactors.
- **Explainable line by line.** Record real decisions (and the alternative rejected)
  with the `adr` skill so the change is defensible later.
- **Never** run migrations against shared/prod data, perform irreversible deletes, or trigger
  external side effects that MUTATE something outside our control (payments, emails, webhooks,
  deploys) as part of an automated loop. Keep those outside the loop's blast radius (e.g. no prod
  credentials in the loop's env). A read-only, idempotent call to a public endpoint (fetching
  data, not changing it) is not this category by itself — don't tag a phase supervised on "it
  makes an external call" alone; judge the actual reversibility/consequence.
- **Money:** never use `float` for currency — use `Decimal` / integer minor units, and
  document the rounding.
- **Path false-positive? Use the allowlist FILE, not a code comment.** `HIGH_STAKES_RE`'s
  loose substrings (`money`, `email`, `deploy`, …) match anywhere in a path, so a benign
  file like `ADR-001-decimal-money-as-yaml-strings.md` can trip the gate on zero real
  signal. `.claude/high-stakes-path-allowlist` is the sanctioned escape for that: a
  separate, git-tracked file where each exception is its own reviewable line
  (`<exact path>: <reason>`, a real reason required) — never an inline suppression, and
  never a rename-to-dodge-the-regex. It affects ONLY the path/keyword matcher. The
  content marker (`high-stakes-ok: <reason>`, inline on a diff line) is a completely
  separate, content-only mechanism and is unaffected by this file, and vice versa.
  `scripts/doctor.sh` reports active allowlist entries **and every active `high-stakes-ok:` content
  marker in the tracked tree**, so neither kind of suppression is ever hidden.
- **Over-broad match blocking a legitimate phase? Fix `HIGH_STAKES_RE` in a commit BEFORE that
  phase's base — never inside it.** Editing `_high-stakes.sh` (or the path allowlist) *within* a
  phase is itself gated: `tick.sh` forces supervised review (exit 3) on any in-phase change to the
  gate's own config, so a phase can't self-narrow the regex that guards it. If the shipped regex is
  genuinely too broad for your repo, tighten it as its own small, reviewed commit that lands BEFORE
  you set the blocked phase's `.claude/.phase-base` — then the fix is already inside the phase's scan
  floor, not part of the phase diff. (Fixing it inside the phase just converts one refusal into
  another.)
- **Tag the code that TOUCHES the sensitive data, not code that merely sits NEAR a sensitive feature.**
  High-stakes is about blast radius on the actual data/effect, not proximity to a scary word. A
  stats-only export or a read-only dashboard that aggregates already-safe numbers is NOT high-stakes
  just because it lives beside a PII pipeline; the **redaction/anonymization path that reads the raw
  PII** IS. Point `HIGH_STAKES_RE` (and any `supervised` phase) at the mutation / redaction / egress
  code, and use the allowlist for benign neighbors that only trip the keyword match.

If a task in these paths is ambiguous, STOP and ask rather than guessing.
