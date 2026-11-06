#!/usr/bin/env bash
# The host acts as the perimeter firewall:
#  - client (10.90.30.10) reaches both apps at 10.90.30.1:443 (DNAT → VIP), with
#    its real IP preserved (first X-Forwarded-For entry = client IP, no SNAT),
#  - client cannot reach anything else inside (e.g. a backend directly),
#  - client has Internet access and a synchronized clock,
#  - the host LAN address 192.168.1.20:443 is also DNAT'd to the VIP.
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
source "$ROOT/lab/inventory.env"
C() { "$ROOT/lab/ssh.sh" client "$@"; }
fail=0; ok() { echo "PASS $*"; }; ko() { echo "FAIL $*"; fail=1; }
for app in app1 app2; do
  body=$(C "curl -s -m 5 --cacert /home/lab/ca.crt https://$app.waflab.example/")
  xff1=$(python3 -c 'import json,sys; print(json.loads(sys.argv[1])["xff"].split(",")[0].strip())' "$body" 2>/dev/null)
  [ "$xff1" = "$CLIENT_IP" ] && ok "client → $app via firewall, real IP preserved ($xff1)" || ko "client → $app: ${body:0:120}"
done
body=$(C "curl -s -m 5 --cacert /home/lab/ca.crt -H 'X-Forwarded-For: 6.6.6.6' https://app1.waflab.example/")
xff1=$(python3 -c 'import json,sys; print(json.loads(sys.argv[1])["xff"].split(",")[0].strip())' "$body" 2>/dev/null)
[ "$xff1" = "$CLIENT_IP" ] && ok "client-supplied X-Forwarded-For is discarded (first entry = $xff1)" || ko "XFF spoofable: backend saw '${body:0:140}'"
code=$(C "curl -s -o /dev/null -m 3 -w '%{http_code}' -k https://$BACKEND1_IP/")
[ "$code" = 000 ] && ok "client cannot reach backend1 directly" || ko "client reached backend1 directly (HTTP $code)"
code=$(C "curl -s -o /dev/null -m 3 -w '%{http_code}' -k https://$NODE1_IP:$AGENT_PORT/")
[ "$code" = 000 ] && ok "client cannot reach an agent directly" || ko "client reached agent directly (HTTP $code)"
code=$(C "curl -s -o /dev/null -m 5 -w '%{http_code}' https://portal.checkpoint.com")
[ "$code" != 000 ] && ok "client has Internet (HTTP $code)" || ko "client has no Internet"
C 'timedatectl' | grep -q 'synchronized: yes' && ok "client clock synchronized" || ko "client clock not synchronized"
body=$(curl -s -m 5 --cacert "$ROOT/certs/ca/ca.crt" --resolve "app1.waflab.example:443:192.168.1.20" https://app1.waflab.example/)
[[ $body == *'"app":"app1"'* ]] && ok "host LAN 192.168.1.20:443 → VIP" || ko "host LAN DNAT: ${body:0:80}"
exit $fail
