#!/usr/bin/env bash
# Delete ALL lab VMs (networks are kept). Destructive.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
for vm in client waf-node3 waf-node2 waf-node1 backend2 backend1; do "$ROOT/lab/destroy-vm.sh" "$vm"; done
