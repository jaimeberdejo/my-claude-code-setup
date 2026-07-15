# ADR-001: Native requirement traceability, not a promoted Spec Kit profile

Date: 2026-07-16
Decision: Implement requirement traceability natively — stable `REQ/AC/OBJ` ids flowing `SPEC.md` → roadmap `Requirements:` → plan tasks → the conditional evaluator, with a small deterministic id-validation helper — instead of installing or promoting Spec Kit as a profile.
Why: The Release 2 Spec Kit experiment proved the traceability value but showed it is separable from the tool, while Spec Kit imposed permanent always-loaded context, extra artifacts (`.specify/`, `specs/`, `tasks.md`), a second task queue, and CLI/preset upkeep; the native extension gives the same evaluator benefit at ~0 always-loaded cost, so the promoted-profile integration was rejected.
