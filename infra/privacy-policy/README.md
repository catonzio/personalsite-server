# privacy-policy

Minimal Go web server (single dependency: [goldmark](https://github.com/yuin/goldmark),
distroless nonroot image) that serves privacy policy pages for the other
apps in this repo, under the `/privacy-policy/` path.

## Why this design

- **Content is authored as Markdown**: `./policies/*.md` is bind-mounted
  read-only into the container. Editing a policy is just editing a `.md`
  file — no rebuild, no redeploy, no HTML to hand-write.
- **Rendered to HTML on every request**: a request for `/name.html` reads
  `policies/name.md`, converts it with goldmark, and wraps it in a small
  shared HTML template (title taken from the first `# Heading`). Any other
  path (e.g. an image) falls back to a plain static file server. Directory
  listing is disabled (a request for a directory without an `index.md`
  returns 404) to avoid leaking the file list.
- **Traefik does the prefix stripping**: the container only ever sees
  root-relative paths (`/`, `/wedding-photos.html`, ...). This matches the
  `stripprefix` pattern already used by `portfolio` and `whatsapp-assistant`,
  so the app itself needs zero knowledge of the `/privacy-policy` prefix.

## Adding a new policy page

Drop a Markdown file into `policies/`, e.g. `policies/my-app.md`, starting
with a `# Title` heading, and link it (as `my-app.html`) from
`policies/index.md`. It's served immediately (no rebuild needed since the
folder is a bind mount) — just refresh the browser.

## Usage

```bash
cd infra/privacy-policy
docker compose up -d --build
```

Then visit:

- `https://<host>/privacy-policy/` — index
- `https://<host>/privacy-policy/wedding-photos.html`
- `https://<host>/privacy-policy/whatsapp-assistant.html`

For local testing without Traefik/HTTPS, the compose file also maps the
container directly to `http://localhost:4100/` (e.g.
`http://localhost:4100/whatsapp-assistant.html`).
