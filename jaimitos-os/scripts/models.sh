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

current_model() {
  grep -E '^model:' "$1" 2>/dev/null | head -1 | sed -E 's/^model:[[:space:]]*//'
}

check_not_duplicated() {
  f="$1"
  n=$(grep -cE '^model:' "$f" 2>/dev/null || true)
  if [ "${n:-0}" -gt 1 ]; then
    echo "models: '$f' has $n 'model:' lines (expected 0 or 1) -- fix it by hand first" >&2
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
  if grep -qE '^model:' "$f"; then
    # Escape the value for safe use as sed REPLACEMENT text: unescaped '&' means "the whole
    # match" and a bare '\' starts a backreference/escape in that position, while '/' collides
    # with the s/// delimiter. Escaping all three with a leading backslash makes sed treat them
    # as inert literal characters instead of metacharacters, so the value round-trips verbatim.
    esc=$(printf '%s' "$v" | sed -e 's/[&/\]/\\&/g')
    if sed -i.bak -E "s/^model:.*/model: $esc/" "$f"; then
      rm -f "$f.bak"
    else
      rm -f "$f.bak"
      echo "models: failed to update the model: line in '$f'" >&2
      return 1
    fi
  else
    if [ "$(head -n1 "$f")" != "---" ] || [ "$(grep -c '^---$' "$f")" -lt 2 ]; then
      echo "models: '$f' has no well-formed --- frontmatter block -- refusing to insert a model: line" >&2
      return 1
    fi
    # Pass the value through ENVIRON rather than awk -v: POSIX mandates backslash-escape
    # processing on -v assignments, so a literal \n or \b in the value would be turned into a
    # real newline or backspace byte in the file. ENVIRON values are not escape-processed.
    if MODELS_VAL="$v" awk '
      NR==1 { print; next }
      !done && /^---$/ { print "model: " ENVIRON["MODELS_VAL"]; print; done=1; next }
      { print }
    ' "$f" > "$f.tmp"; then
      # Preserve the original file's permission bits on the replacement (a plain '>' redirect
      # takes the umask default instead), so this path matches sed -i's behavior above.
      mode=$(stat -c '%a' "$f" 2>/dev/null || stat -f '%Lp' "$f" 2>/dev/null)
      [ -n "$mode" ] && chmod "$mode" "$f.tmp" 2>/dev/null
      mv "$f.tmp" "$f"
    else
      rm -f "$f.tmp"
      echo "models: failed to insert a model: line in '$f'" >&2
      return 1
    fi
  fi
}

remove_model() {
  f="$1"
  grep -vE '^model:' "$f" > "$f.tmp" && mv "$f.tmp" "$f"
}

is_valid_value() {
  v="$1"
  [ -n "$v" ] || return 1
  case "$v" in *[[:space:]]*) return 1 ;; esac
  case "$v" in *:*) return 1 ;; esac
  case "$v" in *'#'*) return 1 ;; esac
  return 0
}

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
  remove_model "$(role_file research)"
  remove_model "$(role_file plan)"
  remove_model "$(role_file exec)"
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
