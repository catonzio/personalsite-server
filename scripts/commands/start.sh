#!/bin/bash

# Start Command
# Start one or all services

cmd_start() {
    local service=$1
    
    if [ -z "$service" ]; then
        print_header "Starting All Services"
        
        # Start traefik first if it exists (it creates the shared network)
        if [[ " ${INFRA_SERVICES[@]} " =~ " traefik " ]]; then
            print_info "Starting traefik (creates shared network)..."
            cmd_start "traefik"
            echo ""
        fi
        
        # Start remaining infrastructure services
        print_info "Starting infrastructure services..."
        for svc in "${INFRA_SERVICES[@]}"; do
            if [ "$svc" != "traefik" ]; then
                cmd_start "$svc"
            fi
        done
        
        echo ""
        print_info "Starting application services..."
        for svc in "${APP_SERVICES[@]}"; do
            cmd_start "$svc"
        done
        
        echo ""
        print_success "All services started!"
        source "$SCRIPT_DIR/scripts/commands/status.sh"
        cmd_status
    else
        if ! service_exists "$service"; then
            print_error "Service '$service' not found"
            exit 1
        fi
        
        local path=$(get_service_path "$service")
        print_info "Starting $service..."
        local env_flag=""
        if [ -f "$path/compose.env" ]; then
            env_flag="--env-file compose.env"
        fi
        (cd "$path" && docker compose $env_flag up -d)
        print_success "$service started"
    fi
}

# Execute if run directly
if [ "${BASH_SOURCE[0]}" = "$0" ]; then
    cmd_start "$@"
fi
