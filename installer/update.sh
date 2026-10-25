#!/usr/bin/env bash
# ==============================================================================
# Nova Panel - Update Utility
# ==============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "${SCRIPT_DIR}/common.sh" 2>/dev/null || true

require_root
init_logging

print_step "Starting Nova Panel Update Process..."

if [[ ! -d "${PANEL_DIR}" ]]; then
    print_fatal "Nova Panel is not installed in ${PANEL_DIR}. Run 'nova install' first."
fi

# 1. Identify Current Version
CURRENT_VERSION=$(php -r '
    chdir("/var/www/nova-panel");
    require "vendor/autoload.php";
    $app = require_once "bootstrap/app.php";
    $kernel = $app->make(Illuminate\Contracts\Console\Kernel::class);
    $kernel->bootstrap();
    echo config("nova.version", "1.0.0");
' 2>/dev/null || echo "1.0.0")

print_info "Current Installed Nova Panel Version: ${BOLD}${CURRENT_VERSION}${RESET}"

# 2. Pre-Update Backup
print_step "Creating pre-update safety backup..."
if "${SCRIPT_DIR}/backup.sh" >> "${INSTALL_LOG}" 2>&1; then
    print_success "Pre-update safety backup created successfully."
else
    print_warning "Backup completed with non-zero exit code. Review logs if necessary."
    if ! prompt_confirm "Continue with update without guaranteed backup?" "N"; then
        print_fatal "Update aborted."
    fi
fi

# 3. Enter Maintenance Mode
print_info "Putting panel into maintenance mode..."
cd "${PANEL_DIR}" || print_fatal "Could not access ${PANEL_DIR}"
php artisan down >> "${INSTALL_LOG}" 2>&1 || true

# 4. Check Disk Space
local_free_mb=$(df -m "${PANEL_DIR}" | awk 'NR==2 {print $4}')
if [[ $local_free_mb -lt 1000 ]]; then
    php artisan up >> "${INSTALL_LOG}" 2>&1 || true
    print_fatal "Insufficient free disk space for update (${local_free_mb} MB available, 1000 MB needed)."
fi

# 5. Fetch / Apply Update
print_info "Updating application files..."
# If this repo has local panel files, sync them, else download release
if [[ -d "${SCRIPT_DIR}/../panel" ]]; then
    print_info "Syncing latest Nova Panel core from repository..."
    cp -a "${SCRIPT_DIR}/../panel/." "${PANEL_DIR}/"
fi

# 6. Install PHP Dependencies & Run Migrations
print_info "Updating composer dependencies..."
export COMPOSER_ALLOW_SUPERUSER=1
composer install --no-dev --optimize-autoloader --no-interaction >> "${INSTALL_LOG}" 2>&1 || {
    print_error "Composer update reported issues. Check install log."
}

print_info "Applying database migrations..."
php artisan migrate --force >> "${INSTALL_LOG}" 2>&1 || {
    php artisan up >> "${INSTALL_LOG}" 2>&1 || true
    print_fatal "Database migration failed during update. Restore from pre-update backup if needed."
}

# 7. Clear Caches & Optimize
print_info "Clearing and optimizing caches..."
php artisan view:clear >> "${INSTALL_LOG}" 2>&1 || true
php artisan config:clear >> "${INSTALL_LOG}" 2>&1 || true
php artisan route:clear >> "${INSTALL_LOG}" 2>&1 || true

# 8. Reset File Permissions
print_info "Securing filesystem permissions..."
chown -R www-data:www-data "${PANEL_DIR}"
chmod -R 755 "${PANEL_DIR}/storage" "${PANEL_DIR}/bootstrap/cache"

# 9. Update Wings Daemon if Requested
print_info "Checking Wings daemon status..."
if command_exists wings; then
    WINGS_INSTALLED=$(/usr/local/bin/wings version 2>/dev/null | head -n1 || echo "unknown")
    print_info "Installed Wings Version: ${WINGS_INSTALLED}"
    if prompt_confirm "Would you like to update the Wings daemon binary as well?" "Y"; then
        "${SCRIPT_DIR}/modules/wings.sh" >> "${INSTALL_LOG}" 2>&1 || print_warning "Wings update failed."
    fi
fi

# 10. Bring Application Online & Restart Services
print_info "Bringing panel online and restarting queue workers..."
php artisan up >> "${INSTALL_LOG}" 2>&1 || true
php artisan queue:restart >> "${INSTALL_LOG}" 2>&1 || true
systemctl restart pteroq >> "${INSTALL_LOG}" 2>&1 || true
systemctl restart nginx >> "${INSTALL_LOG}" 2>&1 || true

print_success "Nova Panel updated successfully!\n"
