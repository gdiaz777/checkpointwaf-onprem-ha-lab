#!/usr/bin/env bash
# Delete one lab VM and its disks. Usage: lab/destroy-vm.sh <name>
set -euo pipefail
NAME=${1:?usage: $0 <name>}
VIRSH="virsh -c qemu:///system"
$VIRSH destroy "$NAME" 2>/dev/null || true
$VIRSH undefine "$NAME" --nvram 2>/dev/null || $VIRSH undefine "$NAME" 2>/dev/null || true
sudo rm -f "/var/lib/libvirt/images/waflab/$NAME.qcow2" "/var/lib/libvirt/images/waflab/$NAME-seed.iso"
echo "$NAME destroyed"
