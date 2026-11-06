#!/usr/bin/env bash
# Create the lab certificate authority (once). Output: certs/ca/ca.crt, certs/ca/ca.key
# In production you use your public CA or internal PKI instead (chapter 11).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
OUT="$ROOT/certs/ca"
mkdir -p "$OUT"; chmod 700 "$ROOT/certs" "$OUT"
if [ -f "$OUT/ca.crt" ]; then echo "CA already exists: $OUT/ca.crt"; exit 0; fi
openssl req -x509 -new -nodes -newkey rsa:3072 -sha256 -days 3650 \
  -subj "/O=WAF Lab/CN=WAF Lab Root CA" \
  -addext "basicConstraints=critical,CA:TRUE" \
  -addext "keyUsage=critical,keyCertSign,cRLSign" \
  -keyout "$OUT/ca.key" -out "$OUT/ca.crt" 2>/dev/null
chmod 600 "$OUT/ca.key"
echo "CA created: $OUT/ca.crt"
