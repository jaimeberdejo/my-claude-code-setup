#!/usr/bin/env bash
# models.sh — deterministic get/set for which model each /phase stage uses.
#
# Persisted directly in that stage's agent frontmatter (.claude/agents/<role>.md's `model:`
# line) -- the SAME file /phase reads when it delegates to that subagent, so there is nothing
# else to keep in sync. This script OWNS all mutation of that line: .claude/commands/models.md
# and skills/setup-jaimitos-os/SKILL.md both shell out here rather than editing frontmatter
# themselves -- deterministic config mutation belongs in a script, exactly like
# tick.sh/record-grade.sh/next-adr.sh, never in a model's freehand file edit.
#
# Usage:
#   bash scripts/models.sh                                    show current config, all 4 roles
#   bash scripts/models.sh exec=opus                           set one role
#   bash scripts/models.sh research=opus plan=opus exec=sonnet eval=sonnet   set several
#   bash scripts/models.sh all=haiku exec=sonnet                all=X sets all 4; an explicit
#                                                                pair for the SAME role in the
#                                                                SAME invocation wins over all=,
#                                                                regardless of argument order
#   bash scripts/models.sh reset                                researcher/planner/executor ->
#                                                                inherit; evaluator -> sonnet
#                                                                (each role's OWN shipped default)
#
# If the SAME key is given more than once in one invocation (e.g. exec=opus exec=haiku), the
# LAST occurrence in argv wins -- standard last-write-wins, not an error.
#
# No model-name allowlist: whatever string you give is written verbatim. Claude Code is the
# authority on valid model names/aliases and validates at actual invocation time -- a hardcoded
# list here would go stale the moment a new alias ships. Only YAML-syntax validity is checked.
set -uo pipefail
cd "$(git rev-parse --show-toplevel 2>/dev/null || echo .)" || exit 1

role_file() {
  case "$1" in
    research) printf '%s' ".claude/agents/researcher.md" ;;
    plan)     printf '%s' ".claude/agents/planner.md" ;;
    exec)     printf '%s' ".claude/agents/executor.md" ;;
    eval)     printf '%s' ".claude/agents/evaluator.md" ;;
    *) return 1 ;;
  esac
}

# --- frontmatter scoping (mirrors sync.sh's C3 fix): only a `model:` line INSIDE the first
# ---...--- block is our config; a stray `model:` in the markdown body is never read or written (M3). ---
has_wellformed_frontmatter() {
  [ "$(sed -n '1p' "$1" 2>/dev/null)" = "---" ] || return 1
  [ "$(grep -c '^---$' "$1" 2>/dev/null)" -ge 2 ] || return 1
}
fm_model_lines() {
  awk 'NR==1 && $0=="---"{infm=1; next} infm && $0=="---"{exit} infm && /^model:/{print}' "$1" 2>/dev/null
}

current_model() {
  fm_model_lines "$1" | head -1 | sed -E 's/^model:[[:space:]]*//'
}

check_not_duplicated() {
  f="$1"
  [ -f "$f" ] || return 0   # a missing file is reported by set_model/remove_model, not here
  n=$(fm_model_lines "$f" | grep -c . 2>/dev/null || true)
  if [ "${n:-0}" -gt 1 ]; then
    echo "models: '$f' has $n frontmatter 'model:' lines (expected 0 or 1) -- fix it by hand first" >&2
    return 1
  fi
  return 0
}

show_all() {
  for r in research plan exec eval; do
    f=$(role_file "$r")
    m=$(current_model "$f")
    if [ -n "$m" ]; then printf '%-9s%s\n' "$r:" "$m"
    else printf '%-9s(inherits session model)\n' "$r:"
    fi
  done
  if [ -n "${CLAUDE_CODE_SUBAGENT_MODEL:-}" ]; then
    echo ""
    echo "WARNING: CLAUDE_CODE_SUBAGENT_MODEL=$CLAUDE_CODE_SUBAGENT_MODEL is set in this shell -- it"
    echo "  overrides ALL FOUR settings above uniformly (env > per-invocation > frontmatter)."
  fi
}

set_model() {
  f="$1"; v="$2"
  if [ ! -f "$f" ]; then
    echo "models: role file '$f' not found -- cannot set its model" >&2
    return 1
  fi
  if ! has_wellformed_frontmatter "$f"; then
    echo "models: '$f' has no well-formed --- frontmatter block -- refusing to set a model: line" >&2
    return 1
  fi
  # Update the model: line INSIDE the frontmatter if one exists, else insert it just before the
  # closing ---. Scoped to the ---...--- block so a stray body 'model:' line is never rewritten (M3).
  # The value is passed via ENVIRON (never awk -v or a sed replacement), so sed metacharacters
  # (& / \) and a literal \n/\b round-trip byte-for-byte with NO escape processing — the v2.1.0
  # injection-hardening guarantee, preserved and now applied to both the update and insert paths.
  if MODELS_VAL="$v" awk '
    NR==1 && $0=="---" { print; infm=1; next }
    infm && $0=="---"  { if (!seen) print "model: " ENVIRON["MODELS_VAL"]; print; infm=0; next }
    infm && /^model:/ && !seen { print "model: " ENVIRON["MODELS_VAL"]; seen=1; next }
    { print }
  ' "$f" > "$f.tmp"; then
    # Preserve the original file's permission bits on the replacement (a plain '>' takes the umask
    # default otherwise).
    mode=$(stat -c '%a' "$f" 2>/dev/null || stat -f '%Lp' "$f" 2>/dev/null)
    [ -n "$mode" ] && chmod "$mode" "$f.tmp" 2>/dev/null
    mv "$f.tmp" "$f"
  else
    rm -f "$f.tmp"
    echo "models: failed to set the model: line in '$f'" >&2
    return 1
  fi
}

remove_model() {
  f="$1"
  # H2: give reset the same guards set_model has — a missing file is a LOUD non-zero, with NO stray
  # .tmp created (the existence check precedes any write), instead of the old silent false-success.
  if [ ! -f "$f" ]; then
    echo "models: role file '$f' not found -- cannot reset its model" >&2
    return 1
  fi
  if ! has_wellformed_frontmatter "$f"; then
    echo "models: '$f' has no well-formed --- frontmatter block -- refusing to modify it" >&2
    return 1
  fi
  # Strip model: lines INSIDE the frontmatter only; a stray body 'model:' is left untouched (M3).
  if awk '
    NR==1 && $0=="---" { print; infm=1; next }
    infm && $0=="---"  { print; infm=0; next }
    infm && /^model:/  { next }
    { print }
  ' "$f" > "$f.tmp"; then
    mode=$(stat -c '%a' "$f" 2>/dev/null || stat -f '%Lp' "$f" 2>/dev/null)
    [ -n "$mode" ] && chmod "$mode" "$f.tmp" 2>/dev/null
    mv "$f.tmp" "$f"
  else
    rm -f "$f.tmp"
    echo "models: failed to remove the model: line from '$f'" >&2
    return 1
  fi
}

is_valid_value() {
  v="$1"
  [ -n "$v" ] || return 1
  case "$v" in *[[:space:]]*) return 1 ;; esac
  case "$v" in *:*) return 1 ;; esac
  case "$v" in *'#'*) return 1 ;; esac
  return 0
}

case "${1:-}" in
  -h|--help)
    echo "usage: models.sh                        show current model config for all 4 /phase stages"
    echo "       models.sh <role>=<model> ...      set one or more (role: research|plan|exec|eval|all)"
    echo "       models.sh reset                   restore each role's shipped default (eval=sonnet, rest inherit)"
    exit 0 ;;
esac

# Fail-safe: refuse to operate on any role file that's already corrupted (more than one
# model: line), rather than silently picking or overwriting one and masking the corruption.
for r in research plan exec eval; do
  check_not_duplicated "$(role_file "$r")" || exit 1
done

# --- no arguments: show and exit ---
if [ "$#" -eq 0 ]; then
  show_all
  exit 0
fi

# --- reset: restore each role to ITS OWN shipped default ---
if [ "$#" -eq 1 ] && [ "$1" = "reset" ]; then
  remove_model "$(role_file research)" || exit 1
  remove_model "$(role_file plan)"     || exit 1
  remove_model "$(role_file exec)"     || exit 1
  set_model "$(role_file eval)" "sonnet" || exit 1
  echo "Reset to shipped defaults:"
  show_all
  exit 0
fi

# --- key=value pairs: validate ALL first, apply NONE until every pair is valid ---
for pair in "$@"; do
  case "$pair" in
    *=*) key="${pair%%=*}"; val="${pair#*=}" ;;
    *) echo "models: unrecognized argument '$pair' (expected key=value, or 'reset')" >&2; exit 1 ;;
  esac
  case "$key" in
    research|plan|exec|eval|all) ;;
    *) echo "models: unrecognized key '$key' (expected research, plan, exec, eval, or all)" >&2; exit 1 ;;
  esac
  is_valid_value "$val" || { echo "models: invalid value for '$key' -- '$val' (must be non-empty, no whitespace, no ':' or '#')" >&2; exit 1; }
done

# Resolve: all=X sets the baseline for all 4; an explicit role=X pair in the SAME invocation
# overrides that role's baseline, applied after the all= sweep regardless of argument order.
R_RESEARCH=""; R_PLAN=""; R_EXEC=""; R_EVAL=""
for pair in "$@"; do
  key="${pair%%=*}"; val="${pair#*=}"
  [ "$key" = "all" ] && { R_RESEARCH="$val"; R_PLAN="$val"; R_EXEC="$val"; R_EVAL="$val"; }
done
for pair in "$@"; do
  key="${pair%%=*}"; val="${pair#*=}"
  case "$key" in
    research) R_RESEARCH="$val" ;;
    plan)     R_PLAN="$val" ;;
    exec)     R_EXEC="$val" ;;
    eval)     R_EVAL="$val" ;;
  esac
done

[ -n "$R_RESEARCH" ] && { set_model "$(role_file research)" "$R_RESEARCH" || exit 1; }
[ -n "$R_PLAN" ]     && { set_model "$(role_file plan)"     "$R_PLAN"     || exit 1; }
[ -n "$R_EXEC" ]     && { set_model "$(role_file exec)"     "$R_EXEC"     || exit 1; }
[ -n "$R_EVAL" ]     && { set_model "$(role_file eval)"     "$R_EVAL"     || exit 1; }

echo "Updated:"
show_all
