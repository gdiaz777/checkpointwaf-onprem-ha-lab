#!/usr/bin/env bash
# Every node presents the SAME current certificate for each app, on both TLS layers,
# matching certs/apps/<fqdn>.crt:
#   haproxy  = HAProxy, checked from the node itself on 127.0.0.1:443 (it listens on VIP + loopback)
#   agent    = the agent's NGINX on <node IP>:AGENT_PORT
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
source "$ROOT/lab/inventory.env"
fail=0
serial_of() { openssl x509 -noout -serial 2>/dev/null | cut -d= -f2; }
for app in "$APP1_FQDN" "$APP2_FQDN"; do
  want=$(openssl x509 -in "$ROOT/certs/apps/$app.crt" -noout -serial | cut -d= -f2)
  for n in $WAF_NODES; do
    node=${n%%:*} ip=${n#*:}
    got_h=$("$ROOT/lab/ssh.sh" "$node" "timeout 5 openssl s_client -connect 127.0.0.1:443 -servername $app </dev/null 2>/dev/null" | serial_of)
    got_a=$(timeout 5 openssl s_client -connect "$ip:$AGENT_PORT" -servername "$app" </dev/null 2>/dev/null | serial_of)
    for pair in "haproxy:$got_h" "agent:$got_a"; do
      layer=${pair%%:*} got=${pair#*:}
      [ "$got" = "$want" ] && echo "PASS $node $layer $app serial …${got: -8}" || { echo "FAIL $node $layer $app serial '…${got: -8}' want …${want: -8}"; fail=1; }
    done
  done
done
exit $fail
