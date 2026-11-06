#!/usr/bin/env bash
# Create one lab VM from the Ubuntu 24.04 cloud image (idempotent).
# Usage: lab/create-vm.sh <name> <network> <ip/cidr> <gw> <vcpu> <ram_mb> <disk_gb>
set -euo pipefail
[ $# -eq 7 ] || { echo "usage: $0 <name> <network> <ip/cidr> <gw> <vcpu> <ram_mb> <disk_gb>" >&2; exit 2; }
NAME=$1 NET=$2 IP_CIDR=$3 GW=$4 VCPU=$5 RAM=$6 DISK=$7
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck disable=SC1091
source "$ROOT/.env"
VIRSH="virsh -c qemu:///system"
IMG_SRC="${WAFLAB_IMAGE:-$HOME/.cache/waflab/noble-server-cloudimg-amd64.img}"
IMG_DIR=/var/lib/libvirt/images/waflab
BASE="$IMG_DIR/base-noble.qcow2"

if $VIRSH dominfo "$NAME" >/dev/null 2>&1; then
  echo "$NAME already exists, skipping"; exit 0
fi

sudo mkdir -p "$IMG_DIR"
[ -f "$BASE" ] || sudo cp "$IMG_SRC" "$BASE"
sudo qemu-img create -q -f qcow2 -F qcow2 -b "$BASE" "$IMG_DIR/$NAME.qcow2" "${DISK}G"

# The outside network has no Internet access: no package install there.
if [ "$NET" = "wafout" ]; then PKG_UPDATE=false PACKAGES=""; else PKG_UPDATE=true PACKAGES="qemu-guest-agent"; fi

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
PUBKEY="$(cat "${LAB_SSH_KEY/#\~/$HOME}.pub")"
sed -e "s|__HOSTNAME__|$NAME|g" -e "s|__SSH_PUBKEY__|$PUBKEY|" \
    -e "s|__PKG_UPDATE__|$PKG_UPDATE|" -e "s|__PACKAGES__|$PACKAGES|" \
    "$ROOT/lab/cloud-init/user-data.tmpl" > "$TMP/user-data"
sed -e "s|__IP_CIDR__|$IP_CIDR|" -e "s|__GW__|$GW|" \
    "$ROOT/lab/cloud-init/network-config.tmpl" > "$TMP/network-config"
printf 'instance-id: %s\nlocal-hostname: %s\n' "$NAME" "$NAME" > "$TMP/meta-data"
cloud-localds --network-config="$TMP/network-config" "$TMP/seed.iso" "$TMP/user-data" "$TMP/meta-data"
sudo cp "$TMP/seed.iso" "$IMG_DIR/$NAME-seed.iso"

virt-install --connect qemu:///system --name "$NAME" \
  --memory "$RAM" --vcpus "$VCPU" --cpu host-passthrough \
  --import --os-variant ubuntu24.04 \
  --disk "path=$IMG_DIR/$NAME.qcow2,format=qcow2,bus=virtio" \
  --disk "path=$IMG_DIR/$NAME-seed.iso,device=cdrom" \
  --network "network=$NET,model=virtio" \
  --graphics none --noautoconsole
echo "$NAME created ($IP_CIDR on $NET)"
