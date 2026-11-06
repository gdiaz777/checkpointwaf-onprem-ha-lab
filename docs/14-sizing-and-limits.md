# 14. Sizing and limits

> **Not validated under load.** The lab measured availability (failover, scale-out, rotation), not capacity. This chapter combines the architecture's behaviour with the limits read from the lab nodes. Load-test your own nodes before production (14.5).

## 14.1 The rule: every node is identical, and sized for the worst case

**Any node can become the VIP owner**, after a failure, a reboot or a failback. So:

- **Never give the "current" VIP owner more resources than the others.** After a failover, a smaller node would inherit the whole HAProxy load without the CPU to carry it, which is exactly when you need capacity most.
- **Size every node for the worst case:** it holds the VIP **and** one other node is down.

In that worst case the node runs two roles at once:

| Role | Load on the node | Why |
|---|---|---|
| **HAProxy (VIP owner)** | **100 %** of the traffic | terminates **all** client TLS (leg ①), re-encrypts to the agents (leg ②), routes, checks |
| **Agent (inspection)** | **1 / (N − 1)** of the traffic | the inspection is shared by the surviving agents |

```
CPU per node  ≥  CPU_HAProxy(100 % of traffic)  +  CPU_agent(traffic / (N − 1))
```

Consequences:

- **Adding nodes reduces the inspection share of each node, but not the HAProxy share.** Every node must always be able to carry the full HAProxy load. Beyond a few nodes, the HAProxy part dominates and more nodes bring less and less.
- **With 2 nodes, N − 1 = 1:** each node must be able to carry **everything alone** (HAProxy + all inspection). That is the price of HA with two nodes.
- The same applies to **memory** (TLS sessions, connections, agent) and to the **NIC**: on the VIP owner, the traffic crosses the NIC 2–3 times (client → HAProxy → agents → back).

## 14.2 Limits, from the hardest to hit to the easiest

| Limit | Value in the lab | Practical impact |
|---|---|---|
| Nodes per cluster (HAProxy servers, keepalived peers) | thousands of servers per backend; VRRP priorities 1–254 | **None** in practice |
| HAProxy `maxconn` | **262 113** (derived from the file-descriptor limit; `show info`) | Not a limit, but **set it explicitly** so behaviour under load is predictable (14.4) |
| Health checks | N HAProxy × N agents × A apps, every 3 s. Lab: 3 × 3 × 2 / 3 s = **6 checks/s** | Grows with **N² × A**: 10 nodes × 10 apps ≈ 330 checks/s on the agents, and as many log events if the log trigger records every request ([chapter 6](06-haproxy.md)) |
| TLS handshakes on the VIP owner | — | **The real ceiling of the design:** one HAProxy terminates every new client TLS connection and opens TLS to the agents. New connections per second cost far more CPU than bytes per second |
| NIC / east-west traffic of the VIP owner | — | All traffic goes through one node's NIC 2–3 times |
| **NGINX `worker_connections`** | **768** per worker × 2 workers (2 vCPU), soft limit of **1024 open files** per worker (Ubuntu defaults) | **The first limit you will hit.** Each request through the agent uses 2 connections (from HAProxy, to the backend): about **768 concurrent requests per node**. Raise it (14.4) |
| Perimeter firewall connection table | — | Check the firewall's connection capacity for the published IP |
| Agent inspection capacity | — | Depends on the agent version, the practice and the traffic profile. Ask Check Point for sizing figures for your version |

## 14.3 Where the bottleneck moves as you grow

1. **Few nodes, defaults:** NGINX `worker_connections` (768) caps concurrency per agent.
2. **After raising it:** **inspection CPU** on the agents. This scales **linearly** with nodes.
3. **Many nodes:** the **VIP owner's HAProxy**: TLS handshakes, CPU and NIC. This does **not** scale with nodes, because only one HAProxy is active.

## 14.4 Recommended production settings

> Proposed values, not load-tested in this lab. They are not applied in the lab configs; validate them with 14.5.

**Every node, NGINX** (`/etc/nginx/nginx.conf`):

```nginx
worker_processes auto;                 # one per vCPU
worker_rlimit_nofile 65535;            # raise the per-worker file limit
events {
    worker_connections 16384;          # default 768 → ~768 concurrent requests per node
}
```

**Every node, HAProxy** (`global` / `defaults`):

```haproxy
global
    maxconn 50000                       # explicit ceiling instead of the fd-derived 262k
    nbthread <vCPUs>                    # HAProxy 2.8 uses all CPUs by default; keep it explicit
    tune.ssl.cachesize 100000           # TLS session cache: resumed sessions avoid full handshakes
defaults
    http-reuse safe                     # (default) reuse HAProxy → agent connections
```

- **Prefer ECDSA certificates** for the client-facing leg if your clients support them. ECDSA handshakes cost far less CPU than RSA-2048. HAProxy can serve both, ECDSA and RSA, for the same SNI.
- **Keep client keep-alive enabled.** Most of the cost is in new TLS connections, not in requests on an existing connection.

**Health checks** when N or the number of apps grows:

- check each agent **once** with an agent-only check (for example a dedicated `/healthz` server block answered by NGINX itself), instead of once per app end to end, accepting that a backend failure is then detected only from real traffic (`observe layer7`), or
- lengthen `inter` (for example `5s`) at the cost of slower detection.

## 14.5 How to size: measure before production

Use the lab's method with a load generator instead of the probe:

1. Build the nodes **identical** (same vCPU, RAM, NIC) and with the 14.4 settings.
2. From a client outside the firewall, load the VIP with a realistic mix:
   - **new-connection-heavy** (no keep-alive, every request a new TLS handshake), for example `h2load -n 200000 -c 200 --h1 -H 'Connection: close' https://app1.example.com/`, and
   - **keep-alive** (many requests per connection), for example `h2load -n 500000 -c 200 -m 10 https://app1.example.com/`.
3. Watch **CPU per process** on the VIP owner (`haproxy`, `nginx`, `cp-nano-http-transaction-handler`) and on the other nodes, plus latency and errors at the client.
4. **Repeat with one node powered off (N − 1)** and with attacks mixed in (inspection cost rises with what the agent has to analyse).
5. The capacity you can sell is the **N − 1 result**, with headroom (for example ≤ 60–70 % CPU on the VIP owner).

## 14.6 If one node's HAProxy is not enough

All options keep the nodes of each role **identical**:

| Option | How | Trade-off |
|---|---|---|
| **More vCPU on every node** | Scale all nodes up equally | Simplest. Every node keeps being able to take the VIP |
| **Split the roles** | A dedicated, identical **HAProxy/keepalived pair** (sized for 100 % of the TLS) in front of N **agent-only** nodes | Each layer is sized for its own job. Two more VMs. `render.sh` needs separate lists for HAProxy servers and keepalived peers |
| **Several active VIPs** | 2+ VIPs with different `virtual_router_id`, each preferring a different node, and the firewall publishing both (or DNS round-robin) | Spreads the HAProxy load in normal operation. **When a node fails, a survivor holds several VIPs**, so the worst-case sizing of 14.1 still applies |
