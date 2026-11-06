# Check Point WAF on-prem HA lab — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build, test and document a two-app Check Point WAF HA lab with no load balancer. Every node runs HAProxy, keepalived and the agent. The guide is published as a public GitHub repo.

**Architecture:**
- KVM/libvirt VMs on the Ubuntu host:
  - 2 WAF nodes, plus a 3rd added during scale-out,
  - 2 backends,
  - 1 test-client VM on a separate "outside" network.
- The host plays the perimeter firewall, with DNAT to a keepalived VIP.
- On every WAF node, HAProxy routes by SNI/Host to per-app pools that list all agents. Each pool health-checks with its own Host header.
- Every chapter of the guide is written right after its step is executed and verified.

**Tech Stack:**
- Ubuntu 24.04 (host and guests), libvirt/QEMU, `virt-install`, cloud-init
- HAProxy (Ubuntu package), keepalived, NGINX
- Check Point WAF Linux agent
- openssl
- Python 3 (stdlib only) for the probe and summary scripts, with pytest for those scripts
- nftables/iptables on the host
- `gh` CLI

**Spec:** `docs/design/2026-11-06-cgwaf-onprem-ha-lab-design.md` (approved). Read it before any task.

## Global Constraints

- Repo root is this repository. GitHub repo is `gdiaz777/cgwaf-onprem-ha-lab`, **public**, MIT license, all content in **English**.
- The repo has **no reference to any customer**. FQDNs are `app1.waflab.example` and `app2.waflab.example` only.
- **No secrets are ever committed:** agent tokens, private keys, lab certificates, passwords, tenant or profile IDs.
  - Secrets go in `.env` (git-ignored) and `certs/` (git-ignored).
  - `tools/check-secrets.sh` must pass before every commit (pre-commit hook).
- **Every documented step has been executed.** Every behaviour claim cites probe output.
  - Exception: the vSphere and Check Point sections, which carry a visible `> **Not validated in this lab.**` banner.
- Inside-VM steps must not depend on KVM. Anything KVM-specific lives only in `docs/01-lab-host.md`, `docs/02-vms.md` (lab part) and `lab/`.
- Network `waflab` (NAT): `10.90.20.0/24`, gateway `.1`.
  - WAF nodes: node1 `.11`, node2 `.12`, node3 `.13`.
  - Backends: backend1 `.5`, backend2 `.6`.
  - VIP: `.100`.
- Network `wafout` (routed, simulates the Internet side of the firewall): `10.90.30.0/24`, host `.1`, client VM `.10`.
- Sizing:
  - WAF nodes: 2 vCPU / 2048 MB / 20 GB.
  - Backends and client: 1 vCPU / 1024 MB / 10 GB.
- Portal objects are created **by Gabriel**. When a task needs one, stop and give him exact field values, then wait.
- `sudo` commands on the host are run or approved by Gabriel. Show the exact command first.
- Do not create the GitHub repo or push until Gabriel explicitly confirms (Task 14).
- Commit after each verified task. Commit messages end with `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.

## Review Focus

1. **HAProxy on a node that does not hold the VIP.** A reboot of the BACKUP node must leave HAProxy `active (running)`, which needs `net.ipv4.ip_nonlocal_bind=1`. This is tested in Task 7.
2. **Split-brain.** If VRRP adverts are blocked (for example by ufw or nftables on a node), both nodes take the VIP. After every scenario, `tools/vip-owner.sh` must report exactly one owner. This is tested in Tasks 7 and 10.
3. **Real client IP.**
   - The backend must see the client VM IP (`10.90.30.10`) in `X-Forwarded-For`.
   - Infinity Portal logs must show `10.90.30.10`, not a node IP.
   - This is tested in Tasks 6 and 8.
4. **Clock skew on VMs.** It breaks agent registration and TLS validity. Each VM must show `System clock synchronized: yes`. This is tested in Task 2.
5. **Secret leakage into the public repo.** This covers probe logs, configs rendered with tokens, and certificates. `check-secrets.sh` must catch a planted token, a PEM private key and a `.env` file. This is tested in Task 0.

---

### Task 0: Repository scaffold and secret guard

**Files:**
- Create: `README.md` (skeleton: title, disclaimer, chapter index placeholders), `LICENSE` (MIT, `Copyright (c) 2026 Gabriel Díaz`), `.gitignore`, `.env.example`, `tools/check-secrets.sh`, `tools/install-hooks.sh`, `tests/test_check_secrets.sh`

**Interfaces:**
- Produces:
  - `tools/check-secrets.sh [paths...]`: exit 0 when clean, exit 1 when a finding exists, printing `file:line:rule`. With no arguments it scans the staged files.
  - `.env` keys used later: `WAF_TOKEN` (agent registration token), `LAB_SSH_KEY` (path).

- [ ] **Step 1:** `git init`. `.gitignore` must contain `.env`, `certs/`, `*.key`, `*.pem`, `*.p12`, `*.qcow2`, `*.img`, `*.iso`, `tests/results/**/raw/`.
- [ ] **Step 2: Write the failing test** `tests/test_check_secrets.sh`. It creates a temp dir with three files and asserts that `check-secrets.sh` exits 1 for each and 0 for a clean file:
  - `cp-<64 hex chars>`, which mimics a token,
  - `-----BEGIN PRIVATE KEY-----`,
  - a file named `.env`.
- [ ] **Step 3:** Run `bash tests/test_check_secrets.sh`. Expected: FAIL (script missing).
- [ ] **Step 4:** Implement `tools/check-secrets.sh`. Rules:
  - PEM private key headers,
  - `WAF_TOKEN=` followed by a non-placeholder value,
  - the token-like regex `\bcp-[A-Za-z0-9]{32,}\b`,
  - any file named `.env`,
  - the forbidden-word list read from `tools/forbidden-words.txt`. That file is git-ignored and lists customer names, so the list itself never ships.

  Also implement `tools/install-hooks.sh`, which installs a pre-commit hook that calls the checker.
- [ ] **Step 5:** Run the test. Expected: PASS. Run `tools/install-hooks.sh`.
- [ ] **Step 6:** README skeleton with the disclaimer: *"Community lab guide. Not official Check Point documentation and not supported by Check Point."*
- [ ] **Step 7:** Commit, including the design and plan docs.

### Task 1: Lab host — libvirt and networks

**Files:**
- Create: `lab/net-waflab.xml`, `lab/net-wafout.xml`, `docs/01-lab-host.md`

**Interfaces:**
- Produces: active libvirt networks `waflab` (NAT, bridge `virbr-waf`) and `wafout` (route, bridge `virbr-out`).

- [ ] **Step 1:** Give Gabriel the commands to run with sudo:
  - `sudo apt install -y qemu-kvm libvirt-daemon-system virtinst cloud-image-utils`
  - `sudo usermod -aG libvirt "$USER"`

  Also tell him a re-login (or `newgrp libvirt`) is needed.
- [ ] **Step 2:** Define and autostart both networks with `virsh -c qemu:///system net-define/net-start/net-autostart`.
- [ ] **Step 3: Verify.** `virsh net-list` shows both networks active. `ip -br a show virbr-waf` shows `10.90.20.1/24`. Record the libvirt version and the firewall backend (`/etc/libvirt/network.conf`, `firewall_backend`), because Task 8 depends on it.
- [ ] **Step 4:** Write `docs/01-lab-host.md` from what was actually run, then commit.

### Task 2: VM factory (cloud-init) and base VMs

**Files:**
- Create: `lab/cloud-init/user-data.tmpl`, `lab/cloud-init/network-config.tmpl`, `lab/create-vm.sh`, `lab/destroy-vm.sh`, `lab/lab-up.sh`, `lab/lab-down.sh`, `lab/inventory.env`, `docs/02-vms.md`

**Interfaces:**
- Produces:
  - `lab/create-vm.sh <name> <network> <ip/cidr> <gw> <vcpu> <ram_mb> <disk_gb>`, which is idempotent and exits 0 if the VM already exists.
  - `lab/inventory.env` defines `NODE1_IP`, `NODE2_IP`, `NODE3_IP`, `BACKEND1_IP`, `BACKEND2_IP`, `VIP`, `CLIENT_IP`, `GW_WAF`, `GW_OUT`.
  - SSH as user `lab` with the key from `LAB_SSH_KEY`.
  - Hostnames: `waf-node1`, `waf-node2`, `waf-node3`, `backend1`, `backend2`, `client`.

- [ ] **Step 1:** Download the Ubuntu 24.04 cloud image to `~/.cache/waflab/` (outside the repo). Write the templates:
  - static IP,
  - chrony enabled,
  - `qemu-guest-agent`,
  - ssh key,
  - no password login.
- [ ] **Step 2:** Implement `create-vm.sh`: qcow2 overlay, seed ISO from the templates with `cloud-localds`, then `virt-install --import --os-variant ubuntu24.04 --noautoconsole`.
- [ ] **Step 3:** `lab-up.sh` creates `backend1`, `backend2`, `waf-node1`, `waf-node2` and `client`. node3 is created only in Task 11.
- [ ] **Step 4: Verify** for each VM:
  - `ssh lab@<ip> hostname` returns the right name,
  - `curl -sI https://portal.checkpoint.com` succeeds from the waflab VMs,
  - `timedatectl | grep 'synchronized: yes'` matches (Review Focus 4).
- [ ] **Step 5:** Write `docs/02-vms.md` with the lab part only. The vSphere part comes in Task 13. Commit.

### Task 3: Lab CA, backend certificates and the two backends

**Files:**
- Create: `lab/certs/make-ca.sh`, `lab/certs/issue-cert.sh`, `configs/backend/echo.conf.tmpl`, `lab/deploy-backend.sh`, `docs/03-backend.md`

**Interfaces:**
- Produces:
  - `lab/certs/make-ca.sh` writes `certs/ca/ca.crt` and `ca.key`.
  - `lab/certs/issue-cert.sh <cn> <san,...> <outdir> [days]` writes `<outdir>/<cn>.crt`, `.key` and `.pem` (crt+key, the format HAProxy needs).
  - Backend JSON contract (Task 9's probe relies on these exact keys): `{"app","backend","client_addr","xff","host"}`.
    - `client_addr` is NGINX `$remote_addr`, which is the agent node IP that forwarded the request.

- [ ] **Step 1:** Implement both cert scripts with RSA 2048, SHA-256, and `subjectAltName` set from the SAN list. Issue `backend1.waflab.internal` (SAN IP `10.90.20.5`) and `backend2.waflab.internal` (SAN IP `10.90.20.6`).
- [ ] **Step 2:** NGINX server listening on `443 ssl`, returning the JSON above with `default_type application/json`.
  - `app` is `app1` on backend1 and `app2` on backend2.
  - Also expose `/healthz`, which returns 200 `ok`.
- [ ] **Step 3: Verify.** From the host, `curl --cacert certs/ca/ca.crt https://10.90.20.5/` returns JSON with `"app":"app1"`, and the same for `.6` and app2.
- [ ] **Step 4:** Write the doc and commit. The cert scripts are committed; `certs/` is not.

### Task 4: Infinity Portal objects (manual, Gabriel)

**Files:**
- Create: `docs/04-infinity-portal.md`

**Interfaces:**
- Consumes: FQDNs, backend IPs and the lab CA from Task 3.
- Produces: `WAF_TOKEN` in `.env`, plus the asset names `waflab-app1` and `waflab-app2` (used in the docs).

- [ ] **Step 1:** Read the current official docs for the Linux deployment (`https://waf-doc.inext.checkpoint.com/getting-started/deploy-enforcement-point/linux` and its sub-pages) and decide the profile type. The expected type is Linux/embedded NGINX, in which case the local NGINX config is ours, which resolves design open point 1(a). Record the decision and the source URL in the doc.
- [ ] **Step 2:** Give Gabriel exact instructions and **wait**:
  - one profile for all WAF nodes,
  - assets `waflab-app1` (URL `https://app1.waflab.example`, upstream `https://10.90.20.5`) and `waflab-app2` (URL `https://app2.waflab.example`, upstream `https://10.90.20.6`),
  - practice in **Prevent** mode,
  - source identifier `X-Forwarded-For` with trusted sources `10.90.20.11`, `.12` and `.13`,
  - enforce.
- [ ] **Step 3:** Gabriel pastes the token into `.env` himself (never in chat if avoidable). Verify with `grep -c '^WAF_TOKEN=.\+' .env` returning `1`.
- [ ] **Step 4:** Write the doc with field values, no tenant identifiers, and screenshots only if Gabriel provides them. Commit.

### Task 5: Agent on node1 and node2, and the port collision

**Files:**
- Create: `lab/deploy-agent.sh`, `configs/agent/nginx-waf.conf.tmpl` (if the profile is embedded NGINX), `docs/05-agent.md`

**Interfaces:**
- Consumes: `WAF_TOKEN`, the backend contract.
- Produces: the agent listener `AGENT_PORT`, written into `lab/inventory.env`. The preferred value is `8443`. Each agent serves both FQDNs over TLS on `<node_ip>:AGENT_PORT`.

- [ ] **Step 1:** Install the agent on node1 following the official procedure from Task 4. The token is read from `.env` and passed over ssh, never written into the repo.
- [ ] **Step 2:** Make the agent listen on `AGENT_PORT` and not on 443. If 8443 is impossible, use design fallback (b), then (c). Document what was tried and why it failed.
- [ ] **Step 3: Verify on node1.** `curl --cacert certs/ca/ca.crt --resolve app1.waflab.example:8443:10.90.20.11 https://app1.waflab.example:8443/` returns app1 JSON.
  - Repeat for app2.
  - `.../?q=<script>alert(1)</script>` (URL-encoded) is blocked with HTTP 403 or the Check Point block page.
  - Ask Gabriel to confirm the block appears in the portal logs.
- [ ] **Step 4:** Repeat on node2. Verify that node2 also appears as an agent in the portal with status OK.
- [ ] **Step 5:** Doc and commit. Write down the cert question (agent's own server cert for re-encryption) as resolved by what was done; Task 12 expands on it.

### Task 6: HAProxy on each node

**Files:**
- Create: `configs/haproxy/haproxy.cfg.tmpl`, `configs/haproxy/crt-list.txt`, `configs/sysctl/99-waflab.conf`, `lab/render.sh`, `lab/deploy-haproxy.sh`, `docs/06-haproxy.md`

**Interfaces:**
- Consumes: `AGENT_PORT`, `inventory.env`, app certs from `issue-cert.sh`.
- Produces:
  - `lab/render.sh <template> <node>` renders a template from `inventory.env` plus `WAF_NODES` (a space-separated list of `name:ip`). That list is the single place node3 gets added.
  - Every response carries the header `X-Served-By: <haproxy node>/<server name>`.

- [ ] **Step 1:** Issue `app1.waflab.example` and `app2.waflab.example` certs, 825 days, into `certs/apps/`.
- [ ] **Step 2:** Template:
  - `bind *:443 ssl crt-list /etc/haproxy/crt-list.txt alpn h2,http/1.1`,
  - `ssl-min-ver TLSv1.2`,
  - an `:80` redirect,
  - `option forwardfor`,
  - `X-Forwarded-Proto https`,
  - `use_backend be_app1 if { req.hdr(host),field(1,:) -i app1.waflab.example }`, and the same for app2,
  - a default backend returning 404.

  Each `be_appN` has:
  - `balance leastconn`, `retries 3`, `option redispatch`,
  - `http-check send meth GET uri /healthz ver HTTP/1.1 hdr Host appN.waflab.example`, `http-check expect status 200`,
  - `default-server check inter 3s fall 3 rise 2 slowstart 30s ssl verify required ca-file /etc/haproxy/ca.crt sni str(appN.waflab.example) observe layer7 error-limit 10 on-error mark-down`,
  - one `server` line per entry in `WAF_NODES`.

  Stats go on `<node_ip>:8404` with credentials read from `.env` (`HAPROXY_STATS_PASS`).
- [ ] **Step 3:** Deploy to node1 and node2, with sysctl `net.ipv4.ip_nonlocal_bind=1`. Check with `haproxy -c -f` before every reload.
- [ ] **Step 4: Verify.**
  - `curl --resolve app1.waflab.example:443:10.90.20.11` returns app1 JSON.
  - 20 requests show `client_addr` alternating between `.11` and `.12`.
  - The same works for app2.
  - Stats show 4/4 servers UP.
  - `xff` contains the requester IP.
- [ ] **Step 5:** Doc (explaining each directive) and commit.

### Task 7: keepalived and the VIP

**Files:**
- Create: `configs/keepalived/keepalived.conf.tmpl`, `configs/keepalived/chk_haproxy.sh`, `tools/vip-owner.sh`, `lab/deploy-keepalived.sh`, `docs/07-keepalived.md`

**Interfaces:**
- Produces:
  - `tools/vip-owner.sh` prints the hostnames that hold the VIP, one per line. Exit 0 if exactly one, exit 2 if none or more than one.
  - Config: `vrrp_instance VI_WAF`, `virtual_router_id 51`, `advert_int 1`, every node `state BACKUP` and `nopreempt`, priorities node1 `110` / node2 `100` / node3 `90`, `unicast_peer` from `WAF_NODES`.
  - `chk_haproxy.sh` succeeds only if `curl -sk -o /dev/null -w '%{http_code}' --resolve app1.waflab.example:443:127.0.0.1 https://app1.waflab.example/healthz` returns any HTTP code other than `000`. In other words, HAProxy is answering.
  - `vrrp_script` uses `interval 2 fall 2 rise 2 weight -30`.

- [ ] **Step 1:** Deploy to node1 and node2. Start node1 first.
- [ ] **Step 2: Verify.**
  - `tools/vip-owner.sh` prints `waf-node1` and exits 0.
  - `curl --resolve app1.waflab.example:443:10.90.20.100` returns app1 JSON.
- [ ] **Step 3: Verify Review Focus 1.** Reboot node2 while node1 holds the VIP. After boot, `systemctl is-active haproxy` on node2 returns `active`.
- [ ] **Step 4: Verify Review Focus 2.** Temporarily block VRRP (protocol 112) on node2 with nftables. Show that `vip-owner.sh` exits 2 (split-brain), then remove the block and show it exits 0 again. Document this as a warning in the guide.
- [ ] **Step 5:** Doc and commit.

### Task 8: Simulated perimeter firewall (host DNAT) and the Check Point equivalent

**Files:**
- Create: `lab/host-fw.sh` (`up|down|status`), `docs/08-firewall-dnat.md`

**Interfaces:**
- Produces:
  - The client VM reaches `https://appN.waflab.example` through `10.90.30.1:443`, which is DNAT'd to `10.90.20.100:443` with **no SNAT**.
  - On the host LAN, `192.168.1.20:443` is DNAT'd to the VIP as a convenience.

- [ ] **Step 1:** Implement the DNAT rules plus a forward-accept rule ahead of libvirt's own chains. libvirt's NAT network rejects new inbound connections by default, so the rule must match the backend recorded in Task 1. On the client VM, `/etc/hosts` maps both FQDNs to `10.90.30.1`. Copy the lab CA to the client.
- [ ] **Step 2: Verify.**
  - From the client, `curl --cacert ca.crt https://app1.waflab.example/` returns JSON with `xff` = `10.90.30.10`.
  - The same works for app2.
  - Gabriel confirms the portal log for an attack from the client shows source `10.90.30.10` (Review Focus 3).
- [ ] **Step 3:** Doc. The lab part is executed. The Check Point section (an access rule plus a static NAT/manual NAT, original destination = public IP, translated destination = VIP, no hide NAT on the source) carries the **Not validated in this lab** banner. Commit.

### Task 9: Probe and summary tooling

**Files:**
- Create: `tests/probe.py`, `tests/summarize.py`, `tests/test_summarize.py`, `tests/fixtures/sample-probe.csv`, `lab/run-scenario.sh`

**Interfaces:**
- Produces:
  - `probe.py --url <url> --cacert <file> --interval 0.2 --out <csv> [--duration S]`. CSV columns are `ts_iso,app,status,latency_ms,served_by,agent,error`:
    - `agent` is the backend JSON `client_addr`,
    - `status` is `0` on connection error.
  - `summarize.py <csv>...` prints, per app:
    - `total`, `failed`, `max_gap_s` (the longest interval between consecutive successful 2xx responses),
    - `per_agent` counts for three windows: before the first failure, during, and after the last failure.

    `--json` gives the same data machine-readable.
  - `lab/run-scenario.sh <id> <inject_cmd> <restore_cmd> [settle_s]`:
    1. starts one probe per app on the client,
    2. waits 10 s,
    3. runs inject, waits `settle_s` (default 30), runs restore, waits 40 s,
    4. stops the probes,
    5. copies the CSVs to `tests/results/<id>/raw/`, writes `tests/results/<id>/summary.md`, and checks `vip-owner.sh`.

- [ ] **Step 1: Write failing tests** in `tests/test_summarize.py` using the fixture:
  - `test_counts`: total 50, failed 5.
  - `test_max_gap`: a gap of 2.4 s computed from success timestamps.
  - `test_per_agent_windows`: before `{.11:10,.12:10}`, during `{.11:5}`.
  - `test_all_failed_app`: `max_gap_s` equals the window length, and there is no crash on zero successes.
- [ ] **Step 2:** Run `pytest tests/test_summarize.py -v`. Expected: FAIL.
- [ ] **Step 3:** Implement `summarize.py` (stdlib csv and datetime only) and `probe.py` (stdlib `urllib` + `ssl`, 2 s timeout, never crashes on errors).
- [ ] **Step 4:** Run pytest. Expected: PASS. Smoke test: a 20 s probe from the client gives `failed 0` for both apps.
- [ ] **Step 5:** Commit. Raw results are git-ignored. Summaries are committed after `check-secrets.sh`.

### Task 10: Failover scenarios 1–9

**Files:**
- Create: `tests/scenarios/s01-agent2-stop.sh` … `s09-failback-nopreempt.sh`, `tests/results/sNN/summary.md`, `docs/09-failover-tests.md`

**Interfaces:**
- Consumes: `run-scenario.sh` and `vip-owner.sh`. Each scenario script only defines inject and restore and calls `run-scenario.sh`.

| ID | Inject | Restore | Pass condition |
|---|---|---|---|
| s01 | stop agent service on node2 | start it | both apps: `failed` ≤ the requests in flight; after restore, node2 serves again |
| s02 | `virsh destroy waf-node2` | `virsh start` | same as s01; VIP owner stays node1 |
| s03 | `virsh destroy waf-node1` | `virsh start` | VIP owner = node2 within 5 s; `max_gap_s` recorded |
| s04 | `kill -STOP` HAProxy master+workers on node1 | `kill -CONT` | VIP moves to node2; agent `.11` still in `per_agent` during the window |
| s05 | make agent2 return 5xx (method chosen at build time and documented, e.g. a local NGINX `return 503` for `/healthz`) | revert | node2 removed from rotation; error count recorded |
| s06 | (follows s01) | — | node2's share ramps up over about 30 s (slowstart), shown with per-10 s counts |
| s07 | put agent2 into fail-open, or simulate it (documented; if not reproducible, collect evidence of what HAProxy sees vs the portal agent status) | revert | doc states clearly whether HAProxy detects it |
| s08 | stop NGINX on backend1 | start | app1 returns 503 for the window; **app2 `failed` = 0** |
| s09 | after s03 restore | — | VIP stays on node2 (`nopreempt`); doc shows how to fail back on purpose |

- [ ] **Step 1:** Write and run the scenarios one by one. After each: `vip-owner.sh` exits 0 and the results summary is produced.
- [ ] **Step 2:** For any pass condition that fails, use superpowers:systematic-debugging. Fix the config, rerun, and document both the failure and the fix.
- [ ] **Step 3:** Write `docs/09-failover-tests.md`: per scenario, what was done, the commands, the measured summary, and the conclusion. End with a results table. Commit.

### Task 11: Scale-out to node3

**Files:**
- Modify: `lab/inventory.env` (`WAF_NODES`). Create: `docs/10-scale-out.md`, `tests/results/s10-scale-out/summary.md`

- [ ] **Step 1:** Start the probes (run-scenario style, long settle).
- [ ] **Step 2:**
  1. Create `waf-node3`.
  2. Install the agent with the same token.
  3. Add it to `WAF_NODES`.
  4. Re-render and **reload** HAProxy and keepalived on node1 and node2 (reload, never restart, and node1 last).
  5. Deploy HAProxy and keepalived on node3.
- [ ] **Step 3: Verify.**
  - Both apps report `failed` = 0 during the whole procedure, or any failure is explained.
  - After about 60 s, `per_agent` includes `.13`.
  - `vip-owner.sh` exits 0.
  - The portal shows 3 agents.
- [ ] **Step 4:** Doc as an ordered runbook, plus a removal procedure (drain with `set server ... state drain` via the runtime API, then remove), which is also executed. Commit.

### Task 12: Certificate management

**Files:**
- Create: `tools/check-cert-expiry.sh`, `lab/rotate-app-cert.sh`, `docs/11-certificates.md`, `tests/results/s11-cert-rotation/summary.md`

**Interfaces:**
- Produces:
  - `tools/check-cert-expiry.sh <host:port> <sni> [warn_days=30]` prints the notAfter date and days left. Exit 1 if below the threshold.
  - `lab/rotate-app-cert.sh <appN>` issues a new cert, pushes it to every node in `WAF_NODES`, runs `haproxy -c`, then `systemctl reload haproxy` node by node.

- [ ] **Step 1:** Document the certificate map: client→HAProxy (app certs), HAProxy→agent (agent cert, verified against the CA), agent→backend (backend certs), and where each one lives and is managed (local file or portal).
- [ ] **Step 2:** Rotate the app1 cert while probes run. Verify:
  - `failed` = 0 for both apps,
  - the new serial is served on all nodes (`openssl s_client -connect <node>:443 -servername app1...`),
  - app2's serial is unchanged.
- [ ] **Step 3:** Run `check-cert-expiry.sh` against the VIP for both apps, and against one node with a short-lived (1-day) test cert to show the warning path.
- [ ] **Step 4:** Doc, including a section on public CA / internal PKI / ACME. That section is reference-only for anything not executed and carries the banner. Commit.

### Task 13: vSphere chapter

**Files:**
- Create: `docs/12-vsphere.md`. Modify: `docs/02-vms.md` (link)

- [ ] **Step 1:** Write the mapping table and procedures, with the **Not validated in this lab** banner:
  - template and clone with cloud-init or guest customization,
  - port group,
  - port group security (Promiscuous, MAC changes and Forged transmits not needed without `use_vmac`, plus why),
  - DRS VM-VM anti-affinity rule,
  - VMware Tools / open-vm-tools,
  - NTP,
  - snapshots before upgrades.

  Cross-check every vSphere claim against VMware docs and cite the URLs.
- [ ] **Step 2:** Commit.

### Task 14: Final docs, diagram, publish

**Files:**
- Create: `docs/13-troubleshooting.md`, `docs/img/architecture.png`, `docs/img/architecture.excalidraw`. Modify: `README.md`

- [ ] **Step 1:** Regenerate the architecture and failure-scenario diagram (excalidraw skill) with lab IPs, both apps and no customer reference. Export a PNG.
- [ ] **Step 2:** The troubleshooting chapter collects every problem actually hit during the build. The README gets the overview, diagram, prerequisites, a quick start (`lab-up.sh` → chapters in order), the results table from Task 10, the chapter index and the disclaimer.
- [ ] **Step 3:** Full-repo checks:
  - `tools/check-secrets.sh $(git ls-files)` is clean,
  - `git log -p | grep -iE 'BEGIN .*PRIVATE|WAF_TOKEN=[^<]'` is empty,
  - a forbidden-words scan over the full history is empty.
- [ ] **Step 4:** Ask Gabriel for explicit confirmation to publish. Only then run `gh repo create gdiaz777/cgwaf-onprem-ha-lab --public --source . --push --description "..."` and give him the URL.
