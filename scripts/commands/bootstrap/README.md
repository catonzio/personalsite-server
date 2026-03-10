# Bootstrap Command

This directory contains the bootstrap command and its templates for creating new applications.

## Structure

```text
bootstrap/
├── bootstrap.sh                   # Main bootstrap command script
└── templates/                     # Template files for new apps
    ├── fe/                        # Frontend templates
    │   ├── index.html.template    # HTML frontend template
    │   └── Dockerfile.template    # Frontend Dockerfile
    ├── be/                        # Backend templates
    │   ├── app.py.template        # FastAPI backend template
    │   ├── Dockerfile.template    # Backend Dockerfile
    │   └── requirements.txt.template  # Python dependencies
    ├── docker-compose.yml.template    # Service orchestration
    └── README.md.template             # App documentation
```

## Usage

From the project root:

```bash
./manage.sh bootstrap <app-name>
```

Example:

```bash
./manage.sh bootstrap my-new-app
```

## Template Variables

Templates use the following placeholders that are automatically replaced:

- `{{APP_NAME}}` - The app name (e.g., "my-new-app")
- `{{APP_TITLE}}` - The app title with capitalized words (e.g., "My New App")

## Adding New Templates

1. Create a new `.template` file in the appropriate directory
2. Use `{{APP_NAME}}` and `{{APP_TITLE}}` placeholders as needed
3. Update `bootstrap.sh` to process the new template using the `process_template` function

## Template Processing

The `process_template` function in `bootstrap.sh` performs simple sed-based replacements:

- Reads the template file
- Replaces `{{APP_NAME}}` with the provided app name
- Replaces `{{APP_TITLE}}` with the generated app title
- Writes the result to the target location
