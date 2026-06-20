#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
TARGET_SCRIPT="${PROJECT_ROOT}/src/get-external-ip.sh"
CRON_TAG="# managed-by-update-ddns-get-external-ip"
CRON_SCHEDULE="*/2 * * * *"
CRON_COMMAND="cd ${PROJECT_ROOT} && ${TARGET_SCRIPT}"
CRON_ENTRY="${CRON_SCHEDULE} ${CRON_COMMAND} ${CRON_TAG}"

require_cmd() {
  local cmd="$1"
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo "Error: required command '$cmd' is not installed." >&2
    exit 1
  fi
}

get_current_crontab() {
  crontab -l 2>/dev/null || true
}

write_crontab() {
  local content="$1"

  if [[ -n "${content}" ]]; then
    printf '%s\n' "${content}" | crontab -
  else
    crontab -r 2>/dev/null || true
  fi
}

filter_managed_entries() {
  local content="$1"
  printf '%s\n' "${content}" | grep -vF "${CRON_TAG}" || true
}

install_cron() {
  local current filtered

  if [[ ! -x "${TARGET_SCRIPT}" ]]; then
    echo "Error: target script is missing or not executable: ${TARGET_SCRIPT}" >&2
    exit 1
  fi

  current="$(get_current_crontab)"
  filtered="$(filter_managed_entries "${current}")"

  if [[ -n "${filtered}" ]]; then
    write_crontab "${filtered}"$'\n'"${CRON_ENTRY}"
  else
    write_crontab "${CRON_ENTRY}"
  fi

  echo "Installed cron job (every 2 minutes):"
  echo "${CRON_ENTRY}"
}

uninstall_cron() {
  local current filtered

  current="$(get_current_crontab)"
  if [[ -z "${current}" ]]; then
    echo "No crontab found. Nothing to uninstall."
    return 0
  fi

  filtered="$(filter_managed_entries "${current}")"
  if [[ "${filtered}" == "${current}" ]]; then
    echo "Managed get-external-ip cron job was not found."
    return 0
  fi

  write_crontab "${filtered}"
  echo "Uninstalled managed get-external-ip cron job."
}

status_cron() {
  local current

  current="$(get_current_crontab)"
  if grep -Fq "${CRON_TAG}" <<<"${current}"; then
    echo "Installed managed cron entry:"
    grep -F "${CRON_TAG}" <<<"${current}"
  else
    echo "Managed get-external-ip cron job is not installed."
  fi
}

usage() {
  cat <<'EOF'
Usage:
  ./src/manage-get-external-ip-cron.sh install
  ./src/manage-get-external-ip-cron.sh uninstall
  ./src/manage-get-external-ip-cron.sh status

This script manages a cron job that runs get-external-ip every 2 minutes.
EOF
}

main() {
  require_cmd crontab

  case "${1:-}" in
    install)
      install_cron
      ;;
    uninstall)
      uninstall_cron
      ;;
    status)
      status_cron
      ;;
    *)
      usage
      exit 1
      ;;
  esac
}

main "$@"
