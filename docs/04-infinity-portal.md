# 4. Infinity Portal: profile and assets

The agents are managed from the Infinity Portal (CloudGuard WAF). You need **one profile** for all WAF nodes and **one asset per published application**.

## 4.1 Deployment type: Linux (NGINX add-on)

CloudGuard WAF on Linux runs as an **add-on to NGINX**. You install and manage NGINX yourself. Check Point's installer adds a dynamic module (`ngx_cp_attachment_module.so`) that hands every proxied request to the local agent for inspection. Source: [Deploy on Linux / NGINX](https://waf-doc.inext.checkpoint.com/getting-started/deploy-enforcement-point/linux/nginx). The [deployment overview](https://waf-doc.inext.checkpoint.com/getting-started/deploy-enforcement-point) lists this row as *Reverse Proxy: "Provided and managed by Admin"*.

That is what makes this architecture possible on a single VM:

- **You own `nginx.conf`.** The agent's NGINX listens on **the node's own IP, port 443**. HAProxy listens on **the VIP, port 443** (and on 127.0.0.1). Same port, different addresses, so there is no conflict.
- **Server certificates for the agent's NGINX are files you manage** ([chapter 11](11-certificates.md)). They are not uploaded to the portal.

> The other on-prem option, the pre-packaged *WAF Gateway* VM (VMware/OVA), ships its own reverse proxy managed from the portal. You cannot add HAProxy/keepalived to it, so it does not fit this design.

## 4.2 How the agent matches a request to an asset: host **and** listening port

This is the most important detail of the whole design. The agent applies an asset (and therefore inspects and logs) only when the request matches the asset's **host and the port NGINX received it on**. The policy the agent downloads (`/etc/cp/conf/policy.json`) shows it for the lab assets:

```
context = Any(All(Any(EqualHost(app1.waflab.example)), EqualListeningPort(443)))
```

The asset URL `https://app1.waflab.example` implies port 443. In the first version of this lab the agent's NGINX listened on 8443, and the result was:

- **no request matched any asset**, so nothing was inspected (attacks returned 200 even in Prevent mode),
- **no security logs in the portal**. Only agent operational events (for example *"Web AppSec Policy Loaded Successfully"*) appeared, with an empty *Asset Name*,
- in Detect mode this is invisible, because an attack returns 200 either way.

Proof on one node, with the same XSS request:

| NGINX listening on | Result |
|---|---|
| `:443` | **403** (asset matched, Prevent) |
| `:8443` | 200 (no asset, not inspected) |

So **the port NGINX listens on must be the port in the asset URL**, which is why the agent's NGINX uses `<node IP>:443`. If you must use another port, add that port to the asset's URLs (for example `https://app1.example.com:8443`), but it is easy to forget and fails silently. Always validate with an attack in Prevent mode ([chapter 5](05-agent.md), 5.5).

## 4.3 Profile

**Policy → Profiles → New** → profile type **Linux** (NGINX add-on).

| Field | Lab value |
|---|---|
| Name | `waflab-linux` |
| Type | Linux. The agent reports itself as `Type: Embedded` in `cpnano -s` |

1. Click **Enforce** right after creating it. The documentation warns that a new profile must be enforced before its token works.
2. Copy the token from the profile's **Authentication** section.
3. Put it in `.env` (git-ignored), quoted: `CGWAF_TOKEN="…"`. Never put it on a command line or in a file that is committed. `tools/check-secrets.sh` blocks commits that contain it.

**All WAF nodes register with the same token and the same profile**, so they all receive the same policy. Adding a node needs nothing new in the portal ([chapter 10](10-scale-out.md)).

## 4.4 Assets (one per application)

Create a **Web Application** asset for each app:

| Field | `waflab-app1` | `waflab-app2` |
|---|---|---|
| Asset URL | `https://app1.waflab.example` | `https://app2.waflab.example` |
| Application URL for the reverse proxy function | not needed: the upstream is in our NGINX config ([chapter 5](05-agent.md)) | not needed |
| *Note* | the URL's host **and port** must match what the agent's NGINX receives (4.2) | same |
| Profile | `waflab-linux` | `waflab-linux` |
| Practice | Web Application Best Practice | same |
| Mode | **Detect** first, then **Prevent** once the lab works | same |
| Source identity | **X-Forwarded-For Header** | same |
| Trusted sources | `10.90.20.11`, `10.90.20.12`, `10.90.20.13` (the HAProxy nodes) | same |

Then **Publish** and **Enforce**.

Why X-Forwarded-For: every request reaches the agent from a HAProxy node, so the TCP source is always a node IP. HAProxy puts the real client IP in `X-Forwarded-For` ([chapter 6](06-haproxy.md)), and the asset is told to use that header. The trusted sources are the proxies whose header can be believed. The documentation describes this in [Configure contextual machine learning for best accuracy](https://waf-doc.inext.checkpoint.com/how-to/configure-contextual-machine-learning-for-best-accuracy).

> **Detect vs Prevent.** Start in Detect: the agent logs attacks but lets them through, so you can validate the plumbing and tune exceptions without breaking the app. Move to Prevent when ready. The block test in [chapter 5](05-agent.md) needs Prevent.
