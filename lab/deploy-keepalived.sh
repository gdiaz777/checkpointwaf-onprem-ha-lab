#!/usr/bin/env bash
# Install/update keepalived on a WAF node. Reload keeps the current VRRP state.
# Usage: lab/deploy-keepalived.sh <node-name>
set -euo pipefail
NODE=$1
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
S() { "$ROOT/lab/ssh.sh" "$NODE" "$@"; }
S 'command -v keepalived >/dev/null || sudo DEBIAN_FRONTEND=noninteractive apt-get install -y -qq keepalived >/dev/null 2>&1'
S 'sudo tee /etc/keepalived/chk_haproxy.sh >/dev/null && sudo chmod 755 /etc/keepalived/chk_haproxy.sh' < "$ROOT/configs/keepalived/chk_haproxy.sh"
"$ROOT/lab/render.sh" "$ROOT/configs/keepalived/keepalived.conf.tmpl" "$NODE" | S 'sudo tee /etc/keepalived/keepalived.conf.new >/dev/null'
S 'sudo keepalived -t -f /etc/keepalived/keepalived.conf.new >/dev/null 2>&1 || { sudo keepalived -t -f /etc/keepalived/keepalived.conf.new; echo "config check FAILED, not applied" >&2; exit 1; }
sudo mv /etc/keepalived/keepalived.conf.new /etc/keepalived/keepalived.conf
sudo systemctl enable -q keepalived
if systemctl is-active -q keepalived; then sudo systemctl reload keepalived; else sudo systemctl start keepalived; fi
echo "keepalived on $(hostname): $(systemctl is-active keepalived), $(keepalived -v 2>&1 | head -1)"'
