#!/usr/bin/env bash
# Each WAF node's NGINX (agent) proxies both apps on AGENT_PORT with TLS.
# EXPECT_WAF=1 also requires that an XSS probe is blocked (agent installed, Prevent mode).
# Usage: tests/test_agent_proxy.sh [node-name...]   (default: all WAF_NODES)
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
source "$ROOT/lab/inventory.env"
CA="$ROOT/certs/ca/ca.crt"
fail=0
nodes=("$@"); [ ${#nodes[@]} -gt 0 ] || nodes=($(for n in $WAF_NODES; do echo "${n%%:*}"; done))
for node in "${nodes[@]}"; do
  ip=$(for n in $WAF_NODES; do [ "${n%%:*}" = "$node" ] && echo "${n#*:}"; done)
  for app in app1 app2; do
    fqdn=$app.waflab.example
    body=$(curl -s -m 5 --cacert "$CA" --resolve "$fqdn:$AGENT_PORT:$ip" "https://$fqdn:$AGENT_PORT/")
    if python3 -c 'import json,sys; d=json.loads(sys.argv[1]); sys.exit(0 if d["app"]==sys.argv[2] and d["client_addr"]==sys.argv[3] else 1)' "$body" "$app" "$ip" 2>/dev/null; then
      echo "PASS $node $app proxied"
    else echo "FAIL $node $app proxied: ${body:0:100}"; fail=1; fi
    if [ "${EXPECT_WAF:-0}" = 1 ]; then
      code=$(curl -s -o /dev/null -w '%{http_code}' -m 5 --cacert "$CA" --resolve "$fqdn:$AGENT_PORT:$ip" \
        "https://$fqdn:$AGENT_PORT/?q=%3Cscript%3Ealert(1)%3C%2Fscript%3E")
      [ "$code" = 403 ] && echo "PASS $node $app XSS blocked (403)" || { echo "FAIL $node $app XSS not blocked (HTTP $code)"; fail=1; }
    fi
  done
done
exit $fail
