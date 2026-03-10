#!/bin/bash

# Personal Server Management Script
# Main dispatcher - sources libraries and routes commands

set -e

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Source library files
source "$SCRIPT_DIR/scripts/lib/helpers.sh"
source "$SCRIPT_DIR/scripts/lib/discovery.sh"
source "$SCRIPT_DIR/scripts/lib/service-utils.sh"

# Initialize services
init_services

# Main command dispatcher
case "${1:-help}" in
    bootstrap)
        source "$SCRIPT_DIR/scripts/commands/bootstrap/bootstrap.sh"
        cmd_bootstrap "${2:-}"
        ;;
    init)
        source "$SCRIPT_DIR/scripts/commands/init.sh"
        cmd_init
        ;;
    start)
        source "$SCRIPT_DIR/scripts/commands/start.sh"
        cmd_start "${2:-}"
        ;;
    stop)
        source "$SCRIPT_DIR/scripts/commands/stop.sh"
        cmd_stop "${2:-}"
        ;;
    restart)
        source "$SCRIPT_DIR/scripts/commands/restart.sh"
        cmd_restart "${2:-}"
        ;;
    build)
        source "$SCRIPT_DIR/scripts/commands/build.sh"
        cmd_build "${2:-}"
        ;;
    rebuild)
        source "$SCRIPT_DIR/scripts/commands/rebuild.sh"
        cmd_rebuild "${2:-}"
        ;;
    logs)
        source "$SCRIPT_DIR/scripts/commands/logs.sh"
        cmd_logs "${2:-}" "${3:-}"
        ;;
    status)
        source "$SCRIPT_DIR/scripts/commands/status.sh"
        cmd_status
        ;;
    ps)
        source "$SCRIPT_DIR/scripts/commands/ps.sh"
        cmd_ps
        ;;
    clean)
        source "$SCRIPT_DIR/scripts/commands/clean.sh"
        cmd_clean
        ;;
    help|--help|-h)
        source "$SCRIPT_DIR/scripts/commands/help.sh"
        show_help
        ;;
    *)
        print_error "Unknown command: $1"
        echo ""
        source "$SCRIPT_DIR/scripts/commands/help.sh"
        show_help
        exit 1
        ;;
esac
