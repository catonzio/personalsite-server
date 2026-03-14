#!/bin/bash

# Service Utility Functions
# Functions for working with services - paths, containers, validation

get_service_path() {
    local service=$1
    
    # Check infrastructure directory
    if [ -d "infra/$service" ] && { [ -f "infra/$service/docker-compose.yml" ] || [ -f "infra/$service/compose.yaml" ]; }; then
        echo "infra/$service"
        return 0
    fi
    
    # Check apps directory
    if [ -d "apps/$service" ] && { [ -f "apps/$service/docker-compose.yml" ] || [ -f "apps/$service/compose.yaml" ]; }; then
        echo "apps/$service"
        return 0
    fi
    
    # Service not found
    return 1
}

service_exists() {
    local service=$1
    get_service_path "$service" > /dev/null 2>&1
    return $?
}

get_service_containers() {
    local service=$1
    local path=$(get_service_path "$service" 2>/dev/null)
    
    if [ -z "$path" ] || [ ! -f "$path/docker-compose.yml" ]; then
        return 1
    fi
    
    # Extract container names from docker-compose.yml
    # Look for container_name: entries
    local containers=()
    while IFS= read -r line; do
        if [[ $line =~ container_name:[[:space:]]*([^[:space:]]+) ]]; then
            containers+=("${BASH_REMATCH[1]}")
        fi
    done < "$path/docker-compose.yml"
    
    # Return space-separated list
    echo "${containers[@]}"
}
