#!/bin/bash

# Init Command
# Initialize the environment

cmd_init() {
    print_header "Initializing Environment"
    
    # Check if docker is running
    if ! docker info > /dev/null 2>&1; then
        print_error "Docker is not running. Please start Docker and try again."
        exit 1
    fi
    
    print_success "Docker is running"
    
    # Build all applications
    print_info "Building all application images..."
    source "$SCRIPT_DIR/scripts/commands/build.sh"
    cmd_build
    
    # Start all services
    print_info "Starting all services..."
    source "$SCRIPT_DIR/scripts/commands/start.sh"
    cmd_start
    
    echo ""
    print_success "Environment initialized successfully!"
    echo ""
    source "$SCRIPT_DIR/scripts/commands/status.sh"
    cmd_status
}

# Execute if run directly
if [ "${BASH_SOURCE[0]}" = "$0" ]; then
    cmd_init
fi
