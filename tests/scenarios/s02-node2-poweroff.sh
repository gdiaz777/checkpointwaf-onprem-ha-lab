#!/usr/bin/env bash
# S2 — node2 VM powered off hard (it does not hold the VIP).
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
V="sg libvirt -c"
exec "$ROOT/lab/run-scenario.sh" s02-node2-poweroff \
  "$V 'virsh -c qemu:///system destroy waf-node2'" \
  "$V 'virsh -c qemu:///system start waf-node2'; until $ROOT/lab/ssh.sh waf-node2 true 2>/dev/null; do sleep 2; done; echo node2 back" 30 90
