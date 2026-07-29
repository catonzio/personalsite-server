#!/bin/bash

# Pull Command
# Pull from git (repo root), then optionally build or rebuild+restart app services
#
# Usage: cmd_pull [service] [--build|--rebuild]
#   --build    build after pulling (no restart)
#   --rebuild  build and restart after pulling

cmd_pull() {
    local service=""
    local mode=""

    # Parse arguments
    for arg in "$@"; do
        case "$arg" in
            --build)   mode="build" ;;
            --rebuild) mode="rebuild" ;;
            *)         service="$arg" ;;
        esac
    done

    # Always git pull from repo root
    print_header "Git Pull"
    print_info "Pulling latest changes from git..."
    git -C "$SCRIPT_DIR" pull
    print_success "Git pull complete"

    [ -z "$mode" ] && return 0

    if [ -z "$service" ]; then
        # Apply to all app services
        for svc in "${APP_SERVICES[@]}"; do
            _pull_apply_mode "$svc" "$mode"
        done
        print_success "All app services ${mode}ed"
    else
        if ! service_exists "$service"; then
            print_error "Service '$service' not found"
            exit 1
        fi
        _pull_apply_mode "$service" "$mode"
    fi
}

_pull_apply_mode() {
    local service=$1
    local mode=$2
    local path
    path=$(get_service_path "$service")
    local env_flag=""
    if [ -f "$path/compose.env" ]; then
        env_flag="--env-file compose.env"
    fi

    if [ "$mode" = "rebuild" ]; then
        print_header "Rebuilding and restarting $service"
        (cd "$path" && docker compose $env_flag up -d --build)
        print_success "$service rebuilt and restarted"
    elif [ "$mode" = "build" ]; then
        print_header "Building $service"
        (cd "$path" && docker compose $env_flag build)
        print_success "$service built"
    fi
}

# Execute if run directly
if [ "${BASH_SOURCE[0]}" = "$0" ]; then
    cmd_pull "$@"
fi
