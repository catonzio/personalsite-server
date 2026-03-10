#!/bin/bash

# PS Command
# Show running containers

cmd_ps() {
    print_header "Running Containers"
    
    # Build dynamic filter pattern from discovered services
    local filter_pattern=""
    for svc in "${ALL_SERVICES[@]}"; do
        if [ -z "$filter_pattern" ]; then
            filter_pattern="${svc}"
        else
            filter_pattern="${filter_pattern}|${svc}"
        fi
    done
    
    if [ -z "$filter_pattern" ]; then
        print_warning "No services discovered"
        return
    fi
    
    docker ps --filter "name=${filter_pattern}" --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"
}

# Execute if run directly
if [ "${BASH_SOURCE[0]}" = "$0" ]; then
    cmd_ps
fi
