#!/usr/bin/env bash
# S3 — node1 VM (VIP holder) powered off hard. The VIP must move to node2.
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
V="sg libvirt -c"
exec "$ROOT/lab/run-scenario.sh" s03-node1-poweroff \
  "$V 'virsh -c qemu:///system destroy waf-node1'" \
  "$V 'virsh -c qemu:///system start waf-node1'; until $ROOT/lab/ssh.sh waf-node1 true 2>/dev/null; do sleep 2; done; echo node1 back" 30 90
