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
  but a human approves it before it lands. Keep `permission_mode: default`.
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
  `scripts/doctor.sh` reports active allowlist entries so a suppression is never hidden.

If a task in these paths is ambiguous, STOP and ask rather than guessing.
