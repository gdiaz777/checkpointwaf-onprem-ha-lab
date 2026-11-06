#!/usr/bin/env bash
# Install NGINX on a backend VM with its certificate and the echo site.
# Usage: lab/deploy-backend.sh <backend-vm> <app> <ip>
set -euo pipefail
VM=$1 APP=$2 IP=$3
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CN="$VM.waflab.internal"
"$ROOT/lab/certs/issue-cert.sh" "$CN" "$CN,$IP" "$ROOT/certs/backends"
S="$ROOT/lab/ssh.sh"
$S "$VM" 'sudo DEBIAN_FRONTEND=noninteractive apt-get install -y -qq nginx >/dev/null 2>&1 && sudo mkdir -p /etc/nginx/tls && sudo rm -f /etc/nginx/sites-enabled/default'
$S "$VM" "sudo tee /etc/nginx/tls/backend.crt >/dev/null" < "$ROOT/certs/backends/$CN.crt"
$S "$VM" "sudo tee /etc/nginx/tls/backend.key >/dev/null && sudo chmod 600 /etc/nginx/tls/backend.key" < "$ROOT/certs/backends/$CN.key"
sed "s/__APP__/$APP/" "$ROOT/configs/backend/echo.conf.tmpl" | $S "$VM" "sudo tee /etc/nginx/sites-enabled/echo.conf >/dev/null"
$S "$VM" 'sudo nginx -t -q && sudo systemctl reload nginx && systemctl is-active nginx'
