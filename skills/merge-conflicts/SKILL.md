---
name: merge-conflicts
description: Resolve an in-progress git merge/rebase conflict by understanding both intents, never by inventing behavior. Use when a merge or rebase stops on conflicts — "merge conflict", "resuelve el conflicto", "el merge falla", "rebase stopped on conflicts", or when integrating a phase branch built in a git worktree.
---

# Merge conflicts

1. **See the current state** of the merge/rebase: git history and the conflicting files.
2. **Find the primary sources** for each conflict. Understand why each side's change was made
   and what its original intent was — commit messages, PRs, the phase's plan under `docs/plans/`,
   ADRs in `docs/decisions/`.
3. **Resolve each hunk.** Preserve both intents where possible. Where they're incompatible, pick
   the one matching the merge's stated goal and note the trade-off. Do **not** invent new
   behavior. Always resolve; never `--abort` as the fix.
4. **Run the project's automated checks** — typically typecheck, then tests, then format (the
   commands are in CLAUDE.md). Fix anything the merge broke.
5. **Finish the merge/rebase.** Stage everything and commit; if rebasing, continue until all
   commits are rebased.

## The worktree phase-branch integration case
Merging a phase branch built in a git worktree (the default for `scripts/autopilot.sh`) back into
your checkout has two extra rules:
- **A `docs/STATE.md` conflict is expected and harmless** — every `/phase` run rewrites the same
  narrative line. Keep whichever sentence is still accurate (or note both); never revert a real
  code change over it. The machine-managed block between the `lean:auto` markers heals itself on
  the next tick.
- **The human picks the resolution.** Stop on the conflict and present options rather than choosing
  for them: a conflict between phases that were expected to be disjoint means that expectation was
  wrong somewhere, and that judgment belongs to the user. Use steps 1–2 above to explain *why* the
  hunks conflict and to build the 1–3 options presented; apply exactly what the user chooses.

<!-- Adapted from mattpocock/skills (MIT) — https://github.com/mattpocock/skills -->
