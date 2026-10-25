#!/usr/bin/env bash
# ==============================================================================
# Nova Panel - Restore Utility
# ==============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "${SCRIPT_DIR}/common.sh" 2>/dev/null || true

require_root
init_logging

ARCHIVE_PATH="$1"

print_step "Starting Nova Panel Restoration..."

if [[ -z "${ARCHIVE_PATH}" ]]; then
    echo -e "Available backups in ${BACKUP_DIR}:"
    ls -lh "${BACKUP_DIR}"/*.tar.gz 2>/dev/null || true
    echo ""
    ARCHIVE_PATH=$(prompt_input "Enter full path to backup archive (.tar.gz)")
fi

if [[ ! -f "${ARCHIVE_PATH}" ]]; then
    print_fatal "Backup archive not found at: ${ARCHIVE_PATH}"
fi

# Validation
print_info "Validating archive integrity..."
if ! tar -tzf "${ARCHIVE_PATH}" >/dev/null 2>&1; then
    print_fatal "Archive is corrupt or not a valid gzip tarball."
fi
print_success "Archive integrity verified."

echo -e "\n${YELLOW}${BOLD}WARNING:${RESET} Restoring this backup will overwrite current database records"
echo -e "         and application configuration with the contents of the archive."
if ! prompt_confirm "Are you sure you want to proceed with restoration?" "N"; then
    print_info "Restoration aborted."
    exit 0
fi

RESTORE_TMP="/tmp/nova_restore_$(date '+%s')"
mkdir -p "${RESTORE_TMP}"

print_info "Extracting archive..."
tar -xzf "${ARCHIVE_PATH}" -C "${RESTORE_TMP}" >> "${INSTALL_LOG}" 2>&1
RESTORE_DATA_DIR=$(find "${RESTORE_TMP}" -mindepth 1 -maxdepth 1 -type d | head -n 1)

if [[ -z "${RESTORE_DATA_DIR}" || ! -d "${RESTORE_DATA_DIR}" ]]; then
    RESTORE_DATA_DIR="${RESTORE_TMP}"
fi

# 1. Restore Configurations
if [[ -f "${RESTORE_DATA_DIR}/configs/panel.env" ]]; then
    print_info "Restoring panel environment (.env)..."
    cp -a "${RESTORE_DATA_DIR}/configs/panel.env" "${PANEL_DIR}/.env"
    chmod 600 "${PANEL_DIR}/.env"
    chown www-data:www-data "${PANEL_DIR}/.env"
fi

if [[ -d "${RESTORE_DATA_DIR}/configs/nova-panel" ]]; then
    print_info "Restoring Nova configuration (/etc/nova-panel)..."
    mkdir -p /etc/nova-panel
    cp -a "${RESTORE_DATA_DIR}/configs/nova-panel/." /etc/nova-panel/
    chmod -R 600 /etc/nova-panel
fi

if [[ -f "${RESTORE_DATA_DIR}/configs/wings/config.yml" ]]; then
    print_info "Restoring Wings daemon configuration..."
    mkdir -p /etc/pterodactyl
    cp -a "${RESTORE_DATA_DIR}/configs/wings/config.yml" /etc/pterodactyl/config.yml
    chmod 600 /etc/pterodactyl/config.yml
fi

if [[ -f "${RESTORE_DATA_DIR}/configs/nginx-nova-panel.conf" ]]; then
    print_info "Restoring Nginx configuration..."
    cp -a "${RESTORE_DATA_DIR}/configs/nginx-nova-panel.conf" /etc/nginx/sites-available/nova-panel.conf
    ln -sf /etc/nginx/sites-available/nova-panel.conf /etc/nginx/sites-enabled/nova-panel.conf
fi

# 2. Restore Database
if [[ -f "${RESTORE_DATA_DIR}/database.sql" ]]; then
    print_info "Restoring database SQL dump..."
    
    DB_DATABASE=$(grep -E '^DB_DATABASE=' "${PANEL_DIR}/.env" 2>/dev/null | cut -d '=' -f2- | tr -d '"\047')
    DB_USERNAME=$(grep -E '^DB_USERNAME=' "${PANEL_DIR}/.env" 2>/dev/null | cut -d '=' -f2- | tr -d '"\047')
    DB_PASSWORD=$(grep -E '^DB_PASSWORD=' "${PANEL_DIR}/.env" 2>/dev/null | cut -d '=' -f2- | tr -d '"\047')
    DB_HOST=$(grep -E '^DB_HOST=' "${PANEL_DIR}/.env" 2>/dev/null | cut -d '=' -f2- | tr -d '"\047')
    DB_PORT=$(grep -E '^DB_PORT=' "${PANEL_DIR}/.env" 2>/dev/null | cut -d '=' -f2- | tr -d '"\047')

    DB_DATABASE="${DB_DATABASE:-novapanel}"
    DB_USERNAME="${DB_USERNAME:-novapanel}"
    DB_HOST="${DB_HOST:-127.0.0.1}"
    DB_PORT="${DB_PORT:-3306}"

    RESTORE_CLI="mysql"
    if command_exists mariadb; then
        RESTORE_CLI="mariadb"
    fi

    if [[ -n "${DB_PASSWORD}" ]]; then
        ${RESTORE_CLI} -h "${DB_HOST}" -P "${DB_PORT}" -u "${DB_USERNAME}" -p"${DB_PASSWORD}" "${DB_DATABASE}" < "${RESTORE_DATA_DIR}/database.sql" 2>> "${INSTALL_LOG}" || {
            ${RESTORE_CLI} "${DB_DATABASE}" < "${RESTORE_DATA_DIR}/database.sql" 2>> "${INSTALL_LOG}" || print_warning "Database restore encountered non-fatal notices."
        }
    else
        ${RESTORE_CLI} "${DB_DATABASE}" < "${RESTORE_DATA_DIR}/database.sql" 2>> "${INSTALL_LOG}" || true
    fi
    print_success "Database restored successfully."
fi

# Clean up
rm -rf "${RESTORE_TMP}"

# 3. Clear Caches & Restart Services
print_info "Optimizing caches and restarting application services..."
if [[ -d "${PANEL_DIR}" ]]; then
    cd "${PANEL_DIR}" || true
    php artisan view:clear >> "${INSTALL_LOG}" 2>&1 || true
    php artisan config:clear >> "${INSTALL_LOG}" 2>&1 || true
    php artisan cache:clear >> "${INSTALL_LOG}" 2>&1 || true
    php artisan queue:restart >> "${INSTALL_LOG}" 2>&1 || true
fi

systemctl restart nginx >> "${INSTALL_LOG}" 2>&1 || true
systemctl restart pteroq >> "${INSTALL_LOG}" 2>&1 || true
systemctl restart wings >> "${INSTALL_LOG}" 2>&1 || true

print_success "Restoration completed successfully!\n"
