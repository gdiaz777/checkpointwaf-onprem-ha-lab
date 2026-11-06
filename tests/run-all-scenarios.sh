#!/usr/bin/env bash
# Re-run every measured scenario in the order used by the guide (~20 min).
# Starts from the 3-node cluster with the VIP on waf-node1.
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
S="$ROOT/tests/scenarios"
run() { echo; echo "######## $*"; "$@"; echo "######## exit=$?"; }
run "$ROOT/lab/run-scenario.sh" s11-scale-in "$ROOT/lab/remove-node.sh waf-node3" "true" 5 40 10
run "$ROOT/lab/run-scenario.sh" s00-baseline "true" "true" 5 5 5
for s in s01-agent2-proxy-stop s02-node2-poweroff s05-agent2-5xx s07-agent2-failopen s08-backend1-down s03-node1-poweroff s09-failback s04-haproxy1-hang; do
  run "$S/$s.sh"
done
# put the VIP back on node1 (after S4 it is on node2)
"$ROOT/lab/ssh.sh" waf-node2 'sudo systemctl restart keepalived'; sleep 5
run "$ROOT/lab/run-scenario.sh" s10-scale-out "$ROOT/lab/add-node.sh waf-node3 10.90.20.13" "true" 5 60 10
run "$ROOT/lab/run-scenario.sh" s12-cert-rotation "$ROOT/lab/rotate-app-cert.sh app1" "true" 10 20 10
echo; echo "VIP owner at the end: $("$ROOT/tools/vip-owner.sh" | tr '\n' ' ')"
