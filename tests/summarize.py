#!/usr/bin/env python3
"""Summarize probe CSVs (from probe.py): failures, longest outage, agent spread.

Usage:
  summarize.py <csv>... [--json] [--buckets SECONDS]

Per app it reports:
  total, failed (status 0 or >= 500), max_gap_s (longest interval without a
  successful 2xx/3xx answer), and requests per agent in three windows:
  before the first failure, during (first..last failure), after the last one.
"""
import argparse
import csv
import json
from collections import Counter, defaultdict
from datetime import datetime


def load(paths):
    """Read probe CSVs → {app: [row, ...]} sorted by time."""
    by_app = defaultdict(list)
    for p in paths:
        with open(p, newline="") as f:
            for r in csv.DictReader(f):
                r["t"] = datetime.fromisoformat(r["ts_iso"]).timestamp()
                r["status"] = int(r["status"])
                by_app[r["app"]].append(r)
    for rows in by_app.values():
        rows.sort(key=lambda r: r["t"])
    return dict(by_app)


def is_ok(r):
    return 200 <= r["status"] < 400


def split_from_events(events_log, any_ts_iso):
    """(inject_t, restore_t) epoch seconds from a run-scenario events.log.

    events.log has only HH:MM:SS.mmm (UTC); the date is taken from a probe row."""
    day = datetime.fromisoformat(any_ts_iso)
    found = {}
    for line in open(events_log):
        for tag in ("INJECT", "RESTORE"):
            if f"  {tag}:" in line and tag not in found:
                h, m, rest = line.split()[0].split(":")
                sec, ms = rest.split(".")
                found[tag] = day.replace(hour=int(h), minute=int(m), second=int(sec),
                                         microsecond=int(ms) * 1000).timestamp()
    return found["INJECT"], found["RESTORE"]


def summarize(rows, split=None):
    failed = [r for r in rows if not is_ok(r)]
    ok_times = [r["t"] for r in rows if is_ok(r)]
    start, end = rows[0]["t"], rows[-1]["t"]
    # longest interval without a success, including the window edges
    points = [start] + ok_times + [end]
    max_gap = max(b - a for a, b in zip(points, points[1:])) if len(points) > 1 else 0.0
    per_agent = {"before": Counter(), "during": Counter(), "after": Counter()}
    first_fail = failed[0]["t"] if failed else None
    last_fail = failed[-1]["t"] if failed else None
    if split:  # windows defined by the inject/restore events instead of by failures
        first_fail, last_fail = split
    for r in rows:
        if not is_ok(r) or not r["agent"]:
            continue
        if first_fail is None or r["t"] < first_fail:
            per_agent["before"][r["agent"]] += 1
        elif r["t"] <= last_fail:
            per_agent["during"][r["agent"]] += 1
        else:
            per_agent["after"][r["agent"]] += 1
    return {
        "total": len(rows),
        "failed": len(failed),
        "max_gap_s": round(max_gap, 2),
        "window_s": round(end - start, 2),
        "first_failure": failed[0]["ts_iso"] if failed else None,
        "last_failure": failed[-1]["ts_iso"] if failed else None,
        "per_agent": {k: dict(sorted(v.items())) for k, v in per_agent.items()},
        "status_counts": dict(sorted(Counter(r["status"] for r in rows).items())),
    }


def buckets(rows, seconds):
    """Successful requests per agent in consecutive time buckets of `seconds`."""
    start = rows[0]["t"]
    out = defaultdict(Counter)
    for r in rows:
        if is_ok(r) and r["agent"]:
            out[int((r["t"] - start) // seconds)][r["agent"]] += 1
    n = max(out) + 1 if out else 0
    return [dict(sorted(out[i].items())) for i in range(n)]


def main():
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("csv", nargs="+")
    ap.add_argument("--json", action="store_true")
    ap.add_argument("--buckets", type=float, default=0, help="also print per-agent counts per N seconds")
    ap.add_argument("--events", help="events.log from run-scenario: windows = before INJECT / INJECT..RESTORE / after")
    a = ap.parse_args()
    data = load(a.csv)
    result = {}
    for app, rows in sorted(data.items()):
        split = split_from_events(a.events, rows[0]["ts_iso"]) if a.events else None
        result[app] = summarize(rows, split)
    if a.buckets:
        for app, rows in data.items():
            result[app]["buckets"] = buckets(rows, a.buckets)
    if a.json:
        print(json.dumps(result, indent=2))
        return
    for app, s in result.items():
        print(f"{app}: total={s['total']} failed={s['failed']} max_gap_s={s['max_gap_s']} window_s={s['window_s']}")
        if s["failed"]:
            print(f"  failures: {s['first_failure']} → {s['last_failure']}")
            print(f"  status counts: {s['status_counts']}  (0 = no answer within the probe timeout)")
        if a.events:
            print("  windows: before INJECT / INJECT→RESTORE / after RESTORE")
        for w in ("before", "during", "after"):
            print(f"  {w:<6} {s['per_agent'][w]}")
        for i, b in enumerate(s.get("buckets", [])):
            print(f"  t+{i * a.buckets:>5.0f}s {b}")


if __name__ == "__main__":
    main()
