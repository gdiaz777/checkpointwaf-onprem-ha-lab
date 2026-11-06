# 12. Running it on VMware vSphere

> **Not validated in this lab.** The lab runs on KVM. This chapter maps every KVM-specific step to its vSphere equivalent. Statements marked *(lab-verified)* were checked in the KVM lab and do not depend on the hypervisor. Statements marked *(docs)* come from the cited vendor documentation. Validate everything else in your vSphere environment.

## 12.1 What changes and what does not

| Area | KVM lab | vSphere |
|---|---|---|
| Hypervisor setup | [Chapter 1](01-lab-host.md) (libvirt, networks) | Existing cluster, see 12.2 |
| VM creation | `lab/create-vm.sh`: cloud image + cloud-init seed ISO | Template / OVA + cloud-init via guestinfo or guest customization (12.3) |
| Networks | libvirt `waflab` (NAT) and `wafout` (routed) | One port group (VLAN) for WAF nodes + VIP. Backends wherever they live today |
| Perimeter firewall | `lab/host-fw.sh` (iptables DNAT) | Check Point cluster NAT ([chapter 8](08-firewall-dnat.md), section 8.3) |
| NIC name | `enp1s0` (virtio) | Depends on the vNIC (vmxnet3 is usually `ens192`/`ens160`). Check with `ip -br link` and set `VRRP_IFACE` in `inventory.env` |
| **Chapters 3–7, 9–11** (backends, portal, agent, HAProxy, keepalived, tests, scale-out, certificates) | — | **Identical**: same packages, same configs, same scripts (they only need SSH to the VMs) |

## 12.2 Placement and availability

### Same L2 segment

All WAF nodes **and** the VIP must be on the **same port group / VLAN**. The VIP is an extra IP that moves between the nodes' vNICs, and keepalived announces it with gratuitous ARP. Backends can be on another network, reachable through routing or the firewall.

### Keep nodes on different ESXi hosts: DRS anti-affinity

If two WAF nodes run on the same ESXi host, losing that host takes down both. Create a VM-VM anti-affinity rule *(docs: [Create a VM-VM Affinity Rule](https://techdocs.broadcom.com/us/en/vmware-cis/vsphere/vsphere/8-0/vsphere-resource-management/using-drs-clusters-to-manage-resources/create-a-vm-vm-affinity-rule.html))*:

1. In the vSphere Client, browse to the **cluster** → **Configure** → **VM/Host Rules** → **Add**.
2. Name: `waf-nodes-separate`. Type: **Separate Virtual Machines**.
3. Add all WAF node VMs → **OK**.
4. Add new nodes to the rule when you scale out ([chapter 10](10-scale-out.md)).

From the same documentation: *"If you use the vSphere HA Specify Failover Hosts admission control policy and designate multiple failover hosts, VM-VM affinity rules are not supported."* Check how your cluster's DRS automation level and HA settings treat the rule (see [Using Affinity Rules without vSphere DRS](https://techdocs.broadcom.com/us/en/vmware-cis/vsphere/vsphere/8-0/vsphere-resource-management/using-drs-clusters-to-manage-resources/using-affinity-rules-without-vsphere-drs.html)).

### vSphere HA

vSphere HA restarting a failed WAF node is a nice complement, but it is **not** the failover mechanism. keepalived moves the VIP in seconds (4–6 s measured, [chapter 9](09-failover-tests.md)), while an HA restart takes minutes. The restarted node rejoins by itself (scenarios 2 and 3).

## 12.3 Building the VMs

Any of these gives the same result as `lab/create-vm.sh`: Ubuntu 24.04, user with an SSH key, static IP, time sync.

**Option A: Ubuntu cloud OVA + cloud-init through guestinfo.** Canonical publishes `noble-server-cloudimg-amd64.ova` ("VMware/Virtualbox OVA") at <https://cloud-images.ubuntu.com/noble/current/>. cloud-init's VMware datasource reads its configuration from the VM's advanced settings *(docs: [cloud-init VMware datasource](https://docs.cloud-init.io/en/latest/reference/datasources/vmware.html))*:

| Key (VM advanced settings / `extraConfig`) | Content |
|---|---|
| `guestinfo.metadata` + `guestinfo.metadata.encoding` | instance-id, hostname and a `network:` section (Netplan v2, like [`network-config.tmpl`](../lab/cloud-init/network-config.tmpl)) |
| `guestinfo.userdata` + `guestinfo.userdata.encoding` | the [`user-data.tmpl`](../lab/cloud-init/user-data.tmpl) of this lab, rendered |

Encoding: `base64` or `gzip+base64`. For example with `govc` (VM powered off):

```bash
govc vm.change -vm waf-node1 \
  -e guestinfo.metadata="$(gzip -c9 meta-data.yaml | base64 -w0)" -e guestinfo.metadata.encoding=gzip+base64 \
  -e guestinfo.userdata="$(gzip -c9 user-data | base64 -w0)"     -e guestinfo.userdata.encoding=gzip+base64
```

**Option B: guest OS customization with cloud-init.** *"Since vSphere 7.0 Update 3 version, users can create a Linux customization specification"* that carries cloud-init meta-data and user-data *(docs: same cloud-init page)*.

**Option C: your standard Ubuntu template.** Clone it and set hostname, IP and SSH key the way you already do. Then continue at [chapter 3](03-backend.md).

Then:

- **open-vm-tools**: install it (`apt install open-vm-tools`) if your image does not include it.
- **Time**: the WAF nodes need an accurate clock (agent registration, TLS). Use NTP (`systemd-timesyncd` or chrony) against your NTP servers, and follow your VMware standard on whether VMware Tools periodic time sync is also enabled. Do not let two sources fight. In the lab: `timedatectl` must show `System clock synchronized: yes`.

## 12.4 Port group security settings and VRRP

vSphere port groups have three security settings: **Promiscuous mode**, **MAC address changes** and **Forged transmits**. Their definitions *(docs: [Security Policy](https://techdocs.broadcom.com/us/en/vmware-cis/vsphere/vsphere/8-0/vsphere-networking/networking-policies/security-policy.html))*:

- **Forged transmits = Reject**: the switch *"drops any outbound frame from a virtual machine adapter with a source MAC address that is different"* from the MAC in the VM's `.vmx` file.
- **MAC address changes = Reject**: if the guest changes the adapter's effective MAC, *"the switch drops all inbound frames to the adapter."*
- **Promiscuous mode** lets a VM see frames not addressed to it. Not needed here.

**This design does not need any of them set to Accept**, because keepalived is configured **without `use_vmac`**:

- The VIP is an additional IP on the node's own interface. ARP replies and gratuitous ARPs for the VIP use the **vNIC's own MAC**. *(lab-verified: the host's ARP entry for the VIP was `52:54:00:e0:d5:1d`, the MAC of node1's `enp1s0`, while node1 held the VIP.)*
- VRRP adverts are unicast IP packets from the node's own address and MAC.
- With **`use_vmac`**, keepalived would create a macvlan interface with the VRRP virtual MAC (`00-00-5E-00-01-{VRID}`, [RFC 5798 §7.3](https://www.rfc-editor.org/rfc/rfc5798#section-7.3)) and send from it. Outbound frames with that source MAC would need *Forged transmits = Accept*, and inbound frames to the virtual MAC would need *Promiscuous mode* (or MAC learning on the switch). That is one more reason not to use it. *(Reasoned from the definitions above; not tested.)*

So: keep your port group at your standard (secure) settings. If failover does not work on vSphere, check first that **VRRP (IP protocol 112) is allowed between the nodes** (NSX DFW, guest firewalls) and that the firewall updates its ARP entry for the VIP ([chapter 7](07-keepalived.md), split-brain).

## 12.5 NSX

If the port group is an NSX segment with the distributed firewall:

- allow **IP protocol 112 (VRRP)** between the WAF nodes,
- allow **HAProxy → agents** on TCP **443** to every WAF node's own IP (every HAProxy uses every agent),
- allow **agents → backends** (TCP 443 in this lab) and **agents → Infinity Portal** (HTTPS outbound),
- allow **firewall → VIP** on TCP 80/443,
- if **SpoofGuard** is enabled on the segment, the VIP is an IP the VM was not bound to. Add the VIP to each WAF node's allowed bindings, otherwise the VIP traffic may be dropped. *(Not validated: check your NSX version's SpoofGuard documentation.)*
