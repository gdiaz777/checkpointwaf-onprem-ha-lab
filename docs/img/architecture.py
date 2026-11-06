"""CloudGuard WAF on-prem HA without a load balancer: architecture + measured failure scenarios.

Usage: python3 docs/img/architecture.py docs/img/architecture.excalidraw
"""
import sys
import textwrap
sys.path.insert(0, __import__("os").path.dirname(__import__("os").path.abspath(__file__)))  # exdraw.py lives next to this file
from exdraw import Diagram, C

out = sys.argv[1] if len(sys.argv) > 1 else "architecture.excalidraw"
d = Diagram(scale=1.0)

# ---------- estilos ----------
HAP = dict(stroke=C.blue, bg=C.blue_bg, label_color=C.blue)
HAP_SB = dict(stroke=C.gray, bg="#f1f3f5", label_color=C.gray, style="dashed")
AG = dict(stroke="#a61e4d", bg="#fcc2d7", label_color="#a61e4d")
KA = dict(stroke=C.purple_dark, bg="#e5dbff", label_color=C.purple_dark)
VIP = dict(stroke=C.purple_dark, bg=C.purple, label_color=C.white)
FAIL = dict(stroke="#e03131", bg="#ffe3e3", label_color="#e03131", style="dashed")
WARN = dict(stroke="#f08c00", bg="#fff3bf", label_color="#e67700")
OKG = dict(stroke="#2f9e44", bg="#d3f9d8", label_color="#2f9e44")
APP = dict(stroke=C.green, bg=C.green_bg, label_color=C.green)
RED, GREEN, AMBER = "#e03131", "#2f9e44", "#f08c00"

# =====================================================================
# 1) ARQUITECTURA
# =====================================================================
d.text(20, 0, "CloudGuard WAF on-prem HA · HAProxy + keepalived + agent on every node",
       size=26)
d.text(20, 36, "No load balancer · perimeter firewall DNAT to a VIP · any hypervisor (lab: KVM, IPs from the lab)",
       size=15, color=C.gray)

# Usuario y FW
d.ellipse(150, 75, 120, 44, stroke=C.black, bg=C.white, label="Client", size=15)
d.arrow((210, 119), (210, 150), stroke=C.black, stroke_width=2)
d.rect(60, 150, 300, 56, stroke=C.red, bg="#fff0f0", stroke_width=2, rounded=True,
       label="Perimeter firewall (e.g. Check Point)\nDNAT public IP:443 → VIP (no SNAT)", size=14,
       label_color=C.red)
d.arrow((210, 206), (210, 250), stroke=C.black, stroke_width=2)

# VIP
d.rect(110, 250, 200, 46, stroke_width=2, rounded=True,
       label="VIP 10.90.20.100:443\n(keepalived / VRRP)", size=13, **VIP)
d.arrow((210, 296), (210, 382), stroke=C.purple_dark, stroke_width=2)

# VRRP entre keepalived (ruta por arriba)
d.line((357, 382), (357, 316), (817, 316), (817, 382), stroke=C.purple, stroke_width=2,
       style="dashed")
d.text(470, 298, "VRRP unicast (advert every 1 s)", size=12, color=C.purple_dark)
d.line((817, 316), (1277, 316), (1277, 382), stroke=C.purple, stroke_width=1,
       style="dotted")


def vm(x0, name, ip, active, future=False):
    st = "dashed" if future else "solid"
    d.rect(x0, 330, 320, 370, stroke=C.gray if future else C.black,
           bg=C.white, stroke_width=2, style=st, rounded=True,
           label=f"{name} · {ip}", label_pos="top-left", size=14,
           label_color=C.gray if future else C.black)
    if future:
        d.rect(x0 + 20, 382, 180, 75, size=12, rounded=True,
               label="HAProxy VIP:443\n(standby)", **HAP_SB)
        d.rect(x0 + 210, 382, 95, 75, size=12, rounded=True, style="dashed",
               stroke=C.gray, bg="#f1f3f5", label="keepalived\nBACKUP",
               label_color=C.gray)
        d.rect(x0 + 20, 580, 280, 100, size=13, rounded=True, style="dashed",
               stroke=AG["stroke"], bg="#fff0f6", label="NGINX + CG WAF agent\nnode IP:443 (registers with\nthe same profile/token)",
               label_color=AG["label_color"])
        return
    if active:
        d.rect(x0 + 20, 382, 180, 75, stroke_width=2, size=12, rounded=True,
               label="HAProxy VIP:443 (ACTIVE)\nTLS · resets client XFF\nper-app pools · checks",
               **HAP)
    else:
        d.rect(x0 + 20, 382, 180, 75, size=12, rounded=True,
               label="HAProxy VIP:443\n(standby: same config,\nno traffic)", **HAP_SB)
    d.rect(x0 + 210, 382, 95, 75, size=12, rounded=True,
           label="keepalived\n" + ("MASTER" if active else "BACKUP"), **KA)
    d.rect(x0 + 20, 580, 280, 100, stroke_width=2, size=13, rounded=True,
           label="NGINX + CG WAF agent\nnode IP:443 (inspection)", **AG)


vm(100, "waf-node1", "10.90.20.11", active=True)
vm(560, "waf-node2", "10.90.20.12", active=False)
vm(1020, "waf-node3 (scale-out)", "10.90.20.13", active=False, future=True)

# active HAProxy -> all agents (bus)
d.line((110 + 100, 457), (210, 520), stroke=C.blue, stroke_width=2)
d.line((210, 520), (1180, 520), stroke=C.blue, stroke_width=2)
d.line((720, 520), (1180, 520), stroke=C.blue, stroke_width=2, style="dashed")
d.arrow((260, 520), (260, 580), stroke=C.blue, stroke_width=2)
d.arrow((720, 520), (720, 580), stroke=C.blue, stroke_width=2)
d.arrow((1180, 520), (1180, 580), stroke=C.blue, stroke_width=2, style="dashed")
d.text(222, 463, "leastconn · per-app pools\nhealth check per Host, 3 s\nretries + redispatch 1",
       size=11, color=C.blue)

# agents -> backends
for x, st in ((260, "solid"), (720, "solid"), (1180, "dashed")):
    d.line((x, 680), (x, 750), stroke=C.green, stroke_width=2, style=st)
d.line((260, 750), (1180, 750), stroke=C.green, stroke_width=2)
d.arrow((560, 750), (560, 785), stroke=C.green, stroke_width=2)
d.rect(410, 785, 300, 56, stroke_width=2, rounded=True, size=14,
       label="app1 → backend1 10.90.20.5\napp2 → backend2 10.90.20.6", **APP)

# Infinity Portal
d.rect(1060, 75, 280, 70, stroke="#1971c2", bg="#e7f5ff", stroke_width=2, rounded=True,
       label="Infinity Portal (CloudGuard WAF)\npolicy · assets · logs · status", size=13,
       label_color="#1971c2")
d.text(1060, 152, "All agents: outbound HTTPS to the portal\n(same profile & policy on every node)",
       size=12, color="#1971c2")

# Notes
d.note(1380, 75, 330, 230,
       "Normal flow\n"
       "1. Client → firewall published IP\n"
       "2. Firewall DNATs to the VIP (on node1)\n"
       "3. HAProxy on node1 terminates TLS, adds XFF\n"
       "4. Routes by Host to be_app1 / be_app2,\n"
       "    each pool = ALL agents\n"
       "5. Agent (NGINX + CG WAF) inspects\n"
       "    and proxies to the app backend\n\n"
       "Agent inspects only if host AND port (443)\n"
       "match the asset → NGINX on node IP:443.\n"
       "keepalived decides WHICH node has the VIP.", size=13)
d.note(1380, 320, 330, 205,
       "Key settings\n"
       "HAProxy:\n"
       "  check inter 3s fall 3 rise 2 · slowstart 30s\n"
       "  timeout connect 1s · retries 3 · redispatch 1\n"
       "  observe layer7 · on-error fastinter\n"
       "keepalived:\n"
       "  advert_int 1 · unicast_peer · nopreempt\n"
       "  chk_haproxy WITHOUT weight (→ FAULT)\n"
       "System:\n"
       "  net.ipv4.ip_nonlocal_bind=1", size=13)
d.note(1380, 540, 330, 160,
       "Scale-out (node3, node4…)  — measured: 0 errors\n"
       "• Build VM, install agent with the same token\n"
       "• Add it to WAF_NODES\n"
       "• Reload keepalived, then HAProxy on existing nodes\n"
       "• Start HAProxy + keepalived on the new node LAST\n"
       "• No change on the firewall or the portal", size=13)

# Leyenda
lx, ly = 1380, 720
d.text(lx, ly, "Legend", size=14)
items = [("Active", HAP), ("Standby", HAP_SB), ("Down", FAIL), ("Degraded", WARN),
         ("Recovering", OKG)]
for i, (t, s) in enumerate(items):
    yy = ly + 25 + i * 26
    d.rect(lx, yy, 34, 20, **{k: v for k, v in s.items() if k != "label_color"})
    d.text(lx + 44, yy + 2, t, size=13)

# =====================================================================
# 2) ESCENARIOS
# =====================================================================
SY = 900
d.text(20, SY, "Failure scenarios (2 nodes, measured with ~5 req/s per app)", size=24)
d.line((20, SY + 36), (1710, SY + 36), stroke=C.lightgray, stroke_width=1)

PW, PH = 410, 450


def panel(col, row, title, header, cfg, lines, badge, badge_color):
    px, py = 20 + col * (PW + 20), SY + 55 + row * (PH + 25)
    d.rect(px, py, PW, PH, stroke=C.lightgray, bg=C.white, stroke_width=1, rounded=True)
    d.rect(px, py, PW, 34, stroke=header, bg=header, label=title, size=15,
           label_color=C.white)
    vip_on = cfg.get("vip", 1)
    for i in (1, 2):
        vx = px + 15 + (i - 1) * 200
        st = cfg.get(f"vm{i}", "ok")
        d.rect(vx, py + 85, 180, 150, stroke=RED if st == "down" else C.black,
               bg="#fff5f5" if st == "down" else C.white,
               style="dashed" if st == "down" else "solid", rounded=True,
               label=f"node{i}" + ("  ✖ down" if st == "down" else ""),
               label_pos="top-left", size=12,
               label_color=RED if st == "down" else C.black)
        hs = cfg.get(f"hap{i}")
        if hs is None:
            hs = "ok" if i == vip_on else "sb"
        if st == "down":
            hs = "down"
        hstyle = {"ok": HAP, "sb": HAP_SB, "down": FAIL}[hs]
        hlabel = {"ok": "HAProxy (active)", "sb": "HAProxy (standby)",
                  "down": "✖ HAProxy"}[hs]
        if hs == "down" and st != "down":
            hlabel = "✖ HAProxy hung"
        d.rect(vx + 10, py + 110, 160, 38, rounded=True, size=12, label=hlabel, **hstyle)
        ag = cfg.get(f"ag{i}", "ok")
        if st == "down":
            ag = "down"
        astyle = {"ok": AG, "down": FAIL, "warn": WARN, "rec": OKG}[ag]
        alabel = cfg.get(f"ag{i}_label") or {"ok": "WAF agent", "down": "✖ WAF agent",
                                              "warn": "⚠ WAF agent", "rec": "↻ WAF agent"}[ag]
        d.rect(vx + 10, py + 185, 160, 40, rounded=True, size=12, label=alabel, **astyle)
        # agent -> backends
        d.line((vx + 90, py + 225), (vx + 90, py + 250),
               stroke=RED if ag == "down" else C.green, stroke_width=1,
               style="dashed" if ag == "down" else "solid")
    d.line((px + 105, py + 250), (px + 305, py + 250), stroke=C.green)
    app_st = cfg.get("app", "ok")
    d.arrow((px + 205, py + 250), (px + 205, py + 262), stroke=C.green)
    d.rect(px + 125, py + 262, 160, 28, rounded=True, size=12,
           label="✖ app1 backend down" if app_st == "down" else "Backends",
           **(FAIL if app_st == "down" else APP))

    # VIP
    vx = px + 15 + (vip_on - 1) * 200
    d.rect(vx + 45, py + 44, 90, 26, rounded=True, size=12, label="VIP", **VIP)
    d.arrow((vx + 90, py + 70), (vx + 90, py + 110), stroke=C.purple_dark, stroke_width=2)
    if cfg.get("vip_moved"):
        ox = px + 15 + (2 - vip_on) * 200
        d.rect(ox + 45, py + 44, 90, 26, rounded=True, size=12, style="dashed",
               stroke=C.gray, bg=C.white, label="VIP (before)", label_color=C.gray)
        d.arrow((ox + 135, py + 57), (vx + 45, py + 57), stroke=C.purple, stroke_width=2,
                style="dashed")
        d.text((ox + vx) / 2 + 90, py + 36, "failover", size=11, color=C.purple_dark,
               anchor="top-center")

    # active HAProxy -> agents
    ax = px + 15 + (vip_on - 1) * 200 + 90
    for i in (1, 2):
        tx = px + 15 + (i - 1) * 200 + 90
        link = cfg.get(f"link{i}", "ok")
        col = {"ok": C.blue, "down": RED, "rec": GREEN, "warn": AMBER}[link]
        sty = "dashed" if link in ("down", "rec") else "solid"
        if tx == ax:
            d.arrow((ax, py + 148), (ax, py + 185), stroke=col, stroke_width=2, style=sty)
            mx, my = ax + 32, py + 160
        else:
            off = 40 if tx > ax else -40
            d.arrow((ax + off, py + 148), (ax + off, py + 166), (tx, py + 166), (tx, py + 185),
                    stroke=col, stroke_width=2, style=sty)
            mx, my = (tx - 42 if tx > ax else tx + 42), py + 150
        tag = cfg.get(f"link{i}_tag")
        if tag:
            d.text(mx, my, tag, size=11, color=col, anchor="top-center")

    # texto
    body = []
    for ln in lines:
        if ln.startswith("•"):
            w = textwrap.wrap(ln, 56, subsequent_indent="   ")
        else:
            w = textwrap.wrap(ln, 56)
        body.extend(w or [""])
    d.text(px + 12, py + 302, "\n".join(body), size=12)
    d.rect(px + 12, py + PH - 36, PW - 24, 26, rounded=True, stroke=badge_color,
           bg=badge_color, label=badge, size=13, label_color=C.white)


panel(0, 0, "1 · Agent data path on node2 down", "#495057",
      dict(ag2="down", link2="down", link2_tag="✖ DOWN  "),
      ["• Injected: NGINX stopped on node2 (VM up).",
       "• Refused connection → same request retried on node1 (retries + redispatch); health check DOWN in ~9 s.",
       "• keepalived: no change.",
       "• Measured: 0 failed, no gap."],
      "Impact: transparent", GREEN)

panel(1, 0, "2 · node2 VM powered off", "#495057",
      dict(vm2="down", link2="down", link2_tag="✖ DOWN  "),
      ["• Injected: virsh destroy (no TCP reset).",
       "• timeout connect 1s + redispatch 1 → retried on node1.",
       "• VIP stays on node1. node2 rejoins by itself after boot.",
       "• Measured: 0 failed (6 with connect 3s), gap 1.0 s."],
      "Impact: transparent", GREEN)

panel(2, 0, "3 · node1 VM (VIP owner) powered off", "#c92a2a",
      dict(vm1="down", vip=2, vip_moved=True, link1="down", link1_tag="✖ DOWN  "),
      ["• node2 misses VRRP adverts (~3 s) → MASTER, VIP + gratuitous ARP.",
       "• In-flight connections lost (no state sync).",
       "• node1 returns as BACKUP (nopreempt).",
       "• Measured: 1–2 failed, gap 2.2–4.2 s."],
      "Impact: 2–4 s outage", AMBER)

panel(3, 0, "4 · HAProxy hangs on node1 (VIP owner)", "#c92a2a",
      dict(hap1="down", hap2="ok", vip=2, vip_moved=True),
      ["• Injected: SIGSTOP (process exists, no answer).",
       "• chk_haproxy (curl -m 2) fails ×2 → FAULT → VIP to node2.",
       "• node1's AGENT keeps serving via node2's HAProxy.",
       "• Measured: 3 failed, longest gap 6.2 s."],
      "Impact: ~6 s outage", AMBER)

panel(0, 1, "5 · Agent on node2 answers 503", "#495057",
      dict(ag2="warn", ag2_label="⚠ WAF agent (503)", link2="down", link2_tag="✖ DOWN  "),
      ["• observe layer7 … on-error fastinter → active check every 1 s once errors show → ejected in 2–4 s.",
       "• Measured: 6–12 × 503, then 0.",
       "• Not mark-down: it would eject ALL agents on backend 5xx. Option: retry-on 503."],
      "Impact: errors for 2–4 s", AMBER)

panel(1, 1, "6 · node2's agent comes back", "#2b8a3e",
      dict(ag2="rec", link2="rec", link2_tag="↻ rise 2"),
      ["• 2 good checks (rise 2) → UP, back in ~3 s.",
       "• Balanced again within 5 s.",
       "• slowstart 30s barely visible at light load with leastconn; it protects under real concurrency."],
      "Impact: none", GREEN)

panel(2, 1, "7 · ⚠ Agent stops inspecting (fail-open)", "#e67700",
      dict(ag2="warn", ag2_label="⚠ agent not inspecting", link2="warn", link2_tag="check OK"),
      ["• Injected: cpnano -q on node2 (NGINX keeps running).",
       "• XSS via node1 → 403, via node2 → 200: NOT inspected. HAProxy still sends node2 50 %.",
       "• Detect via portal agent status / cpnano -s / attack probe."],
      "Risk: uninspected traffic", RED)

panel(3, 1, "8 · app1 backend down", "#e67700",
      dict(app="down", link1="down", link2="down", link1_tag="✖  ", link2_tag="✖  "),
      ["• be_app1 checks fail on all agents → app1 gets 502/503.",
       "• be_app2 (same agents, own Host check) stays UP.",
       "• VIP does not move (would not help).",
       "• Measured: app2 0 failed."],
      "Impact: app1 only", RED)

print(d.save(out))
