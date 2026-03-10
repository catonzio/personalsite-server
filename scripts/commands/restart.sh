#!/bin/bash

# Restart Command
# Restart one or all services

cmd_restart() {
    local service=$1
    
    if [ -z "$service" ]; then
        print_header "Restarting All Services"
        source "$SCRIPT_DIR/scripts/commands/stop.sh"
        cmd_stop
        sleep 2
        source "$SCRIPT_DIR/scripts/commands/start.sh"
        cmd_start
    else
        if ! service_exists "$service"; then
            print_error "Service '$service' not found"
            exit 1
        fi
        
        print_header "Restarting $service"
        source "$SCRIPT_DIR/scripts/commands/stop.sh"
        cmd_stop "$service"
        sleep 1
        source "$SCRIPT_DIR/scripts/commands/start.sh"
        cmd_start "$service"
    fi
}

# Execute if run directly
if [ "${BASH_SOURCE[0]}" = "$0" ]; then
    cmd_restart "$@"
fi
