#!/usr/bin/env bash
# Power the lab OFF without deleting anything (VMs, disks, agents, configs are kept).
# Usage: lab/lab-stop.sh
# Order: client first, WAF nodes from the last to node1 (the VIP owner goes last,
# so the VIP keeps moving to a live node until the end), then the backends.
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
source "$ROOT/lab/inventory.env"
VIRSH="virsh -c qemu:///system"
nodes=$(for n in $WAF_NODES; do echo "${n%%:*}"; done | tac)
order="client $nodes backend2 backend1"

"$ROOT/lab/host-fw.sh" down
for vm in $order; do
  if $VIRSH domstate "$vm" 2>/dev/null | grep -q running; then
    $VIRSH shutdown "$vm" >/dev/null && echo "shutting down $vm"
  fi
done
# wait up to 90 s for a clean shutdown, then force the stragglers off
for i in $(seq 1 45); do
  running=$(for vm in $order; do $VIRSH domstate "$vm" 2>/dev/null | grep -q running && echo "$vm"; done)
  [ -z "$running" ] && break
  sleep 2
done
for vm in $running; do echo "forcing off $vm"; $VIRSH destroy "$vm" >/dev/null; done
$VIRSH list --all | grep -E "$(echo $order | tr ' ' '|')"
