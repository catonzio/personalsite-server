#!/bin/bash

# Clean Command
# Clean up Docker resources

cmd_clean() {
    print_header "Cleaning Up"
    print_warning "This will remove stopped containers, unused networks, and dangling images"
    read -p "Continue? (y/N) " -n 1 -r
    echo
    
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        print_info "Stopping all services..."
        source "$SCRIPT_DIR/scripts/commands/stop.sh"
        cmd_stop
        
        print_info "Removing containers..."
        # Dynamically remove containers from all discovered services
        for svc in "${INFRA_SERVICES[@]}"; do
            if [ -f "infra/$svc/docker-compose.yml" ]; then
                docker-compose -f "infra/$svc/docker-compose.yml" rm -f 2>/dev/null || true
            fi
        done
        
        for svc in "${APP_SERVICES[@]}"; do
            if [ -f "apps/$svc/docker-compose.yml" ]; then
                docker-compose -f "apps/$svc/docker-compose.yml" rm -f 2>/dev/null || true
            fi
        done
        
        print_info "Pruning Docker system..."
        docker system prune -f
        
        print_success "Cleanup complete!"
    else
        print_info "Cleanup cancelled"
    fi
}

# Execute if run directly
if [ "${BASH_SOURCE[0]}" = "$0" ]; then
    cmd_clean
fi
