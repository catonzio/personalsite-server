#!/bin/bash

# Logs Command
# Show logs for a service

cmd_logs() {
    local service=$1
    local follow=${2:-false}
    
    if [ -z "$service" ]; then
        print_error "Please specify a service name"
        echo "Usage: $0 logs <service> [follow]"
        exit 1
    fi
    
    if ! service_exists "$service"; then
        print_error "Service '$service' not found"
        exit 1
    fi
    
    local path=$(get_service_path "$service")
    print_info "Showing logs for $service..."
    
    if [ "$follow" = "follow" ] || [ "$follow" = "-f" ]; then
        (cd "$path" && docker compose logs -f)
    else
        (cd "$path" && docker compose logs --tail=100)
    fi
}

# Execute if run directly
if [ "${BASH_SOURCE[0]}" = "$0" ]; then
    cmd_logs "$@"
fi
