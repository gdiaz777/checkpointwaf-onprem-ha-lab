#!/usr/bin/env bash
# HAProxy on each node (tested from the node itself on 127.0.0.1, since HAProxy
# only listens on the VIP and loopback): TLS with the right cert per SNI, routes by Host to the
# right app, spreads requests across ALL agents, adds X-Served-By, keeps XFF,
# returns 404 for unknown hosts, and its stats show every server UP.
# Usage: tests/test_haproxy.sh [target-ip]   (default: every node in WAF_NODES)
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
source "$ROOT/lab/inventory.env"; source "$ROOT/.env"
CA="$ROOT/certs/ca/ca.crt"
fail=0
ok() { echo "PASS $*"; }; ko() { echo "FAIL $*"; fail=1; }
nodes=$(for n in $WAF_NODES; do echo "${n#*:}"; done)
targets=${1:-$nodes}
n_agents=$(wc -w <<<"$WAF_NODES")
for t in $targets; do
  for app in app1 app2; do
    fqdn=$app.waflab.example
    agents=""
    for i in $(seq 1 $((n_agents * 6))); do
      out=$("$ROOT/lab/ssh.sh" "$t" "curl -s -m 5 -D - --cacert /etc/haproxy/ca.crt --resolve $fqdn:443:127.0.0.1 https://$fqdn/")
      agents+=" $(sed -n 's/.*"client_addr":"\([^"]*\)".*/\1/p' <<<"$out")"
      [ "$i" = 1 ] && { hdr=$(grep -i '^x-served-by:' <<<"$out" | tr -d '\r'); body=$(tail -1 <<<"$out"); }
    done
    python3 -c 'import json,sys; d=json.loads(sys.argv[1]); assert d["app"]==sys.argv[2]; assert d["xff"].split(",")[0].strip()=="127.0.0.1"' "$body" "$app" 2>/dev/null \
      && ok "$t $app routed, xff starts with client" || ko "$t $app routing/xff: ${body:0:120}"
    [ -n "$hdr" ] && ok "$t $app $hdr" || ko "$t $app missing X-Served-By"
    distinct=$(tr ' ' '\n' <<<"$agents" | grep . | sort -u | wc -l)
    [ "$distinct" -eq "$n_agents" ] && ok "$t $app spread over $distinct agents" || ko "$t $app spread over $distinct/$n_agents agents:$(tr ' ' '\n' <<<"$agents" | sort | uniq -c | tr '\n' ' ')"
  done
  code=$("$ROOT/lab/ssh.sh" "$t" "curl -s -o /dev/null -w '%{http_code}' -m 5 -k --resolve other.waflab.example:443:127.0.0.1 https://other.waflab.example/")
  [ "$code" = 404 ] && ok "$t unknown host → 404" || ko "$t unknown host → $code"
done
for n in $WAF_NODES; do
  ip=${n#*:}
  up=$(curl -s -m 5 -u "admin:$HAPROXY_STATS_PASS" "http://$ip:8404/stats;csv" | awk -F, '$1 ~ /^be_app/ && $2 !~ /BACKEND/ && $18 ~ /^UP/' | wc -l)
  [ "$up" -eq $((2 * n_agents)) ] && ok "${n%%:*} stats: $up/$((2 * n_agents)) servers UP" || ko "${n%%:*} stats: $up/$((2 * n_agents)) servers UP"
done
exit $fail
