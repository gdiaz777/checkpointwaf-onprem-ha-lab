# 10. Scale-out: adding (and removing) a node

Capacity grows by adding another identical node. **Nothing changes on the firewall or in the Infinity Portal**: the new agent registers with the same token and profile, and the firewall keeps DNATing to the same VIP.

Measured in the lab with probes running (≈5 req/s per app):

| Operation | Failed requests | Longest gap | VIP |
|---|---|---|---|
| Add `waf-node3` to a running 2-node cluster | **0** | 0.2 s (= the probe interval, i.e. no gap) | stays on node1 |
| Remove `waf-node3` from a running 3-node cluster | **0** | 0.2 s | stays on node1 |

## 10.1 Add a node

[`lab/add-node.sh <name> <ip>`](../lab/add-node.sh) runs the procedure below. Run it by hand the first time. **The order matters.**

| Step | Action | Why this order |
|---|---|---|
| 1 | Build the VM (same template) and install NGINX + the agent with the **same token**. Wait for `Registered Instances > 0` | The new agent must be ready before it receives traffic. This step does not touch the running cluster |
| 2 | Add the node to `WAF_NODES` in [`lab/inventory.env`](../lab/inventory.env) | This is the single list every config is rendered from |
| 3 | Re-render and **reload keepalived on the existing nodes** | They learn the new `unicast_peer` |
| 4 | Re-render and **reload HAProxy on the existing nodes** | The new agent is added to every pool. A reload is hitless |
| 5 | Deploy HAProxy and keepalived on the **new node last** | When it starts, it already hears the current master, so it stays BACKUP |

> **Do not start keepalived on the new node before step 3.** With unicast VRRP the existing master only sends adverts to the peers it knows. A new node that is not yet in their `unicast_peer` list hears nothing, declares itself MASTER and grabs the VIP: a split-brain.

Lab run (`tests/results/s10-scale-out/`):

```
=== 01:52:13  1/5 create VM waf-node3 (10.90.20.13)
=== 01:52:14  1/5 NGINX + agent on waf-node3
=== 01:52:18  2/5 WAF_NODES is now: waf-node1:10.90.20.11 waf-node2:10.90.20.12 waf-node3:10.90.20.13
=== 01:52:18  3/5 keepalived: existing nodes learn the new peer
=== 01:52:22  4/5 HAProxy: existing nodes add the new agent to every pool
=== 01:52:28  5/5 HAProxy + keepalived on waf-node3 (joins as BACKUP)
    VIP owner: waf-node1

app1: total=512 failed=0 max_gap_s=0.2
  before {'10.90.20.11': 27, '10.90.20.12': 26}
  during {'10.90.20.11': 63, '10.90.20.12': 63, '10.90.20.13': 32}
  after  {'10.90.20.11': 101, '10.90.20.12': 100, '10.90.20.13': 100}
```

The new agent takes its third of the traffic as soon as HAProxy is reloaded (step 4). Its HAProxy and keepalived do not handle client traffic until it becomes VIP owner.

> In the measured run the VM and the agent (step 1) already existed (the node had just been removed, see 10.2), so the script skipped the build and the measured window covers steps 2–5, the ones that touch the running cluster. Step 1 sends no traffic to the new node by construction.

After adding:

```bash
bash tests/test_haproxy.sh      # "spread over 3 agents" on every node, "6/6 servers UP" on every node
bash tests/test_keepalived.sh   # VIP owner unchanged
```

On **vSphere**, also add the new VM to the DRS anti-affinity rule ([chapter 12](12-vsphere.md)). Add its IP to the asset's **trusted sources** if you list the HAProxy nodes there ([chapter 4](04-infinity-portal.md)). The lab already listed `.13` from the start.

## 10.2 Remove a node

[`lab/remove-node.sh <name>`](../lab/remove-node.sh):

| Step | Action |
|---|---|
| 1 | **Drain** the node on every HAProxy through the runtime API: `set server be_appN/<node> state drain`. No new requests go to it, existing ones finish, and no reload is needed. Wait until its active sessions are 0 |
| 2 | Make sure it does not hold the VIP. If it does, stop its keepalived first: a clean stop hands the VIP over immediately ([chapter 9](09-failover-tests.md), S9) |
| 3 | Stop keepalived on it, remove it from `WAF_NODES`, re-render and reload keepalived and HAProxy on the remaining nodes |
| 4 | Stop HAProxy and NGINX on the removed node |

```bash
echo "set server be_app1/waf-node3 state drain" | sudo socat stdio /run/haproxy/admin.sock
```

Lab run (`tests/results/s11-scale-in/`):

```
=== 1/4 drain waf-node3 on every HAProxy
    active sessions to waf-node3: 0
=== 2/4 VIP must not be on waf-node3
=== 3/4 stop keepalived on waf-node3, update WAF_NODES, reload the remaining nodes
=== 4/4 stop HAProxy and NGINX on waf-node3
app1: total=354 failed=0 max_gap_s=0.2
  before {'10.90.20.11': 18, '10.90.20.12': 17, '10.90.20.13': 18}
  during {'10.90.20.11': 49, '10.90.20.12': 50}
```

**Decommissioning** (not executed in the lab, which kept node3): run `sudo cpnano -u` on the node to uninstall the agent, delete the agent from the Infinity Portal agents list, remove the VM from the DRS rule and delete the VM.

## 10.3 How far does this scale?

- **Agents (inspection)** scale linearly: every HAProxy spreads the load over all of them.
- **Only one HAProxy is active at a time**: the one holding the VIP terminates **all** client TLS. Keep **all nodes identical** and size **every** node for the case where it holds the VIP while another node is down, because any node can become VIP owner. See [chapter 14](14-sizing-and-limits.md). If you ever need more, split the roles: run a dedicated HAProxy/keepalived pair in front of N agent-only nodes. The configs carry over, but `lab/render.sh` derives both the HAProxy server list and the keepalived peers from `WAF_NODES`, so you would need two lists. *(Not built or tested in this lab.)*
- **keepalived priorities** come from the node's position in `WAF_NODES` (110, 100, 90, …).
