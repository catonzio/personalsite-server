# Traefik Comprehensive Cheatsheet

> **Quick Reference**: Traefik configuration, routing rules, Docker labels, and troubleshooting guide for the personal server environment.

## Table of Contents

- [Overview](#overview)
- [Architecture](#architecture)
- [Configuration Files](#configuration-files)
- [Docker Labels Reference](#docker-labels-reference)
- [Routing Rules](#routing-rules)
- [Common Operations](#common-operations)
- [Debugging & Troubleshooting](#debugging--troubleshooting)
- [Advanced Configurations](#advanced-configurations)
- [Security Best Practices](#security-best-practices)

---

## Overview

### What is Traefik?

**Traefik** is a modern reverse proxy and load balancer designed for microservices. It automatically discovers services through Docker, Kubernetes, or other providers and routes traffic based on dynamic configuration.

### Role in This Project

In our setup (Traefik v2.11), Traefik:

- **Reverse Proxy + TLS termination**: Listens on `80` (permanent redirect to HTTPS) and `443`, and serves a Let's Encrypt wildcard certificate for `danilocatone.com` / `*.danilocatone.com`
- **Path-Based Routing**: One host, one path per app: `https://danilocatone.com/portfolio`, `/prova`, `/privacy-policy`, ...
- **Auto-Discovery**: Detects new Docker containers via labels (docker provider) and loads shared routers/middlewares/TLS options from a file (file provider)
- **Dashboard**: Web UI at `http://192.168.1.101:8081` (LAN/VPN, no auth, see [Security](#security-best-practices)). The `api` router on `traefik.danilocatone.com` exists, but that hostname has no DNS record
- **Infra dashboard**: launcher page at `https://danilocatone.com/infra/` (basicAuth) that lists apps by reading the Traefik API (see [Infra dashboard](#infra-dashboard-infradashboard))

### Key Benefits

- **No manual configuration**: Services register themselves via Docker labels
- **Hot reload**: Docker labels and `traefik_dynamic.yml` are picked up without a restart
- **Single entry point**: All apps are reachable via `https://danilocatone.com/<app>`
- **Service isolation**: Each app keeps its own network while sharing `traefik-network`

---

## Architecture

### Network Topology

```text
Internet / LAN
      │  https://danilocatone.com/<app>
      ↓
┌──────────────────────────────────────────────────────────────┐
│ Host (80, 443, dashboard 8081)                               │
│  ┌────────────────────────────────────────────────────────┐  │
│  │ Traefik v2.11                                          │  │
│  │  web :80 ──(301 → https)──→ websecure :443 (TLS, SNI)  │  │
│  │  providers: docker (labels) + file (traefik_dynamic)   │  │
│  └─────────────────────────┬──────────────────────────────┘  │
│                            ↓                                 │
│              traefik-network (bridge)                        │
│   /portfolio        → portfolio                              │
│   /wedding-photos   → wedding-photos                         │
│   /whatsapp-assistant → wa-ass                               │
│   /prova, /prova/api → prova fe / be                         │
│   dls-platform(-staging), dls-platform-webapp(-staging)      │
│   /privacy-policy   → privacy-policy                         │
│   /infra            → infra-dashboard (basicAuth)            │
│   /infra/api        → api@internal    (basicAuth, read-only) │
│   /  → redirect to /portfolio/   (root-redirect router)      │
│   traefik.danilocatone.com → api@internal (no DNS record)    │
└──────────────────────────────────────────────────────────────┘
```

### Traffic Flow

1. **Request arrives**: Browser requests `https://danilocatone.com/portfolio/info` (plain `http://` gets a permanent redirect to HTTPS)
2. **Traefik receives**: Request hits the `websecure` entrypoint (443); the certificate is chosen by SNI
3. **Route matching**: Traefik matches `PathPrefix(/portfolio)`
4. **Middlewares**: `portfolio-slash` (adds a trailing slash when missing) and `portfolio-strip` (removes `/portfolio`)
5. **Backend forward**: Sends `/info` to the `portfolio` container on `traefik-network`
6. **Response**: The app responds and Traefik forwards it back to the browser

---

## Configuration Files

### 1. `traefik/traefik.yml` (Static Configuration)

Static configuration loaded at startup. Changes require a container restart.

```yaml
api:
  dashboard: true
  insecure: true # Dashboard without auth on host :8081

entryPoints:
  web:
    address: ":80"
    # Redirect HTTP to HTTPS
    http:
      redirections:
        entryPoint:
          to: websecure
          scheme: https
          permanent: true

  websecure:
    address: ":443"

providers:
  docker:
    endpoint: "unix:///var/run/docker.sock"
    exposedByDefault: false # Only services with traefik.enable=true
    watch: true # Auto-discover new containers

  file:
    directory: /etc/traefik/conf.d
    watch: true

certificatesResolvers:
  letsencrypt:
    acme:
      email: danilocatone@gmail.com
      storage: /letsencrypt/acme.json
      # DNS-01 through the IONOS DNS API (needed for the wildcard certificate)
      dnsChallenge:
        provider: ionos
        resolvers:
          - "1.1.1.1:53"
          - "8.8.8.8:53"

log:
  level: INFO
```

**Key Settings Explained:**

| Setting | Value | Purpose |
| --------- | ------- | --------- |
| `api.dashboard` | `true` | Enables the Traefik dashboard UI |
| `api.insecure` | `true` | Exposes the dashboard on container port 8080 (host `8081`) **without auth** |
| `entryPoints.web.http.redirections` | permanent to `websecure` | Every HTTP request is redirected to HTTPS |
| `exposedByDefault` | `false` | Services must explicitly opt-in with `traefik.enable=true` |
| `providers.file.directory` | `/etc/traefik/conf.d` | Loads `traefik_dynamic.yml`, hot-reloaded |
| `certificatesResolvers.letsencrypt` | DNS-01 / IONOS | Issues the wildcard certificate |

### 2. `traefik/traefik_dynamic.yml` (Dynamic Configuration)

Loaded by the file provider and **hot-reloaded** (no restart needed, but a bad edit breaks every route). The file is a Go template (Sprig functions available): the basicAuth users are read from an environment variable, so no hash is committed.

```yaml
http:
  middlewares:
    services:
      basicAuth:
        users:
          # htpasswd line ("user:$2y$..."), from TRAEFIK_BASIC_AUTH_USERS in ./.env
          - '{{ env "TRAEFIK_BASIC_AUTH_USERS" }}'
    compress:
      compress: {}
    hsts:
      headers:
        stsSeconds: 2592000
    redirect-to-portfolio:
      redirectRegex:
        regex: "^https?://([^/]+)/?$"
        replacement: "https://${1}/portfolio/"
        permanent: true
  routers:
    root-redirect:
      rule: "Path(`/`)"
      entrypoints:
        - websecure
      middlewares:
        - redirect-to-portfolio
      service: api@internal
      priority: 1
      tls: {}
    api:
      rule: Host(`traefik.danilocatone.com`)
      entrypoints:
        - websecure
      middlewares:
        - services
      service: api@internal
      # This router requests the wildcard certificate; every other router is served
      # with it automatically through SNI matching
      tls:
        certResolver: letsencrypt
        domains:
          - main: danilocatone.com
            sans:
              - "*.danilocatone.com"

tls:
  options:
    default:
      cipherSuites:
        - TLS_ECDHE_RSA_WITH_AES_128_GCM_SHA256
        - TLS_ECDHE_RSA_WITH_AES_256_GCM_SHA384
        - TLS_ECDHE_RSA_WITH_CHACHA20_POLY1305_SHA256
      sniStrict: true
```

| Item | Purpose |
| ---- | ------- |
| router `root-redirect` | `/` redirects to `/portfolio/` (priority 1, lowest) |
| router `api` | Dashboard at `traefik.danilocatone.com` behind `services` (hostname has no DNS record); kept because it is the only router that requests the wildcard certificate |
| middleware `services` | basicAuth, users from `TRAEFIK_BASIC_AUTH_USERS` (see [Basic Auth](#middleware-basic-auth)). Used by `/infra` and `/infra/api`. Do **not** write `$$` in this file: it is not unescaped here |
| middlewares `compress`, `hsts` | Defined but **not attached to any router yet** |
| middleware `redirect-to-portfolio` | Used by `root-redirect` |
| `tls.options.default` | Three ECDHE cipher suites and `sniStrict: true`: a request without a matching SNI hostname fails the TLS handshake (so `https://localhost` does not work) |

> Never add a static `defaultCertificate` for the domain: it blocks ACME.

### 3. `traefik/docker-compose.yml`

Container definition and port mappings.

```yaml
services:
  traefik:
    image: traefik:v2.11
    container_name: traefik
    restart: unless-stopped
    env_file:
      - ../ports.env
    environment:
      # IONOS DNS API key is "<public prefix>.<secret>"; the parts come from ./.env
      - IONOS_API_KEY=${IONOS_PUBLIC_APIKEY}.${IONOS_PRIVATE_APIKEY}
      # basicAuth for the "services" middleware (read by traefik_dynamic.yml).
      # In .env, single-quote it and keep single "$": 'user:$2y$12$...'
      - TRAEFIK_BASIC_AUTH_USERS=${TRAEFIK_BASIC_AUTH_USERS:?set TRAEFIK_BASIC_AUTH_USERS in .env}
    ports:
      - "${TRAEFIK_HTTP_PORT:-80}:80"           # HTTP entrypoint
      - "${TRAEFIK_HTTPS_PORT:-443}:443"        # HTTPS entrypoint
      - "${TRAEFIK_DASHBOARD_PORT:-8081}:8080"  # Traefik dashboard
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock:ro  # Docker socket for auto-discovery
      - ./traefik.yml:/etc/traefik/traefik.yml:ro
      - ./traefik_dynamic.yml:/etc/traefik/conf.d/traefik_dynamic.yml:ro  # Dynamic configuration
      - ./letsencrypt:/letsencrypt  # ACME storage (acme.json)
    networks:
      - traefik-network
    labels:
      - "traefik.enable=true"

networks:
  traefik-network:
    name: traefik-network
    driver: bridge
```

**Port Mapping:**

| Host Port | Container Port | Purpose |
| --------- | -------------- | ------- |
| `80` | `80` | `web`: redirects to HTTPS |
| `443` | `443` | `websecure`: all apps |
| `8081` | `8080` | Dashboard and API (`api.insecure`, no auth) |

Host `8080` is **not** Traefik any more: it belongs to pi-hole's web UI.

### 4. `infra/ports.env`

Centralized port configuration (ports only, no secrets):

```bash
TRAEFIK_DOMAIN=danilocatone.com
TRAEFIK_HTTP_PORT=80
TRAEFIK_HTTPS_PORT=443
TRAEFIK_DASHBOARD_PORT=8081
PORTAINER_HTTP_PORT=9000
PORTAINER_HTTPS_PORT=9443
APP_INTERNAL_PORT=8000           # Internal port used by the FastAPI apps
```

---

## Docker Labels Reference

Docker labels are **dynamic configuration** for Traefik. They tell Traefik how to route traffic to each service.

### Minimal Labels (Required)

Every service exposed through Traefik needs these:

```yaml
labels:
  - "traefik.enable=true"
```

This single label tells Traefik: "This container should be discoverable."

### Complete Label Set (Convention)

This server uses **path-based routing on one host** (not subdomains). Template:

```yaml
labels:
  - "traefik.enable=true"
  - "traefik.docker.network=traefik-network"
  - "traefik.http.routers.<app>.rule=PathPrefix(`/<app>`)"
  - "traefik.http.routers.<app>.entrypoints=websecure"
  - "traefik.http.routers.<app>.tls=true"
  - "traefik.http.routers.<app>.middlewares=<app>-slash,<app>-strip"
  # <app>-slash: add the trailing slash
  - "traefik.http.middlewares.<app>-slash.redirectregex.regex=^https?://([^/]+)/<app>$$"
  - "traefik.http.middlewares.<app>-slash.redirectregex.replacement=https://$${1}/<app>/"
  - "traefik.http.middlewares.<app>-slash.redirectregex.permanent=true"
  # <app>-strip: remove the prefix before forwarding
  - "traefik.http.middlewares.<app>-strip.stripprefix.prefixes=/<app>"
  - "traefik.http.services.<app>.loadbalancer.server.port=<internal port>"
```

Notes:

- `entrypoints=websecure` is enough: `web` already redirects to HTTPS (older apps still list `web,websecure`, which is harmless).
- `tls=true` with **no** `certresolver`: the wildcard certificate is requested only by the `api` router and every other router gets it via SNI.
- Router and middleware names are **global across all stacks**, so they must be unique.
- Escape `$` as `$$` in compose labels.
- **Strip prefix OR app-side base path, not both.** With `<app>-strip` the app sees `/` and needs no configuration. The alternative is to skip the strip middleware and make the app aware of the prefix (e.g. FastAPI `root_path="/<app>"`; wedding-photos has no strip).
- Priorities: API routers 100, frontends 50, `root-redirect` 1.

### Label Breakdown

#### 1. Enable Traefik

```yaml
- "traefik.enable=true"
```

**Required**: Without this, Traefik ignores the container (`exposedByDefault=false`).

#### 2. Router Configuration

```yaml
- "traefik.http.routers.{router-name}.rule=PathPrefix(`/path`)"
- "traefik.http.routers.{router-name}.entrypoints=websecure"
- "traefik.http.routers.{router-name}.tls=true"
```

**Router**: Defines how requests are matched and routed.

- `{router-name}`: Unique identifier (usually matches service name)
- `.rule`: Matching criteria (see [Routing Rules](#routing-rules))
- `.entrypoints`: Which entrypoint(s) to listen on (`websecure` = port 443)
- `.tls`: Terminate TLS with the certificate matched by SNI

#### 3. Service Configuration

```yaml
- "traefik.http.services.{service-name}.loadbalancer.server.port=8000"
```

**Service**: The backend Traefik forwards traffic to.

- `{service-name}`: Unique identifier (should match router name)
- `.loadbalancer.server.port`: Port the app listens on **inside its container**

#### 4. Network Selection

```yaml
- "traefik.docker.network=traefik-network"
```

**Important**: If your container is on multiple networks, this tells Traefik which one to use for routing.

### Real Examples

See [apps/portfolio/docker-compose.yml](../apps/portfolio/docker-compose.yml) (app with strip prefix, `web,websecure`), [apps/prova/docker-compose.yml](../apps/prova/docker-compose.yml) (API + frontend with priorities) and [infra/privacy-policy/compose.yaml](privacy-policy/compose.yaml). Each stack must declare the shared network as external:

```yaml
networks:
  traefik-network:
    external: true              # Created by the traefik stack: start it first
```

---

## Routing Rules

Traefik supports powerful routing rules to match incoming requests.

### PathPrefix (Most Common)

Matches requests starting with a specific path:

```yaml
- "traefik.http.routers.app.rule=PathPrefix(`/portfolio`)"
```

**Matches:**

- ✅ `/portfolio`
- ✅ `/portfolio/`
- ✅ `/portfolio/health`
- ✅ `/portfolio/api/data`

**Does NOT Match:**

- ❌ `/portfolios`
- ❌ `/my-portfolio`

### Host

Match by domain/hostname:

```yaml
- "traefik.http.routers.app.rule=Host(`example.com`)"
```

**Matches:**

- ✅ `http://example.com/anything`

**Does NOT Match:**

- ❌ `http://www.example.com`
- ❌ `http://api.example.com`

### Path (Exact Match)

Exact path only (no subpaths):

```yaml
- "traefik.http.routers.app.rule=Path(`/api`)"
```

**Matches:**

- ✅ `/api`

**Does NOT Match:**

- ❌ `/api/users`
- ❌ `/api/`

### Combining Rules (AND Logic)

Use `&&` to combine multiple conditions:

```yaml
- "traefik.http.routers.app.rule=Host(`api.example.com`) && PathPrefix(`/v1`)"
```

**Matches:**

- ✅ `http://api.example.com/v1/users`

**Does NOT Match:**

- ❌ `http://example.com/v1/users` (wrong host)
- ❌ `http://api.example.com/v2/users` (wrong path)

### OR Logic

Use `||` for alternative matches:

```yaml
- "traefik.http.routers.app.rule=PathPrefix(`/api`) || PathPrefix(`/admin`)"
```

**Matches:**

- ✅ `/api/users`
- ✅ `/admin/dashboard`

### Headers

Match by HTTP headers:

```yaml
- "traefik.http.routers.app.rule=Headers(`Content-Type`, `application/json`)"
```

### Method

Match by HTTP method:

```yaml
- "traefik.http.routers.app.rule=Method(`POST`, `PUT`)"
```

### Query Parameters

Match by query string:

```yaml
- "traefik.http.routers.app.rule=Query(`version`, `v2`)"
```

**Matches:**

- ✅ `/api?version=v2`

### Complex Example

```yaml
- "traefik.http.routers.api.rule=Host(`api.example.com`) && PathPrefix(`/v2`) && Method(`GET`, `POST`)"
```

Only routes GET/POST requests to `api.example.com/v2/*`.

---

## Common Operations

### View All Routes & Services

**Dashboard**: Open `http://192.168.1.101:8081` (LAN/VPN, no auth), or `https://danilocatone.com/infra/` for the app launcher

Navigate through:

- **HTTP Routers**: See all active routes and rules
- **HTTP Services**: See backend services and health
- **HTTP Middlewares**: See active middleware (if any)

**CLI**:

```bash
# List all containers with Traefik labels
docker ps --filter "label=traefik.enable=true"

# Inspect labels on a specific container
docker inspect portfolio-app | grep -A 20 "Labels"
```

### Test Routing

```bash
# Test portfolio route
curl https://danilocatone.com/portfolio/

# Test with verbose output
curl -v https://danilocatone.com/portfolio/

# Local test, bypassing DNS (sniStrict needs the hostname)
curl -k --resolve danilocatone.com:443:127.0.0.1 https://danilocatone.com/portfolio/

# Follow redirects
curl -L https://danilocatone.com/portfolio
```

### Hot Reload Configuration

**No Restart Needed!** Traefik automatically detects:

- New containers
- Label changes on containers
- Container stop/start

To update labels:

```bash
# 1. Update labels in docker-compose.yml
# 2. Stop and recreate container
cd apps/portfolio
docker compose up -d --force-recreate

# Traefik detects changes automatically within seconds
```

### Manual Restart

Only needed if changing `traefik.yml` (static config):

```bash
cd infra/traefik
docker compose restart

# Or using management script
./manage.sh restart traefik
```

### View Traefik Logs

```bash
# Follow logs in real-time
docker logs traefik -f

# Last 100 lines
docker logs traefik --tail 100

# Search for errors
docker logs traefik 2>&1 | grep -i error

# Using management script
./manage.sh logs traefik -f
```

### Check Backend Health

Traefik automatically health-checks services by attempting connections.

```bash
# View service status in logs
docker logs traefik 2>&1 | grep -i "health"

# Or check dashboard at http://localhost:8081
```

---

## Debugging & Troubleshooting

### Problem: Service Not Appearing in Dashboard

**Checklist:**

1. **Container running?**

   ```bash
   docker ps | grep portfolio
   ```

2. **Traefik enabled?**

   ```bash
   docker inspect portfolio-app | grep "traefik.enable"
   # Should show: "traefik.enable": "true"
   ```

3. **On traefik-network?**

   ```bash
   docker inspect portfolio-app | grep -A 5 "Networks"
   # Should show traefik-network
   ```

4. **Labels syntax correct?**

   ```bash
   docker inspect portfolio-app --format='{{json .Config.Labels}}' | jq
   ```

5. **Traefik logs show detection?**

   ```bash
   docker logs traefik 2>&1 | grep portfolio
   ```

### Problem: 404 Page Not Found

**Causes:**

1. **Path mismatch**: Request path doesn't match `PathPrefix` rule

   ```bash
   # If rule is PathPrefix(`/portfolio`)
   curl https://danilocatone.com/portfolio/  # ✅ Works
   curl https://danilocatone.com/portfolios/ # ❌ 404
   ```

2. **Prefix handling mismatch**: either the router strips the prefix (`<app>-strip`) and the app serves from `/`, or there is no strip middleware and the app must know its prefix (e.g. `FastAPI(root_path="/portfolio")`). Never both.

3. **TLS / SNI**: `sniStrict: true` rejects requests without a matching hostname, so `https://localhost/...` fails the handshake. Use the real hostname or `--resolve`:

   ```bash
   curl -k --resolve danilocatone.com:443:127.0.0.1 https://danilocatone.com/portfolio/
   ```

### Problem: 502 Bad Gateway

**Meaning**: Traefik reached the backend but got no response.

**Causes:**

1. **App not listening**: Container is running but app crashed

   ```bash
   docker logs portfolio-app
   ```

2. **Wrong port**: `loadbalancer.server.port` doesn't match app's listen port

   ```yaml
   # Label says 8000 but app listens on 3000 ❌
   - "traefik.http.services.portfolio.loadbalancer.server.port=8000"
   ```

3. **Network issue**: Container not actually on traefik-network

   ```bash
   docker network inspect traefik-network
   ```

4. **App listening on localhost only**:

   ```python
   # ❌ Wrong - only accepts from localhost
   uvicorn.run(app, host="127.0.0.1", port=8000)
   
   # ✅ Correct - accepts from any network interface
   uvicorn.run(app, host="0.0.0.0", port=8000)
   ```

### Problem: 503 Service Unavailable

**Meaning**: Traefik has no available backend for the route.

**Causes:**

1. **No containers match**: Service stopped or never started

   ```bash
   docker ps | grep portfolio
   ```

2. **All backends unhealthy**: Traefik can't connect to any instance

### Problem: Changes Not Taking Effect

**Solution**: Force recreate container to apply label changes

```bash
cd apps/portfolio
docker compose up -d --force-recreate

# Wait 2-3 seconds for Traefik to detect
sleep 3
curl https://danilocatone.com/portfolio/
```

### Debug Mode

Enable detailed logging:

**Edit `traefik.yml`:**

```yaml
log:
  level: DEBUG    # Change from INFO to DEBUG
```

**Restart Traefik:**

```bash
cd infra/traefik
docker compose restart
```

**View detailed logs:**

```bash
docker logs traefik -f
```

⚠️ **Remember to set back to INFO**: DEBUG is very verbose!

### Verify Traefik Configuration

**Check static config loaded correctly:**

```bash
docker exec traefik cat /etc/traefik/traefik.yml
```

**Check Docker socket accessible:**

```bash
docker exec traefik ls -la /var/run/docker.sock
# Should show: srw-rw---- ... /var/run/docker.sock
```

### Common Error Messages

| Error | Meaning | Solution |
| ------- | --------- | ---------- |
| `Gateway Timeout` | Backend took too long | Check app performance/logs |
| `Client.Timeout` | Request timeout | Increase timeout or optimize app |
| `cannot create connection` | Can't reach Docker | Check socket mount |
| `host not found` | DNS resolution failed | Check service name |
| `i/o timeout` | Network connectivity issue | Check networks |

---

## Advanced Configurations

### Middleware: Strip Prefix

Remove the path prefix before forwarding to backend:

```yaml
labels:
  - "traefik.enable=true"
  - "traefik.http.routers.app.rule=PathPrefix(`/api`)"
  - "traefik.http.routers.app.entrypoints=websecure"
  
  # Create middleware to strip /api prefix
  - "traefik.http.middlewares.strip-api.stripprefix.prefixes=/api"
  
  # Apply middleware to router
  - "traefik.http.routers.app.middlewares=strip-api@docker"
  
  - "traefik.http.services.app.loadbalancer.server.port=8000"
```

**Example:**

- Request: `https://danilocatone.com/api/users`
- Backend receives: `/users` (prefix stripped)

### Middleware: Add Headers

```yaml
labels:
  - "traefik.enable=true"
  # ... router and service configuration ...
  
  # Add custom headers
  - "traefik.http.middlewares.custom-headers.headers.customrequestheaders.X-Custom-Header=MyValue"
  
  # Apply middleware
  - "traefik.http.routers.app.middlewares=custom-headers@docker"
```

### Middleware: Basic Auth

**Shared `services` middleware (preferred)**: add `services@file` to a router's middlewares. Its users come from `infra/traefik/.env`:

```bash
# Generate a bcrypt line (htpasswd is not installed on the host); prompts for the password
docker run --rm -it httpd:2.4-alpine htpasswd -nBC 12 <user>
```

```env
# infra/traefik/.env: single quotes, single "$"
TRAEFIK_BASIC_AUTH_USERS='<user>:$2y$12$...'
```

Then recreate Traefik (`cd infra/traefik && docker compose up -d`, all routes down for a few seconds). Check it without printing the hash: `curl -s localhost:8081/api/http/middlewares/services@file` must show `"status":"enabled"`. A `disabled` status plus `error parsing BasicUser` in the logs means a malformed line (e.g. `$$`, or the username written twice).

**Per-app middleware in labels** (e.g. dls staging):

```yaml
labels:
  - "traefik.enable=true"
  # ... router and service configuration ...
  
  # Create basic auth middleware
  - "traefik.http.middlewares.auth.basicauth.users=admin:$$apr1$$..."
  
  # Apply middleware
  - "traefik.http.routers.app.middlewares=auth@docker"
```

**Note**: Escape `$` with `$$` in docker-compose.yml!

### Middleware: Rate Limiting

```yaml
labels:
  - "traefik.enable=true"
  # ... router and service configuration ...
  
  # Allow 100 requests per second, burst of 50
  - "traefik.http.middlewares.rate-limit.ratelimit.average=100"
  - "traefik.http.middlewares.rate-limit.ratelimit.burst=50"
  
  # Apply middleware
  - "traefik.http.routers.app.middlewares=rate-limit@docker"
```

### Middleware: CORS Headers

```yaml
labels:
  - "traefik.enable=true"
  # ... router and service configuration ...
  
  # Configure CORS
  - "traefik.http.middlewares.cors.headers.accesscontrolallowmethods=GET,POST,PUT,DELETE,OPTIONS"
  - "traefik.http.middlewares.cors.headers.accesscontrolalloworiginlist=http://localhost:3000,https://danilocatone.com"
  - "traefik.http.middlewares.cors.headers.accesscontrolmaxage=100"
  - "traefik.http.middlewares.cors.headers.addvaryheader=true"
  
  # Apply middleware
  - "traefik.http.routers.app.middlewares=cors@docker"
```

### Middleware: Chain Multiple

Apply multiple middlewares in order:

```yaml
labels:
  - "traefik.enable=true"
  # ... router and service configuration ...
  
  # Define individual middlewares
  - "traefik.http.middlewares.strip-api.stripprefix.prefixes=/api"
  - "traefik.http.middlewares.auth.basicauth.users=admin:$$apr1$$..."
  - "traefik.http.middlewares.cors.headers.accesscontrolallowmethods=GET,POST"
  
  # Chain them together (order matters!)
  - "traefik.http.routers.app.middlewares=auth@docker,strip-api@docker,cors@docker"
```

**Execution order**: auth → strip-api → cors → backend

### Multiple Routers for Same Service

Route different paths to the same backend:

```yaml
labels:
  - "traefik.enable=true"
  
  # Router 1: /api path
  - "traefik.http.routers.app-api.rule=PathPrefix(`/api`)"
  - "traefik.http.routers.app-api.entrypoints=websecure"
  - "traefik.http.routers.app-api.service=app-service"
  
  # Router 2: /admin path
  - "traefik.http.routers.app-admin.rule=PathPrefix(`/admin`)"
  - "traefik.http.routers.app-admin.entrypoints=websecure"
  - "traefik.http.routers.app-admin.middlewares=auth@docker"
  - "traefik.http.routers.app-admin.service=app-service"
  
  # Single service definition
  - "traefik.http.services.app-service.loadbalancer.server.port=8000"
```

### Load Balancing (Multiple Replicas)

If you have multiple instances of the same service:

```yaml
services:
  app:
    image: myapp:latest
    deploy:
      replicas: 3        # Run 3 instances
    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.app.rule=PathPrefix(`/app`)"
      - "traefik.http.services.app.loadbalancer.server.port=8000"
    networks:
      - traefik-network
```

Traefik automatically load-balances across all replicas using round-robin.

### Sticky Sessions

Keep users on the same backend instance:

```yaml
labels:
  - "traefik.enable=true"
  # ... router configuration ...
  
  # Enable sticky sessions with cookies
  - "traefik.http.services.app.loadbalancer.sticky.cookie=true"
  - "traefik.http.services.app.loadbalancer.sticky.cookie.name=app_sticky"
  - "traefik.http.services.app.loadbalancer.server.port=8000"
```

### Health Check Configuration

Customize health check behavior:

```yaml
labels:
  - "traefik.enable=true"
  # ... router configuration ...
  
  # Configure health check
  - "traefik.http.services.app.loadbalancer.healthcheck.path=/health"
  - "traefik.http.services.app.loadbalancer.healthcheck.interval=10s"
  - "traefik.http.services.app.loadbalancer.healthcheck.timeout=3s"
  - "traefik.http.services.app.loadbalancer.server.port=8000"
```

### Redirect HTTP to HTTPS

Already handled globally by the `web` entrypoint redirection in `traefik.yml`: no per-app redirect router or middleware is needed.

### Infra dashboard (`infra/dashboard`)

`infra-dashboard` (nginx:alpine, `html/` mounted read-only) uses two routers:

| Router | Rule | Middlewares | Service |
| ------ | ---- | ----------- | ------- |
| `infra-dashboard` | ``PathPrefix(`/infra`)``, priority 50 | `infra-dashboard-slash`, `services@file`, `infra-dashboard-strip` | nginx :80 |
| `infra-dashboard-api` | ``PathPrefix(`/infra/api/`)``, priority 60 | `services@file`, `infra-dashboard-strip` | `api@internal` |

The page calls `api/http/routers` (same origin and same basicAuth session). It takes the first path segment of every enabled `Path`/`PathPrefix` rule, skips `@internal` routers and the `api`, `infra`, `dashboard` paths, and shows one card per app. Apps that are not routed by Traefik (wg-easy, Portainer, Pi-hole, the Traefik dashboard) are listed by hand in `html/services.js` with LAN URLs.

### Apps that cannot run under a subpath

Some UIs (wg-easy v15, Portainer) hard-code absolute redirects and cookie paths, so `PathPrefix` + strip breaks login. Options: a subdomain (needs a DNS record, e.g. a `CNAME` to `danilocatone.com`; the wildcard certificate already covers it), or LAN/VPN-only access linked from the infra dashboard (current choice).

---

## Security Best Practices

### Current State

| Area | State |
| ---- | ----- |
| HTTPS + HTTP redirect | Done (`web` permanently redirects to `websecure`) |
| Let's Encrypt | Done (wildcard via DNS-01, see below) |
| Dashboard | **Open without auth on host `:8081`** (`api.insecure: true`; the `traefik.danilocatone.com` router has no DNS record). The read-only API is also exposed at `/infra/api/*` behind basicAuth. To-do: set `insecure: false` or stop publishing 8081 |
| basicAuth | Users loaded from `infra/traefik/.env`, nothing committed |
| Docker socket | Mounted read-only into Traefik. To-do: socket proxy |
| Security headers / compression | `hsts` and `compress` middlewares are defined but **not attached to any router**. To-do |
| Access log | Not enabled. To-do |
| TLS options | `sniStrict: true` and three ECDHE cipher suites |

### Production Security Checklist

#### 1. Secure the Dashboard

Either disable it (`api.dashboard: false`) or remove `insecure: true` (and the `8081` port mapping) so that it is only reachable through the `api` router, which is protected by the `services` basicAuth middleware.

#### 2. Enable HTTPS

Already done: see `entryPoints` in [traefik.yml](traefik/traefik.yml).

#### 3. Use Let's Encrypt

This server already does: [traefik.yml](traefik/traefik.yml) defines the `letsencrypt` resolver with a DNS-01
challenge on IONOS (wildcard `*.danilocatone.com`), and the `api` router in
[traefik_dynamic.yml](traefik/traefik_dynamic.yml) requests the certificate. Traefik renews it by itself
(30 days before expiry); it is stored in `traefik/letsencrypt/acme.json`. The IONOS API key
(`IONOS_PUBLIC_APIKEY` / `IONOS_PRIVATE_APIKEY`) is read from `traefik/.env` (not committed; same keys as
`update-ddns/.env`). Do not delete `acme.json` lightly (Let's Encrypt rate limits).

Generic example (HTTP-01, for a single-host certificate):

```yaml
certificatesResolvers:
  letsencrypt:
    acme:
      email: your-email@example.com
      storage: /letsencrypt/acme.json
      httpChallenge:
        entryPoint: web
```

#### 4. Restrict Docker Socket Access

The Docker socket is powerful. Use a Docker Socket Proxy (e.g. Tecnativa's docker-socket-proxy) so that Traefik only gets read-only access to container info.

#### 5. Set Security Headers

Attach the existing `hsts` / `compress` middlewares to routers, e.g. `...middlewares=<app>-slash,<app>-strip,hsts@file,compress@file`, or define more headers:

```yaml
labels:
  - "traefik.http.middlewares.security.headers.framedeny=true"
  - "traefik.http.middlewares.security.headers.stsSeconds=31536000"
  - "traefik.http.middlewares.security.headers.stsIncludeSubdomains=true"
  - "traefik.http.middlewares.security.headers.contentTypeNosniff=true"
```

#### 6. Enable Access Logs

```yaml
accessLog:
  filePath: "/var/log/traefik/access.log"
  format: json
  fields:
    headers:
      defaultMode: drop    # Don't log sensitive headers
```

#### 7. Filter by IP (if needed)

```yaml
labels:
  - "traefik.http.middlewares.ipwhitelist.ipwhitelist.sourcerange=192.168.1.0/24"
  - "traefik.http.routers.app.middlewares=ipwhitelist@docker"
```

#### 8. Separate Networks

Keep databases off `traefik-network`: put them only on the app's private network.

```yaml
services:
  app:
    networks: [backend-network, traefik-network]
  database:
    networks: [backend-network]   # NOT on traefik-network = not routable
networks:
  backend-network: {}
  traefik-network:
    external: true
```

---

## Quick Reference Card

### Essential Commands

```bash
# View dashboard
open http://localhost:8081   # or https://danilocatone.com/infra/ (launcher, basicAuth)

# Test routing
curl https://danilocatone.com/portfolio/

# View Traefik logs
docker logs traefik -f

# Inspect container labels
docker inspect <container> | grep -A 20 "Labels"

# List Traefik-enabled containers
docker ps --filter "label=traefik.enable=true"

# Restart Traefik
cd infra/traefik && docker compose restart
```

### Label Template

See [Complete Label Set (Convention)](#complete-label-set-convention): replace `<app>` with your service name and `<internal port>` with the container port.

### Routing Rule Syntax

| Pattern | Example | Matches |
| --------- | ------- | ------- |
| `PathPrefix(\`/api\`)` | `/api/users` | Starts with `/api` |
| `Path(\`/api\`)` | `/api` only | Exact path |
| `Host(\`example.com\`)` | Any path | Specific domain |
| `Method(\`GET\`)` | GET requests | HTTP method |
| `Headers(\`key\`,\`val\`)` | Header match | Header present |

### Troubleshooting Flowchart

```text
404 Not Found?
  └─→ Check PathPrefix matches URL
  └─→ Strip prefix OR app root_path (not both)

502 Bad Gateway?
  └─→ Check backend app is running (docker logs)
  └─→ Verify port number in labels
  └─→ Check app listens on 0.0.0.0, not 127.0.0.1

503 Service Unavailable?
  └─→ Check container is running (docker ps)
  └─→ Verify on traefik-network
  └─→ Check traefik.enable=true label

Not in dashboard?
  └─→ Check all labels present and correct
  └─→ Verify on traefik-network
  └─→ Check Traefik logs for errors
```

---

## Additional Resources

### Official Documentation

- **Traefik Docs**: <https://doc.traefik.io/traefik/>
- **Docker Provider**: <https://doc.traefik.io/traefik/providers/docker/>
- **Routing Rules**: <https://doc.traefik.io/traefik/routing/routers/>
- **Middlewares**: <https://doc.traefik.io/traefik/middlewares/overview/>

### Project-Specific Files

- [Main README](../README.md) - Project overview and quick start
- [ports.env](ports.env) / [ports.yml](ports.yml) - Port configuration and host port map
- [traefik.yml](traefik/traefik.yml) - Static configuration
- [traefik_dynamic.yml](traefik/traefik_dynamic.yml) - Dynamic configuration
- [docker-compose.yml](traefik/docker-compose.yml) - Container definition
- [dashboard/compose.yaml](dashboard/compose.yaml) / [dashboard/html/services.js](dashboard/html/services.js) - Infra launcher page

### Example Configurations

See existing apps for working examples:

- [apps/portfolio/docker-compose.yml](../apps/portfolio/docker-compose.yml)
- [apps/prova/docker-compose.yml](../apps/prova/docker-compose.yml)
- [infra/privacy-policy/compose.yaml](privacy-policy/compose.yaml)

---

**Last Updated**: October 21, 2026  
**Traefik Version**: v2.11  
**Maintained by**: Personal Server Project
