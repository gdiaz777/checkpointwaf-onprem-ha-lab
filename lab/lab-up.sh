#!/usr/bin/env bash
# Create the base lab VMs and wait until cloud-init has finished on all of them.
# node3 is NOT created here; it is added later (chapter 10).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
source "$ROOT/lab/inventory.env"
C="$ROOT/lab/create-vm.sh"
$C backend1  waflab "$BACKEND1_IP/24" "$GW_WAF" 1 1024 10
$C backend2  waflab "$BACKEND2_IP/24" "$GW_WAF" 1 1024 10
$C waf-node1 waflab "$NODE1_IP/24"    "$GW_WAF" 2 2048 20
$C waf-node2 waflab "$NODE2_IP/24"    "$GW_WAF" 2 2048 20
$C client    wafout "$CLIENT_IP/24"   "$GW_OUT" 1 1024 10
for vm in backend1 backend2 waf-node1 waf-node2 client; do
  printf 'waiting for %s ' "$vm"
  until "$ROOT/lab/ssh.sh" "$vm" true 2>/dev/null; do printf '.'; sleep 3; done
  "$ROOT/lab/ssh.sh" "$vm" cloud-init status --wait >/dev/null || true
  echo " ready"
done
