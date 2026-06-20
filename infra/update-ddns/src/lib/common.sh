#!/usr/bin/env bash

init_logging() {
  local default_log_file="${1:-update-ddns.log}"
  LOG_FILE="${LOG_FILE:-${default_log_file}}"
}

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
  # log_info "Validated dependency: ${cmd}."
}
