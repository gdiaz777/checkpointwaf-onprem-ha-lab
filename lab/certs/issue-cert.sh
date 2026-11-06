#!/usr/bin/env bash
# Issue a server certificate signed by the lab CA.
# Usage: lab/certs/issue-cert.sh <cn> <san,...> <outdir> [days]
#   SAN entries: DNS names or IPs, e.g. "app1.waflab.example" or "backend1.waflab.internal,10.90.20.5"
# Output: <outdir>/<cn>.crt, <cn>.key and <cn>.pem (cert + key, the format HAProxy wants)
set -euo pipefail
[ $# -ge 3 ] || { echo "usage: $0 <cn> <san,...> <outdir> [days]" >&2; exit 2; }
CN=$1 SANS=$2 OUT=$3 DAYS=${4:-825}
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
CA="$ROOT/certs/ca"
mkdir -p "$OUT"
san=""
IFS=',' read -ra items <<< "$SANS"
for s in "${items[@]}"; do
  if [[ $s =~ ^[0-9.]+$ ]]; then san+="IP:$s,"; else san+="DNS:$s,"; fi
done
san=${san%,}
openssl req -new -nodes -newkey rsa:2048 -sha256 -subj "/O=WAF Lab/CN=$CN" \
  -keyout "$OUT/$CN.key" -out "$OUT/$CN.csr" 2>/dev/null
openssl x509 -req -in "$OUT/$CN.csr" -CA "$CA/ca.crt" -CAkey "$CA/ca.key" -CAcreateserial \
  -days "$DAYS" -sha256 -out "$OUT/$CN.crt" \
  -extfile <(printf 'subjectAltName=%s\nextendedKeyUsage=serverAuth\nkeyUsage=critical,digitalSignature,keyEncipherment\n' "$san") 2>/dev/null
cat "$OUT/$CN.crt" "$OUT/$CN.key" > "$OUT/$CN.pem"
chmod 600 "$OUT/$CN.key" "$OUT/$CN.pem"; rm -f "$OUT/$CN.csr"
echo "issued $OUT/$CN.crt  (SAN: $san, serial $(openssl x509 -in "$OUT/$CN.crt" -noout -serial | cut -d= -f2), $DAYS days)"
