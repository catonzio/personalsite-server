#!/bin/bash

# Status Command
# Show status of all services

get_compose_file() {
    local svc="$1"
    local path
    path=$(get_service_path "$svc" 2>/dev/null) || return 1

    if [ -f "$path/docker-compose.yml" ]; then
        echo "$path/docker-compose.yml"
        return 0
    fi

    if [ -f "$path/compose.yaml" ]; then
        echo "$path/compose.yaml"
        return 0
    fi

    return 1
}

get_running_compose_services() {
    local compose_file="$1"
    docker compose -f "$compose_file" ps --services --filter status=running 2>/dev/null
}

print_service_status_group() {
    local title="$1"
    shift
    local services=("$@")

    if [ ${#services[@]} -eq 0 ]; then
        return 0
    fi

    echo ""
    echo -e "${BLUE}${title}:${NC}"

    for svc in "${services[@]}"; do
        local compose_file
        compose_file=$(get_compose_file "$svc" 2>/dev/null)

        if [ -z "$compose_file" ]; then
            echo -e "  ${RED}●${NC} $svc (stopped)"
            continue
        fi

        local defined_services
        defined_services=$(docker compose -f "$compose_file" config --services 2>/dev/null)

        if [ -z "$defined_services" ]; then
            echo -e "  ${RED}●${NC} $svc (stopped)"
            continue
        fi

        local running_services
        running_services=$(get_running_compose_services "$compose_file")
        local service_count
        service_count=$(printf "%s\n" "$defined_services" | sed '/^$/d' | wc -l)

        if [ "$service_count" -le 1 ]; then
            if [ -n "$running_services" ]; then
                echo -e "  ${GREEN}●${NC} $svc (running)"
            else
                echo -e "  ${RED}●${NC} $svc (stopped)"
            fi
            continue
        fi

        echo -e "  ${BLUE}▶${NC} $svc"
        while IFS= read -r compose_service; do
            [ -z "$compose_service" ] && continue
            if printf "%s\n" "$running_services" | grep -qx "$compose_service"; then
                echo -e "    ${GREEN}●${NC} $compose_service (running)"
            else
                echo -e "    ${RED}●${NC} $compose_service (stopped)"
            fi
        done <<< "$defined_services"
    done
}

cmd_status() {
    print_header "Service Status"

    print_service_status_group "Infrastructure Services" "${INFRA_SERVICES[@]}"
    print_service_status_group "Application Services" "${APP_SERVICES[@]}"
    
    echo ""
    echo -e "${BLUE}Access URLs:${NC}"
    
    # Check if traefik exists and show dashboard
    if [[ " ${INFRA_SERVICES[@]} " =~ " traefik " ]]; then
        echo "  Traefik Dashboard: http://localhost:8081"
    fi
    
    # Show application URLs dynamically
    for svc in "${APP_SERVICES[@]}"; do
        # Capitalize first letter (portable way)
        local svc_display="$(echo "${svc:0:1}" | tr '[:lower:]' '[:upper:]')${svc:1}"
        printf "  %-18s http://localhost:8080/%s\n" "${svc_display}:" "${svc}"
    done
    
    # Check if portainer exists
    if [[ " ${INFRA_SERVICES[@]} " =~ " portainer " ]]; then
        echo "  Portainer:         http://localhost:9000"
    fi
}

# Execute if run directly
if [ "${BASH_SOURCE[0]}" = "$0" ]; then
    cmd_status
fi
