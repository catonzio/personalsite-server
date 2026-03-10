#!/bin/bash

# Bootstrap Command
# Create a new app with FastAPI backend and HTML frontend

# Get the directory where this script is located
BOOTSTRAP_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEMPLATES_DIR="$BOOTSTRAP_DIR/templates"

# Helper function to process template files
process_template() {
    local template_file="$1"
    local output_file="$2"
    local app_name="$3"
    local app_title="$4"
    
    # Read template and replace placeholders
    sed "s/{{APP_NAME}}/$app_name/g; s/{{APP_TITLE}}/$app_title/g" "$template_file" > "$output_file"
}

cmd_bootstrap() {
    local app_name="$1"
    
    # Validate app name is provided
    if [ -z "$app_name" ]; then
        print_error "App name is required"
        echo ""
        echo "Usage: $0 bootstrap <app-name>"
        echo ""
        echo "Example: $0 bootstrap my-new-app"
        echo ""
        echo "The app name should be:"
        echo "  - lowercase"
        echo "  - use hyphens instead of spaces"
        echo "  - contain only letters, numbers, and hyphens"
        exit 1
    fi
    
    # Validate app name format
    if ! [[ "$app_name" =~ ^[a-z0-9-]+$ ]]; then
        print_error "Invalid app name format"
        echo "App name must contain only lowercase letters, numbers, and hyphens"
        exit 1
    fi
    
    # Define app directory
    local app_dir="$SCRIPT_DIR/apps/$app_name"
    
    # Check if app already exists
    if [ -d "$app_dir" ]; then
        print_error "App '$app_name' already exists at: $app_dir"
        exit 1
    fi
    
    print_header "Bootstrapping new app: $app_name"
    
    # Create directory structure
    print_info "Creating directory structure..."
    mkdir -p "$app_dir/fe"
    mkdir -p "$app_dir/be"
    
    # Generate app title from app name (convert hyphens to spaces and capitalize words)
    local app_title=$(echo "$app_name" | sed 's/-/ /g' | awk '{for(i=1;i<=NF;i++) $i=toupper(substr($i,1,1)) tolower(substr($i,2))} 1')
    
    # Create frontend files
    print_info "Creating frontend files..."
    process_template "$TEMPLATES_DIR/fe/index.html.template" "$app_dir/fe/index.html" "$app_name" "$app_title"
    process_template "$TEMPLATES_DIR/fe/Dockerfile.template" "$app_dir/fe/Dockerfile" "$app_name" "$app_title"
    
    # Create backend files
    print_info "Creating backend files..."
    process_template "$TEMPLATES_DIR/be/app.py.template" "$app_dir/be/app.py" "$app_name" "$app_title"
    process_template "$TEMPLATES_DIR/be/Dockerfile.template" "$app_dir/be/Dockerfile" "$app_name" "$app_title"
    process_template "$TEMPLATES_DIR/be/requirements.txt.template" "$app_dir/be/requirements.txt" "$app_name" "$app_title"
    
    # Create docker-compose.yml
    print_info "Creating docker-compose.yml..."
    process_template "$TEMPLATES_DIR/docker-compose.yml.template" "$app_dir/docker-compose.yml" "$app_name" "$app_title"
    
    # Create README.md
    print_info "Creating README.md..."
    process_template "$TEMPLATES_DIR/README.md.template" "$app_dir/README.md" "$app_name" "$app_title"
    
    # Success message
    print_success "Successfully created app: $app_name"
    echo ""
    print_info "App structure:"
    echo "  $app_dir/"
    echo "  ├── fe/            (Frontend - nginx + HTML)"
    echo "  ├── be/            (Backend - FastAPI)"
    echo "  ├── docker-compose.yml"
    echo "  └── README.md"
    echo ""
    print_info "Next steps:"
    echo "  1. Review the generated files"
    echo "  2. Customize the app as needed"
    echo "  3. Start the app:"
    echo "     ./manage.sh start $app_name"
    echo ""
    print_info "Access your app at:"
    echo "  Frontend: http://localhost:8080/$app_name"
    echo "  Backend:  http://localhost:8080/$app_name/api/"
    echo "  Health:   http://localhost:8080/$app_name/api/health"
    echo ""
}

# Execute if run directly
if [ "${BASH_SOURCE[0]}" = "$0" ]; then
    cmd_bootstrap "$@"
fi
