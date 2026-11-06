# 9. Failover tests (measured)

Every scenario below was run in the lab with traffic flowing, and the numbers are measured, not estimated. The setup is the final architecture: 2 WAF nodes, agents on `<node IP>:443`, HAProxy on the VIP, assets in **Prevent**.

## 9.1 Method

[`lab/run-scenario.sh`](../lab/run-scenario.sh) `<id> "<inject>" "<restore>" [settle_s] [post_s]`:

1. starts [`tests/probe.py`](../tests/probe.py) on the **client VM**, one per app, through the firewall DNAT. Each probe sends one HTTPS request every 0.2 s (≈5 req/s per app), opens a **new connection per request** and gives up after **2 s**,
2. runs the failure injection, waits, runs the restore and waits again,
3. collects the CSVs and summarizes them with [`tests/summarize.py`](../tests/summarize.py).

Every probe row records the HTTP status, the latency, `X-Served-By` (which HAProxy and which agent) and `client_addr` from the backend (which agent forwarded the request).

| Metric | Meaning |
|---|---|
| `failed` | requests without a 2xx/3xx answer (status 0 = no answer within 2 s, or a 5xx) |
| `max_gap_s` | **longest time without any successful answer**: the outage a user would feel |
| `before / during / after` | successful requests per agent before INJECT, between INJECT and RESTORE, and after RESTORE |
| `status counts` | answers per HTTP status over the whole run |

[`tests/run-all-scenarios.sh`](../tests/run-all-scenarios.sh) re-runs everything below in about 20 minutes. The raw CSVs stay local (git-ignored). The summaries, with events, windows, status counts and 10 s buckets, are in [`tests/results/`](../tests/results/). Baseline with no failure (`s00`): 0 failed, requests split exactly 50/50 across the two agents.

## 9.2 Results

| # | Scenario | Failed requests (app1 / app2) | Longest outage | VIP | Verdict |
|---|---|---|---|---|---|
| 1 | Agent data path on node2 down (its NGINX stopped) | **0 / 0** | 0.2 s (none) | stays on node1 | ✅ transparent |
| 2 | node2 VM powered off | **0 / 0** | 1.0 s | stays on node1 | ✅ transparent |
| 3 | node1 VM powered off (VIP holder) | 1 / 1 | **2.2 s** | → node2 | ✅ short outage |
| 4 | HAProxy on node1 hangs (SIGSTOP) | 3 / 3 | **6.2 s** | → node2 | ✅ short outage |
| 5 | Agent on node2 answers 503 | 6 / 12 (503) | 0.4 s | stays on node1 | ⚠️ errors for 2–4 s until ejected |
| 6 | node2's agent comes back | 0 | — | — | ✅ back in rotation in ~3 s |
| 7 | Agent on node2 stops inspecting (fail-open) | 1 / 1 (502) | 0.4 s | stays on node1 | ⚠️ **not detected: attacks through node2 pass** |
| 8 | Backend of app1 down | app1: 168 / **app2: 0** | app1: 34 s (whole outage) | stays on node1 | ✅ app2 isolated |
| 9 | Planned failback node2 → node1 | **0 / 0** | 1.1 s | → node1 | ✅ transparent |

### S1. The agent's data path on node2 goes down

[`tests/scenarios/s01-agent2-proxy-stop.sh`](../tests/scenarios/s01-agent2-proxy-stop.sh) runs `systemctl stop nginx` on node2, which is the reverse proxy the agent is attached to. The VM stays up.

```
app1: total=511 failed=0 max_gap_s=0.2
  before {'10.90.20.11': 27, '10.90.20.12': 26}
  during {'10.90.20.11': 150, '10.90.20.12': 1}
  after  {'10.90.20.11': 168, '10.90.20.12': 135}
app2: total=510 failed=0 max_gap_s=0.2
```

The connection to node2 is refused, and HAProxy immediately sends the same request to node1 (`retries 3` + `option redispatch 1`). The health check marks node2 DOWN within about 9 s, and from then on everything goes to node1. **No error and no measurable delay.**

> Why this scenario stops NGINX and not the agent: with fail-open (the default), stopping the agent does **not** stop traffic. That is scenario 7.

### S2. node2 VM powered off

`virsh destroy waf-node2` is the equivalent of pulling the plug. There is no TCP reset, so connections to node2 just hang.

```
app1: total=695 failed=0 max_gap_s=1.04
  during {'10.90.20.11': 138}
```

A request that HAProxy sends to the dead node waits for `timeout connect 1s` and is then retried on node1: about 1 s of extra latency on a few requests, and no errors. With the default `timeout connect 3s` the first runs of this lab had **6 failed requests per app** (the probe gave up after 2 s, see 9.4). When node2 boots again, its agent re-attaches and it rejoins the pools without manual action.

### S3. node1 VM powered off: the VIP moves

```
01:43:08  INJECT: virsh destroy waf-node1
01:43:44  vip owner after inject: waf-node2
app1: total=697 failed=1 max_gap_s=2.2
  status counts: {0: 1, 200: 696}
  during {'10.90.20.12': 141}
  after  {'10.90.20.11': 221, '10.90.20.12': 281}
```

- **Outage ≈ 2–4 s.** keepalived on node2 declares the master dead after about 3 missed adverts (`advert_int 1`), takes the VIP and sends a gratuitous ARP. This run measured 2.2 s; an earlier run of the same scenario measured 4.2 s. Requests in flight on node1 are lost, and clients reconnect.
- When node1 boots, its agent rejoins the pools (traffic is spread again in `after`), but **the VIP stays on node2** (`nopreempt`). That avoids a second outage.

### S4. HAProxy on node1 hangs

`pkill -STOP -x haproxy` on node1 freezes the master and the workers: the process exists but does not answer. A plain `killall -0 haproxy` check would **not** catch this. The curl-based check does:

```
Script `chk_haproxy` now returning 1
VRRP_Script(chk_haproxy) failed (exited with status 1)
(VI_WAF) Entering FAULT STATE             ← VIP released, node2 takes it
(VI_WAF) Entering BACKUP STATE            ← after SIGCONT, node1 stays backup
app1: total=384 failed=3 max_gap_s=6.22
  during {'10.90.20.11': 63, '10.90.20.12': 62}   ← node1's AGENT keeps serving through node2's HAProxy
```

- **Outage ≈ 6 s**: curl timeout (2 s) × `fall 2` with `interval 2`, then the VIP move. You can make it faster (`interval 1`, `curl -m 1`) at the cost of more false positives under load.
- This only works because the script has **no `weight`**, so the failure means FAULT. With `weight` + `nopreempt` the VIP would not have moved ([chapter 7](07-keepalived.md)).

### S5. The agent on node2 answers 503

Simulated by making node2's NGINX `return 503` for every location, the health check included.

```
app1: total=509 failed=6   status counts: {200: 503, 503: 6}    failures 01:38:19.1 → 01:38:21.1
app2: total=508 failed=12  status counts: {200: 496, 503: 12}   failures 01:38:19.1 → 01:38:23.5
  during {'10.90.20.11': 143}
```

`observe layer7 error-limit 10 on-error fastinter fastinter 1s` switches node2's active check to every 1 s as soon as real traffic shows errors, so node2 was ejected **2–4 s** after it started failing. It deliberately does not use `on-error mark-down` (see [chapter 6](06-haproxy.md)): that ejects an agent faster, but it also ejects **every** agent when the *backend* itself returns 5xx.

To hide these errors from users you can add `retry-on 503 conn-failure empty-response`, so HAProxy **retries the request on another agent**. Only do this if replaying requests is safe for your apps.

### S6. A recovered agent rejoins

Recovery phase of S1, in 5 s buckets (app1). NGINX on node2 was restarted at `t+41s` ([summary](../tests/results/s06-recovery-slowstart/summary.md)):

```
t+   40s {'10.90.20.11': 25}
t+   45s {'10.90.20.11': 15, '10.90.20.12': 10}
t+   50s {'10.90.20.11': 12, '10.90.20.12': 13}
```

node2 is back after 2 good checks (`rise 2` × 3 s) and fully balanced within 5 s. **`slowstart 30s` is barely visible here.** With `leastconn` and this light load (short sequential requests), both agents usually have 0 active connections, so the reduced weight hardly matters. `slowstart` protects a recovering agent under **real concurrent load**. Keep it; it costs nothing.

### S7. The agent stops inspecting (fail-open): attacks pass and HAProxy does not notice

`cpnano -q` on node2 stops the agent while its NGINX keeps running. While it was stopped, the same XSS was sent through each node's agent:

```
INJECT: cpnano -q
    Status: Not running
    XSS via agent 10.90.20.11 → HTTP 403          ← node1: inspected, blocked (Prevent)
    XSS via agent 10.90.20.12 → HTTP 200          ← node2: NOT inspected, attack reached the backend
app1: total=489 failed=1 max_gap_s=0.4
  status counts: {200: 488, 502: 1}
  during {'10.90.20.11': 101, '10.90.20.12': 100}  ← node2 still gets 50 % of the traffic
```

The Infinity Portal agrees. Repeating the check with a unique path (`/s7probe`) produced **exactly one** event: *Prevent*, "Cross-Site Scripting Obfuscation Techniques", reported by **node1's agent**. The same attack through node2 left **no event at all**: it was neither blocked nor logged.

Fail-open (`agent.failOpenState.nginxModule = true`, [chapter 5](05-agent.md)) keeps the application available. However, **half of the traffic is no longer inspected or logged**, and nothing in HAProxy or keepalived reacts, because the node is healthy from their point of view. One transient 502 per app was seen while the agent stopped.

How to detect it:

- **Infinity Portal → agent status.** Check in your tenant which agent-health notifications are available.
- Locally: `cpnano -s`, `Status: Not running`. You can export this to your monitoring (for example a Prometheus/Zabbix check that runs `cpnano -s`).
- A synthetic **attack probe** per node (like the XSS above) that alerts when it gets anything other than a block.
- If you prefer **failing closed** (no inspection means no traffic through that node), the agent's fail-open behaviour is a profile setting (`agent.failOpenState.nginxModule`). *Not tested in this lab:* with fail-close the attachment should reject requests while the agent is down, so HAProxy would eject the node as in S5. That trades some availability for never passing uninspected traffic. Validate it before relying on it.

### S8. One app's backend goes down: the other app is unaffected

```
app1: total=412 failed=168 max_gap_s=33.84   status counts: {200: 244, 502: 14, 503: 154}
app2: total=410 failed=0   max_gap_s=0.2
  during {'10.90.20.11': 78, '10.90.20.12': 77}
```

While the agents were still in the pool they answered **502** (they could not reach backend1). Once the end-to-end health checks failed, `be_app1` had no server left and HAProxy answered **503**. **`be_app2`, with the same agents, stayed UP.** This is why each app has its own pool and health check ([chapter 6](06-haproxy.md)). The VIP did not move, which is correct: moving it would not fix a backend. app1 recovered a few seconds after its backend came back (`rise 2`).

### S9. Planned failback

After S3 the VIP stayed on node2. To move it back on purpose (for example after maintenance), restart keepalived on the **current owner**:

```bash
lab/ssh.sh waf-node2 'sudo systemctl restart keepalived'
```

```
vip owner after inject: waf-node1
app1: total=257 failed=0 max_gap_s=1.05
```

A clean stop sends a priority-0 advert, so the other node takes over **immediately**: no errors, about 1 s gap. Do this in a quiet window anyway.

## 9.3 What the numbers mean for users

- **Losing an agent, a non-VIP node, or recovering one** is invisible to users, apart from a possible 1 s delay on a request.
- **Losing the VIP holder** costs **2–6 s**: 2–4 s if the VM dies, about 6 s if HAProxy hangs. Established connections on that node are dropped and clients reconnect. There is no connection state sync between nodes.
- **An agent that fails "softly"** (fail-open, scenario 7) is the one real blind spot: the app stays up but attacks through that node are not blocked. Monitor agent status separately.

## 9.4 Tuning learned from the tests

The first run of S2 (on an earlier version of the lab, with the agent on port 8443 and the default `timeout connect 3s`) showed:

```
s02-node2-poweroff (initial, connect 3s)   app1: failed=6 max_gap_s=2.21     ← requests to the dead node waited 3 s for the connect timeout
s02-node2-poweroff (final, connect 1s)     app1: failed=0 max_gap_s=1.04
```

| Setting | Before | After | Why |
|---|---|---|---|
| `timeout connect` | 3s | **1s** | Agents are on the same LAN. A healthy connect takes milliseconds, so fail fast on a dead node |
| `option redispatch` | (last retry only) | **`redispatch 1`** | Pick **another** agent at every retry instead of retrying the dead one first |
| `observe layer7 … on-error` | `mark-down` | **`fastinter`** | `mark-down` would eject all agents when the backend itself returns 5xx (each pool has all agents) |

The "initial" results are kept in `tests/results/*-initial/` for reference.
