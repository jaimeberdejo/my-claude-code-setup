#!/usr/bin/env bash
# test-high-stakes.sh — assert HIGH_STAKES_RE matches every category the docs promise,
# and does NOT trip on clearly-benign paths. Regression guard for finding #2 (the regex
# used to miss authentication/, oauth/, delete, email, deploy, refund, webhook).

set -uo pipefail
LIB="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/.claude/hooks/_high-stakes.sh"
[ -f "$LIB" ] || { echo "test: cannot find _high-stakes.sh at $LIB" >&2; exit 1; }
# shellcheck disable=SC1090
. "$LIB"

FAILS=0
should_match()   { if high_stakes_match "$1" >/dev/null; then printf '  ✓ matches: %s\n' "$1"; else printf '  ✗ MISSED (should match): %s\n' "$1"; FAILS=$((FAILS+1)); fi; }
should_ignore()  { if high_stakes_match "$1" >/dev/null; then printf '  ✗ FALSE HIT (should ignore): %s\n' "$1"; FAILS=$((FAILS+1)); else printf '  ✓ ignores: %s\n' "$1"; fi; }

echo "high-stakes detection tests"
echo ""
echo "Documented categories (must match):"
for p in \
  "src/auth/session.py" \
  "src/authentication/login.py" \
  "src/authorization/rbac.py" \
  "app/oauth/callback.ts" \
  "services/login/handler.go" \
  "db/migrations/004_drop_users.sql" \
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
  "core/money_utils.py"
do should_match "$p"; done

echo ""
echo "Benign paths (must NOT match):"
for p in \
  "src/utils/strings.py" \
  "tests/test_parser.py" \
  "components/Button.tsx" \
  "docs/README.md" \
  "lib/http_client.go"
do should_ignore "$p"; done

echo ""
if [ "$FAILS" -eq 0 ]; then echo "All high-stakes detection tests passed."; exit 0
else echo "$FAILS detection test(s) FAILED."; exit 1; fi
