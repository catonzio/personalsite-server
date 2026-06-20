#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
DEFAULT_LOG_FILE="${PROJECT_ROOT}/get-external-ip.log"
DEFAULT_STATE_FILE="${PROJECT_ROOT}/external-ip.last"

# shellcheck disable=SC1091
source "${SCRIPT_DIR}/lib/common.sh"

STATE_FILE="${STATE_FILE:-${DEFAULT_STATE_FILE}}"

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
    response="$(curl -fsS --max-time 5 "$provider" || true)"
    response="${response//$'\r'/}"
    response="${response//$'\n'/}"

    if [[ -n "$response" ]] && is_valid_ipv4 "$response"; then
      printf '%s\n' "$response"
      return 0
    fi
  done

  return 1
}

read_last_ip() {
  if [[ ! -f "${STATE_FILE}" ]]; then
    return 0
  fi

  tr -d '\r\n' <"${STATE_FILE}"
}

save_current_ip() {
  mkdir -p "$(dirname "${STATE_FILE}")"
  printf '%s\n' "$1" >"${STATE_FILE}"
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
  fi

  save_current_ip "${current_ip}"
  log_info "Saved current external IPv4 to ${STATE_FILE}."
  log_info "Execution completed successfully."
  log_last_line
}

main "$@"