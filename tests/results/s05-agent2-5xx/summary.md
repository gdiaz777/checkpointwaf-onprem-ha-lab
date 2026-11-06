# Scenario s05-agent2-5xx

```
01:38:08.542  probes started (vip owner: waf-node1 )
01:38:18.546  INJECT: lab/ssh.sh waf-node2 'sudo cp /etc/nginx/conf.d/waf.conf /root/waf.conf.bak && sudo sed -i "s|^    location / {|    location / { return 503;|" /etc/nginx/conf.d/waf.conf && sudo nginx -t -q && sudo systemctl reload nginx && echo node2 now answers 503'
    node2 now answers 503
01:38:49.292  vip owner after inject: waf-node1 
01:38:49.294  RESTORE: lab/ssh.sh waf-node2 'sudo cp /root/waf.conf.bak /etc/nginx/conf.d/waf.conf && sudo nginx -t -q && sudo systemctl reload nginx && echo node2 config restored'
    node2 config restored
01:39:52.029  probes stopped (vip owner: waf-node1, vip-owner rc=0)
```

```
app1: total=509 failed=6 max_gap_s=0.4 window_s=101.72
  failures: 2026-11-06T01:38:19.117+00:00 → 2026-11-06T01:38:21.119+00:00
  status counts: {200: 503, 503: 6}  (0 = no answer within the probe timeout)
  windows: before INJECT / INJECT→RESTORE / after RESTORE
  before {'10.90.20.11': 27, '10.90.20.12': 26}
  during {'10.90.20.11': 146, '10.90.20.12': 1}
  after  {'10.90.20.11': 160, '10.90.20.12': 143}
  t+    0s {'10.90.20.11': 25, '10.90.20.12': 25}
  t+   10s {'10.90.20.11': 42, '10.90.20.12': 2}
  t+   20s {'10.90.20.11': 50}
  t+   30s {'10.90.20.11': 50}
  t+   40s {'10.90.20.11': 36, '10.90.20.12': 14}
  t+   50s {'10.90.20.11': 25, '10.90.20.12': 25}
  t+   60s {'10.90.20.11': 25, '10.90.20.12': 25}
  t+   70s {'10.90.20.11': 26, '10.90.20.12': 24}
  t+   80s {'10.90.20.11': 25, '10.90.20.12': 25}
  t+   90s {'10.90.20.11': 25, '10.90.20.12': 25}
  t+  100s {'10.90.20.11': 4, '10.90.20.12': 5}
app2: total=508 failed=12 max_gap_s=0.4 window_s=101.51
  failures: 2026-11-06T01:38:19.128+00:00 → 2026-11-06T01:38:23.531+00:00
  status counts: {200: 496, 503: 12}  (0 = no answer within the probe timeout)
  windows: before INJECT / INJECT→RESTORE / after RESTORE
  before {'10.90.20.11': 26, '10.90.20.12': 26}
  during {'10.90.20.11': 140, '10.90.20.12': 1}
  after  {'10.90.20.11': 159, '10.90.20.12': 144}
  t+    0s {'10.90.20.11': 25, '10.90.20.12': 25}
  t+   10s {'10.90.20.11': 36, '10.90.20.12': 2}
  t+   20s {'10.90.20.11': 50}
  t+   30s {'10.90.20.11': 50}
  t+   40s {'10.90.20.11': 34, '10.90.20.12': 16}
  t+   50s {'10.90.20.11': 25, '10.90.20.12': 25}
  t+   60s {'10.90.20.11': 25, '10.90.20.12': 25}
  t+   70s {'10.90.20.11': 26, '10.90.20.12': 24}
  t+   80s {'10.90.20.11': 25, '10.90.20.12': 25}
  t+   90s {'10.90.20.11': 25, '10.90.20.12': 25}
  t+  100s {'10.90.20.11': 4, '10.90.20.12': 4}
```
