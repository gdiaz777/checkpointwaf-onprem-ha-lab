#!/usr/bin/env bash
# Power the lab ON again after lab-stop.sh (or a host reboot) and check it is healthy.
# Usage: lab/lab-start.sh
# Order: backends, then WAF nodes starting with node1 (highest keepalived priority,
# so it becomes VIP owner), then the client. Re-applies the host firewall rules
# (they are not persistent) and runs the health checks.
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
source "$ROOT/lab/inventory.env"
VIRSH="virsh -c qemu:///system"
nodes=$(for n in $WAF_NODES; do echo "${n%%:*}"; done)

for net in waflab wafout; do $VIRSH net-start "$net" >/dev/null 2>&1 || true; done
start_wait() {
  local vm=$1
  $VIRSH domstate "$vm" 2>/dev/null | grep -q running || $VIRSH start "$vm" >/dev/null
  printf 'starting %-10s ' "$vm"
  for i in $(seq 1 60); do "$ROOT/lab/ssh.sh" "$vm" true 2>/dev/null && { echo "up"; return 0; }; sleep 2; done
  echo "NOT reachable after 120 s"; return 1
}
start_wait backend1; start_wait backend2
first=1
for n in $nodes; do
  start_wait "$n"
  # give node1 time to win the VRRP election before the others come up
  [ $first = 1 ] && sleep 5 && first=0
done
start_wait client
"$ROOT/lab/setup-client.sh" >/dev/null
"$ROOT/lab/host-fw.sh" up

printf 'waiting for the agents'
for n in $nodes; do
  for i in $(seq 1 30); do
    st=$("$ROOT/lab/ssh.sh" "$n" 'sudo cpnano -s' 2>/dev/null)
    grep -q 'Registered Instances: [1-9]' <<<"$st" && break
    printf '.'; sleep 5
  done
done
echo
for n in $nodes; do
  st=$("$ROOT/lab/ssh.sh" "$n" 'sudo cpnano -s 2>/dev/null' | sed 's/\x1b\[[0-9;]*m//g')
  printf '%-10s agent: %-12s %s  %s\n' "$n" "$(grep -m1 '^Status' <<<"$st" | cut -d: -f2 | xargs)" \
    "$(grep -m1 'Policy version' <<<"$st" | xargs)" "$(grep -m1 'Registered Instances' <<<"$st" | xargs)"
done
echo; echo "== health checks"
bash "$ROOT/tests/test_keepalived.sh"
# the client may need a few seconds to sync its clock after boot
for i in 1 2 3 4 5 6; do bash "$ROOT/tests/test_firewall.sh" >/dev/null 2>&1 && break; sleep 10; done
bash "$ROOT/tests/test_firewall.sh" | grep -E 'PASS client → app|FAIL'
echo; echo "lab is up: https://$APP1_FQDN and https://$APP2_FQDN (from the client VM, or via ${GW_OUT})"
