#!/bin/bash

# Services Command
# List all discovered services

cmd_services() {
    print_header "Discovered Services"

    echo ""
    if [ ${#INFRA_SERVICES[@]} -gt 0 ]; then
        echo -e "${BLUE}Infrastructure Services:${NC}"
        for svc in "${INFRA_SERVICES[@]}"; do
            echo "  - $svc"
        done
    else
        echo -e "${BLUE}Infrastructure Services:${NC} (none found)"
    fi

    echo ""
    if [ ${#APP_SERVICES[@]} -gt 0 ]; then
        echo -e "${BLUE}Application Services:${NC}"
        for svc in "${APP_SERVICES[@]}"; do
            echo "  - $svc"
        done
    else
        echo -e "${BLUE}Application Services:${NC} (none found)"
    fi
}
