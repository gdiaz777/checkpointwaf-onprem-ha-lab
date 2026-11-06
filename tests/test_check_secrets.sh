#!/usr/bin/env bash
# Tests for tools/check-secrets.sh. Run: bash tests/test_check_secrets.sh
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CHECK="$ROOT/tools/check-secrets.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
fail=0

expect() { # expect <expected_exit> <description> <file>
  "$CHECK" "$3" >/dev/null 2>&1
  local rc=$?
  if [ "$rc" -eq "$1" ]; then echo "PASS $2"; else echo "FAIL $2 (exit $rc, want $1)"; fail=1; fi
}

printf 'token: cp-%s\n' "$(printf 'a%.0s' $(seq 1 64))" > "$TMP/token.txt"
printf -- '-----BEGIN PRIVATE KEY-----\nMIIE\n-----END PRIVATE KEY-----\n' > "$TMP/key.txt"
printf 'WAF_TOKEN=<your-token>\n' > "$TMP/.env"
printf 'WAF_TOKEN=<your-token>\nnothing secret here\n' > "$TMP/clean.txt"
printf 'WAF_TOKEN=abc123realvalue\n' > "$TMP/realtoken.txt"
printf 'this mentions acmecorp somewhere\n' > "$TMP/word.txt"
printf 'acmecorp\n' > "$TMP/forbidden.txt"

printf '%s\n' 'Rule: PEM headers like `-----BEGIN PRIVATE KEY-----` in docs' 'grep -c "^WAF_TOKEN=.\+" .env' '`WAF_TOKEN=` followed by a value' > "$TMP/doc.md"
expect 0 "ignores pattern mentions in documentation" "$TMP/doc.md"
expect 1 "detects token-like string" "$TMP/token.txt"
# realistic shape: cp- prefix + hyphenated segments, ~75 chars (fake values)
printf 'sudo ./nanoegg --install --token cp-0f3a9c2e-7b1d-4e8a-9c55-1a2b3c4d5e6f1a2b3c4d-5e6f-7a8b-9c0d1e2f3a4b5c\n' > "$TMP/realshape.md"
expect 1 "detects real-shaped (hyphenated) token in a doc" "$TMP/realshape.md"
expect 1 "detects PEM private key" "$TMP/key.txt"
expect 1 "detects .env file by name" "$TMP/.env"
expect 1 "detects real WAF_TOKEN value" "$TMP/realtoken.txt"
printf 'WAF_TOKEN="abc123realvalue"\n' > "$TMP/quoted.txt"
expect 1 "detects quoted real WAF_TOKEN value" "$TMP/quoted.txt"
printf 'WAF_TOKEN="<your-token>"\n' > "$TMP/quotedph.txt"
expect 0 "accepts quoted placeholder" "$TMP/quotedph.txt"
expect 0 "accepts placeholder and clean file" "$TMP/clean.txt"
FORBIDDEN_WORDS_FILE="$TMP/forbidden.txt" expect 1 "detects forbidden word" "$TMP/word.txt"
expect 0 "forbidden word ignored without list" "$TMP/word.txt"

# pre-commit mode (no args): scans the STAGED content, including renames
R="$TMP/repo"; git init -q "$R"; git -C "$R" config user.email t@t; git -C "$R" config user.name t
printf 'hello\n' > "$R/notes.txt"; git -C "$R" add notes.txt; git -C "$R" commit -qm init
git -C "$R" mv notes.txt notes2.txt; printf 'WAF_TOKEN=abc123realvalue\n' >> "$R/notes2.txt"; git -C "$R" add notes2.txt
( cd "$R" && "$ROOT/tools/check-secrets.sh" >/dev/null 2>&1 ); rc=$?
[ $rc -eq 1 ] && echo "PASS staged rename with token is caught" || { echo "FAIL staged rename with token not caught (rc=$rc)"; fail=1; }
git -C "$R" reset -q --hard; printf 'WAF_TOKEN=abc123realvalue\n' > "$R/staged.txt"; git -C "$R" add staged.txt; printf 'clean now\n' > "$R/staged.txt"
( cd "$R" && "$ROOT/tools/check-secrets.sh" >/dev/null 2>&1 ); rc=$?
[ $rc -eq 1 ] && echo "PASS staged blob is scanned, not the working copy" || { echo "FAIL working copy scanned instead of staged blob (rc=$rc)"; fail=1; }
exit $fail
