#!/usr/bin/env bash
# Scan files for secrets before they reach a public repository.
#
# Usage: tools/check-secrets.sh [file...]
#   With no arguments, scans the files staged in git.
# Exit 0 = clean, 1 = findings (printed as file:line:rule).
#
# Optional forbidden-word list (one word per line, case-insensitive), for
# names that must never appear in the repo. The list itself is git-ignored:
#   FORBIDDEN_WORDS_FILE (default: tools/forbidden-words.txt)
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WORDS="${FORBIDDEN_WORDS_FILE:-$ROOT/tools/forbidden-words.txt}"

found=0
STAGED=0
if [ $# -eq 0 ]; then
  # pre-commit mode: scan the STAGED blobs (what will be committed), renames included
  STAGED=1
  mapfile -t files < <(git diff --cached --name-only --diff-filter=ACMR)
else
  files=("$@")
fi
TMPD=$(mktemp -d); trap 'rm -rf "$TMPD"' EXIT

hit() { echo "$1:$2:$3"; found=1; }

scan() { # scan <file-to-read> <name-to-report>
  local f=$1 name=$2 n w
  case "$(basename "$name")" in
    .env.example) ;;
    .env|.env.*|*.key|*.p12) hit "$name" 0 secret-file-name ;;
  esac
  # this script and its test contain the patterns on purpose
  case "$name" in *check-secrets.sh|*test_check_secrets.sh) return ;; esac
  while IFS=: read -r n _; do hit "$name" "$n" pem-private-key; done < <(grep -nI -E -- '^-----BEGIN ([A-Z]+ )?PRIVATE KEY-----' "$f")
  while IFS=: read -r n _; do hit "$name" "$n" token-value; done < <(grep -nI -E 'WAF_TOKEN=["'\'']?[A-Za-z0-9_.-]{8,}' "$f")
  # Check Point WAF tokens: "cp-" + hyphenated alphanumeric segments (~75 chars)
  while IFS=: read -r n _; do hit "$name" "$n" token-like; done < <(grep -nI -E '\bcp-[A-Za-z0-9-]{30,}' "$f")
  if [ -s "$WORDS" ]; then
    while read -r w; do
      [ -n "$w" ] || continue
      while IFS=: read -r n _; do hit "$name" "$n" forbidden-word; done < <(grep -nIi -F -- "$w" "$f")
    done < "$WORDS"
  fi
}

for f in "${files[@]}"; do
  if [ "$STAGED" = 1 ]; then
    t="$TMPD/blob"; git show ":$f" > "$t" 2>/dev/null || continue
    scan "$t" "$f"
  else
    [ -f "$f" ] || continue
    scan "$f" "$f"
  fi
done
exit $found
