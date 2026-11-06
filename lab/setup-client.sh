#!/usr/bin/env bash
# Prepare the test client (idempotent): trust the lab CA and resolve the app FQDNs
# to the firewall's published IP. The hosts entry also goes into cloud-init's
# template, because cloud-init (manage_etc_hosts) rewrites /etc/hosts at every boot.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
source "$ROOT/lab/inventory.env"
LINE="$GW_OUT $APP1_FQDN $APP2_FQDN"
"$ROOT/lab/ssh.sh" client 'cat > /home/lab/ca.crt' < "$ROOT/certs/ca/ca.crt"
"$ROOT/lab/ssh.sh" client "for f in /etc/hosts /etc/cloud/templates/hosts.debian.tmpl; do
  [ -f \$f ] || continue
  grep -q '$APP1_FQDN' \$f || echo '$LINE' | sudo tee -a \$f >/dev/null
done; getent hosts $APP1_FQDN $APP2_FQDN"
