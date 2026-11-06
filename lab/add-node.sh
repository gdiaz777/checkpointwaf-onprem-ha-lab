#!/usr/bin/env bash
# Add a WAF node to the running cluster without downtime.
# Usage: lab/add-node.sh <name> <ip>
# Order matters:
#   1. build the node and install the agent (it joins the portal profile)
#   2. add it to WAF_NODES (single source of truth)
#   3. reload keepalived on the EXISTING nodes first (they learn the new peer)
#   4. reload HAProxy on the existing nodes (new agent added to every pool)
#   5. start HAProxy + keepalived on the new node LAST: it then hears the
#      current master immediately and stays BACKUP (no split-brain, no VIP move)
set -euo pipefail
NAME=$1 IP=$2
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
source "$ROOT/lab/inventory.env"
step() { printf '\n=== %s  %s\n' "$(date -u +%H:%M:%S)" "$*"; }

step "1/5 create VM $NAME ($IP)"
sg libvirt -c "$ROOT/lab/create-vm.sh $NAME waflab $IP/24 $GW_WAF 2 2048 20"
until "$ROOT/lab/ssh.sh" "$IP" true 2>/dev/null; do sleep 3; done
"$ROOT/lab/ssh.sh" "$IP" 'cloud-init status --wait >/dev/null; timedatectl | grep -q "synchronized: yes" || { echo "clock NOT synchronized" >&2; exit 1; }; echo "clock synchronized"'

step "1/5 NGINX + agent on $NAME"
case " $WAF_NODES " in *" $NAME:"*) ;; *) sed -i "s|^WAF_NODES=\"\(.*\)\"|WAF_NODES=\"\1 $NAME:$IP\"|" "$ROOT/lab/inventory.env" ;; esac
source "$ROOT/lab/inventory.env"   # render.sh needs the node in WAF_NODES to render its config
"$ROOT/lab/deploy-agent.sh" "$NAME" --install-agent > "/tmp/add-node-$NAME.log" 2>&1 || { echo "agent install failed, see /tmp/add-node-$NAME.log" >&2; exit 1; }
grep -E 'successfully installed|already installed|Registration status|^Name' "/tmp/add-node-$NAME.log" || true
printf 'waiting for policy'
tries=0
# (capture first, then grep: "ssh | grep -q" + pipefail would loop forever on SIGPIPE)
until st=$("$ROOT/lab/ssh.sh" "$IP" 'sudo cpnano -s' 2>/dev/null) && grep -q 'Registered Instances: [1-9]' <<<"$st"; do
  tries=$((tries + 1)); [ $tries -le 60 ] || { echo " timeout (10 min) waiting for the agent policy" >&2; exit 1; }
  printf '.'; sleep 10
done; echo ' ok'
"$ROOT/lab/ssh.sh" "$IP" 'sudo cpnano -s | grep -E "Policy version|Registered Instances"'

step "2/5 WAF_NODES is now: $WAF_NODES"

step "3/5 keepalived: existing nodes learn the new peer"
for n in $WAF_NODES; do [ "${n%%:*}" = "$NAME" ] || "$ROOT/lab/deploy-keepalived.sh" "${n%%:*}"; done

step "4/5 HAProxy: existing nodes add the new agent to every pool"
for n in $WAF_NODES; do [ "${n%%:*}" = "$NAME" ] || "$ROOT/lab/deploy-haproxy.sh" "${n%%:*}"; done

step "5/5 HAProxy + keepalived on $NAME (joins as BACKUP)"
"$ROOT/lab/deploy-haproxy.sh" "$NAME"
"$ROOT/lab/deploy-keepalived.sh" "$NAME"
sleep 5
echo "VIP owner: $("$ROOT/tools/vip-owner.sh" | tr '\n' ' ')"
