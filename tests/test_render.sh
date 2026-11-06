#!/usr/bin/env bash
# Tests for lab/render.sh, run in a clean environment (env -i).
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
fail=0
printf 'VIP=10.0.0.100\nAGENT_PORT=8443\nWAF_NODES="n1:10.0.0.11 n2:10.0.0.12 n3:10.0.0.13"\n' > "$TMP/inv.env"
printf 'vip=__VIP__ me=__NODE_NAME__/__NODE_IP__ prio=__NODE_PRIORITY__\npeers:\n__PEERS__\nservers:\n__HAPROXY_SERVERS__\n' > "$TMP/t.tmpl"
out=$(env -i PATH="$PATH" HOME="$HOME" INVENTORY="$TMP/inv.env" "$ROOT/lab/render.sh" "$TMP/t.tmpl" n2 2>&1)
t() { if eval "$2"; then echo "PASS $1"; else echo "FAIL $1"; fail=1; fi; }
t "substitutes inventory vars in clean env" '[[ $out == *"vip=10.0.0.100 me=n2/10.0.0.12 prio=100"* ]]'
t "peers exclude self"                      '[[ $out == *"10.0.0.11"* && $out == *"10.0.0.13"* && $(grep -c "^        10.0.0.12$" <<<"$out") -eq 0 ]]'
t "one server line per node"                '[ "$(grep -c "^    server n[123] 10.0.0.1[123]:8443$" <<<"$out")" -eq 3 ]'
env -i PATH="$PATH" HOME="$HOME" INVENTORY="$TMP/inv.env" "$ROOT/lab/render.sh" "$TMP/t.tmpl" nX >/dev/null 2>&1
t "unknown node fails" '[ $? -ne 0 ]'
printf '__NOPE__\n' > "$TMP/bad.tmpl"
env -i PATH="$PATH" HOME="$HOME" INVENTORY="$TMP/inv.env" "$ROOT/lab/render.sh" "$TMP/bad.tmpl" n1 >/dev/null 2>&1
t "unknown placeholder fails" '[ $? -ne 0 ]'
exit $fail
