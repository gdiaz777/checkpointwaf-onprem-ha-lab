#!/usr/bin/env bash
# S5 — the agent on node2 answers 503 to everything (simulated: its NGINX
# returns 503 for every location, including the health check).
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
exec "$ROOT/lab/run-scenario.sh" s05-agent2-5xx \
  "$ROOT/lab/ssh.sh waf-node2 'sudo cp /etc/nginx/conf.d/waf.conf /root/waf.conf.bak && sudo sed -i \"s|^    location / {|    location / { return 503;|\" /etc/nginx/conf.d/waf.conf && sudo nginx -t -q && sudo systemctl reload nginx && echo node2 now answers 503'" \
  "$ROOT/lab/ssh.sh waf-node2 'sudo cp /root/waf.conf.bak /etc/nginx/conf.d/waf.conf && sudo nginx -t -q && sudo systemctl reload nginx && echo node2 config restored'" 30 60
