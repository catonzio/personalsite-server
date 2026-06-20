#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
DEFAULT_LOG_FILE="${PROJECT_ROOT}/get-external-ip.log"
DEFAULT_STATE_FILE="${PROJECT_ROOT}/external-ip.last"
DEFAULT_UPDATE_DDNS_SCRIPT="${SCRIPT_DIR}/update-ddns.sh"

# shellcheck disable=SC1091
source "${SCRIPT_DIR}/lib/common.sh"

STATE_FILE="${STATE_FILE:-${DEFAULT_STATE_FILE}}"
UPDATE_DDNS_SCRIPT="${UPDATE_DDNS_SCRIPT:-${DEFAULT_UPDATE_DDNS_SCRIPT}}"

is_valid_ipv4() {
  local ip="$1"
  local octet

  [[ "$ip" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]] || return 1

  IFS='.' read -r -a octets <<<"$ip"
  for octet in "${octets[@]}"; do
    (( octet >= 0 && octet <= 255 )) || return 1
  done
}

fetch_external_ip() {
  local provider response
  local -a providers=(
    "https://checkip.amazonaws.com"
    "https://ifconfig.me/ip"
    "https://api.ipify.org"
  )

  for provider in "${providers[@]}"; do
    log_info "Trying external IP provider: ${provider}."
    response="$(curl -fsS --max-time 5 "$provider" || true)"
    response="${response//$'\r'/}"
    response="${response//$'\n'/}"

    if [[ -n "$response" ]] && is_valid_ipv4 "$response"; then
      log_info "Provider ${provider} returned valid IPv4: ${response}."
      printf '%s\n' "$response"
      return 0
    fi

    if [[ -z "$response" ]]; then
      log_warn "Provider ${provider} returned an empty response."
    else
      log_warn "Provider ${provider} returned an invalid IPv4 value: ${response}."
    fi
  done

  log_error "All external IP providers failed to return a valid IPv4 address."
  return 1
}

read_last_ip() {
  if [[ ! -f "${STATE_FILE}" ]]; then
    log_info "State file not found, first run expected: ${STATE_FILE}."
    return 0
  fi

  log_info "Reading last IP from state file: ${STATE_FILE}."
  tr -d '\r\n' <"${STATE_FILE}"
}

save_current_ip() {
  mkdir -p "$(dirname "${STATE_FILE}")"
  printf '%s\n' "$1" >"${STATE_FILE}"
  log_info "Persisted current external IPv4 to state file: ${STATE_FILE}."
}

run_update_ddns() {
  if [[ ! -f "${UPDATE_DDNS_SCRIPT}" ]]; then
    echo "Error: update script not found at ${UPDATE_DDNS_SCRIPT}." >&2
    log_error "Update script not found: ${UPDATE_DDNS_SCRIPT}."
    return 1
  fi

  log_info "IP changed, invoking DDNS update script: ${UPDATE_DDNS_SCRIPT}."
  if bash "${UPDATE_DDNS_SCRIPT}"; then
    log_info "DDNS update script completed successfully."
    return 0
  fi

  log_error "DDNS update script failed."
  return 1
}

main() {
  trap 'on_error "$?" "$LINENO"' ERR

  init_logging "${DEFAULT_LOG_FILE}"
  log_info "Starting get-external-ip execution."
  log_info "Logs are being appended to ${LOG_FILE}."

  require_cmd curl

  local current_ip last_ip

  if ! current_ip="$(fetch_external_ip)"; then
    echo "Error: unable to determine external IPv4 address from known providers." >&2
    log_error "Unable to determine external IPv4 address from known providers."
    log_last_line
    exit 1
  fi

  log_info "Resolved current external IPv4: ${current_ip}."

  last_ip="$(read_last_ip)"
  if [[ -n "${last_ip}" ]] && ! is_valid_ipv4 "${last_ip}"; then
    log_warn "Saved IP in state file is invalid and will be ignored: ${last_ip}."
    last_ip=""
  fi

  if [[ -z "${last_ip}" ]]; then
    printf 'Current external IPv4: %s (first recorded value)\n' "${current_ip}"
    log_info "First IP value recorded: ${current_ip}."
  elif [[ "${last_ip}" == "${current_ip}" ]]; then
    printf 'Current external IPv4: %s (unchanged)\n' "${current_ip}"
    log_info "External IPv4 unchanged: ${current_ip}."
  else
    printf 'External IPv4 changed: %s -> %s\n' "${last_ip}" "${current_ip}"
    log_info "External IPv4 changed from ${last_ip} to ${current_ip}."

    echo "Triggering DDNS update..."
    if run_update_ddns; then
      echo "DDNS update completed."
    else
      echo "Error: DDNS update failed." >&2
      log_last_line
      exit 1
    fi
  fi

  save_current_ip "${current_ip}"
  log_info "Execution completed successfully."
  log_last_line
}

main "$@"