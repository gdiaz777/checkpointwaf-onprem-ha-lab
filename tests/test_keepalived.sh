#!/usr/bin/env bash
# keepalived: exactly one node holds the VIP, the expected one (default: first
# node in WAF_NODES), and both apps answer through the VIP.
# Usage: tests/test_keepalived.sh [expected-owner]
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
source "$ROOT/lab/inventory.env"
CA="$ROOT/certs/ca/ca.crt"
want=${1:-$(set -- $WAF_NODES; echo "${1%%:*}")}
fail=0
owners=$("$ROOT/tools/vip-owner.sh"); rc=$?
[ $rc -eq 0 ] && [ "$owners" = "$want" ] && echo "PASS VIP owner is $owners" || { echo "FAIL VIP owners='$(echo $owners)' rc=$rc want=$want"; fail=1; }
for app in app1 app2; do
  body=$(curl -s -m 5 --cacert "$CA" --resolve "$app.waflab.example:443:$VIP" "https://$app.waflab.example/")
  [[ $body == *"\"app\":\"$app\""* ]] && echo "PASS $app via VIP" || { echo "FAIL $app via VIP: ${body:0:80}"; fail=1; }
done
exit $fail
