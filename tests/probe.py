#!/usr/bin/env python3
"""Send one request every --interval seconds and log each result to CSV.

Runs on the test client. Standard library only.

CSV columns: ts_iso,app,status,latency_ms,served_by,agent,error
  status   HTTP status, or 0 when there was no HTTP answer (timeout, refused, TLS error)
  agent    "client_addr" from the backend's JSON = the WAF node whose agent forwarded it
  served_by X-Served-By header added by HAProxy (<haproxy node>/<agent>)

Stops after --duration seconds, or on SIGINT/SIGTERM.
"""
import argparse
import csv
import json
import signal
import ssl
import sys
import time
import urllib.error
import urllib.request
from datetime import datetime, timezone

stop = False


def _stop(*_):
    global stop
    stop = True


def one(url, ctx, timeout):
    t0 = time.monotonic()
    status, served_by, agent, err = 0, "", "", ""
    try:
        with urllib.request.urlopen(urllib.request.Request(url, headers={"Connection": "close"}),
                                    timeout=timeout, context=ctx) as r:
            status = r.status
            served_by = r.headers.get("X-Served-By", "")
            body = r.read()
    except urllib.error.HTTPError as e:
        status, served_by, body = e.code, e.headers.get("X-Served-By", ""), b""
    except Exception as e:  # timeout, refused, reset, TLS...
        err, body = f"{type(e).__name__}: {e}"[:120], b""
    try:
        agent = json.loads(body).get("client_addr", "") if body else ""
    except ValueError:
        pass
    return status, round((time.monotonic() - t0) * 1000), served_by, agent, err


def main():
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--url", required=True)
    ap.add_argument("--app", default="", help="label written to the CSV (default: URL host)")
    ap.add_argument("--cacert", help="CA bundle to verify the server certificate")
    ap.add_argument("--interval", type=float, default=0.2)
    ap.add_argument("--timeout", type=float, default=2.0)
    ap.add_argument("--duration", type=float, default=0, help="seconds; 0 = until stopped")
    ap.add_argument("--out", required=True)
    a = ap.parse_args()
    app = a.app or urllib.request.urlparse(a.url).hostname.split(".")[0]
    ctx = ssl.create_default_context(cafile=a.cacert) if a.cacert else ssl.create_default_context()
    signal.signal(signal.SIGINT, _stop)
    signal.signal(signal.SIGTERM, _stop)
    end = time.monotonic() + a.duration if a.duration else None
    with open(a.out, "w", newline="", buffering=1) as f:
        w = csv.writer(f)
        w.writerow(["ts_iso", "app", "status", "latency_ms", "served_by", "agent", "error"])
        while not stop and (end is None or time.monotonic() < end):
            started = time.monotonic()
            ts = datetime.now(timezone.utc).isoformat(timespec="milliseconds")
            w.writerow([ts, app, *one(a.url, ctx, a.timeout)])
            time.sleep(max(0.0, a.interval - (time.monotonic() - started)))
    return 0


if __name__ == "__main__":
    sys.exit(main())
