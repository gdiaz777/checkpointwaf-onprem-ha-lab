# 11. Certificate management

## 11.1 Where the certificates are

There are three TLS legs. Each one has its own certificate and trust anchor:

```
client ──TLS①──▶ HAProxy (VIP:443) ──TLS②──▶ agent NGINX (node IP:443) ──TLS③──▶ backend :443
          app cert                   app cert                    backend cert
          (public trust)             verified by HAProxy         verified by the agent NGINX
                                     with ca-file + SNI          with proxy_ssl_trusted_certificate + proxy_ssl_name
```

| Leg | Presented by | Files on each WAF node | Verified by | Trust anchor |
|---|---|---|---|---|
| ① client → HAProxy | HAProxy, chosen by SNI ([`crt-list.txt`](../configs/haproxy/crt-list.txt)) | `/etc/haproxy/certs/<fqdn>.pem` (chain + key) | browsers / clients | public CA or the CA your clients trust |
| ② HAProxy → agent | the agent's NGINX, chosen by SNI | `/etc/nginx/tls/<fqdn>.crt` + `.key` | HAProxy: `ssl verify required ca-file /etc/haproxy/ca.crt sni … check-sni …` | `/etc/haproxy/ca.crt` |
| ③ agent → backend | the backend server | (on the backend) | the agent's NGINX: `proxy_ssl_verify on`, `proxy_ssl_name backendN.waflab.internal` | `/etc/nginx/tls/ca.crt` |

Design choices in this lab:

- **One certificate per app, used on legs ① and ②.** It is the simplest option: one file to renew per app, and the agent sees the same name the client asked for. The alternative is a separate internal certificate on leg ② (for example from an internal CA). Then `/etc/haproxy/ca.crt` must contain that CA.
- **Certificates on the agent are local files**, not portal objects: with the Linux (NGINX add-on) deployment the reverse proxy is yours ([chapter 4](04-infinity-portal.md)).
- **The VIP does not matter for certificates.** Every node has every certificate, because any node can become the VIP owner.

> **Trust on leg ② must match what the agents present.** HAProxy verifies the agent's certificate against `/etc/haproxy/ca.crt`. If you deploy app certificates from a **different CA** (for example a public CA) on the agents' NGINX, add that CA's chain to `/etc/haproxy/ca.crt` (or point `ca-file` at the system bundle `/etc/ssl/certs/ca-certificates.crt`) **before** rotating. Otherwise every health check fails and HAProxy marks all agents DOWN. *(Reasoned from the config; the lab only used the lab CA.)*

## 11.2 Issuing (lab CA)

```bash
lab/certs/make-ca.sh                                                     # once
lab/certs/issue-cert.sh app1.waflab.example app1.waflab.example certs/apps    # 825 days by default
```

All private keys stay in `certs/` (git-ignored) on the admin host and in root-only files (`chmod 600`) on the nodes.

## 11.3 Rotation with no outage

[`lab/rotate-app-cert.sh <app1|app2> [--cert file --key file]`](../lab/rotate-app-cert.sh):

1. archives the current certificate (`certs/apps/archive/<fqdn>-<serial>.crt`),
2. **either** issues a new one from the lab CA, **or** takes the certificate/key you provide. It refuses a key that does not match the certificate and a certificate that does not cover the FQDN (`openssl x509 -checkhost`),
3. for **every node in `WAF_NODES`**, writes the HAProxy `.pem` and the NGINX `.crt/.key` with an atomic rename, validates (`haproxy -c`, `nginx -t`) and does a **graceful reload** of both. The old processes finish their connections with the old certificate.

Rotation of app1 while probes ran (`tests/results/s12-cert-rotation/`):

```
INJECT: lab/rotate-app-cert.sh app1
    new certificate: serial=…7DA4BE86 notAfter=Feb  8 01:54:05 2029 GMT
    waf-node1: haproxy + nginx reloaded
    waf-node2: haproxy + nginx reloaded
    waf-node3: haproxy + nginx reloaded
app1: total=229 failed=0 max_gap_s=0.2
app2: total=228 failed=0 max_gap_s=0.2
```

**0 failed requests on either app.** Then [`tests/test_cert_rotation.sh`](../tests/test_cert_rotation.sh) checks that every node presents the current serial on **both TLS layers**: HAProxy (checked from the node on `127.0.0.1:443`) and the agent's NGINX (`<node IP>:443`). It also checks that app2 was not touched:

```
PASS waf-node1 haproxy app1.waflab.example serial …7DA4BE86
PASS waf-node1 agent app1.waflab.example serial …7DA4BE86
...
PASS waf-node3 agent app1.waflab.example serial …7DA4BE86
PASS waf-node1 haproxy app2.waflab.example serial …7DA4BE80      ← unchanged
...
```

The same test fails if a new certificate exists on the admin host but has not been deployed. It is the check to run after any manual change.

**Bringing your own certificate** (public CA, internal PKI). Put the **full chain** (leaf + intermediates) in the `.crt`:

```bash
lab/rotate-app-cert.sh app2 --cert app2.crt --key app2.key
```

Safety checks, verified in the lab. Both abort before any node is touched:

```
lab/rotate-app-cert.sh app1 --cert app2.crt --key app2.key   →  certificate does not cover app1.waflab.example
lab/rotate-app-cert.sh app1 --cert app1.crt --key app2.key   →  key does not match certificate
```

## 11.4 Monitoring expiry

[`tools/check-cert-expiry.sh <host:port> <sni> [warn_days=30]`](../tools/check-cert-expiry.sh) prints the presented certificate and the days left. It exits **0** if OK, **1** if it expires within `warn_days` and **2** if no certificate is presented:

```bash
tools/check-cert-expiry.sh 10.90.20.100:443 app1.waflab.example 30
```

```
OK   10.90.20.100:443 (app1.waflab.example): CN=app1.waflab.example,O=WAF Lab serial=…7DA4BE86 expires Feb  8 01:54:05 2029 GMT (824 days left)
```

Check **each node on both layers**, not only the VIP: HAProxy (`127.0.0.1:443` on the node) and the agent (`<node IP>:443`). A node that missed a rotation only shows up once it becomes VIP owner (leg ①) or in health checks (leg ②). In this lab, `test_cert_rotation.sh` caught exactly that: a node whose HAProxy was stopped during a failed scale-out kept the old certificate. The warning path is covered by [`tests/test_check_cert_expiry.sh`](../tests/test_check_cert_expiry.sh), which uses a 1-day certificate.

## 11.5 Production notes

> **Not validated in this lab.** Guidance for real certificates.

- **Public CA (manual renewal):** get the new certificate, then run `rotate-app-cert.sh <app> --cert --key`. If the CA differs from the one in `/etc/haproxy/ca.crt`, update `ca.crt` on every node first (11.1).
- **Internal PKI:** issue the app certificates or a separate leg-② certificate, put your root/intermediate in `/etc/haproxy/ca.crt` (leg ②) and `/etc/nginx/tls/ca.crt` (leg ③), and distribute it like the lab CA.
- **ACME (Let's Encrypt or an internal ACME CA):** run the client on **one** admin host (not on every node, or each node would request its own certificate), with DNS-01 validation, because HTTP-01 would hit whichever node holds the VIP. Use a deploy hook that calls `rotate-app-cert.sh <app> --cert fullchain.pem --key privkey.pem`. Short lifetimes make the "every node got it" check (`test_cert_rotation.sh`) essential.
- **Backend certificates (leg ③):** renewing a backend certificate does not touch the WAF nodes as long as it is issued by a CA in `/etc/nginx/tls/ca.crt` and keeps the name in `proxy_ssl_name`. Changing CA or name needs that file or the NGINX config updated on every node.
