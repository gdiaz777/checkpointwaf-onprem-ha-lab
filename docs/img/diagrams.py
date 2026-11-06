"""Explanatory diagrams for GUIDE.md: traffic & ports, scale-out order, test harness.

Usage: python3 docs/img/diagrams.py docs/img
Writes traffic-and-ports.excalidraw, scale-out-order.excalidraw, test-harness.excalidraw
"""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))  # exdraw.py lives next to this file
from exdraw import Diagram, C  # noqa: E402

OUT = sys.argv[1] if len(sys.argv) > 1 else "."

HAP = dict(stroke=C.blue, bg=C.blue_bg, label_color=C.blue)
AG = dict(stroke="#a61e4d", bg="#fcc2d7", label_color="#a61e4d")
KA = dict(stroke=C.purple_dark, bg="#e5dbff", label_color=C.purple_dark)
VIP = dict(stroke=C.purple_dark, bg=C.purple, label_color=C.white)
FW = dict(stroke=C.red, bg="#fff0f0", label_color=C.red)
APP = dict(stroke=C.green, bg=C.green_bg, label_color=C.green)
PORTAL = dict(stroke="#1971c2", bg="#e7f5ff", label_color="#1971c2")
STEP = dict(stroke=C.black, bg=C.white, label_color=C.black)
GREEN, RED, AMBER = "#2f9e44", "#e03131", "#f08c00"


# ---------------------------------------------------------------- 1. traffic & ports
def traffic():
    d = Diagram()
    d.text(20, 0, "How one request flows: addresses, ports, TLS legs and client IP", size=24)
    d.text(20, 34, "Lab values shown. The VIP owner can be any node; every HAProxy uses every agent.",
           size=14, color=C.gray)

    d.ellipse(20, 200, 150, 74, stroke=C.black, bg=C.white, label="Client\n10.90.30.10", size=14)
    d.rect(230, 180, 210, 114, rounded=True, stroke_width=2, size=13,
           label="Perimeter firewall\nDNAT public IP:443\n→ VIP 10.90.20.100:443\n(NO source NAT)", **FW)
    d.arrow((170, 237), (230, 237), stroke=C.black, stroke_width=2)
    d.text(176, 210, "HTTPS", size=12)

    # VIP owner node
    d.rect(490, 90, 350, 400, rounded=True, stroke=C.black, bg=C.white, stroke_width=2,
           label="VIP owner (e.g. waf-node1)", label_pos="top-left", size=14)
    d.rect(510, 130, 310, 40, rounded=True, size=13, label="VIP 10.90.20.100 (moves between nodes)", **VIP)
    d.rect(510, 185, 310, 190, rounded=True, stroke_width=2, size=13,
           label="HAProxy  ·  listens VIP:443 (+127.0.0.1)\n\n① terminates client TLS (cert by SNI)\n"
                 "• deletes client X-Forwarded-For\n• adds XFF = real client IP\n"
                 "• routes by Host → be_app1 / be_app2\n• leastconn over ALL agents\n• health checks + retries",
           **HAP)
    d.rect(510, 390, 310, 80, rounded=True, size=13,
           label="keepalived (VRRP unicast)\nholds the VIP while HAProxy answers", **KA)
    d.arrow((440, 237), (510, 237), stroke=C.black, stroke_width=2)

    # agents
    ys = [90, 230, 370]
    for i, y in enumerate(ys, 1):
        d.rect(930, y, 330, 120, rounded=True, stroke_width=2, size=13,
               label=f"waf-node{i}  ·  NGINX + Check Point WAF agent\nlistens 10.90.20.1{i}:443 (node's own IP)\n"
                     f"② TLS from HAProxy (app cert)\nasset match = Host AND port 443", **AG)
        d.arrow((820, 280), (930, y + 60), stroke=C.blue, stroke_width=2)
    d.text(846, 96, "② TLS\nre-encrypted\n+ verified", size=11, color=C.blue)

    # backends
    d.line((1260, 150), (1290, 150), (1290, 430), (1260, 430), stroke=C.green, stroke_width=2)
    d.line((1260, 290), (1290, 290), stroke=C.green, stroke_width=2)
    d.arrow((1290, 200), (1340, 200), stroke=C.green, stroke_width=2)
    d.arrow((1290, 340), (1340, 340), stroke=C.green, stroke_width=2)
    d.rect(1340, 160, 230, 80, rounded=True, stroke_width=2, size=13,
           label="backend1 · app1\n10.90.20.5:443", **APP)
    d.rect(1340, 300, 230, 80, rounded=True, stroke_width=2, size=13,
           label="backend2 · app2\n10.90.20.6:443", **APP)
    d.text(1296, 395, "③ TLS, backend\ncert verified", size=12, color=C.green)

    d.rect(1340, 60, 230, 70, rounded=True, size=12,
           label="Infinity Portal\npolicy · logs (outbound HTTPS\nfrom every agent)", **PORTAL)

    # notes
    d.note(20, 520, 450, 150,
           "Client IP end to end\n"
           "• Firewall: DNAT only (keeps 10.90.30.10 as source)\n"
           "• HAProxy: drops client XFF, sets XFF = 10.90.30.10\n"
           "• Asset source identity = X-Forwarded-For\n"
           "• Portal: Source IP = HAProxy node,\n"
           "  Source Identifier = 10.90.30.10 (the client)", size=13)
    d.note(490, 520, 520, 150,
           "Why port 443 twice on the same VM?\n"
           "• HAProxy binds the VIP:443 (ip_nonlocal_bind=1 on every node)\n"
           "• NGINX binds the node's own IP:443\n"
           "• The agent applies an asset only if Host AND the listening\n"
           "  port match the asset URL (https://app… = 443).\n"
           "  On 8443 nothing was inspected and nothing was logged.", size=13)
    d.note(1030, 520, 540, 150,
           "Three TLS legs, one cert per app on legs ① and ②\n"
           "① client → HAProxy: app cert (public trust)\n"
           "② HAProxy → agent: same app cert, verified with ca-file\n"
           "③ agent → backend: backend cert, verified by NGINX\n"
           "Rotation = push to every node, validate, graceful reload", size=13)
    return d


# ---------------------------------------------------------------- 2. scale-out order
def scale():
    d = Diagram()
    d.text(20, 0, "Adding and removing a node without downtime: the order matters", size=24)
    d.text(20, 34, "Measured with traffic running: 0 failed requests for both operations.", size=14, color=GREEN)
    add = [
        ("1  Build", "New VM from the template\nNGINX + agent with the\nSAME token / profile\nwait: Registered Instances > 0"),
        ("2  Inventory", "Add the node to WAF_NODES\n(single source of truth for\nHAProxy servers and\nkeepalived peers)"),
        ("3  keepalived", "Re-render + reload on the\nEXISTING nodes first:\nthey learn the new\nunicast peer"),
        ("4  HAProxy", "Re-render + reload on the\nexisting nodes: the new\nagent joins every pool\n(reload is hitless)"),
        ("5  New node", "Start HAProxy + keepalived\non the new node LAST:\nit hears the master and\nstays BACKUP"),
    ]
    d.text(20, 70, "Add a node", size=18)
    for i, (h, t) in enumerate(add):
        x = 20 + i * 300
        d.rect(x, 100, 270, 36, stroke=C.blue, bg=C.blue, label=h, size=15, label_color=C.white)
        d.rect(x, 136, 270, 130, stroke=C.blue, bg=C.blue_bg, label=t, size=13, label_color=C.black)
        if i < 4:
            d.arrow((x + 270, 200), (x + 300, 200), stroke=C.blue, stroke_width=2)
    d.rect(20, 290, 1470, 70, rounded=True, stroke=RED, bg="#fff5f5", style="dashed", stroke_width=2, size=14,
           label="Never start keepalived on the new node before step 3: with unicast VRRP the master only sends adverts "
                 "to peers it knows.\nThe new node hears nobody, becomes MASTER and grabs the VIP (split-brain).",
           label_color=RED)
    rem = [
        ("1  Drain", "HAProxy runtime API on every\nnode: set server … state drain\nwait for 0 active sessions"),
        ("2  VIP", "If the node holds the VIP,\nstop its keepalived first\n(clean handover, no errors)"),
        ("3  Config", "Remove from WAF_NODES,\nreload keepalived + HAProxy\non the remaining nodes"),
        ("4  Stop", "Stop HAProxy + NGINX on it.\nDecommission: cpnano -u,\ndelete agent in the portal"),
    ]
    d.text(20, 385, "Remove a node", size=18)
    for i, (h, t) in enumerate(rem):
        x = 20 + i * 370
        d.rect(x, 415, 340, 36, stroke=C.gray, bg=C.header_gray, label=h, size=15, label_color=C.white)
        d.rect(x, 451, 340, 100, stroke=C.gray, bg="#f1f3f5", label=t, size=13, label_color=C.black)
        if i < 3:
            d.arrow((x + 340, 500), (x + 370, 500), stroke=C.gray, stroke_width=2)
    return d


# ---------------------------------------------------------------- 3. test harness
def harness():
    d = Diagram()
    d.text(20, 0, "How the failover tests measure user impact", size=24)
    d.text(20, 34, "lab/run-scenario.sh  <id>  \"<inject>\"  \"<restore>\"   ·   tests/run-all-scenarios.sh runs everything (~20 min)",
           size=14, color=C.gray)
    d.rect(20, 80, 300, 200, rounded=True, stroke=C.black, bg=C.white, stroke_width=2,
           label="client VM (outside network)", label_pos="top-left", size=14)
    d.rect(40, 120, 260, 140, rounded=True, size=13, stroke=C.orange, bg="#fff4e6", label_color=C.orange,
           label="tests/probe.py  × 2  (app1, app2)\n1 HTTPS request / 0.2 s each\nnew TCP+TLS connection\nper request\n"
                 "gives up after 2 s")
    d.arrow((320, 180), (380, 180), stroke=C.black, stroke_width=2)
    d.rect(380, 120, 420, 120, rounded=True, size=13, stroke=C.black, bg=C.white, label_color=C.black,
           label="firewall DNAT → VIP → HAProxy → agent → backend\n\nbackend answers JSON:\n"
                 "client_addr = the agent that forwarded it\nxff = client IP chain")
    d.arrow((800, 180), (860, 180), stroke=C.black, stroke_width=2)
    d.rect(860, 100, 330, 160, rounded=True, size=13, stroke=C.gray, bg="#f8f9fa", label_color=C.black,
           label="one CSV row per request\n\nts · app · HTTP status · latency\nX-Served-By (HAProxy/agent)\n"
                 "agent (client_addr) · error\n(status 0 = no answer in 2 s)")

    # timeline
    d.text(20, 310, "Timeline of one scenario", size=18)
    segs = [("probes start", 110, C.lightgray), ("PRE 10 s", 140, "#dee2e6"), ("INJECT", 110, RED),
            ("SETTLE ~30 s", 240, "#ffe3e3"), ("RESTORE", 110, GREEN), ("POST 40–90 s", 300, "#d3f9d8"),
            ("probes stop", 110, C.lightgray)]
    x = 20
    for t, w, col in segs:
        d.rect(x, 345, w, 46, stroke=C.black, bg=col, label=t, size=13,
               label_color=C.white if col in (RED, GREEN) else C.black)
        x += w
    d.text(20, 400, "INJECT / RESTORE are plain shell commands (systemctl stop, virsh destroy, kill -STOP, cpnano -q …). "
                    "Their timestamps split the results into before / during / after.", size=13, color=C.gray)

    d.arrow((1190, 180), (1260, 180), stroke=C.black, stroke_width=2)
    d.rect(1260, 80, 330, 290, rounded=True, size=13, stroke=C.blue, bg=C.blue_bg, label_color=C.black,
           label="tests/summarize.py\n→ tests/results/<id>/summary.md\n\nfailed: requests without 2xx/3xx\n"
                 "max_gap_s: longest time without\n  any success = the outage felt\n"
                 "before / during / after:\n  successes per agent\nstatus counts (502, 503, 0 …)\n10 s buckets (recovery ramp)")
    d.note(20, 440, 1570, 110,
           "Example (S3, VIP owner powered off):  app1: total=697 failed=1 max_gap_s=2.2  ·  during {'10.90.20.12': 141}  ·  "
           "vip owner after inject: waf-node2\n"
           "Read it as: one request lost, 2.2 s without answers while the VIP moved, then node2's HAProxy and agent "
           "carried all traffic.\nEvery scenario also checks that exactly ONE node holds the VIP at the end (tools/vip-owner.sh).",
           size=13)
    return d


for name, fn in (("traffic-and-ports", traffic), ("scale-out-order", scale), ("test-harness", harness)):
    print(fn().save(os.path.join(OUT, f"{name}.excalidraw")))
