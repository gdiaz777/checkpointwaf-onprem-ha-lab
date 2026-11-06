#!/usr/bin/env bash
# Print the WAF node(s) that currently hold the VIP, one per line.
# Exit 0 = exactly one owner, 2 = none or more than one (split-brain).
# Nodes that do not answer (powered off) count as not holding it.
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
source "$ROOT/lab/inventory.env"
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
for n in $WAF_NODES; do
  ( "$ROOT/lab/ssh.sh" "${n#*:}" "ip -4 -br addr show" 2>/dev/null | grep -qw "$VIP" && echo "${n%%:*}" > "$tmp/${n%%:*}" ) &
done
wait
owners=$(cat "$tmp"/* 2>/dev/null)
[ -n "$owners" ] && echo "$owners"
[ "$(grep -c . <<<"$owners")" -eq 1 ] && [ -n "$owners" ] && exit 0 || exit 2
