#!/usr/bin/env bash
# Install/update HAProxy on a WAF node: certificates, crt-list, rendered config.
# Validates the config on the node before switching to it, then reloads
# (hitless: HAProxy's master-worker reload keeps established connections).
# Usage: lab/deploy-haproxy.sh <node-name>
set -euo pipefail
NODE=$1
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
source "$ROOT/lab/inventory.env"
S() { "$ROOT/lab/ssh.sh" "$NODE" "$@"; }
S 'command -v haproxy >/dev/null && command -v socat >/dev/null || sudo DEBIAN_FRONTEND=noninteractive apt-get install -y -qq haproxy socat >/dev/null 2>&1; sudo mkdir -p /etc/haproxy/certs'
S 'sudo tee /etc/sysctl.d/99-waflab.conf >/dev/null && sudo sysctl -q -p /etc/sysctl.d/99-waflab.conf' < "$ROOT/configs/sysctl/99-waflab.conf"
S 'sudo tee /etc/haproxy/ca.crt >/dev/null' < "$ROOT/certs/ca/ca.crt"
# Certificates: written to a temp name and renamed (atomic for HAProxy reloads)
for fqdn in "$APP1_FQDN" "$APP2_FQDN"; do
  S "sudo tee /etc/haproxy/certs/.$fqdn.pem.tmp >/dev/null && sudo chmod 600 /etc/haproxy/certs/.$fqdn.pem.tmp && sudo mv /etc/haproxy/certs/.$fqdn.pem.tmp /etc/haproxy/certs/$fqdn.pem" < "$ROOT/certs/apps/$fqdn.pem"
done
S 'sudo tee /etc/haproxy/crt-list.txt >/dev/null' < "$ROOT/configs/haproxy/crt-list.txt"
"$ROOT/lab/render.sh" "$ROOT/configs/haproxy/haproxy.cfg.tmpl" "$NODE" | S 'sudo tee /etc/haproxy/haproxy.cfg.new >/dev/null && sudo chmod 640 /etc/haproxy/haproxy.cfg.new'
# Validate before switching; a broken config never replaces the running one.
S 'sudo haproxy -c -q -f /etc/haproxy/haproxy.cfg.new || { echo "config check FAILED on $(hostname), not applied" >&2; exit 1; }
sudo mv /etc/haproxy/haproxy.cfg.new /etc/haproxy/haproxy.cfg
sudo systemctl enable -q haproxy
if systemctl is-active -q haproxy; then sudo systemctl reload haproxy; else sudo systemctl start haproxy; fi
echo "haproxy on $(hostname): $(systemctl is-active haproxy), $(haproxy -v | head -1)"'
