#!/bin/bash

# Service Discovery Functions
# Discovers available infrastructure and application services

discover_infra_services() {
    local services=()
    if [ -d "infra" ]; then
        for dir in infra/*/; do
            if [ -f "${dir}docker-compose.yml" ]; then
                local service=$(basename "$dir")
                services+=("$service")
            fi
        done
    fi
    echo "${services[@]}"
}

discover_app_services() {
    local services=()
    if [ -d "apps" ]; then
        for dir in apps/*/; do
            if [ -f "${dir}docker-compose.yml" ]; then
                local service=$(basename "$dir")
                services+=("$service")
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
