#!/usr/bin/env bash
# Install a git pre-commit hook that blocks commits containing secrets.
set -euo pipefail
ROOT="$(git rev-parse --show-toplevel)"
cat > "$ROOT/.git/hooks/pre-commit" <<'HOOK'
#!/usr/bin/env bash
ROOT="$(git rev-parse --show-toplevel)"
if ! "$ROOT/tools/check-secrets.sh"; then
  echo "pre-commit: possible secret found (see above). Commit aborted." >&2
  exit 1
fi
HOOK
chmod +x "$ROOT/.git/hooks/pre-commit"
echo "pre-commit hook installed"
