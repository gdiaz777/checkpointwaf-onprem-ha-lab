# 6. HAProxy on each node

HAProxy replaces the load balancer the customer does not have. It runs on **every** WAF node with the **same** config, but only the node holding the VIP receives client traffic ([chapter 7](07-keepalived.md)). That node:

1. terminates the client TLS with the app certificate selected by SNI,
2. adds `X-Forwarded-For` (real client IP) and `X-Forwarded-Proto`,
3. routes by `Host` to the pool of that app,
4. spreads requests across **all** agents (the local one and the other nodes'),
5. health-checks every agent, removes failed ones and retries failed connections on another agent.

HAProxy does **not** inspect traffic. That is the agent's job.

Version in the lab: **HAProxy 2.8.30** (Ubuntu 24.04 package).

## 6.1 Configuration

Template: [`configs/haproxy/haproxy.cfg.tmpl`](../configs/haproxy/haproxy.cfg.tmpl). [`lab/render.sh`](../lab/render.sh) renders it per node from [`lab/inventory.env`](../lab/inventory.env). The `server` lines come from `WAF_NODES`, so adding a node means changing one variable.

Rendered pool for app1 (2 nodes):

```haproxy
backend be_app1
    balance leastconn
    option httpchk
    http-check send meth GET uri /healthz ver HTTP/1.1 hdr Host app1.waflab.example
    http-check expect status 200
    http-response set-header X-Served-By waf-node1/%[srv_name]
    default-server check inter 3s fall 3 rise 2 slowstart 30s ssl verify required ca-file /etc/haproxy/ca.crt sni str(app1.waflab.example) check-sni app1.waflab.example observe layer7 error-limit 10 on-error fastinter fastinter 1s
    server waf-node1 10.90.20.11:443
    server waf-node2 10.90.20.12:443
```

| Directive | Why |
|---|---|
| `bind <VIP>:443 ssl crt-list /etc/haproxy/crt-list.txt` | One listener for all apps, **on the VIP only**: the node's own IP:443 belongs to the agent's NGINX (the asset matches on port 443, [chapter 4](04-infinity-portal.md)). [`crt-list.txt`](../configs/haproxy/crt-list.txt) maps each SNI to its certificate |
| `bind 127.0.0.1:80` / `127.0.0.1:443` | Local listeners for the keepalived track script and for tests run on the node |
| `bind <VIP>:80` + `redirect scheme https` | HTTP → HTTPS |
| `http-request del-header X-Forwarded-For` | HAProxy is the edge (the firewall only DNATs), so a client-supplied `X-Forwarded-For` is **discarded**. Otherwise a client could put any IP first in the chain and impersonate it towards the WAF (rate limits, exceptions, learning). Tested: a request with `X-Forwarded-For: 6.6.6.6` reaches the backend as `10.90.30.10, …` |
| `use_backend be_appN if { req.hdr(host),field(1,:) -i appN… }` | Host-based routing. Unknown hosts get **404** (`be_unknown`) |
| `option forwardfor` | Adds `X-Forwarded-For: <client IP>`. The asset uses it as source identity ([chapter 4](04-infinity-portal.md)) |
| `balance leastconn` | New requests go to the agent with the fewest active connections |
| **One pool per app, same agents in each** | Each pool health-checks with **its own Host**, end to end to that app's backend. If app1's backend fails, only `be_app1` marks its servers DOWN, and app2 keeps working (tested in chapter 9, scenario 8) |
| `http-check send … hdr Host appN…` | Without the right Host (and SNI) the agent's NGINX would not select the app's `server` block |
| `ssl verify required ca-file … sni … check-sni …` | HAProxy re-encrypts to the agent and verifies the agent's certificate, for both traffic and health checks |
| `check inter 3s fall 3 rise 2` | DOWN after 3 failed checks (~9 s), UP again after 2 good ones |
| `slowstart 30s` | A recovered agent gets its share of traffic progressively over 30 s |
| `retries 3` + `option redispatch` | If a connection to an agent fails, the **same request** is retried on another agent, so the client does not see the error |
| `observe layer7 error-limit 10 on-error fastinter fastinter 1s` | Passive check: after 10 consecutive 5xx on real traffic, HAProxy runs the active (end-to-end) check **every 1 s** instead of every 3 s, so a broken agent goes DOWN in ~3 s. It deliberately does **not** use `mark-down`: each pool contains *all* agents, and agents pass the backend's own 5xx through. With `mark-down`, one failing URL of the app would eject every agent and take the whole app down |
| `X-Served-By: <haproxy node>/<agent>` | Debug header showing which HAProxy and which agent handled the request. The tests use it. Remove it in production if you prefer not to expose node names |
| `listen stats` on `<node IP>:8404` | Stats page per node, bound to the node's own IP (not the VIP), password from `.env` |

[`configs/sysctl/99-waflab.conf`](../configs/sysctl/99-waflab.conf) sets `net.ipv4.ip_nonlocal_bind = 1`. It is **required**: HAProxy binds the VIP on every node, and on a node that does not hold the VIP it could not start without it ([chapter 7](07-keepalived.md) tests a reboot of a standby node).

### Health checks show up in the WAF logs

The checks go **through the agents** (that is what makes them end to end), so the agents inspect and, depending on the asset's log settings, **log** them. In the lab the portal showed every check as an *Info* "Web Request" event: URI `/healthz`, Source IP = the HAProxy node. That is 3 HAProxy × 3 agents × 2 apps every 3 s, about **6 events per second, more than 500 000 a day**, all noise. It happens when the log trigger records every web request, not only security events. Options:

- log only security events (not every web request) in the log trigger used by the assets, or
- keep full request logging, but add an exception for `GET /healthz` from the WAF nodes' IPs so it is not logged, or
- make the checks less frequent (`inter 5s`), at the cost of slower detection.

*(Validate the exact option names in your portal; the lab only observed the events.)*

## 6.2 Deploy

```bash
lab/deploy-haproxy.sh waf-node1
lab/deploy-haproxy.sh waf-node2
```

[`lab/deploy-haproxy.sh`](../lab/deploy-haproxy.sh):

1. installs the package,
2. uploads the CA, the app `.pem` files (atomic rename) and the crt-list,
3. renders `haproxy.cfg.new`,
4. **validates it with `haproxy -c` before replacing the running config**,
5. **reloads**. A reload is hitless: the old worker finishes its connections.

```
haproxy on waf-node1: active, HAProxy version 2.8.30-0ubuntu0.24.04.2 2026/10/27 - https://haproxy.org/
haproxy on waf-node2: active, HAProxy version 2.8.30-0ubuntu0.24.04.2 2026/10/27 - https://haproxy.org/
```

## 6.3 Verify

[`tests/test_haproxy.sh`](../tests/test_haproxy.sh) tests **each node's HAProxy** from the node itself on `127.0.0.1:443`, since HAProxy only listens on the VIP and loopback. That works before the VIP exists and on standby nodes:

```bash
bash tests/test_haproxy.sh
```

```
PASS 10.90.20.11 app1 routed, xff starts with client
PASS 10.90.20.11 app1 x-served-by: waf-node1/waf-node2
PASS 10.90.20.11 app1 spread over 3 agents
PASS 10.90.20.11 app2 routed, xff starts with client
PASS 10.90.20.11 app2 spread over 3 agents
PASS 10.90.20.11 unknown host → 404
PASS 10.90.20.12 app1 routed, xff starts with client
PASS 10.90.20.12 app1 x-served-by: waf-node2/waf-node3
...
PASS waf-node1 stats: 6/6 servers UP
PASS waf-node2 stats: 6/6 servers UP
PASS waf-node3 stats: 6/6 servers UP
```

Note `waf-node2/waf-node3`: HAProxy on node2 sent that request to the agent on node3. Every HAProxy uses every agent. (Output with 3 nodes; with 2 nodes it reads "spread over 2 agents" and "4/4 servers UP".)

Stats page: `http://10.90.20.11:8404/stats`, user `admin`, password `HAPROXY_STATS_PASS` from `.env`.
