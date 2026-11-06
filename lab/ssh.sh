#!/usr/bin/env bash
# SSH to a lab VM by name. Usage: lab/ssh.sh <name> [command...]
# LAB ONLY: host-key checking is disabled because lab VMs are re-created often.
# Outside the lab (the deploy scripts push private keys and the agent token through
# this), use your normal SSH with host-key verification (e.g. StrictHostKeyChecking=yes
# and a managed known_hosts) by setting LAB_SSH_OPTS.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
source "$ROOT/lab/inventory.env"; source "$ROOT/.env"
case "$1" in
  waf-node1) IP=$NODE1_IP ;; waf-node2) IP=$NODE2_IP ;; waf-node3) IP=$NODE3_IP ;;
  backend1) IP=$BACKEND1_IP ;; backend2) IP=$BACKEND2_IP ;; client) IP=$CLIENT_IP ;;
  *) IP=$1 ;;
esac
shift
# shellcheck disable=SC2086
exec ssh -q -i "${LAB_SSH_KEY/#\~/$HOME}" ${LAB_SSH_OPTS:--o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null} \
  -o ConnectTimeout=5 -o BatchMode=yes "lab@$IP" "$@"
