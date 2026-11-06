import csv
import json
import os
import socket
import subprocess
import sys
import threading
from http.server import BaseHTTPRequestHandler, HTTPServer

PROBE = os.path.join(os.path.dirname(__file__), "probe.py")


class H(BaseHTTPRequestHandler):
    def do_GET(self):
        body = json.dumps({"app": "app1", "client_addr": "10.90.20.12"}).encode()
        self.send_response(200)
        self.send_header("X-Served-By", "waf-node1/waf-node2")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, *a):
        pass


def run_probe(url, out, duration="0.5"):
    return subprocess.run([sys.executable, PROBE, "--url", url, "--interval", "0.1",
                           "--duration", duration, "--out", out, "--app", "app1"],
                          capture_output=True, text=True, timeout=20)


def test_probe_records_agent_and_served_by(tmp_path):
    srv = HTTPServer(("127.0.0.1", 0), H)
    threading.Thread(target=srv.serve_forever, daemon=True).start()
    out = tmp_path / "p.csv"
    r = run_probe(f"http://127.0.0.1:{srv.server_port}/", str(out))
    srv.shutdown()
    assert r.returncode == 0, r.stderr
    rows = list(csv.DictReader(open(out)))
    assert len(rows) >= 3
    assert rows[0]["status"] == "200"
    assert rows[0]["agent"] == "10.90.20.12"
    assert rows[0]["served_by"] == "waf-node1/waf-node2"
    assert rows[0]["app"] == "app1"


def test_probe_survives_connection_refused(tmp_path):
    s = socket.socket(); s.bind(("127.0.0.1", 0)); port = s.getsockname()[1]; s.close()
    out = tmp_path / "p.csv"
    r = run_probe(f"http://127.0.0.1:{port}/", str(out))
    assert r.returncode == 0, r.stderr
    rows = list(csv.DictReader(open(out)))
    assert rows and all(x["status"] == "0" for x in rows)
    assert rows[0]["error"]
