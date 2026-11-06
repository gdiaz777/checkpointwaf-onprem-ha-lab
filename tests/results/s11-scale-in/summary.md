# Scenario s11-scale-in

```
01:32:22.827  probes started (vip owner: waf-node1 )
01:32:32.830  INJECT: lab/remove-node.sh waf-node3
    
    === 01:32:32  1/4 drain waf-node3 on every HAProxy
    
    
    
    
    
    
    active sessions to waf-node3: 0
    
    === 01:32:34  2/4 VIP must not be on waf-node3
    VIP owner: waf-node1 
    
    === 01:32:35  3/4 stop keepalived on waf-node3, update WAF_NODES, reload the remaining nodes
    inactive
    WAF_NODES is now: waf-node1:10.90.20.11 waf-node2:10.90.20.12
    keepalived on waf-node1: active, Keepalived v2.2.8 (04/04,2023), git commit v2.2.7-154-g292b299e+
    keepalived on waf-node2: active, Keepalived v2.2.8 (04/04,2023), git commit v2.2.7-154-g292b299e+
    haproxy on waf-node1: reloading, HAProxy version 2.8.30-0ubuntu0.24.04.2 2026/10/27 - https://haproxy.org/
    haproxy on waf-node2: active, HAProxy version 2.8.30-0ubuntu0.24.04.2 2026/10/27 - https://haproxy.org/
    
    === 01:32:45  4/4 stop HAProxy and NGINX on waf-node3
    haproxy=inactive nginx=inactive
    VIP owner: waf-node1 
01:32:52.788  vip owner after inject: waf-node1 
01:32:52.789  RESTORE: true
01:33:35.246  probes stopped (vip owner: waf-node1, vip-owner rc=0)
```

```
app1: total=354 failed=0 max_gap_s=0.2 window_s=70.68
  windows: before INJECT / INJECT→RESTORE / after RESTORE
  before {'10.90.20.11': 18, '10.90.20.12': 17, '10.90.20.13': 18}
  during {'10.90.20.11': 49, '10.90.20.12': 50}
  after  {'10.90.20.11': 101, '10.90.20.12': 101}
  t+    0s {'10.90.20.11': 17, '10.90.20.12': 16, '10.90.20.13': 17}
  t+   10s {'10.90.20.11': 24, '10.90.20.12': 25, '10.90.20.13': 1}
  t+   20s {'10.90.20.11': 25, '10.90.20.12': 25}
  t+   30s {'10.90.20.11': 25, '10.90.20.12': 25}
  t+   40s {'10.90.20.11': 25, '10.90.20.12': 25}
  t+   50s {'10.90.20.11': 25, '10.90.20.12': 25}
  t+   60s {'10.90.20.11': 25, '10.90.20.12': 25}
  t+   70s {'10.90.20.11': 2, '10.90.20.12': 2}
app2: total=353 failed=0 max_gap_s=0.2 window_s=70.46
  windows: before INJECT / INJECT→RESTORE / after RESTORE
  before {'10.90.20.11': 18, '10.90.20.12': 17, '10.90.20.13': 17}
  during {'10.90.20.11': 49, '10.90.20.12': 50}
  after  {'10.90.20.11': 101, '10.90.20.12': 101}
  t+    0s {'10.90.20.11': 17, '10.90.20.12': 17, '10.90.20.13': 16}
  t+   10s {'10.90.20.11': 25, '10.90.20.12': 24, '10.90.20.13': 1}
  t+   20s {'10.90.20.11': 25, '10.90.20.12': 25}
  t+   30s {'10.90.20.11': 25, '10.90.20.12': 25}
  t+   40s {'10.90.20.11': 25, '10.90.20.12': 25}
  t+   50s {'10.90.20.11': 25, '10.90.20.12': 25}
  t+   60s {'10.90.20.11': 25, '10.90.20.12': 25}
  t+   70s {'10.90.20.11': 1, '10.90.20.12': 2}
```
