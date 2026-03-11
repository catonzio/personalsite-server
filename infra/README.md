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

In our setup, Traefik:

- **Reverse Proxy**: Routes all HTTP traffic from port `8080` to appropriate backend services
- **Path-Based Routing**: Routes requests like `/portfolio` to the portfolio app, `/small-games` to games app
- **Auto-Discovery**: Automatically detects new Docker containers via labels (no manual config changes)
- **Dashboard**: Provides a web UI at port `8081` to monitor all routes and services

### Key Benefits

✅ **No manual configuration**: Services register themselves via Docker labels  
✅ **Hot reload**: Changes detected automatically without restart  
✅ **Single entry point**: All apps accessible via one port (8080)  
✅ **Service isolation**: Each app maintains its own network while sharing Traefik network

---

## Architecture

### Network Topology

```text
┌─────────────────────────────────────────────────────────────┐
│                        Host Machine                         │
│                                                             │
│  Browser ──────→ localhost:8080 (Traefik HTTP)              │
│                         │                                   │
│                         ↓                                   │
│  ┌──────────────────────────────────────────────────────┐   │
│  │              Traefik Container                       │   │
│  │  • Routes /portfolio → portfolio-app:8000            │   │
│  │  • Routes /small-games → small-games-app:8000        │   │
│  │  • Routes /sette-mezzo → sette-mezzo-be:8000         │   │
│  │  • Dashboard at localhost:8081                       │   │
│  └──────────────────────────────────────────────────────┘   │
│                         │                                   │
│                         ↓                                   │
│         ┌──────────────────────────────────────┐            │
│         │     traefik-network (bridge)         │            │
│         │                                       │           │
│    ┌────┴────┐    ┌────────┴──────┐    ┌──────┴─────┐       │
│    │portfolio│    │ small-games   │    │sette-mezzo │       │
│    │   app   │    │      app      │    │     be     │       │
│    │  :8000  │    │     :8000     │    │   :8000    │       │
│    └─────────┘    └───────────────┘    └────────────┘       │
└─────────────────────────────────────────────────────────────┘
```

### Traffic Flow

1. **Request arrives**: Browser requests `http://localhost:8080/portfolio/info`
2. **Traefik receives**: Request hits Traefik's `web` entrypoint (port 80 inside container, mapped to 8080 on host)
3. **Route matching**: Traefik matches `PathPrefix(/portfolio)` rule
4. **Service lookup**: Routes to `portfolio` service on `traefik-network`
5. **Backend forward**: Sends request to `portfolio-app:8000/portfolio/info`
6. **Response**: FastAPI responds and Traefik forwards back to browser

---

## Configuration Files

### 1. `traefik/traefik.yml` (Static Configuration)

Static configuration loaded at startup. Changes require container restart.

```yaml
# API & Dashboard
api:
  dashboard: true       # Enable web dashboard
  insecure: true       # Allow access without auth (dev only!)

# Entry Points (ports Traefik listens on)
entryPoints:
  web:
    address: ":80"     # HTTP traffic (internal port 80)

# Service Discovery
providers:
  docker:
    endpoint: "unix:///var/run/docker.sock"  # Docker socket access
    exposedByDefault: false                  # Only expose labeled containers
    watch: true                              # Auto-detect new containers

# Logging
log:
  level: INFO          # Options: DEBUG, INFO, WARN, ERROR
```

**Key Settings Explained:**

| Setting | Value | Purpose |
| --------- | ------- | --------- |
| `api.dashboard` | `true` | Enables the Traefik dashboard UI |
| `api.insecure` | `true` | **⚠️ DEV ONLY**: Skips authentication. Never use in production! |
| `exposedByDefault` | `false` | Services must explicitly opt-in with `traefik.enable=true` |
| `watch` | `true` | Continuously monitors Docker for container changes |

### 2. `traefik/docker-compose.yml`

Container definition and port mappings.

```yaml
services:
  traefik:
    image: traefik:v2.10              # Traefik version
    container_name: traefik
    restart: unless-stopped
    env_file:
      - ../ports.env                  # Load port configuration
    ports:
      - "${TRAEFIK_HTTP_PORT:-8080}:80"        # HTTP: host:container
      - "${TRAEFIK_DASHBOARD_PORT:-8081}:8080" # Dashboard: host:container
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock:ro  # Docker API access
      - ./traefik.yml:/etc/traefik/traefik.yml:ro     # Static config
    networks:
      - traefik-network               # Shared network with apps
    labels:
      - "traefik.enable=true"         # Enable Traefik for itself

networks:
  traefik-network:
    name: traefik-network
    driver: bridge
```

**Port Mapping:**

| Host Port | Container Port | Purpose |
| --------- | -------------- | ------- |
| `8080` | `80` | Main HTTP entrypoint for all apps |
| `8081` | `8080` | Traefik dashboard and API |

### 3. `infra/ports.env`

Centralized port configuration:

```bash
TRAEFIK_HTTP_PORT=8080           # Main entry point (change if 8080 conflicts)
TRAEFIK_DASHBOARD_PORT=8081      # Dashboard port
APP_INTERNAL_PORT=8000           # Internal port all FastAPI apps use
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

### Complete Label Set (Recommended)

For full control over routing:

```yaml
labels:
  # Enable Traefik for this container
  - "traefik.enable=true"
  
  # Define a router named "portfolio"
  - "traefik.http.routers.portfolio.rule=PathPrefix(`/portfolio`)"
  - "traefik.http.routers.portfolio.entrypoints=web"
  
  # Define a service named "portfolio"
  - "traefik.http.services.portfolio.loadbalancer.server.port=8000"
  
  # Specify which network Traefik should use
  - "traefik.docker.network=traefik-network"
```

### Label Breakdown

#### 1. Enable Traefik

```yaml
- "traefik.enable=true"
```

**Required**: Without this, Traefik ignores the container (when `exposedByDefault=false`).

#### 2. Router Configuration

```yaml
- "traefik.http.routers.{router-name}.rule=PathPrefix(`/path`)"
- "traefik.http.routers.{router-name}.entrypoints=web"
```

**Router**: Defines how requests are matched and routed.

- `{router-name}`: Unique identifier (usually matches service name)
- `.rule`: Matching criteria (see [Routing Rules](#routing-rules))
- `.entrypoints`: Which entrypoint(s) to listen on (`web` = port 80)

#### 3. Service Configuration

```yaml
- "traefik.http.services.{service-name}.loadbalancer.server.port=8000"
```

**Service**: The backend service Traefik forwards traffic to.

- `{service-name}`: Unique identifier (should match router name)
- `.loadbalancer.server.port`: Port the app listens on **inside its container**

#### 4. Network Selection

```yaml
- "traefik.docker.network=traefik-network"
```

**Important**: If your container is on multiple networks, this tells Traefik which one to use for routing.

### Complete Example: Portfolio App

```yaml
services:
  portfolio:
    build: .
    container_name: portfolio-app
    restart: unless-stopped
    networks:
      - portfolio-network      # Private network for app resources
      - traefik-network        # Shared network for Traefik routing
    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.portfolio.rule=PathPrefix(`/portfolio`)"
      - "traefik.http.routers.portfolio.entrypoints=web"
      - "traefik.http.services.portfolio.loadbalancer.server.port=8000"
      - "traefik.docker.network=traefik-network"

networks:
  portfolio-network:
    name: portfolio-network
    driver: bridge
  traefik-network:
    external: true              # Must already exist (created by Traefik)
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

**Dashboard**: Open browser to `http://localhost:8081`

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
curl http://localhost:8080/portfolio/health

# Test with verbose output
curl -v http://localhost:8080/portfolio/

# Follow redirects
curl -L http://localhost:8080/portfolio
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
   curl http://localhost:8080/portfolio/  # ✅ Works
   curl http://localhost:8080/portfolios/ # ❌ 404
   ```

2. **Missing root_path in FastAPI**:

   ```python
   # app.py should have:
   app = FastAPI(root_path="/portfolio")
   ```

3. **Wrong entrypoint**: Using HTTPS when only HTTP configured

   ```bash
   curl http://localhost:8080/portfolio/  # ✅ Correct
   curl https://localhost:8080/portfolio/ # ❌ Wrong
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
curl http://localhost:8080/portfolio/health
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
  - "traefik.http.routers.app.entrypoints=web"
  
  # Create middleware to strip /api prefix
  - "traefik.http.middlewares.strip-api.stripprefix.prefixes=/api"
  
  # Apply middleware to router
  - "traefik.http.routers.app.middlewares=strip-api@docker"
  
  - "traefik.http.services.app.loadbalancer.server.port=8000"
```

**Example:**

- Request: `http://localhost:8080/api/users`
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

Protect a service with username/password:

```bash
# Generate password (requires htpasswd from apache2-utils)
htpasswd -nb admin secretpassword
# Output: admin:$apr1$...
```

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
  - "traefik.http.middlewares.cors.headers.accesscontrolalloworiginlist=http://localhost:3000,http://localhost:8080"
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
  - "traefik.http.routers.app-api.entrypoints=web"
  - "traefik.http.routers.app-api.service=app-service"
  
  # Router 2: /admin path
  - "traefik.http.routers.app-admin.rule=PathPrefix(`/admin`)"
  - "traefik.http.routers.app-admin.entrypoints=web"
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

For production setups with HTTPS entrypoint:

```yaml
labels:
  - "traefik.enable=true"
  
  # HTTP router redirects to HTTPS
  - "traefik.http.routers.app-http.rule=PathPrefix(`/app`)"
  - "traefik.http.routers.app-http.entrypoints=web"
  - "traefik.http.routers.app-http.middlewares=redirect-to-https@docker"
  
  # HTTPS router (actual service)
  - "traefik.http.routers.app.rule=PathPrefix(`/app`)"
  - "traefik.http.routers.app.entrypoints=websecure"
  - "traefik.http.routers.app.tls=true"
  
  # Redirect middleware
  - "traefik.http.middlewares.redirect-to-https.redirectscheme.scheme=https"
  
  - "traefik.http.services.app.loadbalancer.server.port=8000"
```

---

## Security Best Practices

### ⚠️ Current Setup (Development Only!)

The current configuration is **NOT secure for production**:

```yaml
# ❌ DEV ONLY! Insecure dashboard access
api:
  dashboard: true
  insecure: true
```

### 🔒 Production Security Checklist

Before deploying to production:

#### 1. Secure the Dashboard

**Option A**: Disable completely

```yaml
api:
  dashboard: false
```

**Option B**: Add authentication

```yaml
api:
  dashboard: true
  insecure: false    # Require secure access

# Add basic auth via labels on Traefik itself
labels:
  - "traefik.http.routers.dashboard.rule=Host(`traefik.yourdomain.com`)"
  - "traefik.http.routers.dashboard.service=api@internal"
  - "traefik.http.routers.dashboard.middlewares=auth"
  - "traefik.http.middlewares.auth.basicauth.users=admin:$$apr1$$..."
```

#### 2. Enable HTTPS

Add HTTPS entrypoint:

```yaml
entryPoints:
  web:
    address: ":80"
    http:
      redirections:
        entryPoint:
          to: websecure
          scheme: https
  websecure:
    address: ":443"
```

#### 3. Use Let's Encrypt

Automatic SSL certificates:

```yaml
certificatesResolvers:
  letsencrypt:
    acme:
      email: your-email@example.com
      storage: /letsencrypt/acme.json
      httpChallenge:
        entryPoint: web
```

Then in containers:

```yaml
labels:
  - "traefik.http.routers.app.tls=true"
  - "traefik.http.routers.app.tls.certresolver=letsencrypt"
```

#### 4. Restrict Docker Socket Access

The Docker socket is powerful. In production:

- Use Docker Socket Proxy (e.g., Tecnativa's docker-socket-proxy)
- Limit Traefik's Docker API access to read-only container info

#### 5. Set Security Headers

Add security headers to all responses:

```yaml
labels:
  # Security headers middleware
  - "traefik.http.middlewares.security.headers.framedeny=true"
  - "traefik.http.middlewares.security.headers.sslredirect=true"
  - "traefik.http.middlewares.security.headers.stsSeconds=31536000"
  - "traefik.http.middlewares.security.headers.stsIncludeSubdomains=true"
  - "traefik.http.middlewares.security.headers.stsPreload=true"
  - "traefik.http.middlewares.security.headers.contentTypeNosniff=true"
  - "traefik.http.middlewares.security.headers.browserXssFilter=true"
  
  # Apply to all routers
  - "traefik.http.routers.app.middlewares=security@docker"
```

#### 6. Enable Access Logs

Track all requests:

```yaml
accessLog:
  filePath: "/var/log/traefik/access.log"
  format: json
  fields:
    defaultMode: keep
    headers:
      defaultMode: drop    # Don't log sensitive headers
```

#### 7. Filter by IP (if needed)

Restrict access by source IP:

```yaml
labels:
  # Whitelist middleware
  - "traefik.http.middlewares.ipwhitelist.ipwhitelist.sourcerange=192.168.1.0/24,10.0.0.0/8"
  
  # Apply to router
  - "traefik.http.routers.app.middlewares=ipwhitelist@docker"
```

#### 8. Separate Networks

Best practice: Isolate backend services

```yaml
services:
  app:
    networks:
      - backend-network    # Private network with database
      - traefik-network    # Only Traefik can access
  
  database:
    networks:
      - backend-network    # NOT on traefik-network = not exposed

networks:
  backend-network:
    internal: true         # No external access
  traefik-network:
    external: true
```

---

## Quick Reference Card

### Essential Commands

```bash
# View dashboard
open http://localhost:8081

# Test routing
curl http://localhost:8080/portfolio/health

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

Copy-paste template for new services:

```yaml
labels:
  - "traefik.enable=true"
  - "traefik.http.routers.{SERVICE}.rule=PathPrefix(`/{PATH}`)"
  - "traefik.http.routers.{SERVICE}.entrypoints=web"
  - "traefik.http.services.{SERVICE}.loadbalancer.server.port=8000"
  - "traefik.docker.network=traefik-network"
```

Replace `{SERVICE}` with your service name and `{PATH}` with your URL path.

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
  └─→ Verify FastAPI root_path set correctly

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
- [ports.env](ports.env) - Port configuration
- [traefik.yml](traefik/traefik.yml) - Static configuration
- [docker-compose.yml](traefik/docker-compose.yml) - Container definition

### Example Configurations

See existing apps for working examples:

- [apps/portfolio/docker-compose.yml](../apps/portfolio/docker-compose.yml)
- [apps/small-games/docker-compose.yml](../apps/small-games/docker-compose.yml)
- [apps/sette-mezzo/be/docker-compose.yml](../apps/sette-mezzo/docker-compose.yml) (if exists)

---

**Last Updated**: March 10, 2026  
**Traefik Version**: v2.10  
**Maintained by**: Personal Server Project
