#!/usr/bin/env bash
# test-secret-scan.sh — fixtures for _secret-scan.sh. Asserts the broadened content regex
# catches the credential shapes a project most often leaks (Stripe/Google/URL creds, …)
# AND that benign content (plain URLs, example files) does NOT trip it (a false hit blocks
# a legitimate commit, so the no-false-positive cases matter as much as the catches).

set -uo pipefail
LIB="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/.claude/lib/_secret-scan.sh"
[ -f "$LIB" ] || { echo "test: cannot find _secret-scan.sh at $LIB" >&2; exit 1; }
command -v git >/dev/null 2>&1 || { echo "test: git required"; exit 1; }
# shellcheck disable=SC1090
. "$LIB"

WORK="$(mktemp -d 2>/dev/null || mktemp -d -t secretscan)"
trap 'rm -rf "$WORK"' EXIT
cd "$WORK" || exit 1
git init -q && git config user.email t@t.t && git config user.name t
# An initial commit so `git reset` (used between fixtures to clear the index) resolves
# HEAD — without it, reset fails and staged files leak from one case into the next.
git commit -q --allow-empty -m init

FAILS=0
# stage_only <path> <content>: reset the index, write+stage one file.
stage_only() { git reset -q 2>/dev/null; rm -f f_*; printf '%s\n' "$2" > "$1"; git add "$1" 2>/dev/null; }

want_secret() {  # $1 desc, $2 path, $3 content
  stage_only "$2" "$3"
  if secret_scan_staged >/dev/null; then printf '  ✗ MISSED secret: %s\n' "$1"; FAILS=$((FAILS+1));
  else printf '  ✓ caught: %s\n' "$1"; fi
}
want_clean() {   # $1 desc, $2 path, $3 content
  stage_only "$2" "$3"
  # secret_scan_staged: 0 = clean, non-zero = secret found.
  if secret_scan_staged >/dev/null; then printf '  ✓ clean: %s\n' "$1";
  else printf '  ✗ FALSE HIT: %s\n' "$1"; FAILS=$((FAILS+1)); fi
}

echo "secret-scan fixture tests"
echo ""
echo "Must be caught:"
want_secret "Stripe live key"      "f_stripe.py" 'STRIPE="sk_live_51HxxxxxxxxxxxxxxxxxxYz"'
want_secret "Stripe webhook secret" "f_whsec.py" 'WH=whsec_AbCdEfGhIjKlMnOpQrStUvWx'
want_secret "Google API key"       "f_g.py"      'KEY = "AIzaSyA1234567890abcdefghijklmnopqrstuv"'
want_secret "DB URL with password" "f_db.py"     'DATABASE_URL="postgres://admin:Hunter2@db.prod/app"'
want_secret "AWS access key id"    "f_aws.txt"   'AKIAIOSFODNN7EXAMPLE'
want_secret "AWS 40-char secret"   "f_awssec.py" 'aws_secret_access_key = wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY'
want_secret "AWS secret (UPPER)"   "f_awsu.py"   'AWS_SECRET_ACCESS_KEY="wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY"'
want_secret "OpenAI legacy key"    "f_oai.py"    'OPENAI="sk-abcdefghijklmnopqrstuvwxyz0123"'
want_secret "OpenAI project key"   "f_oaip.py"   'OPENAI=sk-proj-abcdefghijklmnopqrstuvwxyz1234567890'
want_secret "Anthropic key"        "f_ant.py"    'ANTHROPIC_API_KEY="sk-ant-api03-abcdefghijklmnopqrstuvwxyz1234567890"'
want_secret "Google OAuth secret"  "f_gocspx.py" 'GOOGLE_SECRET=GOCSPX-abcdefghijklmnopqrstuv'
want_secret "DigitalOcean token"   "f_do.py"     'DO=dop_v1_abcdef0123456789abcdef0123456789abcdef0123456789abcdef01'
want_secret "JWT"                  "f_jwt.txt"   'Bearer eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiIxMjM0In0.dozjgNryP4J3jVmNHl0w5N'
want_secret "GitHub fine PAT"      "f_ghpat.py"  'GH=github_pat_11ABCDEFG0aBcDeFgHiJ_KLmnOpQrStUvWxYz0123456789AbCdEfGhIj'
want_secret "GitLab PAT"           "f_glpat.py"  'GITLAB_TOKEN=glpat-AbCdEfGhIjKlMnOpQrSt'
want_secret "npm token"            "f_npm.txt"   '_authToken=npm_AbCdEfGhIjKlMnOpQrStUvWxYz0123456789'
want_secret "SendGrid key"         "f_sg.py"     'SG_KEY=SG.AbCdEfGhIjKlMnOp.AbCdEfGhIjKlMnOpQrStUvWxYz0123456789ABCDEFG'
want_secret "Azure AccountKey"     "f_az.txt"    'conn=AccountKey=abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOP1234567890ab==;x'
want_secret "Mailgun key"          "f_mg.py"     'MAILGUN=key-0123456789abcdef0123456789abcdef'
want_secret "PGP private key block" "f_pgp.asc"  '-----BEGIN PGP PRIVATE KEY BLOCK-----'
want_secret "RSA PEM (multiline)"  "f_pem.txt"   'x\n-----BEGIN RSA PRIVATE KEY-----\nMIIabc\n-----END RSA PRIVATE KEY-----\n'
want_secret "secret filename .env" ".env"        'X=1'
want_secret ".npmrc filename"      ".npmrc"      '//r/:_authToken=abc'

echo ""
echo "Must stay clean (false hit would block a legitimate commit):"
want_clean  "plain https URL"      "f_url.py"    'API = "https://api.example.com/v1/users"'
want_clean  "localhost with port"  "f_lh.py"     'DEV = "http://localhost:3000/health"'
want_clean  "credential-less SSH"  "f_ssh.txt"   'git@github.com:org/repo.git'
want_clean  ".env.example template" ".env.example" 'STRIPE=sk_live_xxx_placeholder_here'
want_clean  "ordinary code"        "f_ok.py"     'def add(a, b): return a + b'
want_clean  "word ending in ask-"  "f_ask.py"    'x = "ask-permissionsdialogcontrollerxyzabc"'
want_clean  "risk- prefix token"   "f_risk.py"   'risk_assessmentframeworkmoduleloaderxyz = 1'
want_clean  "task-proj- not a key" "f_tp.py"     'x = "task-proj-mypipelinetokenidentifier1234"'
want_clean  "prose key-value"      "f_kv.md"     'These are key-value pairs in the config.'
want_clean  "git SHA"              "f_sha.txt"   'commit a1b2c3d4e5f6a7b8c9d0e1f2a3b4c5d6e7f8a9b0'
want_clean  "uuid"                 "f_uuid.py"   'id = "550e8400-e29b-41d4-a716-446655440000"'
want_clean  "css class sk-"        "f_css.js"    'cls = "sk-loading-spinner-wrapper-large-variant"'

echo ""
echo "secret_scan_diff range handling (fail-closed on unresolvable range):"
git reset -q 2>/dev/null; rm -f f_*
printf 'ok\n' > r_ok.txt;  git add r_ok.txt;  git commit -q -m c1
BASE=$(git rev-parse HEAD)
printf 'clean\n'  > r_ok2.txt; git add r_ok2.txt; git commit -q -m c2
secret_scan_diff "$BASE..HEAD" >/dev/null 2>&1; rc=$?
[ "$rc" -eq 0 ] && echo "  ✓ valid clean range → clean (0)" || { echo "  ✗ valid clean range rc=$rc"; FAILS=$((FAILS+1)); }
secret_scan_diff "deadbeefdeadbeefdeadbeefdeadbeefdeadbeef..HEAD" >/dev/null 2>&1; rc=$?
[ "$rc" -eq 2 ] && echo "  ✓ unresolvable range → fail-closed (2)" || { echo "  ✗ unresolvable range rc=$rc (expected 2 — FAIL-OPEN REGRESSION)"; FAILS=$((FAILS+1)); }
secret_scan_diff "" >/dev/null 2>&1; rc=$?
[ "$rc" -eq 2 ] && echo "  ✓ empty range → fail-closed (2)" || { echo "  ✗ empty range rc=$rc"; FAILS=$((FAILS+1)); }
printf 'AKIAIOSFODNN7EXAMPLE\n' > r_secret.txt; git add r_secret.txt; git commit -q -m c3
secret_scan_diff "$BASE..HEAD" >/dev/null 2>&1; rc=$?
[ "$rc" -eq 1 ] && echo "  ✓ range containing an AWS key → secret (1)" || { echo "  ✗ range with secret rc=$rc"; FAILS=$((FAILS+1)); }

echo ""
echo "LEAN_SECRET_SCANNER backend dispatch (contract + 0/1/2 exit codes preserved; fail-closed):"
# HEAD now: c3 (AWS key) on top of c2, c1, init. BASE = HEAD at the point captured above (c1's ref).
DIRTY_RANGE="$BASE..HEAD"                        # spans the commit that added the AWS key
CLEAN_RANGE="$BASE..$(git rev-parse 'HEAD~1')"   # BASE..(commit before the secret) → no secret

# 1 — default (unset) == the regex backend, unchanged.
( unset LEAN_SECRET_SCANNER; secret_scan_diff "$DIRTY_RANGE" >/dev/null 2>&1; exit $? ); rc=$?
[ "$rc" -eq 1 ] && echo "  ✓ default (unset) backend = regex, still catches the AWS key (1)" || { echo "  ✗ default backend changed (rc=$rc)"; FAILS=$((FAILS+1)); }
LEAN_SECRET_SCANNER=regex secret_scan_diff "$CLEAN_RANGE" >/dev/null 2>&1; rc=$?
[ "$rc" -eq 0 ] && echo "  ✓ LEAN_SECRET_SCANNER=regex on a clean range → clean (0)" || { echo "  ✗ regex clean range rc=$rc"; FAILS=$((FAILS+1)); }

# 2 — unknown backend → fail-closed (2), never a silent regex fallback.
LEAN_SECRET_SCANNER=bogus secret_scan_diff "$CLEAN_RANGE" >/dev/null 2>&1; rc=$?
[ "$rc" -eq 2 ] && echo "  ✓ unknown backend → fail-closed (2)" || { echo "  ✗ unknown backend rc=$rc (expected 2)"; FAILS=$((FAILS+1)); }

# 3 — gitleaks selected but binary absent → fail-closed (2), no downgrade to regex.
if ! command -v gitleaks >/dev/null 2>&1; then
  LEAN_SECRET_SCANNER=gitleaks secret_scan_diff "$CLEAN_RANGE" >"$WORK/gl.out" 2>&1; rc=$?
  { [ "$rc" -eq 2 ] && grep -qi "not installed" "$WORK/gl.out"; } \
    && echo "  ✓ gitleaks backend + binary absent → fail-closed (2), no silent regex fallback" \
    || { echo "  ✗ gitleaks-absent not fail-closed (rc=$rc)"; FAILS=$((FAILS+1)); }
else
  echo "  · SKIP gitleaks-absent case (gitleaks is installed on this host)"
fi

# 4 — a STUB gitleaks on PATH translates its findings + exit code to the lib's contract.
STUBDIR="$WORK/stubbin"; mkdir -p "$STUBDIR"
cat > "$STUBDIR/gitleaks" <<'EOF'
#!/usr/bin/env bash
rp=""; for a in "$@"; do case "$a" in --report-path=*) rp="${a#--report-path=}";; esac; done
[ -n "$rp" ] && printf '[{"RuleID":"aws-key","Description":"AWS key","File":"r_secret.txt","StartLine":1}]\n' > "$rp"
exit "${STUB_GITLEAKS_RC:-1}"
EOF
chmod +x "$STUBDIR/gitleaks"
out=$(PATH="$STUBDIR:$PATH" LEAN_SECRET_SCANNER=gitleaks STUB_GITLEAKS_RC=1 secret_scan_diff "$CLEAN_RANGE" 2>&1); rc=$?
{ [ "$rc" -eq 1 ] && printf '%s\n' "$out" | grep -q "\[gitleaks\] aws-key in r_secret.txt"; } \
  && echo "  ✓ stub gitleaks exit 1 → findings translated to the lib format, rc 1" \
  || { echo "  ✗ stub gitleaks leak path broken (rc=$rc): $out"; FAILS=$((FAILS+1)); }
PATH="$STUBDIR:$PATH" LEAN_SECRET_SCANNER=gitleaks STUB_GITLEAKS_RC=0 secret_scan_diff "$CLEAN_RANGE" >/dev/null 2>&1; rc=$?
[ "$rc" -eq 0 ] && echo "  ✓ stub gitleaks exit 0 → clean, rc 0" || { echo "  ✗ stub gitleaks clean path rc=$rc"; FAILS=$((FAILS+1)); }
PATH="$STUBDIR:$PATH" LEAN_SECRET_SCANNER=gitleaks STUB_GITLEAKS_RC=2 secret_scan_diff "$CLEAN_RANGE" >/dev/null 2>&1; rc=$?
[ "$rc" -eq 2 ] && echo "  ✓ stub gitleaks error exit → fail-closed (2)" || { echo "  ✗ stub gitleaks error path rc=$rc (expected 2)"; FAILS=$((FAILS+1)); }

echo ""
if [ "$FAILS" -eq 0 ]; then echo "All secret-scan fixture tests passed."; exit 0
else echo "$FAILS fixture test(s) FAILED."; exit 1; fi
