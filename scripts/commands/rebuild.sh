#!/bin/bash

# Rebuild Command
# Rebuild and restart one or all application services

cmd_rebuild() {
    local service=$1
    
    if [ -z "$service" ]; then
        print_header "Rebuilding and Restarting All Application Services"
        
        for svc in "${APP_SERVICES[@]}"; do
            cmd_rebuild "$svc"
        done
        
        print_success "All services rebuilt and restarted!"
    else
        if ! service_exists "$service"; then
            print_error "Service '$service' not found"
            exit 1
        fi
        
        print_header "Rebuilding and Restarting $service"
        local path=$(get_service_path "$service")
        print_info "Rebuilding $service..."
        (cd "$path" && docker compose up -d --build)
        print_success "$service rebuilt and restarted"
    fi
}

# Execute if run directly
if [ "${BASH_SOURCE[0]}" = "$0" ]; then
    cmd_rebuild "$@"
fi
