#!/bin/bash

# Build Command
# Build one or all application services

cmd_build() {
    local service=$1
    
    if [ -z "$service" ]; then
        print_header "Building All Application Services"
        
        for svc in "${APP_SERVICES[@]}"; do
            cmd_build "$svc"
        done
        
        print_success "All services built!"
    else
        if ! service_exists "$service"; then
            print_error "Service '$service' not found"
            exit 1
        fi
        
        local path=$(get_service_path "$service")
        print_info "Building $service..."
        local env_flag=""
        if [ -f "$path/compose.env" ]; then
            env_flag="--env-file compose.env"
        fi
        (cd "$path" && docker compose $env_flag build)
        print_success "$service built"
    fi
}

# Execute if run directly
if [ "${BASH_SOURCE[0]}" = "$0" ]; then
    cmd_build "$@"
fi
