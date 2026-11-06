#!/usr/bin/env bash
# Backends answer over TLS (trusted by the lab CA) with the JSON contract
# {"app","backend","client_addr","xff","host"} and /healthz → 200 "ok".
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
source "$ROOT/lab/inventory.env"
CA="$ROOT/certs/ca/ca.crt"
fail=0
check() { # check <ip> <app>
  local body; body=$(curl -s -m 5 --cacert "$CA" "https://$1/" -H "X-Forwarded-For: 192.0.2.7")
  python3 - "$body" "$2" "$1" <<'PY' || fail=1
import json, sys
body, app, ip = sys.argv[1], sys.argv[2], sys.argv[3]
try:
    d = json.loads(body)
except Exception:
    print(f"FAIL {ip}: not JSON: {body[:80]!r}"); sys.exit(1)
keys = {"app", "backend", "client_addr", "xff", "host"}
ok = keys <= d.keys() and d["app"] == app and d["xff"] == "192.0.2.7" and d["client_addr"] == "10.90.20.1"
print(("PASS" if ok else "FAIL"), ip, d)
sys.exit(0 if ok else 1)
PY
  local hc; hc=$(curl -s -m 5 --cacert "$CA" "https://$1/healthz")
  [ "$hc" = "ok" ] && echo "PASS $1 /healthz" || { echo "FAIL $1 /healthz: $hc"; fail=1; }
}
check "$BACKEND1_IP" app1
check "$BACKEND2_IP" app2
exit $fail
