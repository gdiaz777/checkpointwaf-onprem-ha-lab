# Scenario s09-failback

```
01:45:27.899  probes started (vip owner: waf-node2 )
01:45:37.901  INJECT: lab/ssh.sh waf-node2 'sudo systemctl restart keepalived; echo keepalived restarted on node2'
    keepalived restarted on node2
01:45:59.508  vip owner after inject: waf-node1 
01:45:59.510  RESTORE: true
01:46:21.580  probes stopped (vip owner: waf-node1, vip-owner rc=0)
```

```
app1: total=257 failed=0 max_gap_s=1.05 window_s=52.12
  windows: before INJECT / INJECT→RESTORE / after RESTORE
  before {'10.90.20.11': 27, '10.90.20.12': 26}
  during {'10.90.20.11': 51, '10.90.20.12': 52}
  after  {'10.90.20.11': 51, '10.90.20.12': 50}
  t+    0s {'10.90.20.11': 25, '10.90.20.12': 25}
  t+   10s {'10.90.20.11': 23, '10.90.20.12': 23}
  t+   20s {'10.90.20.11': 25, '10.90.20.12': 25}
  t+   30s {'10.90.20.11': 25, '10.90.20.12': 25}
  t+   40s {'10.90.20.11': 25, '10.90.20.12': 25}
  t+   50s {'10.90.20.11': 6, '10.90.20.12': 5}
app2: total=256 failed=0 max_gap_s=1.07 window_s=51.92
  windows: before INJECT / INJECT→RESTORE / after RESTORE
  before {'10.90.20.11': 25, '10.90.20.12': 26}
  during {'10.90.20.11': 53, '10.90.20.12': 51}
  after  {'10.90.20.11': 50, '10.90.20.12': 51}
  t+    0s {'10.90.20.11': 25, '10.90.20.12': 25}
  t+   10s {'10.90.20.11': 23, '10.90.20.12': 23}
  t+   20s {'10.90.20.11': 25, '10.90.20.12': 25}
  t+   30s {'10.90.20.11': 25, '10.90.20.12': 25}
  t+   40s {'10.90.20.11': 25, '10.90.20.12': 25}
  t+   50s {'10.90.20.11': 5, '10.90.20.12': 5}
```
