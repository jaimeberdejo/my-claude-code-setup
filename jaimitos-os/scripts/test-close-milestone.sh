#!/usr/bin/env bash
# test-close-milestone.sh — the milestone-closure gate must REFUSE while open items or
# unresolved findings remain, archive a finished roadmap (preserving history), scaffold a fresh
# one, reset the STATE auto-block, and be safe to re-run. Runs the REAL script in temp repos.
# Also covers the non-fatal '## Ownership gaps' notice: it must surface open entries without
# ever blocking the close, stay silent when the heading is absent, and stay silent when the
# heading holds only the empty-section '-' placeholder.
set -uo pipefail
SCAFFOLD="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CLOSE="$SCAFFOLD/scripts/close-milestone.sh"
[ -f "$CLOSE" ] || { echo "test: missing $CLOSE" >&2; exit 1; }
command -v git >/dev/null 2>&1 || { echo "test: git required"; exit 1; }

FAILS=0
pass() { printf '  ✓ %s\n' "$1"; }
fail() { printf '  ✗ %s\n' "$1"; FAILS=$((FAILS+1)); }

WORK="$(mktemp -d 2>/dev/null || mktemp -d -t leanstack-ms)"
trap 'rm -rf "$WORK" 2>/dev/null' EXIT

# mkrepo <name> <roadmap-body>: repo with scripts/close-milestone.sh + a STATE auto-block.
mkrepo() {
  REPO="$WORK/$1"; rm -rf "$REPO"; mkdir -p "$REPO/scripts" "$REPO/docs" "$REPO/.claude/lib"
  cp "$CLOSE" "$REPO/scripts/close-milestone.sh"
  # close-milestone now classifies the first open phase's Mode via the shared parser.
  cp "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/.claude/lib/_roadmap.sh" "$REPO/.claude/lib/_roadmap.sh"
  printf '%s\n' "$2" > "$REPO/docs/ROADMAP.md"
  printf '# State\n\n## Auto status\n<!-- lean:auto:begin -->\n- something\n<!-- lean:auto:end -->\n\n## Now\nhi\n' > "$REPO/docs/STATE.md"
  printf 'NEXT_FINDINGS.md\n' > "$REPO/.gitignore"
  ( cd "$REPO" && git init -q && git config user.email t@t.t && git config user.name t \
      && git add -A && git commit -q -m init )
}
runclose() { ( cd "$1" && shift && bash scripts/close-milestone.sh "$@" ) >"$WORK/out" 2>&1; echo $?; }

DONE='## Phase 1 — Work

- [x] do the work

## Phase 2 — More

- [x] more work'
OPEN='## Phase 1 — Work

- [x] done

- [ ] still open'

# Real-world fixture: the `roadmap` skill's own output format prepends this exact legend line
# to every roadmap it writes — permanently present for the life of the milestone. A naive
# substring grep for "- [ ]" (or "- [x]") matches INSIDE this line too, since it isn't anchored
# to actual list-item lines.
LEGEND='> `- [ ]` = todo, `- [x]` = done. The /phase command and hooks read these.'
DONE_WITH_LEGEND="$LEGEND

$DONE"

echo "milestone closure tests"; echo ""

# 1 — open items → refuses, nothing archived.
mkrepo m1 "$OPEN"; rc=$(runclose "$REPO")
{ [ "$rc" = 1 ] && [ ! -d "$REPO/docs/archive" ] && [ -f "$REPO/docs/ROADMAP.md" ]; } \
  && pass "open items → refuses, roadmap not archived" || fail "open-items closure mishandled (rc=$rc)"

# 2 — all done but NEXT_FINDINGS.md present → refuses.
mkrepo m2 "$DONE"; printf 'unresolved\n' > "$REPO/NEXT_FINDINGS.md"; rc=$(runclose "$REPO")
{ [ "$rc" = 1 ] && [ ! -d "$REPO/docs/archive" ]; } \
  && pass "unresolved NEXT_FINDINGS → refuses" || fail "findings-present closure mishandled (rc=$rc)"

# 3 — all done, no findings → archives, fresh roadmap, STATE auto-block reset.
mkrepo m3 "$DONE"; rc=$(runclose "$REPO" --name v1)
arch="$REPO/docs/archive/ROADMAP-v1.md"
{ [ "$rc" = 0 ] && [ -f "$arch" ] && grep -q 'Phase 1 — Work' "$arch"; } \
  && pass "complete roadmap → archived with history" || fail "did not archive complete roadmap (rc=$rc)"
{ [ -f "$REPO/docs/ROADMAP.md" ] && ! grep -qE '\- \[[ xX]\]' "$REPO/docs/ROADMAP.md"; } \
  && pass "fresh empty roadmap created (no checkboxes)" || fail "fresh roadmap not created/clean"
grep -q 'Milestone v1 closed' "$REPO/docs/STATE.md" && pass "STATE auto-block reset to next-scope" || fail "STATE auto-block not reset"

# 4 — re-run after a close (fresh empty roadmap) → refuses 'nothing to close' (idempotent-safe).
rc=$(runclose "$REPO" --name v1)
{ [ "$rc" = 1 ] && grep -q 'nothing to close' "$WORK/out"; } \
  && pass "re-run on empty roadmap → refuses (no duplicate archive)" || fail "re-run not idempotent-safe (rc=$rc)"

# 5 — the `roadmap` skill's own legend line ("`- [ ]` = todo, `- [x]` = done...") must NOT be
# mistaken for an open item — a fully-done roadmap in the REAL generated format must close
# cleanly, not be falsely refused as "open items remain."
mkrepo m5 "$DONE_WITH_LEGEND"; rc=$(runclose "$REPO" --name v2)
{ [ "$rc" = 0 ] && [ -f "$REPO/docs/archive/ROADMAP-v2.md" ]; } \
  && pass "roadmap-skill legend line is not mistaken for an open item (closes cleanly)" \
  || fail "false-positive 'open items remain' from legend line (rc=$rc)"

# 6 — non-empty '## Ownership gaps' entries in STATE.md → still closes (rc 0) AND the notice is
# surfaced in the combined output (teach-back debt must not go silently unmentioned at close).
mkrepo m6 "$DONE"
printf '\n## Ownership gaps\n- teach-back skipped for Phase 2 (auth flow)\n' >> "$REPO/docs/STATE.md"
rc=$(runclose "$REPO" --name v3)
{ [ "$rc" = 0 ] && grep -q "open '## Ownership gaps' entries" "$WORK/out"; } \
  && pass "open Ownership-gaps entries → closes AND surfaces non-fatal notice" \
  || fail "Ownership-gaps notice missing or close wrongly blocked (rc=$rc)"

# 7 — no '## Ownership gaps' heading at all (the scaffold default) → closes, no notice. Section
# absent must be treated exactly like section empty.
mkrepo m7 "$DONE"; rc=$(runclose "$REPO" --name v4)
{ [ "$rc" = 0 ] && ! grep -q "Ownership gaps" "$WORK/out"; } \
  && pass "no Ownership-gaps heading → closes silently (no notice)" \
  || fail "missing heading wrongly produced a notice, or close blocked (rc=$rc)"

# 8 — '## Ownership gaps' heading present but only the lone '-' empty-section placeholder (the
# STATE.md convention also used by '## Open questions') → closes, no notice.
mkrepo m8 "$DONE"
printf '\n## Ownership gaps\n-\n' >> "$REPO/docs/STATE.md"
rc=$(runclose "$REPO" --name v5)
{ [ "$rc" = 0 ] && ! grep -q "Ownership gaps" "$WORK/out"; } \
  && pass "Ownership-gaps heading with only '-' placeholder → closes silently (no notice)" \
  || fail "placeholder-only section wrongly produced a notice, or close blocked (rc=$rc)"

# 9 — a differently-named heading that merely shares the '## Ownership gaps' PREFIX (e.g.
# '## Ownership gaps and blockers') must NOT be mistaken for the canonical section — the match
# must be an exact whole-line match, not a prefix match. A non-empty entry under it must produce
# NO notice, since it isn't the section the notice is documented to surface.
mkrepo m9 "$DONE"
printf '\n## Ownership gaps and blockers\n- something unresolved\n' >> "$REPO/docs/STATE.md"
rc=$(runclose "$REPO" --name v6)
{ [ "$rc" = 0 ] && ! grep -q "Ownership gaps" "$WORK/out"; } \
  && pass "differently-named heading is not prefix-matched as '## Ownership gaps' (no notice)" \
  || fail "prefix-matched a differently-named heading, or close wrongly blocked (rc=$rc)"

# 10 — first open phase is SUPERVISED (v2.4.0): close still refuses, but the message classifies it as
# supervised-awaiting-approval, names the phase, and points at tick.sh --supervised-approved (so a
# supervised phase is no longer a milestone dead end — it just needs an explicit human approval first).
SUP_OPEN='## Phase 1 — Auth

- [ ] wire login
Mode: supervised'
mkrepo m10 "$SUP_OPEN"; rc=$(runclose "$REPO")
{ [ "$rc" = 1 ] && [ ! -d "$REPO/docs/archive" ] && grep -q "SUPERVISED and awaiting" "$WORK/out" \
    && grep -q -- "--supervised-approved" "$WORK/out" && grep -q "Phase 1 — Auth" "$WORK/out"; } \
  && pass "open supervised phase → can't close; message names it + the --supervised-approved path" \
  || fail "supervised-phase classifier message missing or close wrongly allowed (rc=$rc)"

# 11 — an approved+ticked supervised phase is '- [x]' and no longer blocks the close (nothing special
# about a supervised phase once it is legitimately ticked).
SUP_DONE='## Phase 1 — Auth

- [x] wire login
Mode: supervised'
mkrepo m11 "$SUP_DONE"; rc=$(runclose "$REPO" --name v7)
{ [ "$rc" = 0 ] && [ -f "$REPO/docs/archive/ROADMAP-v7.md" ] && grep -q 'Phase 1 — Auth' "$REPO/docs/archive/ROADMAP-v7.md"; } \
  && pass "approved+ticked supervised phase (- [x]) no longer blocks → closes" \
  || fail "ticked supervised phase wrongly blocked the close (rc=$rc)"

# --- architecture staleness notice (v2.11.0) ------------------------------------------------------
# Per-phase review structurally cannot see ten individually-fine phases composing into a
# pass-through layer. The milestone boundary is the only place that view exists — and until now
# close-milestone.sh checked open items, findings and roadmap shape, but NEVER architecture.
# The notice is NON-FATAL, exactly like the Ownership-gaps one: it informs, it never blocks.
#
# "This milestone" = since the previous close (the commit that created the newest
# docs/archive/ROADMAP-*.md), so the notice fires when a WHOLE milestone was built without ever
# refreshing the map — not on every close, which would be noise nobody reads.

# arch_repo <name>: a closable repo whose previous milestone was already archived.
arch_repo() {
  mkrepo "$1" "$DONE"
  ( cd "$REPO" && mkdir -p docs/archive && printf '# old\n' > docs/archive/ROADMAP-m1.md \
      && git add -A && git commit -q -m "close previous milestone" )
}
commit_code()  { ( cd "$1" && mkdir -p src && printf 'x=%s\n' "$2" > "src/app$2.py" && git add -A && git commit -q -m "code $2" ); }
commit_arch()  { ( cd "$1" && printf '# Architecture\n\n## Module map\n- %s\n' "$2" > docs/ARCHITECTURE.md && git add -A && git commit -q -m "mapme refresh" ); }

# 12 — a whole milestone of code landed and docs/ARCHITECTURE.md was never refreshed → NOTE, but
# the close still succeeds (rc 0). This is the gap v2.11.0 exists to close.
# Built by hand (not arch_repo) so the map is written BEFORE the archive commit that starts this
# milestone — i.e. the map is a leftover from the PREVIOUS milestone, which is the real scenario.
mkrepo m12 "$DONE"
( cd "$REPO" && printf '# Architecture\n\n## Module map\n- old\n' > docs/ARCHITECTURE.md && git add -A && git commit -q -m "arch (previous milestone)" )
( cd "$REPO" && mkdir -p docs/archive && printf '# old\n' > docs/archive/ROADMAP-m1.md && git add -A && git commit -q -m "close previous milestone" )
commit_code "$REPO" 1; commit_code "$REPO" 2
rc=$(runclose "$REPO" --name v1)
{ [ "$rc" = 0 ] && grep -q "NOTE — docs/ARCHITECTURE.md was not refreshed" "$WORK/out" && grep -q "mapme" "$WORK/out"; } \
  && pass "stale architecture map across a whole milestone → NOTE (names mapme), close still succeeds" \
  || fail "stale architecture map was not surfaced at the milestone boundary (rc=$rc)"

# 13 — the map WAS refreshed during this milestone → silent. The notice must not cry wolf, or it
# becomes the kind of always-on warning people learn to scroll past.
arch_repo m13
commit_code "$REPO" 1
commit_arch "$REPO" "fresh"
rc=$(runclose "$REPO" --name v1)
{ [ "$rc" = 0 ] && ! grep -q "NOTE — docs/ARCHITECTURE.md" "$WORK/out"; } \
  && pass "architecture map refreshed during the milestone → no notice (never cries wolf)" \
  || fail "notice fired even though ARCHITECTURE.md was refreshed this milestone (rc=$rc)"

# 14 — no architecture map at all, but code shipped → NOTE pointing at mapme.
arch_repo m14
commit_code "$REPO" 1
rc=$(runclose "$REPO" --name v1)
{ [ "$rc" = 0 ] && grep -q "NOTE — no docs/ARCHITECTURE.md" "$WORK/out" && grep -q "mapme" "$WORK/out"; } \
  && pass "no architecture map + shipped code → NOTE (names mapme), close still succeeds" \
  || fail "missing architecture map was not surfaced (rc=$rc)"

# 15 — a docs-only milestone touched no code → nothing to re-map, so no notice.
arch_repo m15
( cd "$REPO" && printf 'note\n' >> docs/STATE.md && git add -A && git commit -q -m "docs only" )
rc=$(runclose "$REPO" --name v1)
{ [ "$rc" = 0 ] && ! grep -q "NOTE — no docs/ARCHITECTURE.md" "$WORK/out" && ! grep -q "NOTE — docs/ARCHITECTURE.md" "$WORK/out"; } \
  && pass "docs-only milestone (no code commits) → no architecture notice" \
  || fail "architecture notice fired on a docs-only milestone (rc=$rc)"

# 16 — the notice NEVER blocks: a repo that would otherwise close cleanly still closes, and the
# roadmap is really archived, even with the notice printed.
arch_repo m16
commit_code "$REPO" 1
rc=$(runclose "$REPO" --name v9)
{ [ "$rc" = 0 ] && [ -f "$REPO/docs/archive/ROADMAP-v9.md" ] && [ -f "$REPO/docs/ROADMAP.md" ]; } \
  && pass "architecture notice is non-fatal — roadmap still archived and a fresh one scaffolded" \
  || fail "architecture notice blocked the close (rc=$rc)"

echo ""
echo "--name validation (v2.17): usage errors exit 2, a missing value cannot hang, unsafe labels refuse"
# A watchdog-wrapped runner: a --name with no value used to infinite-loop on `shift 2`; SIGALRM (rc 142)
# would flag a regression instead of hanging the whole suite. A clean usage refusal returns 2.
run_to() { ( cd "$1" && shift && perl -e 'alarm shift; exec @ARGV' 5 bash scripts/close-milestone.sh "$@" ) >"$WORK/out" 2>&1; echo $?; }

mkrepo mv1 "$DONE"; rc=$(run_to "$REPO" --name)
{ [ "$rc" = 2 ] && grep -q 'requires a value' "$WORK/out"; } \
  && pass "--name with no value → exit 2 (no infinite loop)" || fail "--name missing value mishandled (rc=$rc)"

mkrepo mv2 "$DONE"; rc=$(runclose "$REPO" --name '   ')
{ [ "$rc" = 2 ] && grep -q 'empty after trimming' "$WORK/out" && [ ! -d "$REPO/docs/archive" ]; } \
  && pass "--name all-whitespace → exit 2, nothing archived" || fail "empty --name mishandled (rc=$rc)"

mkrepo mv3 "$DONE"; rc=$(runclose "$REPO" --name 'a..b')
{ [ "$rc" = 2 ] && grep -qi "not contain '..'" "$WORK/out" && [ ! -d "$REPO/docs/archive" ]; } \
  && pass "--name with '..' → exit 2 (no traversal), nothing archived" || fail "traversal --name mishandled (rc=$rc)"

mkrepo mv4 "$DONE"; rc=$(runclose "$REPO" --name 'a/b')
{ [ "$rc" = 2 ] && grep -qi 'path separator' "$WORK/out"; } \
  && pass "--name with a path separator → exit 2" || fail "path-sep --name mishandled (rc=$rc)"

mkrepo mv5 "$DONE"; rc=$(runclose "$REPO" --bogus)
[ "$rc" = 2 ] && pass "unknown argument → exit 2 (usage)" || fail "unknown arg did not exit 2 (rc=$rc)"

mkrepo mv6 "$DONE"; rc=$(runclose "$REPO" --name "$(printf 'a\nb')")
{ [ "$rc" = 2 ] && [ ! -d "$REPO/docs/archive" ]; } \
  && pass "--name with an embedded newline → exit 2, nothing archived" || fail "newline --name mishandled (rc=$rc)"

echo ""
echo "Transactional close (v2.17): a failure during apply restores ROADMAP + STATE byte-for-byte"
# Inject an archive-move failure: make docs/archive a READ-ONLY directory so the mv into it fails
# AFTER the backups + temp preparation. The transaction must roll back — restore ROADMAP and STATE
# exactly, create no archive, exit non-zero.
mkrepo mt1 "$DONE"
R_BEFORE=$( { shasum -a 256 "$REPO/docs/ROADMAP.md" 2>/dev/null || sha256sum "$REPO/docs/ROADMAP.md"; } | cut -d' ' -f1)
S_BEFORE=$( { shasum -a 256 "$REPO/docs/STATE.md"   2>/dev/null || sha256sum "$REPO/docs/STATE.md";   } | cut -d' ' -f1)
mkdir "$REPO/docs/archive"; chmod 555 "$REPO/docs/archive"
rc=$(runclose "$REPO" --name v1)
R_AFTER=$( { shasum -a 256 "$REPO/docs/ROADMAP.md" 2>/dev/null || sha256sum "$REPO/docs/ROADMAP.md"; } | cut -d' ' -f1)
S_AFTER=$( { shasum -a 256 "$REPO/docs/STATE.md"   2>/dev/null || sha256sum "$REPO/docs/STATE.md";   } | cut -d' ' -f1)
chmod 755 "$REPO/docs/archive" 2>/dev/null || true
archived_count=$(find "$REPO/docs/archive" -type f 2>/dev/null | wc -l | tr -d ' ')
{ [ "$rc" = 1 ] && [ "$R_AFTER" = "$R_BEFORE" ] && [ "$S_AFTER" = "$S_BEFORE" ] && [ "$archived_count" = 0 ] && grep -q 'rolled back' "$WORK/out"; } \
  && pass "archive-move failure → rolled back byte-for-byte, no archive, exit 1" \
  || fail "transaction did not roll back cleanly (rc=$rc, R:$([ "$R_AFTER" = "$R_BEFORE" ] && echo ok || echo CHANGED) S:$([ "$S_AFTER" = "$S_BEFORE" ] && echo ok || echo CHANGED) archived=$archived_count)"

echo ""
if [ "$FAILS" -eq 0 ]; then echo "All milestone closure tests passed."; exit 0
else echo "$FAILS milestone test(s) FAILED."; echo "--- last output ---"; tail -n 15 "$WORK/out" 2>/dev/null; exit 1; fi
