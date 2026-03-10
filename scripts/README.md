# Scripts Directory

This directory contains the modularized components of the Personal Server Management Script.

## Structure

```text
scripts/
├── lib/              # Shared library functions
│   ├── helpers.sh    # Print utilities and color definitions
│   ├── discovery.sh  # Service discovery functions
│   └── service-utils.sh  # Service utility functions (paths, containers)
└── commands/         # Command implementations
    ├── build.sh      # Build command
    ├── clean.sh      # Clean command
    ├── help.sh       # Help command
    ├── init.sh       # Init command
    ├── logs.sh       # Logs command
    ├── ps.sh         # PS command
    ├── rebuild.sh    # Rebuild command
    ├── restart.sh    # Restart command
    ├── start.sh      # Start command
    ├── status.sh     # Status command
    └── stop.sh       # Stop command
```

## Library Files (`lib/`)

### helpers.sh

Contains color definitions and print utility functions:

- `print_header()` - Print a formatted header
- `print_success()` - Print a success message
- `print_error()` - Print an error message
- `print_warning()` - Print a warning message
- `print_info()` - Print an info message

### discovery.sh

Service discovery functions:

- `discover_infra_services()` - Discover infrastructure services
- `discover_app_services()` - Discover application services
- `init_services()` - Initialize service arrays

### service-utils.sh

Service utility functions:

- `get_service_path()` - Get the path to a service's directory
- `service_exists()` - Check if a service exists
- `get_service_containers()` - Get container names for a service

## Command Files (`commands/`)

Each command file implements a specific command:

- Contains a main function (e.g., `cmd_start()`)
- Can be sourced or executed directly
- Sources required libraries as needed

## Adding New Commands

To add a new command:

1. Create a new file in `scripts/commands/` (e.g., `mycommand.sh`)
2. Add the command function (e.g., `cmd_mycommand()`)
3. Add the direct execution check at the bottom:

   ```bash
   if [ "${BASH_SOURCE[0]}" = "$0" ]; then
       cmd_mycommand "$@"
   fi
   ```

4. Update the main `manage.sh` dispatcher to include the new command
5. Update `scripts/commands/help.sh` to document the new command

## Usage

All library functions and command functions are available to the main `manage.sh` script through sourcing. The libraries are sourced first, then the appropriate command script is sourced and executed based on the CLI argument.
