# privacy-policy

Minimal static web server (Go, stdlib only, distroless nonroot image) that
serves privacy policy pages for the other apps in this repo, under the
`/privacy-policy/` path.

## Why this design

- **Files on disk, not baked into the image**: `./policies` is bind-mounted
  read-only into the container. Adding/editing a policy is just adding/
  editing an `.html` file in `policies/` — no rebuild, no redeploy.
- **Go stdlib `net/http.FileServer`**: no framework, no dependencies, ~10MB
  final image, starts in milliseconds. Directory listing is disabled (a
  request for a directory without an `index.html` returns 404) to avoid
  leaking the file list.
- **Traefik does the prefix stripping**: the container only ever sees
  root-relative paths (`/`, `/wedding-photos.html`, ...). This matches the
  `stripprefix` pattern already used by `portfolio` and `whatsapp-assistant`,
  so the app itself needs zero knowledge of the `/privacy-policy` prefix.

## Adding a new policy page

Drop an HTML file into `policies/`, e.g. `policies/my-app.html`, and link it
from `policies/index.html`. It's served immediately (no rebuild needed since
the folder is a bind mount) — just refresh the browser.

## Usage

```bash
cd infra/privacy-policy
docker compose up -d --build
```

Then visit:

- `https://<host>/privacy-policy/` — index
- `https://<host>/privacy-policy/wedding-photos.html`
- `https://<host>/privacy-policy/whatsapp-assistant.html`
