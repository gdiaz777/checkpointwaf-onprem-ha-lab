# Scenario s12-cert-rotation

```
01:53:54.829  probes started (vip owner: waf-node1 )
01:54:04.833  INJECT: lab/rotate-app-cert.sh app1
    issued certs/apps/app1.waflab.example.crt  (SAN: DNS:app1.waflab.example, serial 4BE446A4AF120D254368363CD05A75C17DA4BE86, 825 days)
    new certificate: serial=4BE446A4AF120D254368363CD05A75C17DA4BE86 notAfter=Feb  8 01:54:05 2029 GMT 
    waf-node1: haproxy + nginx reloaded
    waf-node2: haproxy + nginx reloaded
    waf-node3: haproxy + nginx reloaded
01:54:19.964  vip owner after inject: waf-node1 
01:54:19.965  RESTORE: true
01:54:42.044  probes stopped (vip owner: waf-node1, vip-owner rc=0)
```

```
app1: total=229 failed=0 max_gap_s=0.2 window_s=45.65
  windows: before INJECT / INJECT→RESTORE / after RESTORE
  before {'10.90.20.11': 17, '10.90.20.12': 18, '10.90.20.13': 18}
  during {'10.90.20.11': 26, '10.90.20.12': 25, '10.90.20.13': 24}
  after  {'10.90.20.11': 33, '10.90.20.12': 34, '10.90.20.13': 34}
  t+    0s {'10.90.20.11': 16, '10.90.20.12': 17, '10.90.20.13': 17}
  t+   10s {'10.90.20.11': 17, '10.90.20.12': 17, '10.90.20.13': 16}
  t+   20s {'10.90.20.11': 17, '10.90.20.12': 17, '10.90.20.13': 16}
  t+   30s {'10.90.20.11': 17, '10.90.20.12': 16, '10.90.20.13': 17}
  t+   40s {'10.90.20.11': 9, '10.90.20.12': 10, '10.90.20.13': 10}
app2: total=228 failed=0 max_gap_s=0.2 window_s=45.45
  windows: before INJECT / INJECT→RESTORE / after RESTORE
  before {'10.90.20.11': 17, '10.90.20.12': 18, '10.90.20.13': 17}
  during {'10.90.20.11': 26, '10.90.20.12': 24, '10.90.20.13': 25}
  after  {'10.90.20.11': 33, '10.90.20.12': 34, '10.90.20.13': 34}
  t+    0s {'10.90.20.11': 16, '10.90.20.12': 17, '10.90.20.13': 17}
  t+   10s {'10.90.20.11': 18, '10.90.20.12': 16, '10.90.20.13': 16}
  t+   20s {'10.90.20.11': 16, '10.90.20.12': 17, '10.90.20.13': 17}
  t+   30s {'10.90.20.11': 17, '10.90.20.12': 17, '10.90.20.13': 16}
  t+   40s {'10.90.20.11': 9, '10.90.20.12': 9, '10.90.20.13': 10}
```
