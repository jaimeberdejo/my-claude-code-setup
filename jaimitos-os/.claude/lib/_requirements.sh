#!/usr/bin/env bash
# _requirements.sh — SHARED, focused validator for native requirement ids (sourced, not a hook).
#
# This is the smallest helper that owns REQ/AC/OBJ id SEMANTICS, so lint-roadmap.sh stays the
# roadmap-schema linter and does NOT become the parser/owner of docs/SPEC.md. lint-roadmap.sh
# sources this file and calls `requirements_lint` only when a phase actually carries a
# `Requirements:` line; the function itself is a no-op (rc 0, no output) when no phase declares one,
# so it is inert in a default project.
#
# It validates STRUCTURE only — never semantic satisfaction, completeness, measurability, or test
# quality (those stay evaluator + human judgment). Concretely it checks:
#   - malformed ids, and duplicate ids inside one roadmap phase's `Requirements:` block
#   - each roadmap-referenced id resolves to a definition in docs/SPEC.md — but only for a phase
#     whose source IS the spec (its `Sources:` names docs/SPEC.md, or it has no `Sources:` and the
#     spec has a Requirements section). A phase sourced from an external file is left to the
#     evaluator to resolve.
#   - in docs/SPEC.md: duplicate REQ/OBJ ids; AC ids duplicated ANYWHERE (globally unique); and a
#     `Status: Approved` requirement whose text still carries `[NEEDS CLARIFICATION` (a strict
#     validation failure — a Proposed/Clarifying one may keep the marker).
#
# Native ids are REQ-###, AC-###, OBJ-### (the ### is one or more digits). An external id
# (FR-001, REQ-AR-001, JIRA-1234) is accepted STRUCTURALLY — a generic PREFIX-### shape — only when
# the authoritative source defines it; this helper hard-codes the semantics of no external prefix.
#
# Pure awk/grep, bash-3.2 / BSD-userland / non-root mawk safe. Regexes go to awk via ENVIRON, never
# -v (awk processes escapes in a -v assignment and would mangle the `[`/`\`); ENVIRON is literal.

# A native id: exactly one of REQ/AC/OBJ, then a dash and digits.
REQ_NATIVE_RE='^(REQ|AC|OBJ)-[0-9]+$'
# A structurally valid id of any prefix: an uppercase-alnum prefix (optionally hyphen-segmented),
# ending in a numeric segment. Matches REQ-001, AC-002, FR-001, REQ-AR-001, JIRA-1234.
REQ_GENERIC_RE='^[A-Z][A-Z0-9]*(-[A-Z0-9]+)*-[0-9]+$'
export REQ_NATIVE_RE REQ_GENERIC_RE

# Task-line detection reuses the ONE shared task regex from _roadmap.sh — the project forbids
# hand-writing a task-line regex outside that file (test-roadmap-lib.sh enforces it). Source it if a
# caller has not already; if it is unavailable the task-detection rule simply stays inert.
if [ -z "${ROADMAP_TASK_RE:-}" ]; then
  _req_dir="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" 2>/dev/null && pwd)" || _req_dir=""
  if [ -n "$_req_dir" ] && [ -f "$_req_dir/_roadmap.sh" ]; then . "$_req_dir/_roadmap.sh" 2>/dev/null || true; fi
fi

# requirements_lint <roadmap-file> [spec-file]
#   Prints "  ! <problem>" lines for every id problem found. Default spec-file is SPEC.md beside the
#   roadmap. rc 0 = clean (INCLUDING "no Requirements: block anywhere" — inert). rc 1 = problems.
requirements_lint() {
  local road="$1" spec="${2:-}"
  [ -f "$road" ] || return 0
  if [ -z "$spec" ]; then spec="$(dirname "$road")/SPEC.md"; fi

  # Fast inert path: if no phase declares a Requirements: line, there is nothing native to validate.
  grep -qE '^[[:space:]]*Requirements:[[:space:]]*$' "$road" 2>/dev/null || return 0

  local specarg=""
  [ -f "$spec" ] && specarg="$spec"

  local out
  out=$(SPECF="$specarg" GEN_RE="$REQ_GENERIC_RE" NAT_RE="$REQ_NATIVE_RE" TASK_RE="${ROADMAP_TASK_RE:-}" awk '
    function prob(m) { problems[++np] = "  ! " m }

    # Strip <!-- ... --> (single- and multi-line) using a persistent in-comment state, so a
    # commented example in the SPEC template is never read as a real definition.
    function stripcom(line,   out,p) {
      out=""
      while (1) {
        if (incom) { p=index(line,"-->"); if (p==0) return out; line=substr(line,p+3); incom=0 }
        else       { p=index(line,"<!--"); if (p==0) return out line; out=out substr(line,1,p-1); line=substr(line,p+4); incom=1 }
      }
    }
    function firsttok(s,   a,n) { gsub(/^[[:space:]]+/,"",s); n=split(s,a,/[[:space:]]/); return a[1] }

    # flush the current SPEC requirement block: enforce Approved + [NEEDS CLARIFICATION]
    function flush_req() {
      if (cur_req != "" && cur_status == "Approved" && cur_clar)
        prob("requirement " cur_req " is Status: Approved but still carries [NEEDS CLARIFICATION] in docs/SPEC.md")
      cur_req=""; cur_status=""; cur_clar=0
    }
    # flush the current ROADMAP phase: cross-ref its refs against SPEC defs when spec-sourced
    function flush_phase(   i,id) {
      if (cur_phase == "" ) return
      spec_sourced = 0
      if (phase_sources ~ /docs\/SPEC\.md/) spec_sourced = 1
      else if (!phase_has_sources && spec_has_req) spec_sourced = 1
      if (spec_sourced && SPEC != "")
        for (i=1;i<=nref;i++) { id=ref[i]; if (!(id in defall)) prob("phase references " id " not defined in docs/SPEC.md — " cur_phase) }
      cur_phase=""; phase_sources=""; phase_has_sources=0; in_src=0; in_req=0; nref=0; delete refseen
    }

    BEGIN { SPEC=ENVIRON["SPECF"]; GEN=ENVIRON["GEN_RE"]; NAT=ENVIRON["NAT_RE"]; np=0; incom=0 }

    # ---------------- SPEC pass (ARGV[1], read first) ----------------
    SPEC != "" && FILENAME==SPEC {
      a = stripcom($0)
      if (a ~ /^[[:space:]]*$/) next
      # A requirement/objective definition heading: "### REQ-001 — title" / "### OBJ-002 — ..."
      if (a ~ /^###[[:space:]]+[A-Za-z]/) {
        flush_req()
        h=a; sub(/^###[[:space:]]+/,"",h); id=firsttok(h)
        if (id ~ /^(REQ|OBJ)-/ || id ~ /^AC-/) {
          spec_has_req=1
          if (id !~ GEN) prob("malformed id in docs/SPEC.md heading: " id)
          else {
            if (id ~ /^AC-/) { if (id in acall) prob("duplicate AC id " id " (AC ids must be unique across the whole spec)"); acall[id]=1 }
            else if (id in defall) prob("duplicate id " id " defined in docs/SPEC.md")
            defall[id]=1
          }
          if (id ~ /^(REQ|OBJ)-/) cur_req=id
        }
        next
      }
      # Status line inside a requirement block
      if (cur_req != "" && a ~ /^[[:space:]]*Status:[[:space:]]*/) {
        s=a; sub(/^[[:space:]]*Status:[[:space:]]*/,"",s); s=firsttok(s); cur_status=s; next
      }
      if (cur_req != "" && a ~ /\[NEEDS CLARIFICATION/) cur_clar=1
      # An acceptance-criterion definition bullet: "- AC-001: ..."
      if (a ~ /^[[:space:]]*-[[:space:]]+AC-/) {
        spec_has_req=1
        b=a; sub(/^[[:space:]]*-[[:space:]]+/,"",b); id=firsttok(b); sub(/:.*/,"",id)
        if (id !~ GEN) prob("malformed AC id in docs/SPEC.md: " id)
        else { if (id in acall) prob("duplicate AC id " id " (AC ids must be unique across the whole spec)"); acall[id]=1; defall[id]=1 }
      }
      next
    }

    # ---------------- ROADMAP pass ----------------
    /^## / { flush_phase(); flush_req(); cur_phase=$0; next }
    cur_phase=="" { next }
    /^[[:space:]]*Sources:[[:space:]]*$/  { in_src=1; in_req=0; phase_has_sources=1; next }
    /^[[:space:]]*Requirements:[[:space:]]*$/ { in_req=1; in_src=0; next }
    # collect Sources: bullets
    in_src && /^[[:space:]]*-[[:space:]]/ { phase_sources = phase_sources " " $0; next }
    # a task line ends any Sources/Requirements block; it is never a requirement ref (shared regex)
    ENVIRON["TASK_RE"] != "" && $0 ~ ENVIRON["TASK_RE"] { in_src=0; in_req=0; next }
    # collect Requirements: ref bullets
    in_req && /^[[:space:]]*-[[:space:]]/ {
      b=$0; sub(/^[[:space:]]*-[[:space:]]+/,"",b); id=firsttok(b)
      if (id !~ GEN) prob("malformed requirement id in phase: " id " — " cur_phase)
      else { if (id in refseen) prob("duplicate id " id " in one phase Requirements: block — " cur_phase); refseen[id]=1; ref[++nref]=id }
      next
    }
    # any other line ends the inline Sources/Requirements bullet region
    { in_src=0; in_req=0 }

    END { flush_phase(); flush_req(); for (i=1;i<=np;i++) print problems[i]; exit (np>0?1:0) }
  ' ${specarg:+"$specarg"} "$road")
  local rc=$?
  [ -n "$out" ] && printf '%s\n' "$out"
  return $rc
}

return 0 2>/dev/null || exit 0
