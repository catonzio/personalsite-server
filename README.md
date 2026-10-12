# Personal Server Mock Environment

A local development environment that mocks a personal server setup with Traefik reverse proxy, multiple FastAPI applications served as subpaths, and Portainer for container management.

## 📁 Project Structure

```text
.
├── manage.sh                  # Central management script for all services
├── apps/                      # All application services
│   ├── portfolio/            # Portfolio FastAPI app
│   │   ├── app.py
│   │   ├── Dockerfile
│   │   ├── requirements.txt
│   │   └── docker-compose.yml
│   └── small-games/          # Small games FastAPI app
│       ├── app.py
│       ├── Dockerfile
│       ├── requirements.txt
│       └── docker-compose.yml
│
└── infra/                     # Infrastructure services
    ├── traefik/              # Reverse proxy with auto-discovery
    │   ├── docker-compose.yml
    │   ├── traefik.yml
    │   ├── traefik_dynamic.yml
    │   ├── .env              # DNS provider API keys (not committed)
    │   └── letsencrypt/      # acme.json with the issued certificate (not committed)
    ├── portainer/            # Container management UI
    │   └── docker-compose.yml
    ├── .env                  # Centralized port and environment configuration
    └── ports.yml             # Port documentation reference
```

## 🚀 Quick Start

### Option 1: Using Management Script (Recommended)

The easiest way to manage services:

```bash
# Initialize everything (first time setup)
./manage.sh init

# Or start services manually
./manage.sh start              # Start all services
./manage.sh start portfolio    # Start specific service
./manage.sh status             # Check status
```

### Option 2: Manual Docker Compose

Start Traefik first (required to create shared network):

```bash
cd infra/traefik
docker compose up -d
```

Then start applications:

```bash
# Start portfolio
cd apps/portfolio
docker compose up -d

# Start small-games
cd apps/small-games
docker compose up -d
```

(Optional) Start Portainer:

```bash
cd infra/portainer
docker compose up -d
```

## 🌐 Accessing Services

Once running, services are available at:

- **Portfolio App**: <http://localhost:8080/portfolio>
  - Health check: <http://localhost:8080/portfolio/health>
  - Info: <http://localhost:8080/portfolio/info>
  
- **Small Games**: <http://localhost:8080/small-games>
  - Health check: <http://localhost:8080/small-games/health>
  - Games list: <http://localhost:8080/small-games/games>

- **Traefik Dashboard**: <http://localhost:8081>
  - View all discovered services and routes

- **Portainer**: <http://localhost:9000> or <https://localhost:9443>
  - Container management UI

## 🎮 Management Script

A centralized `manage.sh` script with **automatic service discovery** provides easy management of all services.

### ✨ Auto-Discovery Feature

The script automatically discovers all services by scanning:

- `infra/` directory for infrastructure services
- `apps/` directory for application services

**No code changes needed** - just add a folder with a `docker-compose.yml` and it's instantly available!

### Commands

```bash
# Initialization
./manage.sh init                 # Build and start everything

# Service Control
./manage.sh start [service]      # Start all or specific service
./manage.sh stop [service]       # Stop all or specific service  
./manage.sh restart [service]    # Restart all or specific service

# Building
./manage.sh build [service]      # Build application images
./manage.sh rebuild [service]    # Rebuild and restart (useful after code changes)

# Monitoring
./manage.sh status               # Show status of all services
./manage.sh logs <service> [-f]  # View logs (use -f to follow)
./manage.sh ps                   # Show running containers

# Cleanup
./manage.sh clean                # Stop all and clean up Docker resources

# Help
./manage.sh help                 # Show all available commands
```

**Examples:**

```bash
./manage.sh start portfolio      # Start only portfolio
./manage.sh rebuild small-games  # Rebuild after code changes
./manage.sh logs traefik -f      # Follow traefik logs
./manage.sh status               # Check what's running
```

## ⚙️ Port Configuration

All ports are centralized in `infra/.env` for easy management:

```bash
# External Ports (accessible from host)
TRAEFIK_HTTP_PORT=8080          # Main entry point for all apps
TRAEFIK_DASHBOARD_PORT=8081     # Traefik dashboard
PORTAINER_HTTP_PORT=9000        # Portainer UI
PORTAINER_HTTPS_PORT=9443       # Portainer HTTPS

# Internal Port (used by apps inside containers)
APP_INTERNAL_PORT=8000          # All FastAPI apps listen on this port
```

**Important:** Applications use port 8000 *internally* within their containers and are *not* exposed directly to the host. All traffic goes through Traefik on port 8080, which routes to apps based on the URL path.

To change ports, edit `infra/.env` and restart: `./manage.sh restart`

See `infra/ports.yml` for detailed port documentation.

## 🔒 HTTPS Certificate (Let's Encrypt)

Traefik gets and renews the wildcard certificate (`danilocatone.com` + `*.danilocatone.com`) **by itself**, using Let's Encrypt with the **DNS-01 challenge**: it proves it owns the domain by creating a temporary `_acme-challenge` TXT record through the API of the DNS provider. No ports need to be reachable from the internet for the validation, and wildcards are supported.

How the pieces fit together:

| File | Role |
|------|------|
| `infra/traefik/traefik.yml` | Defines the `letsencrypt` resolver: account email, DNS provider name, storage |
| `infra/traefik/traefik_dynamic.yml` | The `api` router requests the certificate (`certResolver` + `domains`). All other routers use it through SNI matching |
| `infra/traefik/docker-compose.yml` | Passes the provider credentials to the container and mounts `./letsencrypt` |
| `infra/traefik/.env` | Provider API keys (git-ignored) |
| `infra/traefik/letsencrypt/acme.json` | Issued certificate and account, managed by Traefik (git-ignored) |

Traefik checks every 24 hours and renews 30 days before expiry. Nothing has to be done manually.

### Setup for IONOS (current setup)

1. Create an API key at <https://developer.hosting.ionos.com> (same one used by `infra/update-ddns`).
2. Put the two parts in `infra/traefik/.env`:

   ```env
   IONOS_PUBLIC_APIKEY=your_public_prefix
   IONOS_PRIVATE_APIKEY=your_secret
   ```

3. `docker-compose.yml` joins them into the variable expected by Traefik (`IONOS_API_KEY=<public>.<private>`).
4. In `traefik.yml` set your email under `certificatesResolvers.letsencrypt.acme.email` and keep `dnsChallenge.provider: ionos`.
5. In `traefik_dynamic.yml` set your domain under the `api` router (`domains.main` / `sans`).
6. Start/recreate Traefik: `cd infra/traefik && docker compose up -d`.

### Setup for another DNS provider

Traefik supports [more than 100 DNS providers](https://doc.traefik.io/traefik/https/acme/#providers) (Cloudflare, OVH, Route53, DigitalOcean, Hetzner, Gandi, ...). The DNS zone of the domain must be hosted by that provider (check with `dig NS yourdomain.com`; the registrar is not relevant). To switch:

1. In `traefik.yml` change `dnsChallenge.provider` to the provider code.
2. Look up the provider's page in the [lego docs](https://go-acme.github.io/lego/dns/) to find the environment variables it needs.
3. Add those variables to `infra/traefik/.env` and list them under `environment:` in `docker-compose.yml` (replacing `IONOS_API_KEY`).
4. Recreate the container: `docker compose up -d`.

Examples:

| Provider | `provider:` | Variables |
|----------|-------------|-----------|
| IONOS | `ionos` | `IONOS_API_KEY` (`<public>.<secret>`) |
| Cloudflare | `cloudflare` | `CF_DNS_API_TOKEN` (token with *Zone:DNS:Edit*) |
| OVH | `ovh` | `OVH_ENDPOINT`, `OVH_APPLICATION_KEY`, `OVH_APPLICATION_SECRET`, `OVH_CONSUMER_KEY` |
| AWS Route53 | `route53` | `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`, `AWS_REGION` |
| DigitalOcean | `digitalocean` | `DO_AUTH_TOKEN` |

If your provider has no API (or you do not need a wildcard) use the HTTP challenge instead of `dnsChallenge`: replace it with `httpChallenge: { entryPoint: web }`, list only the explicit hostnames in `domains` (no `*.`), and make sure port 80 is reachable from the internet.

### Checks and troubleshooting

- Certificate served right now:

  ```bash
  echo | openssl s_client -connect localhost:443 -servername danilocatone.com 2>/dev/null | openssl x509 -noout -issuer -dates -ext subjectAltName
  ```

- Issuance errors: `docker logs traefik 2>&1 | grep -i acme`. Set `log.level: DEBUG` in `traefik.yml` for the full ACME/DNS trace (and restart).
- Try a new provider without risking rate limits: add `caServer: https://acme-staging-v02.api.letsencrypt.org/directory` under `acme`. Staging certificates are not trusted by browsers; remove the line and delete `letsencrypt/acme.json` to get a real one.
- Force a new issuance (e.g. after adding a domain to a different resolver): stop Traefik, delete `infra/traefik/letsencrypt/acme.json`, start it again. Let's Encrypt allows only a few duplicate certificates per week, so do not do this repeatedly.
- Do **not** set a manual `tls.stores.default.defaultCertificate` for the same domain: Traefik then considers the domain already covered and never requests the Let's Encrypt certificate.
- If a router has `sniStrict` TLS options (as in `traefik_dynamic.yml`), HTTPS fails for every hostname until the first certificate has been issued (about 1-2 minutes after a first start).

## 🔍 How It Works

> 💡 **For comprehensive Traefik documentation**, see the [Traefik Cheatsheet](infra/README.md) with detailed routing rules, debugging tips, middleware configuration, and more.

### Automatic Service Discovery

Traefik automatically discovers new services through Docker labels:

```yaml
labels:
  - "traefik.enable=true"
  - "traefik.http.routers.{service}.rule=PathPrefix(`/{subpath}`)"
  - "traefik.http.routers.{service}.entrypoints=web"
  - "traefik.http.services.{service}.loadbalancer.server.port=8000"
  - "traefik.docker.network=traefik-network"
```

### Subpath Routing

Each FastAPI application is configured with `root_path` to work correctly behind a reverse proxy:

```python
app = FastAPI(root_path="/portfolio")
```

This ensures the OpenAPI docs and all routes work correctly under the subpath.

### Network Architecture

- **traefik-network**: Shared network for all services to communicate with Traefik
- **{app}-network**: Isolated network for each application's internal services

## 📝 Adding New Applications

The management script **auto-discovers** all applications! Just create a directory with a docker-compose.yml file.

### Quick Steps

1. Create a new directory under `apps/`:

   ```bash
   mkdir -p apps/my-new-app
   ```

2. Create your FastAPI application (`apps/my-new-app/app.py`):

   ```python
   from fastapi import FastAPI
   
   app = FastAPI(root_path="/my-new-app")
   
   @app.get("/")
   async def root():
       return {"app": "my-new-app", "status": "running"}
   ```

3. Create a `docker-compose.yml` with Traefik labels:

   ```yaml
   services:
     my-new-app:
       build: .
       container_name: my-new-app-app
       networks:
         - my-new-app-network
         - traefik-network
       labels:
         - "traefik.enable=true"
         - "traefik.http.routers.my-new-app.rule=PathPrefix(`/my-new-app`)"
         - "traefik.http.routers.my-new-app.entrypoints=web"
         - "traefik.http.services.my-new-app.loadbalancer.server.port=8000"
         - "traefik.docker.network=traefik-network"
   
   networks:
     my-new-app-network:
       driver: bridge
     traefik-network:
       external: true
   ```

4. **That's it!** The app is now auto-discovered. Use the management script:

   ```bash
   ./manage.sh build my-new-app      # Build the new app
   ./manage.sh start my-new-app      # Start it
   ./manage.sh status                # See it in the list!
   ```

The script automatically:

- ✅ Discovers your new app (no script modifications needed)
- ✅ Shows it in `./manage.sh status` with the URL
- ✅ Includes it in `./manage.sh start` (starts all apps)
- ✅ Lists it in `./manage.sh help`

Access your new app at: `http://localhost:8080/my-new-app`

Traefik will automatically discover and route traffic to your new application!

## 🛠️ Manual Docker Commands

For those who prefer direct Docker commands (or if not using the management script):

### View Running Containers

```bash
docker ps
# Or use the management script
./manage.sh ps
```

### View Logs

```bash
# Manual Docker logs
docker logs traefik -f
docker logs portfolio-app -f
docker logs small-games-app -f

# Or use the management script
./manage.sh logs traefik -f
./manage.sh logs portfolio -f
```

### Stop Services

```bash
# Manual approach - stop a specific app
cd apps/portfolio
docker compose down

# Or use the management script
./manage.sh stop portfolio
./manage.sh stop  # Stop all
```

### Rebuild After Code Changes

```bash
# Manual approach
cd apps/portfolio
docker compose up -d --build

# Or use the management script (recommended)
./manage.sh rebuild portfolio
```

## 🐛 Troubleshooting

> 💡 **For detailed Traefik debugging**, see the [Troubleshooting section](infra/README.md#debugging--troubleshooting) in the Traefik Cheatsheet.

### Application not accessible

1. Check if Traefik is running: `docker ps | grep traefik`
2. Check Traefik dashboard at <http://localhost:8081> for discovered routes
3. Verify the container is on the traefik-network: `docker inspect {container} | grep traefik-network`

### Port already in use

If port 8080 or 8081 is already in use, edit `infra/.env` to use different ports:

```bash
TRAEFIK_HTTP_PORT=8090
TRAEFIK_DASHBOARD_PORT=8091
```

Then restart Traefik:

```bash
cd infra/traefik
docker compose down
docker compose up -d
```

### Container won't start

Check logs for errors:

```bash
docker logs {container-name}
```

## 📚 Additional Resources

### Project Documentation

- **[Traefik Comprehensive Cheatsheet](infra/README.md)** - Complete guide to Traefik configuration, routing rules, Docker labels, debugging, and advanced features

### External Documentation

- [Traefik Documentation](https://doc.traefik.io/traefik/)
- [FastAPI Documentation](https://fastapi.tiangolo.com/)
- [Docker Compose Documentation](https://docs.docker.com/compose/)
- [Portainer Documentation](https://docs.portainer.io/)
