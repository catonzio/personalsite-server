#!/bin/bash

# Help Command
# Show usage information

show_help() {
    cat << EOF
Personal Server Management Script
Auto-discovers services from infra/ and apps/ directories

Usage: $0 <command> [service] [options]

Commands:
  bootstrap <name>   Create a new app with FastAPI backend and HTML frontend
  init               Initialize the environment (build and start all services)
  start [service]    Start service(s) - all if no service specified
  stop [service]     Stop service(s) - all if no service specified
  restart [service]  Restart service(s) - all if no service specified
  build [service]    Build service(s) - all apps if no service specified
  rebuild [service]  Rebuild and restart service(s)
  logs <service> [-f]  Show logs for a service (use -f to follow)
  status             Show status of all services
  ps                 Show running containers
  clean              Stop all services and clean up Docker resources
  help               Show this help message

Currently Discovered Services:
EOF
    
    if [ ${#INFRA_SERVICES[@]} -gt 0 ]; then
        echo "  Infrastructure: ${INFRA_SERVICES[@]}"
    else
        echo "  Infrastructure: (none found)"
    fi
    
    if [ ${#APP_SERVICES[@]} -gt 0 ]; then
        echo "  Applications:   ${APP_SERVICES[@]}"
    else
        echo "  Applications:   (none found)"
    fi
    
    cat << EOF

How to add new services:
  1. Create a new directory under apps/ or infra/
  2. Add a docker-compose.yml file
  3. The script will automatically discover it!

Examples:
  $0 bootstrap my-new-app      # Create a new app called "my-new-app"
  $0 init                      # Initialize everything
  $0 start                     # Start all services
  $0 start portfolio           # Start only portfolio
  $0 stop small-games          # Stop small-games
  $0 restart traefik           # Restart traefik
  $0 rebuild portfolio         # Rebuild and restart portfolio
  $0 logs portfolio            # Show portfolio logs
  $0 logs traefik -f           # Follow traefik logs
  $0 status                    # Show status of all services

EOF
}

# Execute if run directly
if [ "${BASH_SOURCE[0]}" = "$0" ]; then
    show_help
fi
