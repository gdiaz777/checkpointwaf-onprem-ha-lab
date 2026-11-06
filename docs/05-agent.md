# 5. NGINX and the Check Point WAF agent on each node

Each WAF node runs its own NGINX reverse proxy for both apps, with the Check Point WAF agent attached to it.

```
HAProxy (VIP owner) ──TLS──▶ NGINX <node IP>:443 on this node ──TLS──▶ backend1 / backend2
                              │  ngx_cp_attachment_module
                              ▼
                       Check Point WAF agent (inspection, policy from the portal)
```

## 5.1 Ports: both on 443, different addresses

| Listener | Address | Why |
|---|---|---|
| HAProxy | **VIP:443** (+ `127.0.0.1:443/80` for local checks), bound on every node with `ip_nonlocal_bind` | client traffic arrives on the VIP |
| Agent's NGINX | **`<node IP>:443`** | the agent only applies an asset when the **listening port matches the asset URL** (443), see [chapter 4](04-infinity-portal.md), 4.2 |

With the Linux deployment the NGINX config is yours, so this needs nothing special from the agent. The first version of this lab used 8443 for the agent, and **nothing was inspected**. Do not change the port without also changing the asset URLs.

## 5.2 NGINX site

[`configs/agent/nginx-waf.conf.tmpl`](../configs/agent/nginx-waf.conf.tmpl), rendered per node by [`lab/render.sh`](../lab/render.sh) into `/etc/nginx/conf.d/waf.conf`:

- One `server` per app on `<node IP>:443 ssl`, selected by SNI/Host (`app1.waflab.example`, `app2.waflab.example`). It presents the **app certificate**, the same one HAProxy presents to clients ([chapter 11](11-certificates.md)).
- `proxy_pass https://appN_backend` with **upstream TLS verification** (`proxy_ssl_verify on`, lab CA, `proxy_ssl_name backendN.waflab.internal`).
- `X-Forwarded-For $proxy_add_x_forwarded_for`. The backend then receives `<client IP>, <HAProxy node IP>`, where the first entry is the real client.
- `Host $host`, so the backend and the WAF asset see the public FQDN.

On Ubuntu 24.04 the packaged NGINX is **1.24.0**. Do **not** use the `http2 on;` directive, which needs NGINX 1.25.1 or later. HAProxy talks HTTP/1.1 to the agent anyway.

[`lab/deploy-agent.sh <node>`](../lab/deploy-agent.sh) installs NGINX, uploads the CA and both app certificates, renders the site, runs `nginx -t` and reloads.

Check before installing the agent (plain proxy, no inspection yet):

```bash
bash tests/test_agent_proxy.sh
```

```
PASS waf-node1 app1 proxied
PASS waf-node1 app2 proxied
PASS waf-node2 app1 proxied
PASS waf-node2 app2 proxied
```

## 5.3 Install the agent

The official procedure ([Linux / NGINX](https://waf-doc.inext.checkpoint.com/getting-started/deploy-enforcement-point/linux/nginx)), as root on each node:

```bash
wget https://sc1.checkpoint.com/nanoagent/nanoegg -O nanoegg
chmod +x nanoegg
./nanoegg --install --token <token>
```

`lab/deploy-agent.sh <node> --install-agent` does the same. The token travels on SSH **stdin** and is read inside the root shell, so it is not on the `ssh`/`sudo` command lines and does not reach sudo's log (`/var/log/auth.log`). The installer itself takes the token as an argument, so it **is** visible in the process list while `nanoegg` runs, and it may be kept in the installer's own logs on the node. Treat the token as a secret, and use the portal's rotate action if it leaks: existing agents are not affected.

The installer registers the node and downloads the latest agent. It also adds this line to `/etc/nginx/nginx.conf`:

```
load_module /usr/lib/nginx/modules/ngx_cp_attachment_module.so;
```

The output in the lab (IDs removed):

```
Check Point Nano Agent Version 1.2641.8204142-hotfix-ga-8044694 Install Package
...
Check Point Nano Agent is registered to https://inext-agents.cloud.ngen.checkpoint.com
Check Point Nano Agent successfully installed
Registration status: Succeeded
Name: waf-node1
Type: Embedded
```

After installation the agent downloads its manifest and policy. In the lab this took **about 2.5 minutes**, with one transient `Manifest status: Failed. Reason: Failed to download the file manifest` that recovered by itself. Wait until `Policy version` has a value:

```bash
sudo cpnano -s
```

```
Status: Running
Policy version: 18
Registration status: Succeeded
Manifest status: Succeeded
Upgrade mode: automatic
...
---- Check Point Http Transaction Handler Nano Service ----
Registered Instances: 2          ← NGINX worker processes attached
Status: Running
...
NGINX Attachment version: 1.2640.
```

`Registered Instances` must be greater than 0. It equals the number of NGINX workers that the module has attached to the agent.

Useful agent commands ([agent CLI](https://waf-doc.inext.checkpoint.com/references/agent-cli)):

| Command | Purpose |
|---|---|
| `cpnano -s` / `cpnano -s --extended` | status, versions, policy |
| `cpnano -q` / `cpnano -r` | stop / start the agent functions |
| `cpnano -u` | uninstall |

> **Upgrade mode: automatic.** By default the agents upgrade themselves. In an HA cluster, consider whether you want all nodes upgrading at once. The upgrade settings are in the profile.

## 5.4 Fail-open is the default

The profile pushes these settings to the agent (`/etc/cp/conf/settings.json`):

```
agent.failOpenState.nginxModule = true
agent.asyncMode.nginxModule     = true
```

With **fail-open**, if the agent stops inspecting, NGINX keeps proxying traffic **without inspection**. That favours availability. [Chapter 9](09-failover-tests.md) (scenario 7) shows what this means for HAProxy: the node still looks healthy.

## 5.5 Verify: an attack must be blocked

Switch the assets to **Prevent**, then send an XSS through **every** node's agent. It must return **403**:

```bash
EXPECT_WAF=1 bash tests/test_agent_proxy.sh
```

```
PASS waf-node1 app1 proxied
PASS waf-node1 app1 XSS blocked (403)
PASS waf-node1 app2 proxied
PASS waf-node1 app2 XSS blocked (403)
PASS waf-node2 app1 proxied
PASS waf-node2 app1 XSS blocked (403)
...
PASS waf-node3 app2 XSS blocked (403)
```

**Do not skip this test.** A request that matches no asset is proxied without inspection, and in Detect mode that looks exactly like a working WAF (chapter 4, 4.2).
