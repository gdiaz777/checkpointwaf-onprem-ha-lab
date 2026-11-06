#!/usr/bin/env bash
# S4 — HAProxy on node1 (VIP holder) hangs (SIGSTOP); node1's agent stays healthy.
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
exec "$ROOT/lab/run-scenario.sh" s04-haproxy1-hang \
  "$ROOT/lab/ssh.sh waf-node1 'sudo pkill -STOP -x haproxy; echo haproxy stopped with SIGSTOP'" \
  "$ROOT/lab/ssh.sh waf-node1 'sudo pkill -CONT -x haproxy; echo haproxy resumed'" 30 40
