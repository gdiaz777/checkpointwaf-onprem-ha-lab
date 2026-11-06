# 1. Lab host (KVM / libvirt)

> This chapter is **lab-only**. On vSphere you skip it; see [12-vsphere.md](12-vsphere.md) for the equivalent (port groups, templates).

The whole lab runs on one Linux host with KVM. Tested with:

| Item | Value |
|---|---|
| Host OS | Ubuntu 24.04.4 LTS |
| CPU / RAM | 12 vCPU / 31 GB (the lab uses ~8 GB) |
| libvirt | 10.0.0 (Ubuntu package `10.0.0-2ubuntu8.19`) |
| libvirt firewall backend | iptables (`iptables-nft`), the default in libvirt 10.0 |

Check that the CPU exposes virtualization and that `/dev/kvm` exists:

```bash
egrep -c '(vmx|svm)' /proc/cpuinfo   # > 0
ls -l /dev/kvm
```

## 1.1 Install the packages

```bash
sudo apt-get install -y qemu-kvm libvirt-daemon-system virtinst cloud-image-utils
sudo usermod -aG libvirt "$USER"
# log out and back in (or run `newgrp libvirt`) so the group applies
virsh -c qemu:///system list --all
```

`cloud-image-utils` provides `cloud-localds`, which builds the cloud-init seed ISO for each VM ([chapter 2](02-vms.md)).

## 1.2 Lab networks

The lab uses two isolated networks. The host routes between them and plays the role of the **perimeter firewall**.

```
  client VM 10.90.30.10 ── wafout (virbr-out, routed) ── HOST ── waflab (virbr-waf, NAT) ── WAF nodes / VIP / backends
                                 10.90.30.1          (DNAT = "firewall")   10.90.20.1
```

| Network | Bridge | Subnet | Mode | Purpose |
|---|---|---|---|---|
| `waflab` | `virbr-waf` | `10.90.20.0/24` | NAT | WAF nodes, VIP, backends. NAT so the agents reach the Infinity Portal |
| `wafout` | `virbr-out` | `10.90.30.0/24` | routed | Test client, "Internet side" of the firewall. Routed, so the client's source IP is preserved |

Address plan:

| Host | IP |
|---|---|
| Host (gateway of both networks) | `10.90.20.1`, `10.90.30.1` |
| `waf-node1` / `waf-node2` / `waf-node3` | `10.90.20.11` / `.12` / `.13` |
| VIP (keepalived) | `10.90.20.100` |
| `backend1` (app1) / `backend2` (app2) | `10.90.20.5` / `.6` |
| `client` | `10.90.30.10` |

Network definitions: [`lab/net-waflab.xml`](../lab/net-waflab.xml), [`lab/net-wafout.xml`](../lab/net-wafout.xml). IPs are static (set by cloud-init), so there is no DHCP range.

```bash
for n in waflab wafout; do
  virsh -c qemu:///system net-define lab/net-$n.xml
  virsh -c qemu:///system net-start $n
  virsh -c qemu:///system net-autostart $n
done
virsh -c qemu:///system net-list
```

Expected:

```
 Name      State    Autostart   Persistent
--------------------------------------------
 default   active   yes         yes
 waflab    active   yes         yes
 wafout    active   yes         yes
```

The bridges show `DOWN` until the first VM is attached; that is normal.

> **Note on libvirt firewall rules.** libvirt's NAT mode only lets *established* connections into `10.90.20.0/24`. New connections from the outside (our client) are rejected until the firewall rule of [chapter 8](08-firewall-dnat.md) is added. That is intended: nothing reaches the WAF except through the "firewall".
