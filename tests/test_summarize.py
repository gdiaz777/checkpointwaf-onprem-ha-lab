import os
import sys

sys.path.insert(0, os.path.dirname(__file__))
from summarize import load, summarize, buckets  # noqa: E402

FIX = os.path.join(os.path.dirname(__file__), "fixtures", "sample-probe.csv")


def rows():
    return load([FIX])["app1"]


def test_counts():
    s = summarize(rows())
    assert s["total"] == 50
    assert s["failed"] == 5


def test_max_gap():
    assert summarize(rows())["max_gap_s"] == 2.4


def test_per_agent_windows():
    pa = summarize(rows())["per_agent"]
    assert pa["before"] == {"10.90.20.11": 10, "10.90.20.12": 10}
    assert pa["during"] == {"10.90.20.11": 5}
    assert pa["after"] == {"10.90.20.11": 10, "10.90.20.12": 10}


def test_no_failures_puts_everything_in_before():
    ok_rows = [r for r in rows() if r["status"] == 200]
    s = summarize(ok_rows)
    assert s["failed"] == 0
    assert s["per_agent"]["during"] == {} and s["per_agent"]["after"] == {}
    assert sum(s["per_agent"]["before"].values()) == 45


def test_all_failed_app():
    bad = [dict(r, status=0, agent="") for r in rows()]
    s = summarize(bad)
    assert s["failed"] == 50
    assert s["max_gap_s"] == 11.2  # whole window: 01:00:00.0 → 01:00:11.2


def test_status_5xx_counts_as_failed():
    r = rows()
    r[0] = dict(r[0], status=503)
    assert summarize(r)["failed"] == 6


def test_buckets_per_agent_counts():
    b = buckets(rows(), 5)
    assert b[0] == {"10.90.20.11": 10, "10.90.20.12": 10}   # 0–5 s
    assert b[1] == {"10.90.20.11": 12, "10.90.20.12": 6}    # 5–10 s: .11 ×5 during, then 7.4–9.8 alternating (7/.11, 6/.12)


def test_split_windows_by_event_times_without_failures():
    ok_rows = [r for r in rows() if r["status"] == 200]
    t0 = ok_rows[0]["t"]
    s = summarize(ok_rows, split=(t0 + 4.0, t0 + 7.2))
    assert s["per_agent"]["before"] == {"10.90.20.11": 10, "10.90.20.12": 10}
    assert s["per_agent"]["during"] == {"10.90.20.11": 5}
    assert s["per_agent"]["after"] == {"10.90.20.11": 10, "10.90.20.12": 10}


def test_split_from_events_log(tmp_path):
    from summarize import split_from_events
    log = tmp_path / "events.log"
    log.write_text("01:00:00.000  probes started\n01:00:04.000  INJECT: x\n    out\n"
                   "01:00:07.200  RESTORE: y\n01:00:12.000  probes stopped\n")
    a, b = split_from_events(str(log), rows()[0]["ts_iso"])
    assert round(b - a, 1) == 3.2


def test_status_counts():
    r = rows()
    r[0] = dict(r[0], status=503)
    assert summarize(r)["status_counts"] == {0: 5, 200: 44, 503: 1}
