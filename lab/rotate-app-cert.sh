#!/usr/bin/env bash
# Rotate the certificate of ONE published app on EVERY WAF node, with no outage.
# Usage: lab/rotate-app-cert.sh <app1|app2> [--cert file.crt --key file.key]
#   Without --cert/--key: issue a new certificate from the lab CA.
#   With them: deploy the certificate you got from your CA (full chain in .crt).
# The app certificate lives in two places on each node:
#   HAProxy  /etc/haproxy/certs/<fqdn>.pem        (client-facing TLS)
#   NGINX    /etc/nginx/tls/<fqdn>.crt + .key     (HAProxy → agent TLS)
# Each is validated (haproxy -c / nginx -t) before a graceful reload, node by node.
set -euo pipefail
APP=$1; shift
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
source "$ROOT/lab/inventory.env"
case "$APP" in app1) FQDN=$APP1_FQDN ;; app2) FQDN=$APP2_FQDN ;; *) echo "unknown app $APP" >&2; exit 2 ;; esac
CRT="" KEY=""
while [ $# -gt 0 ]; do case "$1" in --cert) CRT=$2; shift 2 ;; --key) KEY=$2; shift 2 ;; *) echo "bad arg $1" >&2; exit 2 ;; esac; done
D="$ROOT/certs/apps"; mkdir -p "$D/archive"
[ -f "$D/$FQDN.crt" ] && cp "$D/$FQDN.crt" "$D/archive/$FQDN-$(openssl x509 -in "$D/$FQDN.crt" -noout -serial | cut -d= -f2).crt"
if [ -n "$CRT" ]; then
  # sanity: key matches cert, cert covers the FQDN
  [ "$(openssl x509 -in "$CRT" -noout -pubkey | sha256sum)" = "$(openssl pkey -in "$KEY" -pubout | sha256sum)" ] || { echo "key does not match certificate" >&2; exit 1; }
  openssl x509 -in "$CRT" -noout -checkhost "$FQDN" | grep -q 'does match' || { echo "certificate does not cover $FQDN" >&2; exit 1; }
  cp "$CRT" "$D/$FQDN.crt"; cp "$KEY" "$D/$FQDN.key"; cat "$D/$FQDN.crt" "$D/$FQDN.key" > "$D/$FQDN.pem"; chmod 600 "$D/$FQDN.key" "$D/$FQDN.pem"
else
  "$ROOT/lab/certs/issue-cert.sh" "$FQDN" "$FQDN" "$D"
fi
echo "new certificate: $(openssl x509 -in "$D/$FQDN.crt" -noout -serial -enddate | tr '\n' ' ')"
for n in $WAF_NODES; do
  node=${n%%:*}; S() { "$ROOT/lab/ssh.sh" "$node" "$@"; }
  S "sudo tee /etc/haproxy/certs/.$FQDN.pem.tmp >/dev/null && sudo chmod 600 /etc/haproxy/certs/.$FQDN.pem.tmp && sudo mv /etc/haproxy/certs/.$FQDN.pem.tmp /etc/haproxy/certs/$FQDN.pem" < "$D/$FQDN.pem"
  S "sudo tee /etc/nginx/tls/.$FQDN.crt.tmp >/dev/null && sudo mv /etc/nginx/tls/.$FQDN.crt.tmp /etc/nginx/tls/$FQDN.crt" < "$D/$FQDN.crt"
  S "sudo tee /etc/nginx/tls/.$FQDN.key.tmp >/dev/null && sudo chmod 600 /etc/nginx/tls/.$FQDN.key.tmp && sudo mv /etc/nginx/tls/.$FQDN.key.tmp /etc/nginx/tls/$FQDN.key" < "$D/$FQDN.key"
  S 'sudo haproxy -c -q -f /etc/haproxy/haproxy.cfg && sudo nginx -t -q && sudo systemctl reload haproxy && sudo systemctl reload nginx && echo "$(hostname): haproxy + nginx reloaded"'
done
