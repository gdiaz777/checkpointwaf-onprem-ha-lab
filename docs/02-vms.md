# 2. Virtual machines

All VMs run **Ubuntu Server 24.04 LTS** (official cloud image) and are configured at first boot by **cloud-init**: hostname, static IP, user `lab` with an SSH key and no password, and time sync.

| VM | Network | IP | vCPU / RAM / disk | Role |
|---|---|---|---|---|
| `waf-node1` | waflab | `10.90.20.11` | 2 / 2 GB / 20 GB | HAProxy + keepalived + CloudGuard WAF agent |
| `waf-node2` | waflab | `10.90.20.12` | 2 / 2 GB / 20 GB | same |
| `waf-node3` | waflab | `10.90.20.13` | 2 / 2 GB / 20 GB | same, added in [chapter 10](10-scale-out.md) |
| `backend1` | waflab | `10.90.20.5` | 1 / 1 GB / 10 GB | web app 1 (`app1.waflab.example`) |
| `backend2` | waflab | `10.90.20.6` | 1 / 1 GB / 10 GB | web app 2 (`app2.waflab.example`) |
| `client` | wafout | `10.90.30.10` | 1 / 1 GB / 10 GB | test client "on the Internet" |

The single source of truth for names, IPs and ports is [`lab/inventory.env`](../lab/inventory.env).

> **On vSphere** you build these VMs from a template instead: see [12-vsphere.md](12-vsphere.md). The cloud-init files below work there too (as a NoCloud seed ISO, or translated into guest customization). Everything from [chapter 3](03-backend.md) on is identical.

## 2.1 Prepare secrets and SSH key (once)

```bash
cp .env.example .env            # .env is git-ignored
ssh-keygen -t ed25519 -N '' -C waflab -f ~/.ssh/waflab_ed25519
```

`.env` holds `LAB_SSH_KEY` (the key above), and later `CGWAF_TOKEN` and `HAPROXY_STATS_PASS`. Keep the values quoted (`KEY="value"`), because the scripts `source` the file.

## 2.2 Download the cloud image

```bash
mkdir -p ~/.cache/waflab && cd ~/.cache/waflab
curl -LO https://cloud-images.ubuntu.com/noble/current/noble-server-cloudimg-amd64.img
curl -LO https://cloud-images.ubuntu.com/noble/current/SHA256SUMS
grep 'noble-server-cloudimg-amd64.img$' SHA256SUMS | sha256sum -c -    # → OK
```

## 2.3 cloud-init templates

- [`lab/cloud-init/user-data.tmpl`](../lab/cloud-init/user-data.tmpl) sets the hostname, user `lab` (sudo, key only, no password login), UTC, `qemu-guest-agent`, and `systemd-timesyncd`.
- [`lab/cloud-init/network-config.tmpl`](../lab/cloud-init/network-config.tmpl) sets a static IP, the default gateway (the host) and public DNS resolvers.

## 2.4 Create the VMs

[`lab/create-vm.sh`](../lab/create-vm.sh) creates one VM and is idempotent:

1. A thin qcow2 overlay on top of the base image (`/var/lib/libvirt/images/waflab/`).
2. A NoCloud seed ISO rendered from the templates (`cloud-localds`).
3. `virt-install --import --os-variant ubuntu24.04`.

```bash
lab/create-vm.sh <name> <network> <ip/cidr> <gateway> <vcpu> <ram_mb> <disk_gb>
```

[`lab/lab-up.sh`](../lab/lab-up.sh) creates the base lab (both backends, node1, node2 and the client) and waits until cloud-init has finished on each one:

```bash
lab/lab-up.sh
```

```
waf-node2 created (10.90.20.12/24 on waflab)
...
waiting for backend1 .. ready
waiting for backend2  ready
waiting for waf-node1  ready
waiting for waf-node2  ready
waiting for client  ready
```

`virt-install` warns that 1 GB is below the recommended RAM for Ubuntu 24.04. It is enough for a backend serving a static page and for a curl client.

[`lab/ssh.sh`](../lab/ssh.sh) opens SSH to a VM by name, for example `lab/ssh.sh waf-node1 hostname`. [`lab/destroy-vm.sh`](../lab/destroy-vm.sh) and [`lab/lab-down.sh`](../lab/lab-down.sh) delete VMs.

## 2.5 Verify

```bash
for vm in backend1 backend2 waf-node1 waf-node2 client; do
  printf '%-10s ' $vm
  lab/ssh.sh $vm 'printf "host=%s inet=%s " "$(hostname)" \
    "$(curl -s -o /dev/null -m 5 -w %{http_code} https://portal.checkpoint.com)"; \
    timedatectl | grep -o "synchronized: [a-z]*"'
done
```

Result in the lab:

```
backend1   host=backend1 inet=200 synchronized: yes
backend2   host=backend2 inet=200 synchronized: yes
waf-node1  host=waf-node1 inet=200 synchronized: yes
waf-node2  host=waf-node2 inet=200 synchronized: yes
client     host=client inet=000 synchronized: no
```

- **WAF nodes must have outbound HTTPS to the Infinity Portal** and a **synchronized clock**. Agent registration and TLS both fail on a skewed clock. On vSphere, check NTP or VMware Tools time sync (chapter 12).
- The client has no Internet yet. Its network is routed and the host has no NAT for it. That is fixed in [chapter 8](08-firewall-dnat.md), where the host becomes the firewall.
