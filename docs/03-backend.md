# 3. Lab CA and the two backend applications

The lab publishes **two applications** behind the same WAF nodes. Each has its own backend VM:

| App | Public FQDN | Backend | Backend certificate |
|---|---|---|---|
| app1 | `app1.waflab.example` | `backend1` `10.90.20.5:443` | `backend1.waflab.internal` + IP SAN `10.90.20.5` |
| app2 | `app2.waflab.example` | `backend2` `10.90.20.6:443` | `backend2.waflab.internal` + IP SAN `10.90.20.6` |

> In your environment these are your real web servers. The only requirement this guide adds is a **health endpoint** that returns 200 cheaply (here `/healthz`). HAProxy's health checks use it ([chapter 6](06-haproxy.md)).

## 3.1 Lab certificate authority

Every certificate in the lab (backends, published apps, agents) is signed by one lab CA. Chapter 11 explains what changes with a public CA or an internal PKI.

```bash
lab/certs/make-ca.sh
# CA created: certs/ca/ca.crt
```

[`lab/certs/make-ca.sh`](../lab/certs/make-ca.sh) creates an RSA 3072 key and a self-signed root that is valid for 10 years. The `certs/` folder is **git-ignored**, so keys never reach the repository.

[`lab/certs/issue-cert.sh`](../lab/certs/issue-cert.sh) issues a server certificate (RSA 2048, SHA-256, `serverAuth`, SANs from the list):

```bash
lab/certs/issue-cert.sh <cn> <san1,san2,...> <outdir> [days]   # default 825 days
```

It writes three files to `<outdir>`:

- `<cn>.crt` and `<cn>.key`: the certificate and the key.
- `<cn>.pem`: the certificate followed by the key, the format HAProxy loads.

## 3.2 Backend web server

Each backend runs NGINX with [`configs/backend/echo.conf.tmpl`](../configs/backend/echo.conf.tmpl). It answers on `:443` (TLS) and `:80`:

- `GET /healthz` returns `200 ok`.
- Any other path returns a JSON document that makes the WAF path visible:

```json
{"app":"app1","backend":"backend1","client_addr":"10.90.20.11","xff":"10.90.30.10","host":"app1.waflab.example","uri":"/"}
```

| Field | Meaning |
|---|---|
| `app` | which application answered |
| `client_addr` | the TCP peer, which is **the WAF agent (node) that forwarded the request**. The failover tests use it to see which agent handled each request |
| `xff` | the `X-Forwarded-For` chain, which must contain the **real client IP** |
| `host` | the Host header the agent sent upstream |

Deploy (installs NGINX, issues the backend certificate, uploads it and the site, then reloads):

```bash
source lab/inventory.env
lab/deploy-backend.sh backend1 app1 $BACKEND1_IP
lab/deploy-backend.sh backend2 app2 $BACKEND2_IP
```

## 3.3 Verify

[`tests/test_backends.sh`](../tests/test_backends.sh) calls both backends from the host. It validates TLS against the lab CA, checks the JSON contract, and checks that an incoming `X-Forwarded-For` is shown:

```bash
bash tests/test_backends.sh
```

```
PASS 10.90.20.5 {'app': 'app1', 'backend': 'backend1', 'client_addr': '10.90.20.1', 'xff': '192.0.2.7', 'host': '10.90.20.5', 'uri': '/'}
PASS 10.90.20.5 /healthz
PASS 10.90.20.6 {'app': 'app2', 'backend': 'backend2', 'client_addr': '10.90.20.1', 'xff': '192.0.2.7', 'host': '10.90.20.6', 'uri': '/'}
PASS 10.90.20.6 /healthz
```

`client_addr` is `10.90.20.1` (the host) here because the test runs from the host. Once the WAF is in the path, it shows the agent node's IP.
