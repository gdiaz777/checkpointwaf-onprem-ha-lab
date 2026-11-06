# Scenario s00-baseline

```
01:33:36.534  probes started (vip owner: waf-node1 )
01:33:41.537  INJECT: true
01:33:47.044  vip owner after inject: waf-node1 
01:33:47.046  RESTORE: true
01:33:53.942  probes stopped (vip owner: waf-node1, vip-owner rc=0)
```

```
app1: total=82 failed=0 max_gap_s=0.2 window_s=16.22
  windows: before INJECT / INJECT→RESTORE / after RESTORE
  before {'10.90.20.11': 14, '10.90.20.12': 14}
  during {'10.90.20.11': 14, '10.90.20.12': 14}
  after  {'10.90.20.11': 13, '10.90.20.12': 13}
  t+    0s {'10.90.20.11': 25, '10.90.20.12': 25}
  t+   10s {'10.90.20.11': 16, '10.90.20.12': 16}
app2: total=80 failed=0 max_gap_s=0.2 window_s=15.82
  windows: before INJECT / INJECT→RESTORE / after RESTORE
  before {'10.90.20.11': 14, '10.90.20.12': 13}
  during {'10.90.20.11': 13, '10.90.20.12': 14}
  after  {'10.90.20.11': 13, '10.90.20.12': 13}
  t+    0s {'10.90.20.11': 25, '10.90.20.12': 25}
  t+   10s {'10.90.20.11': 15, '10.90.20.12': 15}
```
