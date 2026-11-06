#!/usr/bin/env bash
# The lab host plays the perimeter firewall (in production: your Check Point
# cluster, see docs/08-firewall-dnat.md).
#   - DNAT  10.90.30.1:80,443 (outside) and <LAN IP>:80,443 → VIP, NO source NAT
#   - allow only those flows into the WAF network (libvirt rejects the rest)
#   - give the outside network (test client) Internet access via masquerade
# Usage: lab/host-fw.sh up|down|status
# Rules are tagged with the comment "waflab-fw". Not persistent across reboots
# or libvirt network restarts: run "up" again after either.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
source "$ROOT/lab/inventory.env"
TAG=(-m comment --comment waflab-fw)
LAN_IF=${LAN_IF:-$(ip -4 route show default | awk '{print $5; exit}')}
LAN_IP=${LAN_IP:-$(ip -4 -br addr show "$LAN_IF" | awk '{print $3}' | cut -d/ -f1)}
OUT_NET=${GW_OUT%.*}.0/24
IPT="sudo iptables -w"

down() {
  for table in nat filter; do
    { $IPT -t $table -S | grep -- '--comment waflab-fw' || true; } | sed 's/^-A/-D/' | while read -r rule; do
      eval "$IPT -t $table $rule"
    done
  done
}

up() {
  down
  for dst in "$GW_OUT" "$LAN_IP"; do
    $IPT -t nat -I PREROUTING 1 -d "$dst" -p tcp -m multiport --dports 80,443 "${TAG[@]}" -j DNAT --to-destination "$VIP"
  done
  # traffic generated on the host itself to its LAN IP (handy for testing)
  $IPT -t nat -I OUTPUT 1 -d "$LAN_IP" -p tcp -m multiport --dports 80,443 "${TAG[@]}" -j DNAT --to-destination "$VIP"
  # allow the DNAT'd flows into the WAF network, ahead of libvirt/Docker chains
  $IPT -I FORWARD 1 -d "$VIP" -p tcp -m multiport --dports 80,443 -m conntrack --ctstate NEW,ESTABLISHED,RELATED "${TAG[@]}" -j ACCEPT
  # outside network → Internet (not → inside networks)
  $IPT -t nat -I POSTROUTING 1 -s "$OUT_NET" -o "$LAN_IF" "${TAG[@]}" -j MASQUERADE
  echo "host firewall up: $GW_OUT,$LAN_IP :80,443 → $VIP ; $OUT_NET masqueraded via $LAN_IF"
}

status() {
  for table in nat filter; do $IPT -t $table -S | grep -- 'waflab-fw' || true; done
}

case "${1:-}" in up) up ;; down) down; echo "host firewall rules removed" ;; status) status ;; *) echo "usage: $0 up|down|status" >&2; exit 2 ;; esac
