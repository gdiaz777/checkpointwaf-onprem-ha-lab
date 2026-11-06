#!/usr/bin/env bash
# Remove a WAF node from the running cluster without downtime.
# Usage: lab/remove-node.sh <name>
#   1. drain: every HAProxy stops sending NEW requests to the node's agent
#      (runtime API, no reload); wait until its active sessions reach 0
#   2. make sure the node does not hold the VIP (move it away if it does)
#   3. stop keepalived on the node, then remove it from WAF_NODES and reload
#      keepalived + HAProxy on the remaining nodes
#   4. stop HAProxy and NGINX on the removed node
# Decommissioning (cpnano -u, delete the agent in the portal, delete the VM) is
# a separate, manual step: see docs/10-scale-out.md.
set -euo pipefail
NAME=$1
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
source "$ROOT/lab/inventory.env"
step() { printf '\n=== %s  %s\n' "$(date -u +%H:%M:%S)" "$*"; }
others=$(for n in $WAF_NODES; do [ "${n%%:*}" = "$NAME" ] || echo "${n%%:*}"; done)
[ "$(wc -w <<<"$others")" -ge 1 ] || { echo "refusing to remove the last node" >&2; exit 1; }

step "1/4 drain $NAME on every HAProxy"
for h in $WAF_NODES; do
  "$ROOT/lab/ssh.sh" "${h%%:*}" "for b in be_app1 be_app2; do echo \"set server \$b/$NAME state drain\" | sudo socat stdio /run/haproxy/admin.sock; done"
done
for i in $(seq 1 30); do
  cur=0
  for h in $WAF_NODES; do
    st=$("$ROOT/lab/ssh.sh" "${h%%:*}" 'echo "show stat" | sudo socat stdio /run/haproxy/admin.sock')
    cur=$(( cur + $(awk -F, -v s="$NAME" '$2==s {t+=$5} END {print t+0}' <<<"$st") ))
  done
  echo "active sessions to $NAME: $cur"; [ "$cur" -eq 0 ] && break; sleep 2
done
[ "$cur" -eq 0 ] || echo "WARNING: $cur sessions still open on $NAME after 60 s; they will be cut" >&2

step "2/4 VIP must not be on $NAME"
if { "$ROOT/tools/vip-owner.sh" || true; } | grep -qx "$NAME"; then
  "$ROOT/lab/ssh.sh" "$NAME" 'sudo systemctl stop keepalived'; sleep 3
fi
echo "VIP owner: $("$ROOT/tools/vip-owner.sh" | tr '\n' ' ')"

step "3/4 stop keepalived on $NAME, update WAF_NODES, reload the remaining nodes"
"$ROOT/lab/ssh.sh" "$NAME" 'sudo systemctl disable --now keepalived 2>/dev/null; systemctl is-active keepalived || true'
sed -i "s| $NAME:[0-9.]*||; s|\"$NAME:[0-9.]* |\"|" "$ROOT/lab/inventory.env"
source "$ROOT/lab/inventory.env"; echo "WAF_NODES is now: $WAF_NODES"
for n in $WAF_NODES; do "$ROOT/lab/deploy-keepalived.sh" "${n%%:*}"; done
for n in $WAF_NODES; do "$ROOT/lab/deploy-haproxy.sh" "${n%%:*}"; done

step "4/4 stop HAProxy and NGINX on $NAME"
"$ROOT/lab/ssh.sh" "$NAME" 'sudo systemctl disable --now haproxy nginx 2>/dev/null; echo "haproxy=$(systemctl is-active haproxy) nginx=$(systemctl is-active nginx)"'
echo "VIP owner: $("$ROOT/tools/vip-owner.sh" | tr '\n' ' ')"
