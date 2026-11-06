# Scenario s08-backend1-down

```
01:41:33.899  probes started (vip owner: waf-node1 )
01:41:43.902  INJECT: lab/ssh.sh backend1 'sudo systemctl stop nginx; echo backend1 nginx stopped'
    backend1 nginx stopped
01:42:14.902  vip owner after inject: waf-node1 
01:42:14.903  RESTORE: lab/ssh.sh backend1 'sudo systemctl start nginx; echo backend1 nginx started'
    backend1 nginx started
01:42:57.765  probes stopped (vip owner: waf-node1, vip-owner rc=0)
```

```
app1: total=412 failed=168 max_gap_s=33.84 window_s=82.3
  failures: 2026-11-06T01:41:44.614+00:00 → 2026-11-06T01:42:18.051+00:00
  status counts: {200: 244, 502: 14, 503: 154}  (0 = no answer within the probe timeout)
  windows: before INJECT / INJECT→RESTORE / after RESTORE
  before {'10.90.20.11': 26, '10.90.20.12': 27}
  during {'10.90.20.11': 2, '10.90.20.12': 1}
  after  {'10.90.20.11': 92, '10.90.20.12': 96}
  t+    0s {'10.90.20.11': 25, '10.90.20.12': 25}
  t+   10s {'10.90.20.11': 3, '10.90.20.12': 3}
  t+   20s {}
  t+   30s {}
  t+   40s {'10.90.20.11': 12, '10.90.20.12': 14}
  t+   50s {'10.90.20.11': 25, '10.90.20.12': 25}
  t+   60s {'10.90.20.11': 25, '10.90.20.12': 25}
  t+   70s {'10.90.20.11': 24, '10.90.20.12': 26}
  t+   80s {'10.90.20.11': 6, '10.90.20.12': 6}
app2: total=410 failed=0 max_gap_s=0.2 window_s=81.89
  windows: before INJECT / INJECT→RESTORE / after RESTORE
  before {'10.90.20.11': 26, '10.90.20.12': 26}
  during {'10.90.20.11': 77, '10.90.20.12': 77}
  after  {'10.90.20.11': 102, '10.90.20.12': 102}
  t+    0s {'10.90.20.11': 25, '10.90.20.12': 25}
  t+   10s {'10.90.20.11': 25, '10.90.20.12': 25}
  t+   20s {'10.90.20.11': 25, '10.90.20.12': 25}
  t+   30s {'10.90.20.11': 25, '10.90.20.12': 25}
  t+   40s {'10.90.20.11': 25, '10.90.20.12': 25}
  t+   50s {'10.90.20.11': 25, '10.90.20.12': 25}
  t+   60s {'10.90.20.11': 25, '10.90.20.12': 25}
  t+   70s {'10.90.20.11': 25, '10.90.20.12': 25}
  t+   80s {'10.90.20.11': 5, '10.90.20.12': 5}
```
