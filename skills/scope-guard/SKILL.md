---
name: scope-guard
description: Checks that a change matches its stated task and nothing more, and that its paper trail is up to date. Use before committing or when reviewing what was just built — "did I stay on scope", "check this didn't touch anything it shouldn't", "review before commit", "ready to commit", "ship it". Catches helpful-over-reach: unrelated edits, drive-by refactors, unexpected deletions.
allowed-tools: Read, Grep, Glob, Bash(git diff *), Bash(git status *), Bash(git log *)
disallowed-tools: Edit, Write, NotebookEdit
---

# Scope guard

The most common failure in agent-assisted work is doing MORE than asked —
refactoring nearby code, "improving" unrelated files, deleting things that
looked unused. This skill catches that before it lands.

## Steps
1. **State the task in one line.** Pull it from the user, the active plan, or
   docs/STATE.md. If the intended scope is unclear, ask before judging.
2. **Read the diff** (`git diff` and `git diff --cached`, plus `git status` for
   new/deleted files).
3. **Classify every changed file** into:
   - **In scope** — directly required by the task.
   - **Justified support** — needed to make the in-scope change work (a new import, a test).
   - **Out of scope** — unrelated edits, opportunistic refactors, formatting churn in
     untouched files, deletions not implied by the task.
4. **Flag the out-of-scope items explicitly**, with file and a one-line reason.
   Pay special attention to: deleted files/functions, changes in directories the
   task never mentioned, and renames that ripple wider than needed.
5. **Check the paper trail.** If logic changed, did `docs/STATE.md` (or the task notes) get
   updated? If a real decision was made, is there an ADR in `docs/decisions/`? Flag what's
   missing — never auto-write it here. This is the one pre-commit check the native reviewers
   can't make: `/code-review` and `/security-review` read the code, not the scaffold's docs.

## Verdict
- `IN SCOPE` — everything maps to the task or directly supports it, and the paper trail is current.
- `SCOPE CREEP: <items>` — list each out-of-scope change and recommend whether to
  revert it, split it into its own commit, or keep it (with the user's say-so).
- Report a missing STATE update or ADR alongside the verdict — it does not by itself make a
  change out of scope, but it must not ship silently.

## Guardrails
- **Read-only by contract.** The edit tools (Edit/Write/NotebookEdit) are removed in the
  frontmatter, and your shell/git access is for INSPECTION ONLY — never modify anything with it:
  no `sed -i`, `tee`, output redirection (`>`/`>>`), `rm`/`mv`/`cp` over tracked files, or
  `git add`/`commit`/`checkout`/`restore`/`stash`. You produce a verdict, not edits.
- Don't revert anything yourself — surface it and let the user decide.
- "It's an improvement" is not the same as "it's in scope." Note good ideas as
  candidates for a separate, deliberate change.
