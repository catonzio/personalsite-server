#!/usr/bin/env bash
set -euo pipefail

SERVER_URL="https://api.hosting.ionos.com/dns"
DDNS_URL="${SERVER_URL}/v1/dyndns"
DEFAULT_LOG_FILE="update-ddns.log"

LOG_FILE="${LOG_FILE:-${DEFAULT_LOG_FILE}}"

log_message() {
  local severity="$1"
  local message="$2"
  local timestamp
  timestamp="$(date '+%Y-%m-%d %H:%M:%S')"
  printf '[%s] [%s] %s\n' "${timestamp}" "${severity}" "${message}" >> "${LOG_FILE}"
}

log_info() {
  log_message "INFO" "$1"
}

log_warn() {
  log_message "WARN" "$1"
}

log_error() {
  log_message "ERROR" "$1"
}

log_last_line() {
  printf "\n" >> "${LOG_FILE}"
}

on_error() {
  local exit_code="$1"
  local line_no="$2"
  log_error "Script failed at line ${line_no} with exit code ${exit_code}."
}

require_cmd() {
  local cmd="$1"
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo "Error: required command '$cmd' is not installed." >&2
    log_error "Missing required command: ${cmd}."
    log_last_line
    exit 1
  fi
  log_info "Validated dependency: ${cmd}."
}

load_env_settings() {
  if [[ -f .env ]]; then
    # Export vars from .env into current shell.
    set -a
    # shellcheck disable=SC1091
    source .env
    set +a
    log_info "Loaded environment variables from .env file."
  else
    log_warn ".env file not found. Using current shell environment values."
  fi

  : "${IONOS_PUBLIC_APIKEY:?IONOS_PUBLIC_APIKEY is required}"
  : "${IONOS_PRIVATE_APIKEY:?IONOS_PRIVATE_APIKEY is required}"
  : "${DOMAINS:?DOMAINS is required and must be a JSON array, e.g. [\"example.com\"]}"

  if ! jq -e 'type == "array" and all(.[]; type == "string")' >/dev/null 2>&1 <<<"${DOMAINS}"; then
    echo "Error: DOMAINS must be a JSON array of strings." >&2
    log_error "DOMAINS validation failed; expected JSON array of strings."
    log_last_line
    exit 1
  fi

  API_KEY="${IONOS_PUBLIC_APIKEY}.${IONOS_PRIVATE_APIKEY}"
  log_info "Environment validated successfully."
}

build_body() {
  jq -cn --argjson domains "${DOMAINS}" '{domains: $domains, description: "DynamicDNS"}'
}

get_update_url() {
  local body response_code response_body
  body="$(build_body)"
  log_info "Requesting update URL from IONOS API."

  response_body="$(mktemp)"
  response_code="$(curl -sS -o "${response_body}" -w "%{http_code}" \
    -X POST "${DDNS_URL}" \
    -H "Content-Type: application/json" \
    -H "X-API-Key: ${API_KEY}" \
    --data "${body}")"

  if [[ "${response_code}" == "200" ]]; then
    UPDATE_URL="$(jq -r '.updateUrl // empty' <"${response_body}")"
    rm -f "${response_body}"
    if [[ -z "${UPDATE_URL}" ]]; then
      echo "Error: response did not include updateUrl." >&2
      log_error "IONOS API response missing updateUrl field."
      log_last_line
      exit 1
    fi
    log_info "Received update URL successfully."
  else
    rm -f "${response_body}"
    echo "Error: response returned with status code ${response_code} while retrieving update URL." >&2
    log_error "Failed to retrieve update URL; HTTP status ${response_code}"
    log_last_line
    exit 1
  fi
}

make_update() {
  local response_code
  log_info "Submitting DNS update request."
  response_code="$(curl -sS -o /dev/null -w "%{http_code}" "${UPDATE_URL}")"
  if [[ "${response_code}" == "200" ]]; then
    log_info "DNS update request completed with status 200."
  else
    log_error "DNS update request failed with status ${response_code}."
  fi
  [[ "${response_code}" == "200" ]]
}

main() {
  trap 'on_error "$?" "$LINENO"' ERR

  log_info "Starting update-ddns execution."
  log_info "Logs are being appended to ${LOG_FILE}."

  require_cmd curl
  require_cmd jq

  echo -n "Loading API key... "
  load_env_settings
  echo "Done!"
  log_info "API key loaded and configuration initialized."

  echo -n "Fetching update url... "
  get_update_url
  echo "Done!"
  log_info "Update URL fetched."

  echo -n "Updating DNS entry... "
  if make_update; then
    echo "Done!"
    log_info "DNS entry update completed successfully."
  else
    echo "Error!"
    log_error "DNS entry update did not complete successfully."
    log_last_line
    exit 1
  fi

  log_info "Execution completed successfully."
  log_last_line
}

main "$@"
