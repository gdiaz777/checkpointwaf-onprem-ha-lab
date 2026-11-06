#!/usr/bin/env bash
# S9 — planned failback: the VIP is on node2 (after S3) and stays there because of
# nopreempt. Move it back to node1 on purpose by restarting keepalived on node2.
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
exec "$ROOT/lab/run-scenario.sh" s09-failback \
  "$ROOT/lab/ssh.sh waf-node2 'sudo systemctl restart keepalived; echo keepalived restarted on node2'" \
  "true" 20 20
