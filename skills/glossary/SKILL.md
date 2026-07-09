---
name: glossary
description: Creates/updates docs/GLOSSARY.md when domain vocabulary crystallizes — one-line definitions plus the terms rejected. Use when naming settles — "glossary", "define el término", "cómo llamamos a", "we call this X, not Y", "add that to the glossary".
---

# Glossary

Capture the project's domain vocabulary the moment it crystallizes — "we call this X, not Y" is
a decision that evaporates unless written down. The artifact is `docs/GLOSSARY.md`, optional and
created lazily on the first resolved term.

## Format (docs/GLOSSARY.md)
```md
# Glossary

**Order** — a customer's request to buy, from placement to fulfillment.
_Avoid_: purchase, transaction

**Customer** — a person or organization that places orders.
_Avoid_: client, buyer, account
```

## Rules
- **Be opinionated.** When several words exist for one concept, pick the best and list the
  others under `_Avoid_` — the avoid-list is half the value.
- **One line per definition.** What the term IS, not what the code does with it.
- **Domain terms only.** General programming concepts (timeout, retry, cache) don't belong,
  however often the project uses them.
- **Challenge drift.** If the user uses a term that conflicts with the glossary, call it out
  immediately: "the glossary says 'cancellation' means X, but you seem to mean Y — which is it?"
- **Update inline, as it happens.** Don't batch terms up for later; capture each one when it's
  resolved.

## What this skill does NOT do
- It never writes ADRs. An architectural decision that surfaces while naming things goes to
  `docs/decisions/` via the `adr` skill — this file is a glossary and nothing else.
- No bounded-context machinery (context maps, per-context files). One `docs/GLOSSARY.md` per
  repo; if a term genuinely means two things in two areas, give it two entries that say where.

The session-start hook injects the first 30 lines of `docs/GLOSSARY.md` into every session, so
keep it tight — the most load-bearing terms first.

<!-- Adapted from mattpocock/skills (MIT) — https://github.com/mattpocock/skills -->
