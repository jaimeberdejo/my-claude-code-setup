# ADR-004: Architectural claims map to enforcement via a compact ledger

> **SUPERSEDED by [ADR-008](ADR-008-remove-enforcement-and-uat-ledgers.md) (v2.15.0).** The ledger
> shipped a validator with no producer and no caller, so it was reachable only from its own
> fixtures, while the docs graded it Deterministic. Removed under ADR-007's standard. The reasoning
> below is kept as the record of what was decided and why.

Date: 2026-07-16
Decision: Material architectural/operational claims map to one enforcement mechanism — or an explicit advisory label — in an additive `docs/ENFORCEMENT.md` (created only when a repo has claims worth governing), whose structure is validated by `scripts/lint-enforcement.sh` (id/claim/source/enforcement/strength/status/trigger; a DEFERRED row needs a real trigger). The ledger is never regenerated from the current code graph, never ticks, and never grants permission.
Why: The failure being prevented is silent drift — "the architecture doc says a rule exists, but nothing checks or reviews it." Forcing each claim to name its enforcement (deterministic script/test/hook/CI, human review, or honest advisory) makes drift visible. The rejected alternative — regenerating the ledger from the current dependency graph — would bless whatever the code does today as the intended architecture, which is exactly the debt the ledger exists to surface.
