# PLAN — v2.2.1: Adversarial Audit P0 Fixes (surgical patch)

Fixes only the P0/high-severity trust-boundary findings from `AUDIT-JAIMITOS-OS-V2.2.md`.
No new features, no redesign, no docs cleanup. Guiding rule: make `sync.sh`/`tick.sh` **more
conservative, never more magical** — never accept "merged: success" unless the result is
syntactically valid (`bash -n`) and shape-valid; fail safe to manual review; force supervised.

## In scope

| ID  | Finding | Fix target |
|-----|---------|------------|
| C1  | High-stakes gate self-exemption (phase can edit the allowlist / `_high-stakes.sh` to exempt itself) | `scripts/tick.sh` |
| C2  | sync truncates multi-line / odd-quoted `HIGH_STAKES_RE` while reporting success | `scripts/sync.sh` `merge_hs_lib` / `hs_line_count` |
| C3  | sync agent `model:` merge destroys malformed / frontmatter-less project files | `scripts/sync.sh` `merge_agent_model` |
| H1  | sync `paths:` block drops later paths after an unindented comment | `scripts/sync.sh` `paths_block_bounds` |
| H5  | `test-high-stakes.sh` silent-pass (FAILS lost in a subshell) | `scripts/test-high-stakes.sh` |
| H5b | Same bug class found in `test-test-cmd.sh` (whole suite can't fail) | `scripts/test-test-cmd.sh` |

Each fix ships with regression tests that reproduce the bug and prove it closed. One atomic
commit per finding (H5 and H5b are separate commits).

## Explicitly OUT OF SCOPE
- doctor.sh improvements (H3/M4/M11) · README/docs polish (H6) · high-stakes allowlist docs (M10)
- monorepo / off-git-root support (H4) · `models.sh` bugs (H2/M3) · v2.3.0 planning
- general sync redesign · headless "no-bypass" lifecycle rewrite · forgeable-evidence hardening (M1)
- renaming `test-evidence.sh` · any other Medium/Low from the audit

## Required behaviors (acceptance)
- **C1:** if the phase diff includes `.claude/high-stakes-path-allowlist` or
  `.claude/lib/_high-stakes.sh`, `tick.sh` forces supervised (exit 3) regardless of contents.
  Unattended autopilot can no longer self-narrow or self-exempt the gate.
- **C2:** a malformed/wrapped/multi-line/odd-quoted `HIGH_STAKES_RE` routes to manual review with
  the project file byte-identical; any generated merged `_high-stakes.sh` passes `bash -n` before write.
- **C3:** `model:` is only merged inside a well-formed `---`…`---` frontmatter block; otherwise
  manual review, project file byte-identical.
- **H1:** only a real top-level YAML key ends the `paths:` block; blank / indented / bare-comment
  lines never narrow it silently.
- **H5/H5b:** every assertion affects the parent shell's failure count; an intentionally broken
  assertion makes the script exit non-zero.

VERSION bump (2.2.0 → 2.2.1) and any tag are a **separate explicit checkpoint**, never inferred
from "continue"/"resume".
