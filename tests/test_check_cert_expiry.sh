#!/usr/bin/env bash
# tools/check-cert-expiry.sh against local TLS servers with a long and a short-lived cert.
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TMP="$(mktemp -d)"; pids=()
trap 'kill "${pids[@]}" 2>/dev/null; rm -rf "$TMP"' EXIT
fail=0; t() { if eval "$2"; then echo "PASS $1"; else echo "FAIL $1"; fail=1; fi; }
"$ROOT/lab/certs/issue-cert.sh" long.test long.test "$TMP" 400 >/dev/null
"$ROOT/lab/certs/issue-cert.sh" short.test short.test "$TMP" 1 >/dev/null
port() { python3 -c 'import socket;s=socket.socket();s.bind(("127.0.0.1",0));print(s.getsockname()[1])'; }
P1=$(port); openssl s_server -quiet -accept "$P1" -cert "$TMP/long.test.crt" -key "$TMP/long.test.key" -www >/dev/null 2>&1 & pids+=($!)
P2=$(port); openssl s_server -quiet -accept "$P2" -cert "$TMP/short.test.crt" -key "$TMP/short.test.key" -www >/dev/null 2>&1 & pids+=($!)
sleep 1
out=$("$ROOT/tools/check-cert-expiry.sh" "127.0.0.1:$P1" long.test 30); rc=$?
t "long-lived cert → exit 0" '[ $rc -eq 0 ]'
t "prints days left and CN" '[[ $out == *"long.test"* && $out == *"days left"* ]]'
out=$("$ROOT/tools/check-cert-expiry.sh" "127.0.0.1:$P2" short.test 30); rc=$?
t "short-lived cert → exit 1 (below threshold)" '[ $rc -eq 1 ]'
t "warns" '[[ $out == *"WARN"* ]]'
"$ROOT/tools/check-cert-expiry.sh" "127.0.0.1:1" x 30 >/dev/null 2>&1; rc=$?
t "unreachable → exit 2" '[ $rc -eq 2 ]'
exit $fail
