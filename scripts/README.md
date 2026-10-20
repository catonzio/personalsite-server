# Scripts Directory

Modular components of `manage.sh`. The dispatcher `cd`s to the repo root, runs with `set -e`, sources `lib/*.sh`, calls `init_services`, then sources `commands/<cmd>.sh` and runs `cmd_<cmd>` (default: `help`).

## Structure

```text
scripts/
├── lib/
│   ├── helpers.sh        # Colors + print_header/success/error/warning/info
│   ├── discovery.sh      # discover_infra_services, discover_app_services, init_services
│   └── service-utils.sh  # get_service_path, service_exists, get_service_containers
└── commands/
    ├── bootstrap/        # bootstrap.sh + templates/ (see bootstrap/README.md)
    ├── build.sh  clean.sh  help.sh  init.sh  logs.sh  ps.sh  pull.sh
    └── rebuild.sh  restart.sh  services.sh  start.sh  status.sh  stop.sh
```

## Service discovery

- **Infra**: each `infra/*/` dir with `docker-compose.yml` or `compose.yaml`. The name is the dir name. `update-ddns` and `waha` have no compose file, so they are not services.
- **Apps**: depth-first scan of `apps/*/`. A dir with a compose file is a service named by its relative path (`x` or `x/be`), and the scan does not go deeper (so `apps/prova/be` is not a separate service).
- `ALL_SERVICES` = infra + apps. Infra is checked first, so an app with the same name as an infra service is shadowed.
- Compose is invoked as `(cd <dir> && docker compose [--env-file compose.env] <verb>)` with no `-p`/`-f`. The dir's `.env` applies, including `COMPOSE_FILE` / `COMPOSE_PROJECT_NAME` (used by the `*-staging` apps to layer `compose.staging.yaml`).

## Commands

| Command | Behaviour |
|---------|-----------|
| `bootstrap <name>` | Scaffold `apps/<name>` (FastAPI BE + HTML FE + Traefik labels). Name must match `^[a-z0-9-]+$` |
| `init` | `docker info` check, then build all apps, start all, status |
| `start [svc]` | `up -d`. All: traefik first (creates `traefik-network`), then other infra, then apps |
| `stop [svc]` | `down` (volumes kept). All: apps first, then infra |
| `restart [svc]` | stop + start |
| `build [svc]` | `compose build`. All = **apps only** |
| `rebuild [svc]` | `up -d --build`. All = **apps only** |
| `pull [svc] [--build\|--rebuild]` | `git pull` of **this repo only** (not `apps/*` repos), then optional build/rebuild of `svc` or all apps |
| `logs <svc> [-f]` | `logs --tail=100`, or follow |
| `services` / `status` / `ps` | list discovered services / running state per service / `docker ps` filtered by service names |
| `clean` | Asks y/N, stops all, `rm -f`, then **`docker system prune -f` (system-wide)**. Volumes are kept |

## Known quirks

- Nested app names (`x/be`) are listed, but `get_service_path` only resolves `infra/<name>` and `apps/<name>`, so they cannot be targeted individually.
- `clean` and `get_service_containers` only look at `docker-compose.yml` (they skip `compose.yaml`).
- `status` uses `-f <file>`, which ignores `COMPOSE_FILE` overlays. `ps` filters by dir name, so containers with other names (e.g. `wa-ass`) may not show.

## Adding a command

1. Create `commands/mycommand.sh` with `cmd_mycommand()` and the direct-execution guard:

   ```bash
   if [ "${BASH_SOURCE[0]}" = "$0" ]; then
       cmd_mycommand "$@"
   fi
   ```

2. Add the `case` entry in `manage.sh`.
3. Document it in `commands/help.sh` and in the table above.
