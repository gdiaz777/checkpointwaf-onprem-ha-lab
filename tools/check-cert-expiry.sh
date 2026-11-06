#!/usr/bin/env bash
# Check the certificate a TLS endpoint presents for a given SNI.
# Usage: tools/check-cert-expiry.sh <host:port> <sni> [warn_days=30]
# Exit: 0 = OK, 1 = expires within warn_days (or already expired), 2 = no certificate / unreachable
set -u
EP=$1 SNI=$2 WARN=${3:-30}
pem=$(timeout 5 openssl s_client -connect "$EP" -servername "$SNI" </dev/null 2>/dev/null | openssl x509 2>/dev/null)
[ -n "$pem" ] || { echo "ERROR $EP ($SNI): no certificate (unreachable or TLS failure)"; exit 2; }
end=$(openssl x509 -noout -enddate <<<"$pem" | cut -d= -f2)
subj=$(openssl x509 -noout -subject -nameopt RFC2253 <<<"$pem" | sed 's/^subject=//')
serial=$(openssl x509 -noout -serial <<<"$pem" | cut -d= -f2)
days=$(( ( $(date -d "$end" +%s) - $(date +%s) ) / 86400 ))
if openssl x509 -noout -checkend $(( WARN * 86400 )) <<<"$pem" >/dev/null; then
  echo "OK   $EP ($SNI): $subj serial=$serial expires $end ($days days left)"; exit 0
fi
echo "WARN $EP ($SNI): $subj serial=$serial expires $end ($days days left, threshold $WARN)"; exit 1
