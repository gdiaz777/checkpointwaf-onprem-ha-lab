# 7. keepalived and the VIP

keepalived makes sure **exactly one** WAF node holds the VIP `10.90.20.100`, and that the VIP moves when that node or its HAProxy fails. It uses VRRP in **unicast** mode, so the network does not need multicast.

Version in the lab: **Keepalived 2.2.8** (Ubuntu 24.04 package).

## 7.1 Configuration

Template: [`configs/keepalived/keepalived.conf.tmpl`](../configs/keepalived/keepalived.conf.tmpl), rendered per node. Rendered for node1:

```
vrrp_script chk_haproxy {
    script "/etc/keepalived/chk_haproxy.sh"
    interval 2
    timeout 3
    fall 2
    rise 2
}

vrrp_instance VI_WAF {
    state BACKUP
    nopreempt
    interface enp1s0
    virtual_router_id 51
    priority 110
    advert_int 1
    unicast_src_ip 10.90.20.11
    unicast_peer {
        10.90.20.12
    }
    virtual_ipaddress {
        10.90.20.100/24 dev enp1s0
    }
    track_script {
        chk_haproxy
    }
}
```

| Setting | Why |
|---|---|
| `state BACKUP` on **all** nodes + `nopreempt` | The highest priority wins the first election. Later, a node that comes back does **not** take the VIP back, which would cause a second outage. Failback is a manual, planned action ([chapter 9](09-failover-tests.md), scenario 9) |
| `priority` 110 / 100 / 90 | Generated from the node's position in `WAF_NODES` |
| `unicast_src_ip` / `unicast_peer` | VRRP adverts go directly to the other nodes. No multicast is needed on the vSwitch or VLAN |
| `advert_int 1` | One advert per second. A backup takes over after about 3 missed adverts (~3 s) |
| `virtual_router_id 51` | Must be **unique per L2 segment**. If the customer already runs VRRP elsewhere on that VLAN, pick a free ID |
| `interface` | `enp1s0` in this lab (virtio). On vSphere with vmxnet3 it is usually `ens192`. Set it with `VRRP_IFACE` in `inventory.env` |
| `track_script chk_haproxy` | Releases the VIP if the local HAProxy stops answering |

### The track script

[`configs/keepalived/chk_haproxy.sh`](../configs/keepalived/chk_haproxy.sh) runs `curl -m 2 http://127.0.0.1/`, which hits HAProxy's local `127.0.0.1:80` listener. **Any** HTTP answer counts as healthy (HAProxy replies `301` on :80). Only "no answer within 2 s" counts as a failure, which means HAProxy is dead, hung or not listening. The check deliberately does **not** depend on agents or backends, so an application outage never moves the VIP: moving it would not help.

> **Gotcha: `weight` + `nopreempt`.** Many examples (including common HAProxy+keepalived guides) use `weight` in `vrrp_script`, so that a failed check *lowers* the master's priority. With `nopreempt` that does **not** move the VIP: the backup now has the higher priority but is not allowed to preempt. Without `weight`, a failing script puts the node in **FAULT** state, it releases the VIP, and the backup takes over. That is what this config does.

## 7.2 Deploy

Deploy node1 first (it wins the initial election), then node2:

```bash
lab/deploy-keepalived.sh waf-node1
lab/deploy-keepalived.sh waf-node2
```

The script uploads the track script, renders the config, validates it with `keepalived -t`, then starts or reloads keepalived.

```
keepalived on waf-node1: active, Keepalived v2.2.8 (04/04,2023), git commit v2.2.7-154-g292b299e+
keepalived on waf-node2: active, Keepalived v2.2.8 (04/04,2023), git commit v2.2.7-154-g292b299e+
```

Logs (`journalctl -u keepalived`):

```
waf-node1: VRRP_Script(chk_haproxy) succeeded
waf-node1: (VI_WAF) Entering BACKUP STATE
waf-node1: (VI_WAF) Entering MASTER STATE
waf-node2: VRRP_Script(chk_haproxy) succeeded
waf-node2: (VI_WAF) Entering BACKUP STATE
```

## 7.3 Verify

[`tools/vip-owner.sh`](../tools/vip-owner.sh) prints which node(s) hold the VIP. It exits 0 when there is exactly one owner and 2 when there is none or more than one. [`tests/test_keepalived.sh`](../tests/test_keepalived.sh) also checks both apps through the VIP:

```bash
bash tests/test_keepalived.sh
```

```
PASS VIP owner is waf-node1
PASS app1 via VIP
PASS app2 via VIP
```

### The standby node can reboot safely

Reboot node2 while node1 holds the VIP:

```bash
lab/ssh.sh waf-node2 'sudo systemctl reboot'
# after boot:
haproxy=active keepalived=active nginx=active nonlocal_bind=1
Registered Instances: 2
PASS VIP owner is waf-node1
```

HAProxy starts on a node without the VIP (it binds the VIP thanks to `ip_nonlocal_bind`), and the agent re-attaches to NGINX by itself.

### Split-brain: VRRP must be allowed between the nodes

If anything blocks VRRP (IP protocol **112**) between the nodes, each node believes it is alone and **both take the VIP**. The lab reproduces this with a temporary nftables drop on node2:

```bash
lab/ssh.sh waf-node2 'sudo nft add table inet vrrptest;
  sudo nft add chain inet vrrptest in "{ type filter hook input priority -10; }";
  sudo nft add rule inet vrrptest in ip protocol 112 drop'
tools/vip-owner.sh      # → waf-node1, waf-node2   (exit 2: split-brain)
lab/ssh.sh waf-node2 'sudo nft delete table inet vrrptest'
tools/vip-owner.sh      # → waf-node1              (exit 0)
```

With two owners, the firewall's ARP entry for the VIP points at whichever node sent the last gratuitous ARP, so which node receives the traffic is unpredictable. *(The lab measured the double ownership, not the traffic behaviour during it.)*

Allow **protocol 112 between all WAF nodes** in:

- host firewalls on the nodes (ufw, firewalld, nftables),
- NSX distributed firewall rules,
- any ACL between the nodes, if they are not on the same segment. Keep them on the same L2 segment, because the VIP has to move between them.

Monitor `vip-owner`-style checks in production: alert if the VIP is on zero nodes or on more than one.
