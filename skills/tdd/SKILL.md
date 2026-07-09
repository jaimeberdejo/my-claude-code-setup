---
name: tdd
description: The red → green loop plus what makes a test worth keeping — seams, anti-patterns, mocking rules. Use when building test-first — "tdd", "red-green", "test-first", "write the failing test first". The executor agent follows this as its TDD manual.
---

# TDD

TDD is the red → green loop. This skill is the reference that makes the loop produce tests worth
keeping: what a good test is, where tests go, the anti-patterns, and the rules of the loop.
Consult [tests.md](tests.md) for examples and [mocking.md](mocking.md) for mocking rules.

Name tests in the project's own vocabulary — check `docs/GLOSSARY.md` if it exists — and respect
ADRs in `docs/decisions/` for the area you're touching.

## What a good test is
Tests verify behavior through public interfaces, not implementation details. A good test reads
like a specification — "user can checkout with valid cart" — and survives refactors because it
doesn't care about internal structure.

## Seams — where tests go
A **seam** is the public boundary you test at. Tests live at seams, never against internals, and
seams are **pre-agreed, not improvised mid-loop**:
- If `docs/SPEC.md`'s `## Test seams` section (written via `to-spec`) or the phase's plan under
  `docs/plans/` already names the seams, **use those — do not re-ask.** They were confirmed when
  the spec/plan was written.
- Only when neither names a seam: propose the fewest that cover the work (ideal: one), confirm
  with the user, and note the choice in the plan file so the next cycle doesn't re-litigate it.

## Anti-patterns (the evaluator grades against these — teaching and grading are symmetric)
- **Implementation-coupled** — mocks internal collaborators, tests private methods, or verifies
  through a side channel (querying the DB instead of the interface). Tell: the test breaks on a
  refactor when behavior didn't change.
- **Tautological** — the assertion recomputes the expected value the way the code does
  (`expect(add(a,b)).toBe(a+b)`), so it passes by construction and can never disagree with the
  code. Expected values come from an independent source: a known-good literal, a worked example,
  the spec.
- **Mocking the subject under test** — the thing the task asked to build is itself mocked, so the
  test cannot fail.
- **Horizontal slicing** — all tests first, then all implementation. Bulk tests verify *imagined*
  behavior and commit you to structure before understanding. Work in **vertical slices**: one
  test → one implementation → repeat, each test a tracer bullet.

## Rules of the loop
- **Red before green.** Failing test first, then only enough code to pass it. Run the test and
  see it fail — a test that never went red proves nothing.
- **One slice at a time.** One seam, one test, one minimal implementation per cycle. Commit each
  green slice (small, single-purpose commits).
- **Stuck at red after 3 attempts?** Stop and report the blocker — never skip ahead or weaken the
  test to get past it.
- **Refactoring is not part of the loop.** It's a separate, deliberate pass after green — with
  the tests as the safety net.

<!-- Adapted from mattpocock/skills (MIT) — https://github.com/mattpocock/skills -->
