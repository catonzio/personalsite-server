#!/bin/bash

# Service Discovery Functions
# Discovers available infrastructure and application services

discover_infra_services() {
    local services=()
    if [ -d "infra" ]; then
        for dir in infra/*/; do
            if [ -f "${dir}docker-compose.yml" ] || [ -f "${dir}compose.yaml" ]; then
                local service=$(basename "$dir")
                services+=("$service")
            fi
        done
    fi
    echo "${services[@]}"
}

discover_app_services() {
    local services=()
    
    # Recursive function to search for docker-compose.yml files
    # Does depth-first search, stopping each branch when finding a compose file
    find_compose_files() {
        local current_dir="$1"
        local relative_path="$2"
        
        # Check if docker-compose.yml or compose.yaml exists in current directory
        if [ -f "${current_dir}/docker-compose.yml" ] || [ -f "${current_dir}/compose.yaml" ]; then
            # Found a compose file, add this path and stop searching deeper
            services+=("$relative_path")
        else
            # No docker-compose.yml here, recurse into subdirectories
            for subdir in "${current_dir}"/*/; do
                if [ -d "$subdir" ]; then
                    local dirname=$(basename "$subdir")
                    find_compose_files "$subdir" "${relative_path}/${dirname}"
                fi
            done
        fi
    }
    
    if [ -d "apps" ]; then
        for dir in apps/*/; do
            if [ -d "$dir" ]; then
                local app_name=$(basename "$dir")
                find_compose_files "$dir" "$app_name"
            fi
        done
    fi
    
    echo "${services[@]}"
}

# Initialize service arrays
init_services() {
    INFRA_SERVICES=($(discover_infra_services))
    APP_SERVICES=($(discover_app_services))
    ALL_SERVICES=("${INFRA_SERVICES[@]}" "${APP_SERVICES[@]}")
}
