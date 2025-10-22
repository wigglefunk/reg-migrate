#!/bin/bash
# Repository structure creation script for Satellite 6.14 -> 6.17 re-registration project

set -euo pipefail

PROJECT_ROOT="satellite_host_reregistration"

echo "Creating project structure for: ${PROJECT_ROOT}"

# Create base directories
mkdir -p "${PROJECT_ROOT}"/{group_vars,inventories/{dev,prod},playbooks,roles}

# Create group_vars files
touch "${PROJECT_ROOT}/group_vars/all.yml"

# Create inventory files
touch "${PROJECT_ROOT}/inventories/dev/hosts"
touch "${PROJECT_ROOT}/inventories/prod/hosts"

# Create roles with tasks subdirectory only
ROLES=(
    "export_hosts"
    "prepare_import"
    "provision_lifecycle_env"
    "generate_registration_command"
    "register_hosts"
    "log_results"
    "validate"
)

for role in "${ROLES[@]}"; do
    mkdir -p "${PROJECT_ROOT}/roles/${role}/tasks"
    touch "${PROJECT_ROOT}/roles/${role}/tasks/main.yml"
done

# Create playbook stubs
touch "${PROJECT_ROOT}/playbooks/main.yml"
touch "${PROJECT_ROOT}/playbooks/register.yml"
touch "${PROJECT_ROOT}/playbooks/validate.yml"

# Create README
touch "${PROJECT_ROOT}/README.md"

# Create .gitignore
cat > "${PROJECT_ROOT}/.gitignore" << 'GITIGNORE'
# Ansible
*.retry
.vault_pass
*.log

# Python
__pycache__/
*.pyc
*.pyo

# IDEs
.vscode/
.idea/

# OS
.DS_Store
Thumbs.db
GITIGNORE

echo "Repository structure created successfully!"
echo ""
echo "Structure:"
tree -L 3 "${PROJECT_ROOT}" 2>/dev/null || find "${PROJECT_ROOT}" -print | sed -e 's;[^/]*/;|____;g;s;____|; |;g'

