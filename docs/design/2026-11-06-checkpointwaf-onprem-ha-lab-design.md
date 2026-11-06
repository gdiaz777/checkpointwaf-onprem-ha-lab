# Design: Check Point WAF on-prem HA lab without a load balancer

Date: 2026-11-06
Status: draft, pending approval (builder check done; answers incorporated)

## 1. Intent

Many Check Point WAF on-prem customers have:

- a Check Point firewall cluster in front of their web apps,
- a virtualization platform (typically VMware vSphere),
- **no load balancer**,
- and a need for **more than one WAF agent**, for availability and capacity.

Check Point WAF has no built-in HA between agents. This project builds, tests and documents an architecture that solves this without dedicated load balancers. Every node is a VM that runs three things:

- **HAProxy**, which distributes traffic to all agents and health-checks them,
- **keepalived**, which keeps one floating VIP (VRRP) alive across the nodes,
- the **Check Point WAF agent**, which does the inspection.

The firewall DNATs the published IP to the VIP. Adding capacity means adding another identical node.

The deliverable is a **public GitHub repository** (`gdiaz777/checkpointwaf-onprem-ha-lab`, written in English). It holds a step-by-step guide that a customer engineer can follow on vSphere, plus every config file and helper script used. The guide is written from a real lab built on a single Ubuntu host with KVM. **Every step in the guide has actually been executed, and every claimed behaviour has been observed and measured.**

The guide must be generic. It must not reference any specific customer.

## 2. Goals

1. Build the lab end to end on this host (Ubuntu 24.04, KVM):
   - 2 WAF nodes,
   - **2 published applications**, each with its own FQDN, certificate, Infinity Portal asset and backend VM,
   - a simulated perimeter firewall (DNAT on the host).
2. Register the agents in the Infinity Portal tenant (Gabriel's test tenant) and get real traffic inspected **for both apps**. That includes one attack blocked per app and a log showing the real client IP.
   - HAProxy routes by SNI/Host to a per-app backend pool. The pool contains the same agents but has a per-app health check, so one app's failure never takes the agents out of rotation for the other app.
3. Run and document these **failure scenarios**, with a measured client-side impact for each:
   1. Agent on node 2 stopped (node 2 VM still up).
   2. Node 2 VM powered off.
   3. Node 1 VM (VIP holder) powered off. The VIP must move to node 2.
   4. HAProxy on node 1 hung or stopped. The VIP must move, and agent 1 must keep serving traffic.
   5. Agent 2 answering 5xx. If this cannot be forced reliably, the guide explains how it was simulated.
   6. Agent 2 recovers: it rejoins with slowstart.
   7. Agent in fail-open. We demonstrate, or explain with evidence, that HAProxy does not detect it, and show where it is detected (Infinity Portal agent status).
   8. Backend of app1 down: in the app1 pool all agents are marked DOWN and app1 clients get a 503. **App2 must be unaffected.** This is the per-app isolation test. Whatever actually happens is recorded.
   9. Failback behaviour with `nopreempt`: when node 1 returns, the VIP stays on node 2.
4. **Scale-out**: add node 3 to the running cluster with no client-visible outage, following a documented procedure.
5. **Certificate management**, documented and tested:
   - lab CA and **one server certificate per app** (SNI selection on HAProxy),
   - where each certificate lives: HAProxy front end, agent reverse proxy, backend,
   - **certificate rotation with no outage** across all nodes, rotating one app's certificate without touching the other,
   - expiry checks,
   - what changes when the customer uses a public CA or an internal PKI.
6. A **vSphere mapping** section: what is different on vSphere and what is identical. This covers templates and clones, port groups, port group security settings for VRRP, DRS anti-affinity, the firewall DNAT on Check Point, and time sync.
   - **Neither vSphere nor a Check Point gateway is available.** Content that could not be executed (the vSphere chapter and the Check Point NAT rule) is written as reference material and clearly labelled **"Not validated in this lab"** at the top of each such section. This is the only exception to anti-goal 3, and it must always be visible.
7. Reusable artifacts: config templates, cloud-init, lab bring-up and teardown scripts, and a traffic probe script that measures outages.

## 3. Non-goals

- A real Check Point firewall in the lab. The host's nftables/iptables DNAT stands in for it, and the guide shows the equivalent Check Point NAT rule.
- Kubernetes, Docker-based agents, or any other alternative architecture. They may get a short "alternatives" note at most.
- Automating Infinity Portal configuration. Portal steps are done by hand by Gabriel and documented with exact field values. Screenshots are optional.
- Production-grade hardening beyond sensible defaults (TLS ≥ 1.2, stats bound to the management IP, no default passwords in the repo).
- Performance or throughput benchmarking.
- Distributions other than Ubuntu 24.04. The guide can note where RHEL would differ, but the lab does not test it.

## 4. Anti-goals (failure even if it "works")

- **Any secret in the public repo**: agent tokens, private keys, lab certificates, portal identifiers tied to the tenant, passwords. Secrets live in a git-ignored `.env` and a git-ignored `certs/` directory, and a pre-commit check (or a manual grep step before each push) guards this.
- **Any reference to a customer**: names, IPs, diagrams copied from customer material.
- **Steps written from memory that were not executed.** If a step differs from what actually ran, the guide is wrong.
- **Claimed failover times that were not measured.** Every scenario reports the probe output.
- **A guide that only works on KVM.** Everything inside the VMs must apply unchanged to vSphere. Anything KVM-specific is isolated in the lab-setup chapter.

## 5. Constraints

- Host: Ubuntu 24.04.4, 12 vCPU, 31 GB RAM, 366 GB free disk, `/dev/kvm` available, user in `kvm` and `docker` groups. The Windows container is stopped during the lab.
- libvirt/QEMU are not installed. Installing them needs `sudo`, which Gabriel runs or approves.
- VMs need **outbound Internet** (agent registration with the Infinity Portal and package installs). That means a NAT-ed libvirt network.
- Infinity Portal: Gabriel's test tenant. Any portal object (profile, asset, token, certificate upload) is created by Gabriel when asked. The builder gives exact instructions.
- Host LAN IP: `192.168.1.20`. Port 443 on the host is free.

## 6. Decisions already made

| Topic | Decision |
|---|---|
| Lab platform | KVM/libvirt VMs on this host (`virt-install` + cloud-init) |
| Guest OS | Ubuntu Server 24.04 LTS cloud image |
| Agent | Check Point WAF **Linux** installer inside each VM (reverse-proxy mode), not Docker |
| Load balancing | HAProxy (Ubuntu package) on every node, identical config on all nodes |
| VIP / failover | keepalived, VRRP unicast, `nopreempt`, health-tracking script for HAProxy |
| Language / visibility | English, public GitHub repo `gdiaz777/checkpointwaf-onprem-ha-lab` |
| License / framing | MIT license. The README carries a disclaimer: community lab guide, not official Check Point documentation, not supported by Check Point |
| Published apps | Two: `app1.waflab.example` and `app2.waflab.example`, each with its own asset, certificate and backend VM |
| Not executable here | vSphere and Check Point NAT content, labelled "Not validated in this lab" |
| Local path | `` |

## 7. Lab topology (builder's call, adjustable)

```
 test client (host) ──► host 192.168.1.20:443 ──DNAT──► VIP 10.90.20.100:443
                                                        │ (keepalived MASTER)
            ┌───────────────────────────┬───────────────┴───────────┐
       waf-node1 10.90.20.11       waf-node2 10.90.20.12       waf-node3 10.90.20.13 (scale-out)
       HAProxy :443 (VIP)          HAProxy (standby)           HAProxy (standby)
       keepalived                  keepalived                  keepalived
       Check Point WAF agent :<agent port>  Check Point WAF agent                Check Point WAF agent
            └───────────────────────────┴───────────────────────────┘
                          │ HTTPS (asset app1)              │ HTTPS (asset app2)
                backend1 10.90.20.5:443           backend2 10.90.20.6:443
                (NGINX; echoes X-Forwarded-For and which agent forwarded the request)
```

- HAProxy front end: one `bind :443` with both certificates (SNI). Requests are routed by Host to `be_app1` or `be_app2`. Both pools list the same agents. Each pool health-checks the agents with its own Host header, so the check goes end to end to that app's backend. *(Builder's call; it resolves open point 4. The trade-off and the agent-only alternative are documented.)*

- libvirt network `waflab`: NAT mode, `10.90.20.0/24`, gateway `.1`, DHCP reservations or static IPs via cloud-init.
- Sizing: WAF nodes 2 vCPU / 2 GB / 20 GB disk. Backend 1 vCPU / 1 GB.
- Lab FQDNs: `app1.waflab.example` and `app2.waflab.example` (RFC 2606 reserved names), resolved through `/etc/hosts` on the test client.
- Backend VMs: 1 vCPU / 1 GB each. Total lab RAM with 3 WAF nodes is about 8 GB.

## 8. Known open technical points (resolved during the build and documented)

1. **Port collision between HAProxy and the agent.** Both want 443. The candidate solutions, in order of preference:
   - (a) move the agent's listener to another port (e.g. 8443) if the portal or agent allows it,
   - (b) bind HAProxy to the VIP only and the agent to the node IP only,
   - (c) run the agent on 443 of the node IP and HAProxy on the VIP with `ip_nonlocal_bind`.

   The guide documents whichever works and why the others didn't.
2. **Source IP.** XFF from HAProxy must be trusted by the agent (asset source-identifier settings). This is validated by checking that the portal logs show the test client's IP, not the node IP.
3. **TLS between HAProxy and the agent.** The default is to re-encrypt. Whether the agent needs its own certificate (uploaded to the portal, or local) is resolved in the certificate chapter.
4. **Health-check target.** HAProxy checks the agent with an HTTP request carrying the asset's Host header. Whether the check should traverse to the backend (scenario 8) or stop at the agent is documented with its trade-off.
5. **Rate limiting per agent.** Optional: check whether counters are local to each agent, and document the implication for the balancing algorithm.

## 9. Testing method

- `probe.sh` (or Python) runs on the host. It sends one HTTPS request every 100–200 ms through the DNAT path and logs, per request:
  - timestamp,
  - HTTP status,
  - latency,
  - which node handled it (backend echoes a header the agent forwards, or HAProxy adds `X-Served-By`).
- Each scenario follows the same sequence: start the probe, inject the failure, wait, restore, stop the probe. A summary script reports:
  - number of failed requests,
  - the longest gap with no successful response,
  - the distribution across nodes before, during and after.
- Raw probe logs are stored per scenario under `tests/results/` (no secrets in them). The guide quotes the summaries.
- Failure injection is done with plain commands, documented per scenario:
  - `systemctl stop <agent service>`,
  - `virsh destroy`,
  - `kill -STOP` on HAProxy,
  - `iptables` drop, etc.

## 10. Repository layout (builder's call, adjustable)

```
checkpointwaf-onprem-ha-lab/
├── README.md                    architecture, diagram, quick start, chapter index
├── docs/
│   ├── 01-lab-host.md           KVM/libvirt setup (lab only)
│   ├── 02-vms.md                creating the VMs (cloud-init) + vSphere equivalent
│   ├── 03-backend.md
│   ├── 04-infinity-portal.md    profile, asset, token, XFF trust, certificate
│   ├── 05-agent.md
│   ├── 06-haproxy.md
│   ├── 07-keepalived.md
│   ├── 08-firewall-dnat.md      host DNAT + Check Point NAT equivalent
│   ├── 09-failover-tests.md     all scenarios with measured results
│   ├── 10-scale-out.md          adding node 3
│   ├── 11-certificates.md       issuance, placement, rotation, expiry
│   ├── 12-vsphere.md            what changes on vSphere
│   ├── 13-troubleshooting.md
│   ├── img/                     diagram exports
│   └── design/                  this document
├── configs/                     haproxy.cfg, keepalived.conf (templated per node), sysctl, nginx backend
├── lab/                         cloud-init, virt-install / teardown scripts, host DNAT script
├── tests/                       probe + summary scripts, results/
├── .env.example                 placeholders only (agent token etc.)
└── .gitignore                   .env, certs/, *.key, *.pem, images
```

## 11. Left to the builder

- Exact IPs, VM names, sizing, and the lab FQDN, within the spirit of section 7.
- Script language (bash or Python) and probe implementation details.
- Order and granularity of chapters. Diagrams (Excalidraw export of the architecture and failure scenarios, regenerated without any customer reference).
- HAProxy/keepalived tuning values, as long as the chosen values are explained.
- Whether to commit incrementally as chapters are validated (preferred), with a final review for secrets before the first push.
- Creating the GitHub repo happens **only after Gabriel confirms** the first push, because it is public.
