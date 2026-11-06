#!/usr/bin/env bash
# Run one failure scenario with probes running from the test client.
# Usage: lab/run-scenario.sh <id> "<inject cmd>" "<restore cmd>" [settle_s=30] [post_s=40] [pre_s=10]
#   1. start one probe per app on the client (5 req/s each, new connection per request)
#   2. wait pre_s, run <inject cmd> (on this host), wait settle_s
#   3. run <restore cmd>, wait post_s, stop the probes
#   4. copy the CSVs to tests/results/<id>/raw/, write tests/results/<id>/summary.md
# Commands run in bash on the host; use lab/ssh.sh / virsh inside them.
set -euo pipefail
ID=$1 INJECT=$2 RESTORE=$3 SETTLE=${4:-30} POST=${5:-40} PRE=${6:-10}
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
source "$ROOT/lab/inventory.env"
OUT="$ROOT/tests/results/$ID"; mkdir -p "$OUT/raw"
C() { "$ROOT/lab/ssh.sh" client "$@"; }
log() { printf '%s  %s\n' "$(date -u +%H:%M:%S.%3N)" "${*//$ROOT\//}" | tee -a "$OUT/raw/events.log"; }
: > "$OUT/raw/events.log"

C 'cat > /home/lab/probe.py' < "$ROOT/tests/probe.py"
C 'test -f /home/lab/probe.pids && kill $(cat /home/lab/probe.pids) 2>/dev/null; rm -f /home/lab/probe.pids /home/lab/probe-*.csv'
for app in app1 app2; do
  C "nohup python3 /home/lab/probe.py --url https://$app.waflab.example/ --app $app --cacert /home/lab/ca.crt --interval 0.2 --out /home/lab/probe-$app.csv >/dev/null 2>&1 & echo \$! >> /home/lab/probe.pids"
done
log "probes started (vip owner: $("$ROOT/tools/vip-owner.sh" | tr '\n' ' '))"
sleep "$PRE"
log "INJECT: $INJECT"; bash -c "$INJECT" 2>&1 | sed -e 's/\x1b\[[0-9;]*m//g' -e "s|$ROOT/||g" -e 's/^/    /' | tee -a "$OUT/raw/events.log"
inject_rc=${PIPESTATUS[0]}; [ "$inject_rc" -eq 0 ] || log "INJECT FAILED (exit $inject_rc)"
sleep "$SETTLE"
log "vip owner after inject: $("$ROOT/tools/vip-owner.sh" | tr '\n' ' ')"
log "RESTORE: $RESTORE"; bash -c "$RESTORE" 2>&1 | sed -e 's/\x1b\[[0-9;]*m//g' -e "s|$ROOT/||g" -e 's/^/    /' | tee -a "$OUT/raw/events.log" || true
sleep "$POST"
C 'kill $(cat /home/lab/probe.pids) 2>/dev/null; rm -f /home/lab/probe.pids'; sleep 1
for app in app1 app2; do C "cat /home/lab/probe-$app.csv" > "$OUT/raw/probe-$app.csv"; done
owner=$("$ROOT/tools/vip-owner.sh") && rc=0 || rc=$?
log "probes stopped (vip owner: $(echo $owner), vip-owner rc=$rc)"
{
  echo "# Scenario $ID"
  echo
  echo '```'
  cat "$OUT/raw/events.log"
  echo '```'
  echo
  echo '```'
  python3 "$ROOT/tests/summarize.py" "$OUT"/raw/probe-*.csv --events "$OUT/raw/events.log" --buckets 10
  echo '```'
} > "$OUT/summary.md"
python3 "$ROOT/tests/summarize.py" "$OUT"/raw/probe-*.csv --events "$OUT/raw/events.log"
[ "${inject_rc:-0}" -eq 0 ] || exit 3   # the injected action itself failed: results are not valid
exit $rc
