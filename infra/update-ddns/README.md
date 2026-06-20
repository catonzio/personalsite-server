# Update DDNS

This is a little project that helps updating the DNS entries of a IONOS domain when the IP is dynamic.

The repository includes:

1. A Bash implementation (`./src/update-ddns.sh`)
2. A Bash helper to print your current external IPv4 (`./src/get-external-ip.sh`)
3. A shared Bash library for common and logging functions (`./src/lib/common.sh`)
4. A Bash manager to install/uninstall a cron job for the IP helper (`./src/manage-get-external-ip-cron.sh`)

## Installation

1. Get the API key following the [guide](https://developer.hosting.ionos.it/docs/getstarted)
2. Set up the `.env` file:
    1. Copy the file: `cp .env.sample .env`
    2. Update the fields `IONOS_PRIVATE_APIKEY` and `IONOS_PUBLIC_APIKEY` of the `.env` file with your keys
    3. Update the field `DOMAINS` with your domains
3. Follow configuration of official projects: [project](https://www.ionos.it/aiuto/domini/configurare-un-indirizzo-ip/connettere-un-dominio-a-una-rete-con-ip-variabile-utilizzando-il-dns-dinamico-linux/)

### Environment Variables

- `IONOS_PUBLIC_APIKEY` (required)
- `IONOS_PRIVATE_APIKEY` (required)
- `DOMAINS` (required, JSON array of strings)
- `LOG_FILE` (optional, Bash script only; defaults to `update-ddns.log`)
- `STATE_FILE` (optional, external IP helper only; defaults to `external-ip.last` in project root)

Example:

```env
IONOS_PUBLIC_APIKEY=your_public_key
IONOS_PRIVATE_APIKEY=your_private_key
DOMAINS=["example.com","*.example.com"]
LOG_FILE=logs/update-ddns.log
STATE_FILE=state/external-ip.last
```

## Usage

In order to use the program, you should:

1. Ensure required tools are installed:
    - `curl`
    - `jq`
2. Execute the script:

```bash
./src/update-ddns.sh
```

### Bash Script

Run:

```bash
./src/update-ddns.sh
```

Requirements:

- `curl`
- `jq`

The Bash script writes structured logs in append mode to `LOG_FILE`.

Log format:

```text
[YYYY-MM-DD HH:MM:SS] [SEVERITY] message
```

Supported severities:

- `INFO`
- `WARN`
- `ERROR`

Example log lines:

```text
[2026-06-20 09:01:12] [INFO] Starting update-ddns execution.
[2026-06-20 09:01:13] [INFO] Requesting update URL from IONOS API.
[2026-06-20 09:01:14] [ERROR] Failed to retrieve update URL; HTTP status 401.
```

You can inspect the latest entries with:

```bash
tail -n 50 "${LOG_FILE:-update-ddns.log}"
```

### Cron Example (Bash)

```cron
*/5 * * * * cd /path/to/update-ddns && ./src/update-ddns.sh
```

This updates DDNS every 5 minutes and appends execution details to the configured log file.

### External IP Helper Script

Run:

```bash
./src/get-external-ip.sh
```

Requirements:

- `curl`

The script stores the current external IPv4 in a state file and compares it on the next runs.

Output behavior:

- first run: `Current external IPv4: <ip> (first recorded value)`
- unchanged: `Current external IPv4: <ip> (unchanged)`
- changed: `External IPv4 changed: <old> -> <new>`

Defaults:

- state file: `./external-ip.last`
- log file: `./get-external-ip.log`

### Install/Uninstall Cron Job (Every 2 Minutes)

Run:

```bash
./src/manage-get-external-ip-cron.sh install
./src/manage-get-external-ip-cron.sh status
./src/manage-get-external-ip-cron.sh uninstall
```

What it does:

- installs a managed cron entry that runs `./src/get-external-ip.sh` every 2 minutes
- uses a unique tag so only this managed entry is updated/removed
- keeps other existing crontab entries untouched

## References

- [IONOS API DNS Documentation](https://developer.hosting.ionos.it/docs/dns)

## Authors

- Danilo Catone [danilocatone@gmail.com](https://danilocatone.com)
