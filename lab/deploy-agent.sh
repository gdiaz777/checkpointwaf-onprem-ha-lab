#!/usr/bin/env bash
# Prepare a WAF node's NGINX reverse proxy and (optionally) install the
# Check Point WAF agent on it.
# Usage: lab/deploy-agent.sh <node-name> [--install-agent]
#   Without --install-agent: NGINX + certificates + site only (no inspection yet).
#   With --install-agent: also runs Check Point's nanoegg installer with WAF_TOKEN from .env.
set -euo pipefail
NODE=$1 INSTALL=${2:-}
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
source "$ROOT/lab/inventory.env"; source "$ROOT/.env"
S() { "$ROOT/lab/ssh.sh" "$NODE" "$@"; }

# App certificates (shared by HAProxy and the agent's NGINX on every node)
for fqdn in "$APP1_FQDN" "$APP2_FQDN"; do
  [ -f "$ROOT/certs/apps/$fqdn.crt" ] || "$ROOT/lab/certs/issue-cert.sh" "$fqdn" "$fqdn" "$ROOT/certs/apps"
done

S 'sudo DEBIAN_FRONTEND=noninteractive apt-get install -y -qq nginx >/dev/null 2>&1; sudo mkdir -p /etc/nginx/tls; sudo rm -f /etc/nginx/sites-enabled/default'
S 'sudo tee /etc/nginx/tls/ca.crt >/dev/null' < "$ROOT/certs/ca/ca.crt"
for fqdn in "$APP1_FQDN" "$APP2_FQDN"; do
  S "sudo tee /etc/nginx/tls/$fqdn.crt >/dev/null" < "$ROOT/certs/apps/$fqdn.crt"
  S "sudo tee /etc/nginx/tls/$fqdn.key >/dev/null; sudo chmod 600 /etc/nginx/tls/$fqdn.key" < "$ROOT/certs/apps/$fqdn.key"
done
"$ROOT/lab/render.sh" "$ROOT/configs/agent/nginx-waf.conf.tmpl" "$NODE" | S 'sudo tee /etc/nginx/conf.d/waf.conf >/dev/null'
S 'sudo nginx -t -q && sudo systemctl enable -q nginx && { systemctl is-active -q nginx && sudo systemctl reload nginx || sudo systemctl start nginx; } && echo "nginx: $(systemctl is-active nginx), $(nginx -v 2>&1)"'

if [ "$INSTALL" = "--install-agent" ] && S 'sudo sh -c "command -v cpnano" >/dev/null'; then   # cpnano links into root-only /etc/cp
  echo "agent already installed on $NODE, skipping installer"
elif [ "$INSTALL" = "--install-agent" ]; then
  [[ "${WAF_TOKEN:-}" =~ ^[A-Za-z0-9] ]] || { echo "WAF_TOKEN not set in .env" >&2; exit 1; }
  # The token travels on SSH stdin and is read INSIDE the root shell, so it is not on the
  # ssh/sudo command lines (nor in sudo's auth.log). Note: the installer itself takes it as
  # an argument, so it is visible in the process list while nanoegg runs.
  printf '%s\n' "$WAF_TOKEN" | S 'sudo bash -c '"'"'read -r T; cd /tmp && wget -q https://sc1.checkpoint.com/nanoagent/nanoegg -O nanoegg && chmod +x nanoegg && ./nanoegg --install --token "$T"'"'"''
  S 'sudo cpnano -s | head -20'
fi
