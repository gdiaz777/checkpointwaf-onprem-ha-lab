# Scenario s10-scale-out

```
01:52:03.320  probes started (vip owner: waf-node1 )
01:52:13.326  INJECT: lab/add-node.sh waf-node3 10.90.20.13
    
    === 01:52:13  1/5 create VM waf-node3 (10.90.20.13)
    waf-node3 already exists, skipping
    clock synchronized
    
    === 01:52:14  1/5 NGINX + agent on waf-node3
    agent already installed on waf-node3, skipping installer
    waiting for policy ok
    Policy version: 21
    Registered Instances: 2
    
    === 01:52:18  2/5 WAF_NODES is now: waf-node1:10.90.20.11 waf-node2:10.90.20.12 waf-node3:10.90.20.13
    
    === 01:52:18  3/5 keepalived: existing nodes learn the new peer
    keepalived on waf-node1: active, Keepalived v2.2.8 (04/04,2023), git commit v2.2.7-154-g292b299e+
    keepalived on waf-node2: active, Keepalived v2.2.8 (04/04,2023), git commit v2.2.7-154-g292b299e+
    
    === 01:52:22  4/5 HAProxy: existing nodes add the new agent to every pool
    haproxy on waf-node1: active, HAProxy version 2.8.30-0ubuntu0.24.04.2 2026/10/27 - https://haproxy.org/
    haproxy on waf-node2: active, HAProxy version 2.8.30-0ubuntu0.24.04.2 2026/10/27 - https://haproxy.org/
    
    === 01:52:28  5/5 HAProxy + keepalived on waf-node3 (joins as BACKUP)
    haproxy on waf-node3: active, HAProxy version 2.8.30-0ubuntu0.24.04.2 2026/10/27 - https://haproxy.org/
    keepalived on waf-node3: active, Keepalived v2.2.8 (04/04,2023), git commit v2.2.7-154-g292b299e+
    VIP owner: waf-node1 
01:52:44.768  vip owner after inject: waf-node1 
01:52:44.769  RESTORE: true
01:53:47.301  probes stopped (vip owner: waf-node1, vip-owner rc=0)
```

```
app1: total=512 failed=0 max_gap_s=0.2 window_s=102.31
  windows: before INJECT / INJECT→RESTORE / after RESTORE
  before {'10.90.20.11': 27, '10.90.20.12': 26}
  during {'10.90.20.11': 63, '10.90.20.12': 63, '10.90.20.13': 32}
  after  {'10.90.20.11': 101, '10.90.20.12': 100, '10.90.20.13': 100}
  t+    0s {'10.90.20.11': 25, '10.90.20.12': 25}
  t+   10s {'10.90.20.11': 25, '10.90.20.12': 25}
  t+   20s {'10.90.20.11': 20, '10.90.20.12': 19, '10.90.20.13': 11}
  t+   30s {'10.90.20.11': 17, '10.90.20.12': 16, '10.90.20.13': 17}
  t+   40s {'10.90.20.11': 16, '10.90.20.12': 17, '10.90.20.13': 17}
  t+   50s {'10.90.20.11': 17, '10.90.20.12': 17, '10.90.20.13': 16}
  t+   60s {'10.90.20.11': 17, '10.90.20.12': 16, '10.90.20.13': 17}
  t+   70s {'10.90.20.11': 16, '10.90.20.12': 17, '10.90.20.13': 17}
  t+   80s {'10.90.20.11': 17, '10.90.20.12': 17, '10.90.20.13': 16}
  t+   90s {'10.90.20.11': 17, '10.90.20.12': 16, '10.90.20.13': 17}
  t+  100s {'10.90.20.11': 4, '10.90.20.12': 4, '10.90.20.13': 4}
app2: total=511 failed=0 max_gap_s=0.2 window_s=102.08
  windows: before INJECT / INJECT→RESTORE / after RESTORE
  before {'10.90.20.11': 26, '10.90.20.12': 26}
  during {'10.90.20.11': 63, '10.90.20.12': 63, '10.90.20.13': 31}
  after  {'10.90.20.11': 101, '10.90.20.12': 100, '10.90.20.13': 101}
  t+    0s {'10.90.20.11': 25, '10.90.20.12': 25}
  t+   10s {'10.90.20.11': 25, '10.90.20.12': 25}
  t+   20s {'10.90.20.11': 19, '10.90.20.12': 19, '10.90.20.13': 12}
  t+   30s {'10.90.20.11': 17, '10.90.20.12': 17, '10.90.20.13': 16}
  t+   40s {'10.90.20.11': 17, '10.90.20.12': 16, '10.90.20.13': 17}
  t+   50s {'10.90.20.11': 16, '10.90.20.12': 17, '10.90.20.13': 17}
  t+   60s {'10.90.20.11': 17, '10.90.20.12': 17, '10.90.20.13': 16}
  t+   70s {'10.90.20.11': 17, '10.90.20.12': 16, '10.90.20.13': 17}
  t+   80s {'10.90.20.11': 16, '10.90.20.12': 17, '10.90.20.13': 17}
  t+   90s {'10.90.20.11': 17, '10.90.20.12': 17, '10.90.20.13': 16}
  t+  100s {'10.90.20.11': 4, '10.90.20.12': 3, '10.90.20.13': 4}
```
