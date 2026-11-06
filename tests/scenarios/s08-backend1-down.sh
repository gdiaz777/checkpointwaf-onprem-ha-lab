#!/usr/bin/env bash
# S8 — backend of app1 down. app1 must fail (503), app2 must be unaffected.
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
exec "$ROOT/lab/run-scenario.sh" s08-backend1-down \
  "$ROOT/lab/ssh.sh backend1 'sudo systemctl stop nginx; echo backend1 nginx stopped'" \
  "$ROOT/lab/ssh.sh backend1 'sudo systemctl start nginx; echo backend1 nginx started'" 30 40
