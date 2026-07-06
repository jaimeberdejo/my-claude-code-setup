# v2.2.0 milestone — toolkit→project sync mechanism (scope)

> **Status: milestone kickoff / scope.** This defines WHAT v2.2.0 delivers and the design that
> came out of dogfooding research. It is not yet a TDD task breakdown — a few design decisions
> (flagged **[DECISION]** below) should be settled first, then this becomes an executable plan.

## Why

Dogfooding jaimitos-os across real builds surfaced the biggest structural gap: **there is no way
for an already-scaffolded project to pull in fixes the toolkit ships later.** The proof is
concrete — `model-cost-guard` had a stale `.claude/lib/_test-cmd.sh` that predated commit
`bed34ff` (uv.lock/poetry.lock detection) and silently never received the fix; a human had to
hand-copy it (`3a16b25`). `setup-jaimitos-os` only handles brand-new projects. This was split out
of the v2.1.0 hardening milestone deliberately — it's a migration/update system, not an edge fix.

## Goal

A command an already-scaffolded project runs (e.g. `bash scripts/sync.sh`) that pulls in later
toolkit fixes **without clobbering that project's own customizations**, showing a diff and
requiring confirmation for anything ambiguous.

## What the research established (grounded, don't re-derive)

- **`install.sh`** (repo root) ships the scaffold via a blanket `find "$SCAFFOLD" -type f` copy of
  the `jaimitos-os/` tree, minus three exclusions (`toolkit-docs/*`, `.github/*` unless
  `--with-ci`, `.DS_Store`/`*.swp`). Its only per-project safety is **skip-if-exists** (unless
  `--force`). No manifest, no per-file tracking. A sync tool should **reuse this exact
  enumeration** (one source of truth for "what jaimitos-os ships"); `install-smoke.sh`'s list is a
  test sample, not a manifest.
- **VERSION-string comparison is insufficient.** `bed34ff` shipped a real fix with **no VERSION
  bump** — a tool gating on `installed-version == toolkit-version` would report "up to date" while
  files drifted (exactly what bit `model-cost-guard`). Drift detection must compare **file content
  hashes**, not the version string. Precedent exists: `doctor.sh`'s `.claude/.high-stakes-default`
  fingerprint-diff (lines ~76-90) already does per-value drift detection.
- **`.claude/.jaimitos-os-version` is gitignored** in scaffolded projects, so it's absent on a
  fresh clone/CI checkout — the tool must handle "no stamp found" gracefully (same tolerant
  pattern `doctor.sh` uses for `.high-stakes-default`).
- **Three file tiers** (this is the core of the design):
  - **Overwrite-safe** (pure toolkit logic, no project values inside): `.claude/lib/*.sh` logic,
    `.claude/hooks/*.sh`, `scripts/*.sh`, `.claude/skills/**`, `.claude/commands/*.md`.
  - **Never-touch** (project-owned): `docs/{SPEC,ROADMAP,STATE}.md`, filled `CLAUDE.md`, ADRs.
  - **Must-merge (mixed toolkit + project content in one file):**
    - `.claude/lib/_high-stakes.sh` — toolkit logic/comments, but the `HIGH_STAKES_RE=` value is
      project-customized data in the same file.
    - `.claude/agents/*.md` — toolkit body/tool-list, but the `model:` frontmatter is project-set
      via `scripts/models.sh` (never hand-edit — go through the script).
    - `.claude/rules/high-stakes.md` — toolkit prose, project-customized `paths:` frontmatter.
    - `.claude/settings.json` — toolkit hooks/deny defaults + project `env`/customizations.
    - Templates (`CLAUDE.md`, `docs/*`) that flip from "still-shipped-template" to "project-owned"
      the moment the user edits them — indistinguishable without a baseline of the shipped
      placeholder text (which install.sh doesn't currently store).
- **Constraints:** Bash 3.2 (no `declare -A`); `jq` is already a hard toolkit dependency (fine for
  structured sync-state).

## Design (proposed)

- **New `scripts/sync.sh`** in the scaffold: for a scaffolded project, compares each toolkit-shipped
  file against the current toolkit source and applies updates per its tier.
- **Overwrite-safe tier:** diff; if changed upstream and unmodified-by-project (or modified only in
  ways the tool can see), update wholesale after showing the diff.
- **Never-touch tier:** always skip (same as install's skip-if-exists); mention what was skipped.
- **Must-merge tier:** show the diff and **require explicit confirmation**; for the known
  value-bearing lines (`HIGH_STAKES_RE=`, `model:` via `models.sh`, `paths:`), preserve the
  project's value and take the toolkit's surrounding changes — never blindly overwrite.
- **`--dry-run`** shows exactly what would change per tier without writing.
- Reuse `install.sh`'s `find`+exclusions for enumeration; reuse `doctor.sh`'s fingerprint-diff
  pattern for drift detection; handle a missing version stamp gracefully.
- **`scripts/test-sync.sh`** (TDD): a stale overwrite-safe file gets updated; a customized
  `HIGH_STAKES_RE`/`model:` survives; a project doc is never touched; missing stamp handled.

## Resolved design decisions (locked 2026-07-06)

- **[DECISION 1 — RESOLVED] Drift detection = diff against a local toolkit checkout.** No manifest
  yet. `scripts/sync.sh --toolkit <path>` (e.g. `--toolkit ~/projects/Claude_SETUP/jaimitos-os`)
  compares the project's files directly against that local checkout; a helpful error if the path is
  missing/invalid. Rationale: optimize for the real dogfooded failure mode (dev has the toolkit
  checked out, fixes it, needs existing scaffolded projects to receive the fix); a manifest
  reintroduces exactly the release-discipline dependency that caused the original drift. A
  per-release hash manifest can be a **later packaging/CI milestone** once `sync.sh` is proven.
- **[DECISION 2 — RESOLVED] Mixed files = narrow value-preserving auto-merge + confirm.** Take the
  toolkit's updated body but re-inject the project's own value, show the diff, require confirmation
  before writing. **Only known mixed values** are merged: `_high-stakes.sh`'s `HIGH_STAKES_RE=`,
  agent files' `model:` frontmatter, rules files' `paths:`. **No generic/clever merge engine.** If
  a mixed file does not match the expected shape, **fail safe**: skip it, report why, tell the user
  to reconcile manually — never guess, never clobber. Per-file flow: (1) read toolkit file,
  (2) read project file, (3) extract the known project-owned value, (4) apply it onto the updated
  toolkit file, (5) show the diff, (6) confirm, (7) then write.
- **[DECISION 3 — DEFERRED] Release discipline (VERSION-bump-per-fix / auto hash manifest).** Not
  in v2.2.0. Revisit if/when distribution (a manifest) is actually needed.

## Locked implementation rules (from the decisions above)

- **Conservative, never a blind two-way overwrite.** Four tiers, explicit:
  1. **overwrite-safe toolkit-owned** → update from the local checkout (show diff);
  2. **never-touch project-owned** → skip;
  3. **known mixed** → narrow value-preserving merge → diff → confirm → write;
  4. **unknown / unexpectedly-shaped / customized-beyond-recognition** → **fail safe, do NOT clobber**;
     report and let the user decide.
- `--toolkit <path>` is explicit and required; clear error if absent.
- `--dry-run` shows every planned change per tier without writing.
- **Heavily tested — normal AND malformed cases.** For a malformed mixed file the test asserts the
  tool skips + reports + leaves the file byte-identical (never guesses, never clobbers).
- Bash 3.2; reuse `install.sh`'s `find`+exclusions for enumeration; reuse `doctor.sh`'s
  fingerprint-diff pattern; `jq` is available.

## Deferred v2.2+ items carried from the v2.1.0 review (fold in or track separately)

- High-stakes allowlist **future-commit drift**: an entry exempts a path from ALL future commits
  (unlike the per-commit content marker). Candidate mitigation: content-hash-scoped allowlist
  entries, or a periodic allowlist audit. (Both safety-gate reviewers flagged this independently.)
- Minor: `_high_stakes_allowlisted()` re-reads the file + spawns a subprocess per line per matched
  path (O(matches×lines)); an indented `# comment` with a colon parses as a phantom entry
  (cosmetic); a real path containing a colon can't be allowlisted (`%%:*` truncates).

## Not in this milestone

Fixing the headless-permission cliff for real (moving `/phase`'s `.claude/` state-writes out of
the claude process) — deferred indefinitely in v2.1.0 per user decision; only documented there.
