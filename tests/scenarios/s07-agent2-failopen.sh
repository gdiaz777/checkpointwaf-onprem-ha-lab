#!/usr/bin/env bash
# S7 — the WAF agent on node2 stops inspecting (cpnano -q) while its NGINX keeps
# running: with fail-open, traffic continues UNINSPECTED. Does HAProxy notice?
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
exec "$ROOT/lab/run-scenario.sh" s07-agent2-failopen \
  "$ROOT/lab/ssh.sh waf-node2 'sudo cpnano -q; sleep 3; sudo cpnano -s | grep -E \"^.*Status|Registered Instances\" | head -3'; sleep 5; for ip in 10.90.20.11 10.90.20.12; do printf \"XSS via agent %s → HTTP \" \$ip; curl -s -o /dev/null -w '%{http_code}\\n' --cacert $ROOT/certs/ca/ca.crt --resolve app1.waflab.example:443:\$ip 'https://app1.waflab.example/?q=%3Cscript%3Ealert(1)%3C%2Fscript%3E'; done" \
  "$ROOT/lab/ssh.sh waf-node2 'sudo cpnano -r; sleep 5; sudo cpnano -s | grep -E \"^.*Status|Registered Instances\" | head -3'" 30 40
