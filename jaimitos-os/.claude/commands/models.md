Show or change which model each `/phase` stage uses. All the actual logic lives in
`scripts/models.sh` — this command is a thin wrapper, exactly as `/wrap`'s ticking step wraps
`scripts/tick.sh`. Never edit `.claude/agents/*.md`'s frontmatter by hand from this command;
always go through the script, so the mutation stays deterministic and tested
(`scripts/test-models.sh`).

- `/models` → run `bash scripts/models.sh`
- `/models exec=opus` → run `bash scripts/models.sh exec=opus`
- `/models research=opus plan=opus exec=sonnet eval=sonnet` → run `bash scripts/models.sh research=opus plan=opus exec=sonnet eval=sonnet`
- `/models all=haiku exec=sonnet` → run `bash scripts/models.sh all=haiku exec=sonnet`
- `/models reset` → run `bash scripts/models.sh reset`

Run the corresponding command exactly as shown (substituting the actual arguments given),
print its output verbatim, and if it exits non-zero, report the failure as-is — do not retry
with a different argument shape or attempt to fix the input yourself; the script's own error
message already says what's wrong.

If `CLAUDE_CODE_SUBAGENT_MODEL` is set in the environment, the script's output will include a
warning that it overrides all four settings shown (env > per-invocation > frontmatter) — print
that warning verbatim too, same as any other script output.

**The four roles, and which `/phase` step each is invoked from:**
| Key | Role | `/phase` step |
|---|---|---|
| `research` | researcher | step 3 |
| `plan` | planner | step 4 |
| `exec` | executor | step 5 |
| `eval` | evaluator | step 6 |
