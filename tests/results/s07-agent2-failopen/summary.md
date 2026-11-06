# Scenario s07-agent2-failopen

```
01:39:53.281  probes started (vip owner: waf-node1 )
01:40:03.285  INJECT: lab/ssh.sh waf-node2 'sudo cpnano -q; sleep 3; sudo cpnano -s | grep -E "^.*Status|Registered Instances" | head -3'; sleep 5; for ip in 10.90.20.11 10.90.20.12; do printf "XSS via agent %s → HTTP " $ip; curl -s -o /dev/null -w '%{http_code}\n' --cacert certs/ca/ca.crt --resolve app1.waflab.example:443:$ip 'https://app1.waflab.example/?q=%3Cscript%3Ealert(1)%3C%2Fscript%3E'; done
    Check Point Nano Agent stopped successfully
    Status: Not running
    Status: Ready
    Status: Ready
    XSS via agent 10.90.20.11 → HTTP 403
    XSS via agent 10.90.20.12 → HTTP 200
01:40:43.697  vip owner after inject: waf-node1 
01:40:43.698  RESTORE: lab/ssh.sh waf-node2 'sudo cpnano -r; sleep 5; sudo cpnano -s | grep -E "^.*Status|Registered Instances" | head -3'
    Check Point Nano Agent watchdog started successfully
    Status: Running
    Status: Running
    Status: Running
01:41:32.568  probes stopped (vip owner: waf-node1, vip-owner rc=0)
```

```
app1: total=489 failed=1 max_gap_s=0.4 window_s=97.71
  failures: 2026-11-06T01:40:34.639+00:00 → 2026-11-06T01:40:34.639+00:00
  status counts: {200: 488, 502: 1}  (0 = no answer within the probe timeout)
  windows: before INJECT / INJECT→RESTORE / after RESTORE
  before {'10.90.20.11': 27, '10.90.20.12': 26}
  during {'10.90.20.11': 101, '10.90.20.12': 100}
  after  {'10.90.20.11': 117, '10.90.20.12': 117}
  t+    0s {'10.90.20.11': 25, '10.90.20.12': 25}
  t+   10s {'10.90.20.11': 25, '10.90.20.12': 25}
  t+   20s {'10.90.20.11': 25, '10.90.20.12': 25}
  t+   30s {'10.90.20.11': 25, '10.90.20.12': 25}
  t+   40s {'10.90.20.11': 25, '10.90.20.12': 24}
  t+   50s {'10.90.20.11': 25, '10.90.20.12': 25}
  t+   60s {'10.90.20.11': 25, '10.90.20.12': 25}
  t+   70s {'10.90.20.11': 25, '10.90.20.12': 25}
  t+   80s {'10.90.20.11': 25, '10.90.20.12': 25}
  t+   90s {'10.90.20.11': 20, '10.90.20.12': 19}
app2: total=487 failed=1 max_gap_s=0.4 window_s=97.31
  failures: 2026-11-06T01:40:16.667+00:00 → 2026-11-06T01:40:16.667+00:00
  status counts: {200: 486, 502: 1}  (0 = no answer within the probe timeout)
  windows: before INJECT / INJECT→RESTORE / after RESTORE
  before {'10.90.20.11': 26, '10.90.20.12': 26}
  during {'10.90.20.11': 101, '10.90.20.12': 100}
  after  {'10.90.20.11': 116, '10.90.20.12': 117}
  t+    0s {'10.90.20.11': 25, '10.90.20.12': 25}
  t+   10s {'10.90.20.11': 25, '10.90.20.12': 25}
  t+   20s {'10.90.20.11': 25, '10.90.20.12': 24}
  t+   30s {'10.90.20.11': 25, '10.90.20.12': 25}
  t+   40s {'10.90.20.11': 25, '10.90.20.12': 25}
  t+   50s {'10.90.20.11': 25, '10.90.20.12': 25}
  t+   60s {'10.90.20.11': 25, '10.90.20.12': 25}
  t+   70s {'10.90.20.11': 25, '10.90.20.12': 25}
  t+   80s {'10.90.20.11': 25, '10.90.20.12': 25}
  t+   90s {'10.90.20.11': 18, '10.90.20.12': 19}
```
