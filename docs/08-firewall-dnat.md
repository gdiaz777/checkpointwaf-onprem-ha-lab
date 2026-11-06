# 8. Perimeter firewall: DNAT to the VIP

The only thing the perimeter firewall has to do is publish the application IP and **DNAT it to the VIP**, **without source NAT**. The WAF then sees the real client IP, and HAProxy forwards it to the agents in `X-Forwarded-For`.

```
client 10.90.30.10 ──▶ 10.90.30.1:443 (published IP) ──DNAT──▶ VIP 10.90.20.100:443 ──▶ HAProxy on the VIP owner
```

The firewall does not need to know about the nodes. When the VIP moves, the new owner sends a gratuitous ARP and the firewall's ARP entry for the VIP updates.

## 8.1 Lab: the host is the firewall

[`lab/host-fw.sh`](../lab/host-fw.sh) `up | down | status` manages iptables rules on the host, all tagged with the comment `waflab-fw`:

| Rule | Purpose |
|---|---|
| `nat PREROUTING -d 10.90.30.1 -p tcp --dports 80,443 -j DNAT --to 10.90.20.100` | The published IP on the outside network → VIP |
| `nat PREROUTING/OUTPUT -d 192.168.1.20 … -j DNAT --to 10.90.20.100` | The host's LAN IP → VIP (convenience for testing from the LAN) |
| `filter FORWARD -d 10.90.20.100 --dports 80,443 -j ACCEPT` (first in the chain) | libvirt's NAT network rejects new inbound connections. This rule lets **only** the published flows in |
| `nat POSTROUTING -s 10.90.30.0/24 -o <LAN> -j MASQUERADE` | Internet access for the test client (time sync). It is **not** applied towards the WAF network |

```bash
lab/host-fw.sh up
```

```
host firewall up: 10.90.30.1,192.168.1.20 :80,443 → 10.90.20.100 ; 10.90.30.0/24 masqueraded via enp49s0
```

The script is idempotent: `up` removes the previous rules first. The rules are **not persistent**. Run `up` again after a host reboot or a libvirt network restart.

On the client VM, the FQDNs must resolve to the published IP and the lab CA must be trusted. [`lab/setup-client.sh`](../lab/setup-client.sh) does both, and is idempotent:

```bash
lab/setup-client.sh
# 10.90.30.1      app1.waflab.example app2.waflab.example
```

It writes the hosts entry to `/etc/hosts` **and** to `/etc/cloud/templates/hosts.debian.tmpl`, because cloud-init (`manage_etc_hosts: true`) rewrites `/etc/hosts` at every boot. Without the template, the entry disappears after a reboot.

## 8.2 Verify

[`tests/test_firewall.sh`](../tests/test_firewall.sh):

```
PASS client → app1 via firewall, real IP preserved (10.90.30.10)
PASS client → app2 via firewall, real IP preserved (10.90.30.10)
PASS client cannot reach backend1 directly
PASS client cannot reach an agent directly
PASS client has Internet (HTTP 200)
PASS client clock synchronized
PASS host LAN 192.168.1.20:443 → VIP
```

"Real IP preserved" means that the first `X-Forwarded-For` entry the backend receives is `10.90.30.10`. The full chain is `10.90.30.10, <HAProxy node IP>`: HAProxy adds the client, and the agent's NGINX appends the HAProxy node.

HAProxy discards any `X-Forwarded-For` sent by the client ([chapter 6](06-haproxy.md)), so the client cannot choose the IP the WAF sees. Tested: `X-Forwarded-For: 6.6.6.6` from the client still arrives as `10.90.30.10, …`.

**Confirmed in the Infinity Portal logs.** Every event for traffic through the firewall and the VIP shows two fields:

| Portal field | Value | Meaning |
|---|---|---|
| **Source IP** | `10.90.20.11` (the HAProxy node) | the TCP peer the agent saw |
| **Source Identifier** | **`10.90.30.10`** (the client) | the identity the WAF uses, taken from `X-Forwarded-For` because the asset's source identity is *X-Forwarded-For* ([chapter 4](04-infinity-portal.md)) |

The 14 attacks sent from the client (XSS and SQLi, both apps) were logged as *Prevent* with Source Identifier `10.90.30.10`. That includes the two sent with a forged `X-Forwarded-For: 6.6.6.6`: `6.6.6.6` does not appear anywhere in the logs. Use **Source Identifier**, not Source IP, when you search the logs for a client.

## 8.3 Check Point gateway: the equivalent rules

> **Not validated in this lab.** The lab has no Check Point gateway. Below is how the rules above map onto a Check Point cluster (SmartConsole, R81.x/R82). Validate them in your environment.

**Objects**

- Host `app-public` = the published IP (for example `203.0.113.10`).
- Host `waf-vip` = `10.90.20.100`.
- Host objects for the WAF nodes (`10.90.20.11-13`), needed for the rules below.

**NAT rule** (manual NAT, above any automatic hide NAT that could match):

| Original source | Original destination | Original services | Translated source | Translated destination | Translated services |
|---|---|---|---|---|---|
| Any | `app-public` | https, http | **Original** (no source NAT) | `waf-vip` (static) | Original |

**Access rule:**

| Source | Destination | Services | Action |
|---|---|---|---|
| Any (or Internet) | `app-public` | https, http | Accept |

With manual NAT the access rule matches on the **original** destination (`app-public`). Manual NAT rules do not create proxy-ARP automatically. If the upstream router ARPs for the published IP (rather than routing it to the gateway), add a proxy-ARP entry for it on the cluster members (`local.arp` / Gaia proxy ARP).

**Things to keep in mind**

- **No source NAT (hide NAT) towards the WAF**, or every request will come from the gateway IP and the WAF loses the client IP. If the gateway must hide-NAT, the client IP is gone at layer 3. The only alternative is a proxy in front that adds `X-Forwarded-For`.
- **Gratuitous ARP from keepalived.** The VIP moves between nodes with different MAC addresses. The gateway must accept gratuitous ARP on that interface and update its ARP cache. Check Point does by default; if failover takes minutes, look at the ARP cache on the gateway (`arp -a`).
- **Gateway-to-node rules** if the gateway also filters between the WAF network and the backend network. Allow agents → backends on 443, agents → Infinity Portal (HTTPS outbound) and VRRP (protocol 112) between the nodes, if that traffic crosses the gateway.
- **Same L2 segment for all WAF nodes and the VIP.** The VIP must be able to move between them.
