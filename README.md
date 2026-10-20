# Personal Server

Home server on a laptop (Dell XPS 13 7390, Ubuntu) serving `danilocatone.com`. Every service runs with Docker Compose behind a **Traefik** reverse proxy that terminates HTTPS with an automatically renewed Let's Encrypt wildcard certificate. Apps are exposed as **subpaths of one host** (e.g. `https://danilocatone.com/portfolio/`).

> Agent/AI context lives in [CLAUDE.md](CLAUDE.md). Traefik details: [infra/README.md](infra/README.md). Management scripts: [scripts/README.md](scripts/README.md).

## 📁 Project Structure

```text
.
├── manage.sh                 # Central management script (auto-discovers services)
├── scripts/                  # manage.sh libraries and commands (see scripts/README.md)
├── apps/                     # Applications (git-ignored: each app is its own git repo)
│   ├── portfolio/            # Personal site, also the target of "/"
│   ├── wedding-photos/
│   ├── whatsapp-assistant/
│   ├── prova/                # Demo app (FE + BE), reference for new apps
│   └── dls-platform*/        # DLS platform + webapp, prod and -staging copies
└── infra/                    # Infrastructure stacks (tracked in this repo)
    ├── ports.env             # Shared host ports + domain
    ├── ports.yml             # Port reference (documentation)
    ├── traefik/              # Reverse proxy + ACME (traefik.yml, traefik_dynamic.yml, .env, letsencrypt/)
    ├── portainer/            # Docker UI
    ├── pi-hole/              # LAN DNS
    ├── wg-easy/              # WireGuard VPN (split tunnel)
    ├── dashboard/            # Launcher page at /infra (nginx, static html/)
    ├── privacy-policy/       # Go server for the privacy policies (policies/*.md)
    ├── update-ddns/          # Host cron script: updates IONOS DynamicDNS on IP change
    └── waha/                 # WhatsApp HTTP API data (env + sessions only)
```

## 🚀 Quick Start

```bash
./manage.sh start              # traefik first, then other infra, then apps
./manage.sh start portfolio    # one service
./manage.sh status             # what is running
./manage.sh help               # all commands
```

Without the script, start Traefik first (it creates the shared `traefik-network`), then `docker compose up -d` in each service dir.

## 🌐 Accessing Services

**Start from the infra dashboard: <https://danilocatone.com/infra/>** (basic auth). It links every service, so there is no need to remember ports.

| Service | URL |
|---------|-----|
| Infra dashboard | <https://danilocatone.com/infra/> (basic auth) |
| Portfolio (also `/`) | <https://danilocatone.com/portfolio/> |
| Other apps | `https://danilocatone.com/<app>/` (wedding-photos, whatsapp-assistant, prova, dls-platform, ...) |
| Privacy policies | <https://danilocatone.com/privacy-policy/> |
| Traefik dashboard | `http://192.168.1.101:8081` (LAN/VPN, no auth) |
| Portainer | `https://192.168.1.101:9443` / `http://192.168.1.101:9000` |
| Pi-hole admin | `http://192.168.1.101:8080/admin` |
| wg-easy UI | `http://192.168.1.101:51821` (VPN on 51820/udp) |

`192.168.1.101` is the server on the home LAN: these URLs work from home or through the VPN.

## 🧭 Infra Dashboard (`infra/dashboard`)

A static page (nginx + HTML/CSS/JS) at `/infra/`, protected by the `services` basic auth.

- **Infrastructure**: hand-written list in `infra/dashboard/html/services.js` (wg-easy, Portainer, Pi-hole, Traefik) with LAN URLs built from `LAN_HOST`. Edit the file and reload, no restart needed.
- **Apps**: discovered automatically. The page reads the routers from the Traefik API (exposed read-only at `/infra/api/*`, same auth) and shows one card per top-level path. A new app with Traefik labels shows up by itself; a stopped app disappears. Apps whose routers use a basic auth middleware get a "login" badge.

Services without Traefik routes (wg-easy, Portainer, Pi-hole) open in a new tab instead of an iframe: an https page cannot embed `http://` LAN URLs, and their session cookies would not be sent inside a cross-site iframe.

## 🔐 Basic Auth (`services` middleware)

Used by `/infra`. The user and bcrypt hash live in `infra/traefik/.env`, not in the repo:

```bash
docker run --rm -it httpd:2.4-alpine htpasswd -nBC 12 <user>   # prompts for the password
```

Put the printed line in `infra/traefik/.env` **single-quoted, with single `$`**:

```env
TRAEFIK_BASIC_AUTH_USERS='<user>:$2y$12$...'
```

Then recreate Traefik (`cd infra/traefik && docker compose up -d`, every site is down for a few seconds). `traefik_dynamic.yml` reads it with `{{ env "TRAEFIK_BASIC_AUTH_USERS" }}`. Check: `curl -s localhost:8081/api/http/middlewares/services@file` must report `"status":"enabled"`.

## 🔒 VPN (`infra/wg-easy`)

wg-easy v15. Clients use a **split tunnel**: only `10.8.0.0/24` (VPN) and `192.168.1.0/24` (home LAN) go through the tunnel, while normal internet traffic stays on the client's own connection.

- Clients, keys, hooks and allowed IPs are stored in the wg-easy database (`infra/wg-easy/wg-easy/`, git-ignored). **Back up that dir**: losing it means new server keys and re-importing every client.
- The `INIT_*` variables in `compose.yaml` only apply on the first start with an empty database. Admin credentials come from `infra/wg-easy/.env` (see `.env.sample`).
- Allowed IPs of an existing client are changed in the UI; then re-import the config/QR on the device.
- `gw_priority: 1` on `traefik-network` makes it the container's default route, where wg-easy's NAT rule applies. Without it, VPN traffic to the internet/LAN is dropped.
- wg-easy v15 cannot run under a subpath, so it has no Traefik route: use the LAN URL.

## 🎮 Management Script

`manage.sh` auto-discovers services: every `infra/*/` dir and every `apps/**` dir that contains a `docker-compose.yml` or `compose.yaml` (for apps, recursion stops at the first compose file found). It runs `docker compose` inside the service dir, so that dir's `.env` (including `COMPOSE_FILE` / `COMPOSE_PROJECT_NAME`) applies.

```bash
./manage.sh bootstrap <name>                 # scaffold a new app (FastAPI BE + HTML FE)
./manage.sh start|stop|restart [service]     # all if omitted
./manage.sh build|rebuild [service]          # all APPS if omitted (infra untouched)
./manage.sh pull [service] [--build|--rebuild]  # git pull of THIS repo only, then optional build
./manage.sh logs <service> [-f]
./manage.sh status | ps | services
./manage.sh init                             # build + start everything
./manage.sh clean                            # down all + docker system prune -f (system-wide!)
```

Details and known quirks: [scripts/README.md](scripts/README.md).

## ⚙️ Ports

Shared host ports and the domain are in `infra/ports.env` (`TRAEFIK_DOMAIN`, `TRAEFIK_HTTP_PORT=80`, `TRAEFIK_HTTPS_PORT=443`, `TRAEFIK_DASHBOARD_PORT=8081`, `PORTAINER_*`, `APP_INTERNAL_PORT=8000`). Full list of host ports in `infra/ports.yml`.

Apps should be reached only through Traefik (80/443). Some stacks also publish ports on the host (pi-hole, portainer, wg-easy, privacy-policy 4100, some app/DB ports); see `ports.yml`.

## 🔒 HTTPS Certificate (Let's Encrypt)

Traefik gets and renews the wildcard certificate (`danilocatone.com` + `*.danilocatone.com`) **by itself**, using Let's Encrypt with the **DNS-01 challenge**: it proves it owns the domain by creating a temporary `_acme-challenge` TXT record through the API of the DNS provider. No ports need to be reachable from the internet for the validation, and wildcards are supported.

How the pieces fit together:

| File | Role |
|------|------|
| `infra/traefik/traefik.yml` | Defines the `letsencrypt` resolver: account email, DNS provider name, storage |
| `infra/traefik/traefik_dynamic.yml` | The `api` router requests the certificate (`certResolver` + `domains`). All other routers use it through SNI matching |
| `infra/traefik/docker-compose.yml` | Passes the provider credentials to the container and mounts `./letsencrypt` |
| `infra/traefik/.env` | Provider API keys + basic auth users (git-ignored) |
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

## 🔍 How Routing Works

> 💡 Full reference: [Traefik Cheatsheet](infra/README.md).

- Entrypoints: `web` (:80, permanent redirect to HTTPS) and `websecure` (:443).
- Providers: Docker labels (`exposedByDefault=false`) + file provider (`infra/traefik/traefik_dynamic.yml`, hot reloaded).
- `traefik_dynamic.yml` holds the `root-redirect` router (`/` → `/portfolio/`), the `api` router (on `traefik.danilocatone.com`, which has no DNS record: it is kept only to request the wildcard certificate) and shared middlewares (`services` basic auth, `compress`, `hsts`).
- Networks: shared external `traefik-network` + a private network per app (DBs stay off `traefik-network`).

Label template for an app (current convention):

```yaml
labels:
  - "traefik.enable=true"
  - "traefik.docker.network=traefik-network"
  - "traefik.http.routers.<app>.rule=PathPrefix(`/<app>`)"
  - "traefik.http.routers.<app>.entrypoints=websecure"
  - "traefik.http.routers.<app>.tls=true"            # wildcard cert served via SNI, no certresolver needed
  - "traefik.http.routers.<app>.middlewares=<app>-slash,<app>-strip"
  - "traefik.http.middlewares.<app>-slash.redirectregex.regex=^https?://([^/]+)/<app>$$"
  - "traefik.http.middlewares.<app>-slash.redirectregex.replacement=https://$${1}/<app>/"
  - "traefik.http.middlewares.<app>-slash.redirectregex.permanent=true"
  - "traefik.http.middlewares.<app>-strip.stripprefix.prefixes=/<app>"
  - "traefik.http.services.<app>.loadbalancer.server.port=8000"
```

Either strip the prefix in Traefik **or** make the app aware of it (e.g. FastAPI `root_path`), not both. Router/middleware names are global across all stacks and must be unique. Use `priority` when prefixes overlap (API 100, FE 50).

## 📝 Adding a New Application

1. `./manage.sh bootstrap my-app`: creates `apps/my-app/` with `be/` (FastAPI, `/my-app/api`) and `fe/` (static, `/my-app`) and a compose file with Traefik labels. Or create `apps/my-app/` by hand with a compose file following the template above.
2. Usually `git init` it as its own repo (`apps/` is ignored by this repo).
3. `./manage.sh build my-app && ./manage.sh start my-app`
4. Open `https://danilocatone.com/my-app/`.

## 🐛 Troubleshooting

> 💡 More in the [Traefik troubleshooting section](infra/README.md#debugging--troubleshooting).

- **App not reachable**: `docker ps | grep traefik`; check the router in the dashboard; check the container is on `traefik-network` (`docker network inspect traefik-network`).
- **404**: path does not match the rule, or prefix stripped twice / not at all.
- **502**: wrong `loadbalancer.server.port`, or app listening on `127.0.0.1` instead of `0.0.0.0`.
- **TLS error**: `sniStrict` is on, so use the real hostname (`curl --resolve danilocatone.com:443:127.0.0.1 https://danilocatone.com/...`), not `https://localhost`.
- **Logs**: `./manage.sh logs <service> -f` or `docker logs traefik 2>&1 | grep -i <name>`.

## 📚 Resources

- [Traefik Cheatsheet](infra/README.md) · [Scripts](scripts/README.md) · [Bootstrap](scripts/commands/bootstrap/README.md)
- [Traefik docs](https://doc.traefik.io/traefik/) · [Docker Compose](https://docs.docker.com/compose/) · [Portainer](https://docs.portainer.io/) · [wg-easy](https://github.com/wg-easy/wg-easy) · [Pi-hole](https://docs.pi-hole.net/)
