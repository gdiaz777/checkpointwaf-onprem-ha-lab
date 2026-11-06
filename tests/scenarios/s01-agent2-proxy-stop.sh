#!/usr/bin/env bash
# S1 — the agent's data path on node2 goes down (its NGINX stops); node2 VM stays up.
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
exec "$ROOT/lab/run-scenario.sh" s01-agent2-proxy-stop \
  "$ROOT/lab/ssh.sh waf-node2 'sudo systemctl stop nginx; systemctl is-active nginx'" \
  "$ROOT/lab/ssh.sh waf-node2 'sudo systemctl start nginx; systemctl is-active nginx'" 30 60
