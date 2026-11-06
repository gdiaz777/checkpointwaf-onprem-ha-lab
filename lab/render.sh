#!/usr/bin/env bash
# Render a config template for one node from lab/inventory.env.
# Usage: lab/render.sh <template> <node-name>
# Placeholders: __NAME__ for every variable in inventory.env (e.g. __VIP__),
# plus __NODE_NAME__, __NODE_IP__, __NODE_PRIORITY__, __PEERS__ (other nodes' IPs,
# one per line) and __HAPROXY_SERVERS__ (one "server" line per WAF node).
set -euo pipefail
TPL=$1 NODE=$2
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
set -a   # export everything sourced below so the renderer can read it
source "${INVENTORY:-$ROOT/lab/inventory.env}"
if [ -z "${INVENTORY:-}" ] && [ -f "$ROOT/.env" ]; then source "$ROOT/.env"; fi
set +a
python3 - "$TPL" "$NODE" <<'PY'
import os, re, sys
tpl, node = sys.argv[1], sys.argv[2]
env = dict(os.environ)
nodes = [n.split(":") for n in env["WAF_NODES"].split()]
names = [n for n, _ in nodes]
if node not in names:
    sys.exit(f"render: {node} is not in WAF_NODES ({' '.join(names)})")
ip = dict(nodes)[node]
idx = names.index(node)
extra = {
    "NODE_NAME": node,
    "NODE_IP": ip,
    "NODE_PRIORITY": str(110 - 10 * idx),
    "PEERS": "\n".join(f"        {p}" for n, p in nodes if n != node),
    "HAPROXY_SERVERS": "\n".join(f"    server {n} {p}:{env['AGENT_PORT']}" for n, p in nodes),
}
text = open(tpl).read()
def sub(m):
    k = m.group(1)
    if k in extra: return extra[k]
    if k in env: return env[k]
    sys.exit(f"render: unknown placeholder __{k}__")
print(re.sub(r"__([A-Z0-9_]+)__", sub, text), end="")
PY
