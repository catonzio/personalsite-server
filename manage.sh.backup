#!/bin/bash

# Personal Server Management Script
# Manages infrastructure and application containers

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Color output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Service discovery functions
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

# Discover services
INFRA_SERVICES=($(discover_infra_services))
APP_SERVICES=($(discover_app_services))
ALL_SERVICES=("${INFRA_SERVICES[@]}" "${APP_SERVICES[@]}")

# Helper functions
print_header() {
    echo -e "${BLUE}================================${NC}"
    echo -e "${BLUE}$1${NC}"
    echo -e "${BLUE}================================${NC}"
}

print_success() {
    echo -e "${GREEN}✓ $1${NC}"
}

print_error() {
    echo -e "${RED}✗ $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}⚠ $1${NC}"
}

print_info() {
    echo -e "${BLUE}➜ $1${NC}"
}

get_service_path() {
    local service=$1
    
    # Check infrastructure directory
    if [ -d "infra/$service" ] && [ -f "infra/$service/docker-compose.yml" ]; then
        echo "infra/$service"
        return 0
    fi
    
    # Check apps directory
    if [ -d "apps/$service" ] && [ -f "apps/$service/docker-compose.yml" ]; then
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

# Command functions
cmd_start() {
    local service=$1
    
    if [ -z "$service" ]; then
        print_header "Starting All Services"
        
        # Start traefik first if it exists (it creates the shared network)
        if [[ " ${INFRA_SERVICES[@]} " =~ " traefik " ]]; then
            print_info "Starting traefik (creates shared network)..."
            cmd_start "traefik"
            echo ""
        fi
        
        # Start remaining infrastructure services
        print_info "Starting infrastructure services..."
        for svc in "${INFRA_SERVICES[@]}"; do
            if [ "$svc" != "traefik" ]; then
                cmd_start "$svc"
            fi
        done
        
        echo ""
        print_info "Starting application services..."
        for svc in "${APP_SERVICES[@]}"; do
            cmd_start "$svc"
        done
        
        echo ""
        print_success "All services started!"
        cmd_status
    else
        if ! service_exists "$service"; then
            print_error "Service '$service' not found"
            exit 1
        fi
        
        local path=$(get_service_path "$service")
        print_info "Starting $service..."
        (cd "$path" && docker-compose up -d)
        print_success "$service started"
    fi
}

cmd_stop() {
    local service=$1
    
    if [ -z "$service" ]; then
        print_header "Stopping All Services"
        
        # Stop apps first, then infrastructure
        for svc in "${APP_SERVICES[@]}"; do
            cmd_stop "$svc"
        done
        
        for svc in "${INFRA_SERVICES[@]}"; do
            cmd_stop "$svc"
        done
        
        print_success "All services stopped!"
    else
        if ! service_exists "$service"; then
            print_error "Service '$service' not found"
            exit 1
        fi
        
        local path=$(get_service_path "$service")
        print_info "Stopping $service..."
        (cd "$path" && docker-compose down)
        print_success "$service stopped"
    fi
}

cmd_restart() {
    local service=$1
    
    if [ -z "$service" ]; then
        print_header "Restarting All Services"
        cmd_stop
        sleep 2
        cmd_start
    else
        if ! service_exists "$service"; then
            print_error "Service '$service' not found"
            exit 1
        fi
        
        print_header "Restarting $service"
        cmd_stop "$service"
        sleep 1
        cmd_start "$service"
    fi
}

cmd_build() {
    local service=$1
    
    if [ -z "$service" ]; then
        print_header "Building All Application Services"
        
        for svc in "${APP_SERVICES[@]}"; do
            cmd_build "$svc"
        done
        
        print_success "All services built!"
    else
        if ! service_exists "$service"; then
            print_error "Service '$service' not found"
            exit 1
        fi
        
        local path=$(get_service_path "$service")
        print_info "Building $service..."
        (cd "$path" && docker-compose build)
        print_success "$service built"
    fi
}

cmd_rebuild() {
    local service=$1
    
    if [ -z "$service" ]; then
        print_header "Rebuilding and Restarting All Application Services"
        
        for svc in "${APP_SERVICES[@]}"; do
            cmd_rebuild "$svc"
        done
        
        print_success "All services rebuilt and restarted!"
    else
        if ! service_exists "$service"; then
            print_error "Service '$service' not found"
            exit 1
        fi
        
        print_header "Rebuilding and Restarting $service"
        local path=$(get_service_path "$service")
        print_info "Rebuilding $service..."
        (cd "$path" && docker-compose up -d --build)
        print_success "$service rebuilt and restarted"
    fi
}

cmd_logs() {
    local service=$1
    local follow=${2:-false}
    
    if [ -z "$service" ]; then
        print_error "Please specify a service name"
        echo "Usage: $0 logs <service> [follow]"
        exit 1
    fi
    
    if ! service_exists "$service"; then
        print_error "Service '$service' not found"
        exit 1
    fi
    
    local path=$(get_service_path "$service")
    print_info "Showing logs for $service..."
    
    if [ "$follow" = "follow" ] || [ "$follow" = "-f" ]; then
        (cd "$path" && docker-compose logs -f)
    else
        (cd "$path" && docker-compose logs --tail=100)
    fi
}

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

cmd_clean() {
    print_header "Cleaning Up"
    print_warning "This will remove stopped containers, unused networks, and dangling images"
    read -p "Continue? (y/N) " -n 1 -r
    echo
    
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        print_info "Stopping all services..."
        cmd_stop
        
        print_info "Removing containers..."
        # Dynamically remove containers from all discovered services
        for svc in "${INFRA_SERVICES[@]}"; do
            if [ -f "infra/$svc/docker-compose.yml" ]; then
                docker-compose -f "infra/$svc/docker-compose.yml" rm -f 2>/dev/null || true
            fi
        done
        
        for svc in "${APP_SERVICES[@]}"; do
            if [ -f "apps/$svc/docker-compose.yml" ]; then
                docker-compose -f "apps/$svc/docker-compose.yml" rm -f 2>/dev/null || true
            fi
        done
        
        print_info "Pruning Docker system..."
        docker system prune -f
        
        print_success "Cleanup complete!"
    else
        print_info "Cleanup cancelled"
    fi
}

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
    cmd_build
    
    # Start all services
    print_info "Starting all services..."
    cmd_start
    
    echo ""
    print_success "Environment initialized successfully!"
    echo ""
    cmd_status
}

show_help() {
    cat << EOF
Personal Server Management Script
Auto-discovers services from infra/ and apps/ directories

Usage: $0 <command> [service] [options]

Commands:
  init               Initialize the environment (build and start all services)
  start [service]    Start service(s) - all if no service specified
  stop [service]     Stop service(s) - all if no service specified
  restart [service]  Restart service(s) - all if no service specified
  build [service]    Build service(s) - all apps if no service specified
  rebuild [service]  Rebuild and restart service(s)
  logs <service> [-f]  Show logs for a service (use -f to follow)
  status             Show status of all services
  ps                 Show running containers
  clean              Stop all services and clean up Docker resources
  help               Show this help message

Currently Discovered Services:
EOF
    
    if [ ${#INFRA_SERVICES[@]} -gt 0 ]; then
        echo "  Infrastructure: ${INFRA_SERVICES[@]}"
    else
        echo "  Infrastructure: (none found)"
    fi
    
    if [ ${#APP_SERVICES[@]} -gt 0 ]; then
        echo "  Applications:   ${APP_SERVICES[@]}"
    else
        echo "  Applications:   (none found)"
    fi
    
    cat << EOF

How to add new services:
  1. Create a new directory under apps/ or infra/
  2. Add a docker-compose.yml file
  3. The script will automatically discover it!

Examples:
  $0 init                      # Initialize everything
  $0 start                     # Start all services
  $0 start portfolio           # Start only portfolio
  $0 stop small-games          # Stop small-games
  $0 restart traefik           # Restart traefik
  $0 rebuild portfolio         # Rebuild and restart portfolio
  $0 logs portfolio            # Show portfolio logs
  $0 logs traefik -f           # Follow traefik logs
  $0 status                    # Show status of all services

EOF
}

# Main command dispatcher
case "${1:-help}" in
    init)
        cmd_init
        ;;
    start)
        cmd_start "${2:-}"
        ;;
    stop)
        cmd_stop "${2:-}"
        ;;
    restart)
        cmd_restart "${2:-}"
        ;;
    build)
        cmd_build "${2:-}"
        ;;
    rebuild)
        cmd_rebuild "${2:-}"
        ;;
    logs)
        cmd_logs "${2:-}" "${3:-}"
        ;;
    status)
        cmd_status
        ;;
    ps)
        cmd_ps
        ;;
    clean)
        cmd_clean
        ;;
    help|--help|-h)
        show_help
        ;;
    *)
        print_error "Unknown command: $1"
        echo ""
        show_help
        exit 1
        ;;
esac
