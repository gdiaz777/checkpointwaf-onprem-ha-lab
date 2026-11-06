# Scenario s04-haproxy1-hang

```
01:46:22.801  probes started (vip owner: waf-node1 )
01:46:32.805  INJECT: lab/ssh.sh waf-node1 'sudo pkill -STOP -x haproxy; echo haproxy stopped with SIGSTOP'
    haproxy stopped with SIGSTOP
01:47:03.984  vip owner after inject: waf-node2 
01:47:03.986  RESTORE: lab/ssh.sh waf-node1 'sudo pkill -CONT -x haproxy; echo haproxy resumed'
    haproxy resumed
01:47:46.629  probes stopped (vip owner: waf-node2, vip-owner rc=0)
```

```
app1: total=384 failed=3 max_gap_s=6.22 window_s=82.11
  failures: 2026-11-06T01:46:33.556+00:00 → 2026-11-06T01:46:37.569+00:00
  status counts: {0: 3, 200: 381}  (0 = no answer within the probe timeout)
  windows: before INJECT / INJECT→RESTORE / after RESTORE
  before {'10.90.20.11': 26, '10.90.20.12': 27}
  during {'10.90.20.11': 63, '10.90.20.12': 62}
  after  {'10.90.20.11': 102, '10.90.20.12': 101}
  t+    0s {'10.90.20.11': 25, '10.90.20.12': 25}
  t+   10s {'10.90.20.11': 10, '10.90.20.12': 10}
  t+   20s {'10.90.20.11': 25, '10.90.20.12': 25}
  t+   30s {'10.90.20.11': 25, '10.90.20.12': 25}
  t+   40s {'10.90.20.11': 25, '10.90.20.12': 25}
  t+   50s {'10.90.20.11': 25, '10.90.20.12': 25}
  t+   60s {'10.90.20.11': 25, '10.90.20.12': 25}
  t+   70s {'10.90.20.11': 25, '10.90.20.12': 25}
  t+   80s {'10.90.20.11': 6, '10.90.20.12': 5}
app2: total=383 failed=3 max_gap_s=6.21 window_s=81.88
  failures: 2026-11-06T01:46:33.589+00:00 → 2026-11-06T01:46:37.598+00:00
  status counts: {0: 3, 200: 380}  (0 = no answer within the probe timeout)
  windows: before INJECT / INJECT→RESTORE / after RESTORE
  before {'10.90.20.11': 26, '10.90.20.12': 26}
  during {'10.90.20.11': 63, '10.90.20.12': 62}
  after  {'10.90.20.11': 101, '10.90.20.12': 102}
  t+    0s {'10.90.20.11': 25, '10.90.20.12': 25}
  t+   10s {'10.90.20.11': 10, '10.90.20.12': 10}
  t+   20s {'10.90.20.11': 25, '10.90.20.12': 25}
  t+   30s {'10.90.20.11': 25, '10.90.20.12': 25}
  t+   40s {'10.90.20.11': 25, '10.90.20.12': 25}
  t+   50s {'10.90.20.11': 25, '10.90.20.12': 25}
  t+   60s {'10.90.20.11': 25, '10.90.20.12': 25}
  t+   70s {'10.90.20.11': 25, '10.90.20.12': 25}
  t+   80s {'10.90.20.11': 5, '10.90.20.12': 5}
```
