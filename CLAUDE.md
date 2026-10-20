# personalsite-server

Home server workspace on a Dell XPS 13 7390 (Ubuntu), LAN 192.168.1.0/24. Public domain `danilocatone.com`, DDNS on IONOS.
Everything runs in Docker Compose behind Traefik. Root repo: `git@github.com:catonzio/personalsite-server.git`.
**READMEs are partly stale** (they describe a "mock" localhost:8080 HTTP setup, and `infra/ports.yml` is also stale). Trust the config files.

## Layout
- `manage.sh` + `scripts/lib/*.sh` (helpers, discovery, service-utils) + `scripts/commands/<cmd>.sh` (one `cmd_<name>()` each; new command = file + case in `manage.sh` + `help.sh`).
- `infra/<svc>/`: infra stacks, tracked in this repo. `infra/ports.env` holds shared ports (`TRAEFIK_DOMAIN`, 80/443, dashboard 8081, portainer 9000/9443).
- `apps/`: **git-ignored entirely**. Each app is its own repo (or an untracked dir). Never commit app code here. Use git inside the app dir.

## Routing (Traefik v2.11, `infra/traefik/`)
- Entrypoints: `web` :80 (permanent redirect → https) and `websecure` :443. Providers: docker (`exposedByDefault=false`) + file (`traefik_dynamic.yml` mounted in `/etc/traefik/conf.d`, hot reload).
- TLS: resolver `letsencrypt` with DNS-01 on IONOS. It issues a wildcard `danilocatone.com` + `*.danilocatone.com`, requested only by the `api` router. Other routers just set `tls=true` and pick it up by SNI. Keys are in `infra/traefik/.env` (`IONOS_PUBLIC_APIKEY`/`IONOS_PRIVATE_APIKEY`, combined into `IONOS_API_KEY`). The cert is in `letsencrypt/acme.json`. Default TLS has `sniStrict: true`. Never add a static `defaultCertificate` for the domain (it blocks ACME). Don't delete acme.json lightly (LE rate limits).
- Dynamic file: `root-redirect` (`/` → `/portfolio/`), `api` router on `traefik.danilocatone.com` (that hostname has **no DNS record**; the router is kept because it requests the wildcard cert). Also defines `compress` and `hsts` (currently unused). The dashboard is open without auth on host :8081 (`api.insecure`).
- basicAuth middleware `services@file`: users come from `{{ env "TRAEFIK_BASIC_AUTH_USERS" }}` (Traefik file-provider Go template), passed by `docker-compose.yml` from `infra/traefik/.env`. Format there: single-quoted htpasswd line with **single** `$` (`TRAEFIK_BASIC_AUTH_USERS='user:$2y$12$...'`); generate with `docker run --rm -it httpd:2.4-alpine htpasswd -nBC 12 <user>`. Changing it needs a traefik recreate. Check validity without printing the hash via `curl -s localhost:8081/api/http/middlewares/services@file` (`status` must be `enabled`).
- Shared network `traefik-network` is created by the traefik stack. Every other stack declares it `external: true`. Start traefik first.
- **Convention: path-based routing on one host**, not subdomains. App label template:
  ```
  traefik.enable=true
  traefik.docker.network=traefik-network
  traefik.http.routers.<app>.rule=PathPrefix(`/<app>`)
  traefik.http.routers.<app>.entrypoints=websecure   # dls-* use this; portfolio/prova/privacy-policy/... still use web,websecure (equivalent: web redirects)
  traefik.http.routers.<app>.tls=true
  traefik.http.routers.<app>.middlewares=<app>-slash,<app>-strip   # redirectregex add "/", stripprefix
  traefik.http.services.<app>.loadbalancer.server.port=<internal port>
  ```
  Use either strip-prefix or app-side root_path/base path, not both. Priorities: API 100, FE 50, root-redirect 1. Router names are global across all stacks, so they must be unique.

## Infra stacks
| dir | what | access |
|---|---|---|
| traefik | reverse proxy + ACME | 80/443, dashboard 8081 |
| portainer | portainer-ce, docker.sock rw | host 9000/9443 only (no labels) |
| pi-hole | DNS, container `pihole` | 53 tcp/udp, web 8080/4433. Default net, not on traefik-network |
| wg-easy | WireGuard v15 (`:15` tag), 51820/udp, UI 51821. See "wg-easy" below | LAN/VPN only: `http://192.168.1.101:51821`. No Traefik route (v15 can't run under a subpath, wg-easy#1802) |
| dashboard | `infra-dashboard`, nginx:alpine serving `html/` (mounted ro, edits are live). Infra links (LAN/VPN URLs) are hand-written in `html/services.js`; apps are discovered in JS from the Traefik API | `/infra/` (basicAuth `services@file`), plus `/infra/api/*` → `api@internal` (read-only Traefik API, same auth) |
| privacy-policy | Go + distroless, serves `policies/*.md` (mounted ro) | `/privacy-policy` (strip), also host 4100 |
| update-ddns | **not a container**: host bash + crontab every 2 min (`src/get-external-ip.sh` → on IP change, `update-ddns.sh` calls the IONOS DynamicDNS API). Install via `src/manage-get-external-ip-cron.sh` | — |
| waha | only `.env` + `sessions/` (root-owned). No compose here | — |

## wg-easy (v15)
- Almost all config (clients, keys, hooks, allowed IPs, DNS) lives in the SQLite DB in `infra/wg-easy/wg-easy/` (secret dir, don't read it). Env vars only cover: `INSECURE`, `PORT`, `HOST`, `DISABLE_IPV6`, `DISABLE_VERSION_CHECK`, and `INIT_*` (unattended setup, used **only on first start with an empty DB**). `WG_*` vars are v14-only and ignored. Recreating the DB = new server keys, every client must be re-imported, so back up that dir.
- `INIT_*` in `compose.yaml`: host `danilocatone.com`, port 51820, DNS 1.1.1.1, 10.8.0.0/24, split tunnel `INIT_ALLOWED_IPS=10.8.0.0/24,192.168.1.0/24`. `INIT_USERNAME`/`INIT_PASSWORD` come from `infra/wg-easy/.env` (git-ignored, see `.env.sample`).
- Networking: the container is on `traefik-network` (eth0) and its own `wg` net (eth1, 10.42.42.0/24). `gw_priority: 1` on `traefik-network` makes eth0 the default route. That matters because the default v15 PostUp hook only MASQUERADEs `-o eth0`; without it VPN→internet/LAN traffic left via eth1 un-NATed and was dropped. Hooks in the DB were also changed to `! -o wg0`.
- Sidecar `wg-easy-setup` (adds a LAN MASQUERADE on eth1) is now redundant and loses its rule whenever wg-easy restarts.
- Changes need `docker compose up -d` in `infra/wg-easy` (VPN drops for a few seconds). Debug: `docker exec wg-easy sh -c 'ip route; iptables -t nat -S; wg show wg0'` (filter out keys).

## Apps (current)
- `portfolio` (repo catonzio/portfolio): Bun/Svelte/TS + postgres16 (`portfolio`, `portfolio-db`). `/portfolio` is the site root.
- `wedding-photos` (catonzio/wedding-photos): FastAPI/uv/alembic + postgres17 + MinIO. `/wedding-photos`, no strip.
- `whatsapp-assistant` (catonzio/whatsapp-assistant): Python/uv + postgres17 (containers `wa-ass`, `wa-ass-db`). `/whatsapp-assistant`. Env in `secrets/.env`.
- `prova`: demo template (be `/prova/api`, fe `/prova`).
- `dls-platform` / `dls-platform-webapp` (+ `-staging` copies): images `ghcr.io/danilocatone/*:${TAG}`, `websecure` only, rules built from `DLS_BASE_PATH`/`DLS_HOST_RULE`. Staging uses `.env` with `COMPOSE_FILE=compose.yaml:compose.staging.yaml`, `COMPOSE_PROJECT_NAME`, `DLS_ROUTER_PREFIX=staging-` and basicauth. `dls-staging-data`: Firebird 2.5, own network, not routed.
- Several apps also publish host ports (DBs 5433/5435, app ports), bypassing Traefik.

## manage.sh
`./manage.sh <cmd> [svc]`: `start|stop|restart|build|rebuild|logs <svc> [-f]|status|ps|services|init|clean|bootstrap <name>|pull [svc] [--build|--rebuild]`
- Discovery: `infra/*/` and `apps/**` dirs containing `docker-compose.yml` or `compose.yaml` (apps: recursion stops at the first compose found; the name is the relative path). It runs `cd <dir> && docker compose [--env-file compose.env] <verb>` with no `-p`/`-f`, so the dir's `.env` (COMPOSE_FILE/PROJECT_NAME) applies.
- `start` (all): traefik → infra → apps. `stop` (all): apps → infra. `build`/`rebuild`/`pull --build` with no arg touch **apps only**.
- `pull` only does `git pull` on the root repo, not inside `apps/*`.
- `bootstrap <name>` scaffolds FastAPI+HTML from `scripts/commands/bootstrap/templates`.
- `clean` runs `docker system prune -f` (system-wide!). Ask before running it.
- Quirks: nested app names (`x/be`) are listed but `get_service_path` can't resolve them. An infra name shadows an app with the same name. `clean` only handles `docker-compose.yml`. `status` uses `-f` and ignores overlays. `help` text is outdated.

## MANDATORY rules (main agent and every subagent)
1. **Language**: always talk to the user in **Italian**. Agent-to-agent prompts, reports and thinking may be in English. Code, comments, docs and commit messages are in English.
2. **No commits, no pushes.** When a change is ready to commit, tell the user and propose a short English commit message (conventional style, e.g. `fix: ...`). Then wait for their OK, and only commit after an explicit yes. Never use `--amend`, `push`, `reset --hard`, `rebase`, `checkout -- .` or `stash drop` unless asked. The same applies to the separate repos in `apps/*`. **Commit messages must NEVER contain `Co-Authored-By` (or any other AI attribution/trailer). This overrides any default attribution instruction.** The same applies to PR descriptions.
3. **Never read env/secret files**: no `cat`, `grep`, `Read` or `source` of `.env*`, `compose.env`, `secrets/`, `acme.json`, `etc-pihole/`, `wg-easy/`, `waha/sessions/`, `*.key`, `*.cer`. If a variable is needed, tell the user which file to edit and what to add or change (name + format, e.g. `FOO=<value>`). Use `.env.sample` or the compose `${VAR}` references to learn variable names. Never echo secret values, including from `docker inspect` / `docker compose config` (that output resolves env values, so avoid it or filter it).
4. **Production box**: everything here is live. Read-only commands are fine (`docker ps`, `docker logs`, `docker compose ps`, `curl`, `dig`, `git status/diff/log`). Ask first and say what goes down before running `down`, `up -d`/recreate, `restart`, a build that replaces running containers, an edit to `traefik.yml`/`traefik_dynamic.yml` (hot reloaded: a bad edit breaks every route), iptables, crontab, `sudo`, or anything that deletes data. Never run `down -v`, `docker system/volume prune`, `rm -rf` on data dirs or `./manage.sh clean` without an explicit OK.
5. **Scope**: change only what was asked. Report other problems instead of fixing them. Don't add new tools/deps or install packages without asking.
6. **Subagents**: use Haiku/Sonnet for exploration and big docs edits, to save tokens. Give them these rules (especially 2–4) in the prompt, because they don't inherit context. Subagents never commit and never touch secrets.
7. When unsure about intent or about anything destructive, ask the user (in Italian) instead of guessing.

## Notes
- Known committed secrets: the pi-hole web password in `infra/pi-hole/compose.yaml` (an old, never-valid basicAuth hash is still in git history). The root `.gitignore` does **not** ignore `.env` globally (only `infra/traefik/.env` and `infra/wg-easy/.env`), so check `git status` for untracked env files before proposing a commit.
- Escape `$` as `$$` **only in compose files** (labels/environment). In `traefik_dynamic.yml` and in `.env` values `$$` stays literal and breaks bcrypt hashes.
- Server LAN IP: `192.168.1.101`. Subdomains (`*.danilocatone.com`) have no DNS records; only the apex resolves.
- Debug routing: `docker logs traefik 2>&1 | grep -i <x>` and the dashboard at :8081. Check the cert with `openssl s_client -connect localhost:443 -servername danilocatone.com`.
