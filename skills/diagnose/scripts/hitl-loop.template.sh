#!/usr/bin/env bash
# hitl-loop.template.sh — human-in-the-loop reproduction loop (the `diagnose` skill's way #10,
# the last resort when only a human can drive the reproduction).
# Copy this file, edit the steps between the markers, and run it: the agent runs the script,
# the human follows the prompts in their terminal, and the captured values print as KEY=VALUE
# lines at the end for the agent to parse.
#
# Two helpers:
#   step "<instruction>"       → show the instruction, wait for Enter
#   capture VAR "<question>"   → show the question, read the answer into VAR

set -euo pipefail

step() {
  printf '\n>>> %s\n' "$1"
  read -r -p "    [Enter when done] " _
}

capture() {
  local var="$1" question="$2" answer
  printf '\n>>> %s\n' "$question"
  read -r -p "    > " answer
  printf -v "$var" '%s' "$answer"
}

# --- edit below ---------------------------------------------------------

step "Open the app at http://localhost:3000 and sign in."

capture ERRORED "Click the 'Export' button. Did it throw an error? (y/n)"

capture ERROR_MSG "Paste the error message (or 'none'):"

# --- edit above ---------------------------------------------------------

printf '\n--- Captured ---\n'
printf 'ERRORED=%s\n' "$ERRORED"
printf 'ERROR_MSG=%s\n' "$ERROR_MSG"

# Adapted from mattpocock/skills (MIT) — https://github.com/mattpocock/skills
