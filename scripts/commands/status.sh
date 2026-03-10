#!/bin/bash

# Status Command
# Show status of all services

cmd_status() {
    print_header "Service Status"
    
    if [ ${#INFRA_SERVICES[@]} -gt 0 ]; then
        echo ""
        echo -e "${BLUE}Infrastructure Services:${NC}"
        for svc in "${INFRA_SERVICES[@]}"; do
            local containers=($(get_service_containers "$svc"))
            
            if [ ${#containers[@]} -eq 0 ]; then
                # Fallback to service name if no container_name found
                containers=("$svc")
            fi
            
            if [ ${#containers[@]} -eq 1 ]; then
                # Single container - show on one line
                if docker ps --format '{{.Names}}' | grep -q "^${containers[0]}$"; then
                    echo -e "  ${GREEN}●${NC} $svc (running)"
                else
                    echo -e "  ${RED}●${NC} $svc (stopped)"
                fi
            else
                # Multiple containers - show service then sub-items
                echo -e "  ${BLUE}▶${NC} $svc"
                for container in "${containers[@]}"; do
                    if docker ps --format '{{.Names}}' | grep -q "^${container}$"; then
                        echo -e "    ${GREEN}●${NC} $container (running)"
                    else
                        echo -e "    ${RED}●${NC} $container (stopped)"
                    fi
                done
            fi
        done
    fi
    
    if [ ${#APP_SERVICES[@]} -gt 0 ]; then
        echo ""
        echo -e "${BLUE}Application Services:${NC}"
        for svc in "${APP_SERVICES[@]}"; do
            local containers=($(get_service_containers "$svc"))
            
            if [ ${#containers[@]} -eq 0 ]; then
                # Fallback to service-app pattern if no container_name found
                containers=("${svc}-app")
            fi
            
            if [ ${#containers[@]} -eq 1 ]; then
                # Single container - show on one line
                if docker ps --format '{{.Names}}' | grep -q "^${containers[0]}$"; then
                    echo -e "  ${GREEN}●${NC} $svc (running)"
                else
                    echo -e "  ${RED}●${NC} $svc (stopped)"
                fi
            else
                # Multiple containers - show service then sub-items
                echo -e "  ${BLUE}▶${NC} $svc"
                for container in "${containers[@]}"; do
                    if docker ps --format '{{.Names}}' | grep -q "^${container}$"; then
                        echo -e "    ${GREEN}●${NC} $container (running)"
                    else
                        echo -e "    ${RED}●${NC} $container (stopped)"
                    fi
                done
            fi
        done
    fi
    
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
