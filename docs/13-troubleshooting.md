# 13. Troubleshooting

Problems actually hit while building this lab, plus the checks used to find them.

## Quick health check

```bash
tools/vip-owner.sh                       # exactly one owner (exit 0)
bash tests/test_keepalived.sh            # VIP + both apps
bash tests/test_haproxy.sh               # every HAProxy: routing, spread over all agents, all servers UP
bash tests/test_agent_proxy.sh           # every agent's NGINX proxies both apps
bash tests/test_cert_rotation.sh         # every node presents the current cert, on HAProxy and on the agent
lab/ssh.sh waf-node1 'sudo cpnano -s'    # agent: Status Running, Policy version, Registered Instances > 0
```

Per node:

```bash
sudo journalctl -u keepalived -n 50      # Entering MASTER/BACKUP/FAULT STATE, chk_haproxy results
echo "show stat" | sudo socat stdio /run/haproxy/admin.sock | cut -d, -f1,2,18,37 | column -s, -t
sudo nginx -t && grep load_module /etc/nginx/nginx.conf
```

## Problems seen in the lab

| Symptom | Cause | Fix |
|---|---|---|
| **Attacks pass (HTTP 200) even in Prevent, and the portal shows no security events.** Only `Info` events with an empty *Asset Name* appear (e.g. "Web AppSec Policy Loaded Successfully") | The agent matches assets on **host AND listening port** (`EqualListeningPort(443)` in `/etc/cp/conf/policy.json`). The agent's NGINX listened on 8443, so no request matched any asset | Make NGINX listen on the asset URL's port (`<node IP>:443`) and HAProxy on the VIP ([chapter 4](04-infinity-portal.md), 4.2). Check with `EXPECT_WAF=1 bash tests/test_agent_proxy.sh` |
| HAProxy fails to start with "cannot bind socket" for the VIP on a standby node | `net.ipv4.ip_nonlocal_bind` not set | `sysctl.d` file from [`configs/sysctl/`](../configs/sysctl/99-waflab.conf) |
| HAProxy or NGINX fails to start with "address already in use" on 443 | One of them binds `*:443`/`0.0.0.0:443` | HAProxy must bind only the VIP and 127.0.0.1; NGINX only the node's own IP |
| `nginx: [emerg] unknown directive "http2"` after deploying the agent's site | Ubuntu 24.04 ships NGINX **1.24**. `http2 on;` needs 1.25.1+ | Remove it (HAProxy talks HTTP/1.1 to the agent), or use `listen … ssl http2` on 1.24 |
| Agent installed but `Policy version` empty for ~2 minutes, `Manifest status: Failed. Reason: Failed to download the file manifest` | Normal first-time download. It recovered by itself | Wait. Check outbound HTTPS from the node and the clock (`timedatectl`) if it does not recover |
| VIP never moves when HAProxy hangs, although `chk_haproxy` fails | `vrrp_script` with `weight` + `nopreempt`: the master's priority drops, but the backup may not preempt | Use the script **without `weight`** (failure means FAULT). See [chapter 7](07-keepalived.md) |
| `chk_haproxy` keeps succeeding while HAProxy is frozen | Process-existence checks (`killall -0 haproxy`, `pidof`) do not detect a hung process | Check that HAProxy **answers**: `curl -m 2 http://127.0.0.1/` |
| Both nodes hold the VIP | VRRP (IP protocol 112) blocked between nodes (host firewall, NSX DFW, ACL) | Allow protocol 112 between all WAF nodes. Alert when `vip-owner` ≠ 1 |
| New node takes the VIP when it joins (split-brain) | The new node's keepalived started before the existing nodes listed it as `unicast_peer`: it hears no master | Reload keepalived on the existing nodes **first**, start the new node **last** ([chapter 10](10-scale-out.md)) |
| A dead node (powered off) causes 2–3 s stalls / client timeouts for ~10 s | No TCP reset from a powered-off VM. HAProxy waited `timeout connect 3s` before retrying | `timeout connect 1s` + `option redispatch 1` ([chapter 9](09-failover-tests.md), 9.4) |
| Portal flooded with *Info* "Web Request" events for `/healthz` from the HAProxy node IPs | HAProxy end-to-end health checks pass through the agents, and the log trigger records every web request | Log only security events, or add a no-log exception for `/healthz` from the node IPs ([chapter 6](06-haproxy.md)) |
| Searching the portal logs for a client IP finds nothing | **Source IP** is the HAProxy node (TCP peer). The client is in **Source Identifier** (from X-Forwarded-For) | Filter on Source Identifier ([chapter 8](08-firewall-dnat.md)) |
| The WAF sees a client-chosen source IP | HAProxy appended to a client-supplied `X-Forwarded-For` | `http-request del-header X-Forwarded-For` in the frontend ([chapter 6](06-haproxy.md)) |
| Clients get 403s/blocks attributed to a node IP, or learning sees few distinct users | The asset is not using `X-Forwarded-For` as source identity | Asset → Source identity: X-Forwarded-For. Trusted sources: the HAProxy node IPs ([chapter 4](04-infinity-portal.md)) |
| Client IP is the firewall's IP | Source NAT (hide NAT) on the perimeter firewall towards the VIP | DNAT only, keep the original source ([chapter 8](08-firewall-dnat.md)) |
| New connections from outside to the VIP are rejected (lab) | libvirt NAT networks only allow established inbound traffic | `lab/host-fw.sh up` inserts an ACCEPT for the VIP ahead of libvirt's chains. Re-run it after host reboots or libvirt restarts |
| A `git commit` is refused with `pre-commit: possible secret found` | `tools/check-secrets.sh` matched a token, a private key or a forbidden word | Remove the secret from the staged file. Secrets belong in `.env` / `certs/` (git-ignored) |

## Lab tooling pitfalls (if you reuse the scripts)

- `ssh … | grep -q` under `set -o pipefail` can loop forever: `grep -q` exits early, `ssh` gets SIGPIPE and the pipeline "fails". Capture the output first, then grep.
- `pkill -f <pattern>` run through SSH or `bash -c` can match **its own** command line. The scenario runner stops the probes through a PID file instead.
- `.env` is `source`d by the scripts, so quote every value (`KEY="value"`). An unquoted `<placeholder>` is a shell redirection.
