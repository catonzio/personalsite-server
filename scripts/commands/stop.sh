#!/bin/bash

# Stop Command
# Stop one or all services

cmd_stop() {
    local service=$1
    
    if [ -z "$service" ]; then
        print_header "Stopping All Services"
        
        # Stop apps first, then infrastructure
        for svc in "${APP_SERVICES[@]}"; do
            cmd_stop "$svc"
        done
        
        for svc in "${INFRA_SERVICES[@]}"; do
            cmd_stop "$svc"
        done
        
        print_success "All services stopped!"
    else
        if ! service_exists "$service"; then
            print_error "Service '$service' not found"
            exit 1
        fi
        
        local path=$(get_service_path "$service")
        print_info "Stopping $service..."
        local env_flag=""
        if [ -f "$path/compose.env" ]; then
            env_flag="--env-file compose.env"
        fi
        (cd "$path" && docker compose $env_flag down)
        print_success "$service stopped"
    fi
}

# Execute if run directly
if [ "${BASH_SOURCE[0]}" = "$0" ]; then
    cmd_stop "$@"
fi
