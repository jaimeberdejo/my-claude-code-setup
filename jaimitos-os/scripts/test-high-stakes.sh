#!/usr/bin/env bash
# test-high-stakes.sh — assert HIGH_STAKES_RE matches every category the docs promise,
# and does NOT trip on clearly-benign paths. Regression guard for finding #2 (the regex
# used to miss authentication/, oauth/, delete, email, deploy, refund, webhook).

set -uo pipefail
LIB="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/.claude/lib/_high-stakes.sh"
[ -f "$LIB" ] || { echo "test: cannot find _high-stakes.sh at $LIB" >&2; exit 1; }
# shellcheck disable=SC1090
. "$LIB"

FAILS=0
should_match()   { if high_stakes_match "$1" >/dev/null; then printf '  ✓ matches: %s\n' "$1"; else printf '  ✗ MISSED (should match): %s\n' "$1"; FAILS=$((FAILS+1)); fi; }
should_ignore()  { if high_stakes_match "$1" >/dev/null; then printf '  ✗ FALSE HIT (should ignore): %s\n' "$1"; FAILS=$((FAILS+1)); else printf '  ✓ ignores: %s\n' "$1"; fi; }

echo "high-stakes detection tests"
echo ""
echo "Documented categories — directory form (must match):"
for p in \
  "src/auth/session.py" \
  "src/authentication/login.py" \
  "src/authorization/rbac.py" \
  "app/oauth/callback.ts" \
  "app/oauth2/callback.ts" \
  "services/auth-service/x.go" \
  "services/auth_service/x.go" \
  "services/login/handler.go" \
  "db/migrations/004_drop_users.sql" \
  "prisma/migrate/x.sql" \
  "payments/charge.py" \
  "billing/invoice.rb" \
  "lib/user_delete.py" \
  "services/deletion/purge.py" \
  "mailer/email_sender.py" \
  "ops/deploy/release.sh" \
  "api/refund_handler.js" \
  "wallet/withdraw.py" \
  "integrations/stripe_webhook.py" \
  "compliance/suitability_check.py" \
  "secrets/loader.py" \
  "secret/key.py" \
  "transaction/ledger.py" \
  "core/money_utils.py"
do should_match "$p"; done

echo ""
echo "Documented categories — SINGLE-FILE module form (must match; regression for the .ext anchor):"
for p in \
  "src/auth.py" "app/oauth.ts" "services/login.go" "core/session.rb" \
  "models/account.py" "billing.py" "wallet.py" "ledger.py" "kyc.py" \
  "compliance.py" "suitability.py" "transactions.py" "session-store.ts"
do should_match "$p"; done

echo ""
echo "Benign paths (must NOT match — keep the widened anchor tight):"
for p in \
  "src/utils/strings.py" \
  "tests/test_parser.py" \
  "components/Button.tsx" \
  "docs/README.md" \
  "lib/http_client.go" \
  "accounting/reports.py" \
  "src/accountant.py" \
  "src/healthcheck.py"
do should_ignore "$p"; done

echo ""
echo "Fail-safe: an empty/unset HIGH_STAKES_RE must treat ALL paths as high-stakes (never fail open):"
(
  unset HIGH_STAKES_RE
  if high_stakes_match "any/ordinary/path.py" >/dev/null 2>&1; then printf '  ✓ unset regex fails SAFE (matches)\n'
  else printf '  ✗ unset regex FAILED OPEN (matched nothing)\n'; exit 1; fi
) || FAILS=$((FAILS+1))

echo ""
echo "Content-level detection — destructive operations in a benignly-named file (must match):"
content_match()  { if high_stakes_content_match "$1" >/dev/null; then printf '  ✓ content matches: %s\n' "$1"; else printf '  ✗ MISSED content (should match): %s\n' "$1"; FAILS=$((FAILS+1)); fi; }
content_ignore() { if high_stakes_content_match "$1" >/dev/null; then printf '  ✗ FALSE content HIT (should ignore): %s\n' "$1"; FAILS=$((FAILS+1)); else printf '  ✓ ignores content: %s\n' "$1"; fi; }
content_match 'cursor.execute("DROP TABLE users")'
content_match 'DELETE FROM sessions WHERE id = 1'
content_match 'TRUNCATE TABLE audit_log'
content_match 'os.system("reboot now")'
content_match 'subprocess.run(cmd, shell=True)'
content_match 'value = eval(user_input)'
content_match 'subprocess.run("rm -rf /tmp/cache")'
content_match 'git push origin main --force'
content_match 'git commit --no-verify'

echo ""
echo "Content-level — web-framework DELETE routes (must match; found missing via dogfooding,"
echo "a real DELETE /admin/... endpoint tripped neither the path nor the old content matcher):"
content_match '@app.delete("/admin/traces/{id}")'
content_match "@router.delete('/x')"
content_match 'methods=["DELETE", "GET"]'
content_match "app.delete('/admin/traces/:id', handler)"   # Express-style route registration

echo ""
echo "Content-level — benign code that must NOT trip the content matcher:"
content_ignore 'result = retrieval(query)'        # contains "eval(" only inside a word
content_ignore 'df = format_table(rows)'           # "TABLE" but not DROP/TRUNCATE
content_ignore 'items.remove(stale_entry)'         # "rm" only inside a word
content_ignore 'user = get_account(account_id)'
content_ignore 'return shell_path == expected'     # "shell" but not shell=True
content_ignore 'model.eval()'                      # method call, not bare eval( — must not trip
content_ignore 'self.encoder.eval()'               # dotted method call (PyTorch idiom)
content_ignore 'registry.delete(fixture_id)'       # .delete(VAR) — a plain method call by id,
                                                    # not route registration (no string literal)
content_ignore 'user.delete_notes()'               # different method name entirely ("delete_notes")

echo ""
echo "Reviewer suppression marker — CONTENT scanner only (must exempt ONLY the marked line,"
echo "and only when a real reason follows the colon):"
content_match 'rm -f known_file.env  # cleanup, no marker present — must still match'
content_ignore 'rm -f known_file.env  # high-stakes-ok: regenerable local file, not user data'
content_match 'rm -f known_file.env  # high-stakes-ok:'                 # bare marker, no reason
content_match 'rm -f known_file.env  # high-stakes-ok:   '              # colon then only whitespace

echo ""
echo "Suppression marker must NOT reach the path/keyword matcher — that gate stays unbypassable:"
should_match "payments/charge.py  # high-stakes-ok: this is a path, not a diff line anyway"

echo ""
echo "Suppression is per-line: an unmarked destructive line elsewhere in the same text must"
echo "still be caught even when another line in the same blob is legitimately suppressed:"
multi=$'rm -f known_file.env  # high-stakes-ok: regenerable local file\nos.system("reboot now")'
if high_stakes_content_match "$multi" | grep -q 'os.system'; then
  printf '  ✓ unmarked line in a mixed blob still matches\n'
else
  printf '  ✗ unmarked line in a mixed blob was WRONGLY suppressed\n'; FAILS=$((FAILS+1))
fi
if high_stakes_content_match "$multi" | grep -q 'known_file.env'; then
  printf '  ✗ marked line in a mixed blob was WRONGLY still flagged\n'; FAILS=$((FAILS+1))
else
  printf '  ✓ marked line in a mixed blob was correctly suppressed\n'
fi

echo ""
echo "Path allowlist — a separate, git-tracked FILE (.claude/high-stakes-path-allowlist) that"
echo "narrowly suppresses the PATH/keyword matcher for an EXACT path with a real reason. Uses an"
echo "isolated tempdir so the repo's real (empty-template) allowlist is never touched by these tests:"
ALLOW_WORK="$(mktemp -d 2>/dev/null || mktemp -d -t hs-allowlist)"
mkdir -p "$ALLOW_WORK/.claude"
trap 'rm -rf "$ALLOW_WORK" 2>/dev/null' EXIT

ALLOW_FILE="$ALLOW_WORK/.claude/high-stakes-path-allowlist"
set_allowlist()   { printf '%s\n' "$1" > "$ALLOW_FILE"; }
clear_allowlist() { rm -f "$ALLOW_FILE"; }

allow_should_ignore() { # path expected to be SUPPRESSED (not flagged) given the current allowlist
  if ( cd "$ALLOW_WORK" && high_stakes_match "$1" >/dev/null ); then
    printf '  ✗ FALSE HIT (should be suppressed by allowlist): %s\n' "$1"; FAILS=$((FAILS+1))
  else
    printf '  ✓ suppressed by allowlist: %s\n' "$1"
  fi
}
allow_should_match() { # path expected to remain FLAGGED despite the current allowlist
  if ( cd "$ALLOW_WORK" && high_stakes_match "$1" >/dev/null ); then
    printf '  ✓ still flagged: %s\n' "$1"
  else
    printf '  ✗ MISSED (should still be flagged): %s\n' "$1"; FAILS=$((FAILS+1))
  fi
}

echo "  a path matching the regex, with a real reason in the allowlist -> suppressed:"
set_allowlist 'docs/ADR-001-decimal-money-as-yaml-strings.md: doc file, "money" substring only, no code'
allow_should_ignore "docs/ADR-001-decimal-money-as-yaml-strings.md"

echo "  same path, but the allowlist entry has NO reason (bare colon) -> still flagged:"
set_allowlist 'docs/ADR-001-decimal-money-as-yaml-strings.md:'
allow_should_match "docs/ADR-001-decimal-money-as-yaml-strings.md"

echo "  same path, allowlist entry colon followed only by whitespace -> still flagged:"
set_allowlist 'docs/ADR-001-decimal-money-as-yaml-strings.md:   '
allow_should_match "docs/ADR-001-decimal-money-as-yaml-strings.md"

echo "  same path, bare entry with no colon at all -> still flagged:"
set_allowlist 'docs/ADR-001-decimal-money-as-yaml-strings.md'
allow_should_match "docs/ADR-001-decimal-money-as-yaml-strings.md"

echo "  an allowlist entry for path A must NOT suppress a different path B:"
set_allowlist 'docs/ADR-001-decimal-money-as-yaml-strings.md: real reason'
allow_should_match "docs/other-money-file.md"

echo "  adversarial: matching must be EXACT, not prefix/substring — an entry for path A must"
echo "  still flag any path B for which A is a prefix, a suffix, or a directory-prefix of B"
echo "  (mutation guard: would fail if _high_stakes_allowlisted() were ever changed from"
echo "  [ \"\$entry\" = \"\$path\" ] to a prefix/substring test like \`case \"\$path\" in \"\$entry\"*)\`):"
set_allowlist 'docs/money.md: real reason, adversarial prefix/substring regression guard'
allow_should_ignore "docs/money.md"          # exact entry -> suppressed, as expected
allow_should_match "docs/money.md.bak"       # entry is a PREFIX of this path -> must still flag
allow_should_match "xdocs/money.md"          # entry is a SUFFIX of this path -> must still flag
allow_should_match "docs/money.md/sub.txt"   # entry is a DIR-PREFIX of this path -> must still flag

echo "  missing allowlist file entirely -> path matching behaves exactly as before:"
clear_allowlist
allow_should_match "docs/ADR-001-decimal-money-as-yaml-strings.md"

echo ""
echo "Content matcher and path matcher remain independent — an active PATH-allowlist entry must"
echo "not affect content matching (the reverse direction — a content marker not affecting the path"
echo "matcher — is already asserted above via should_match(\"...high-stakes-ok:...\") and is untouched):"
set_allowlist 'payments/charge.py: unrelated allowlist entry, irrelevant to content matching'
content_match 'DELETE FROM sessions WHERE id = 1'
clear_allowlist

echo ""
if [ "$FAILS" -eq 0 ]; then echo "All high-stakes detection tests passed."; exit 0
else echo "$FAILS detection test(s) FAILED."; exit 1; fi
