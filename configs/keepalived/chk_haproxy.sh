#!/bin/sh
# keepalived track script: is the local HAProxy answering?
# Any HTTP answer counts (HAProxy itself replies 301 on :80); only "no answer
# within 2 s" (000: process dead, hung or not listening) is a failure.
# It does NOT depend on agents or backends, so a backend outage never moves the VIP.
code=$(curl -s -m 2 -o /dev/null -w '%{http_code}' http://127.0.0.1/)
[ "$code" != "000" ]
