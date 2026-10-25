#!/usr/bin/env bash
# ==============================================================================
# Nova Panel - Backup Utility
# ==============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "${SCRIPT_DIR}/common.sh" 2>/dev/null || true

require_root
init_logging

BACKUP_DIR="/var/backups/nova-panel"
PANEL_DIR="/var/www/nova-panel"
TIMESTAMP=$(date '+%Y%m%d_%H%M%S')
BACKUP_NAME="nova_backup_${TIMESTAMP}"
WORK_DIR="/tmp/${BACKUP_NAME}"

print_step "Starting Nova Panel Backup..."

mkdir -p "${BACKUP_DIR}" "${WORK_DIR}"

# 1. Back up Database
print_info "Dumping database..."
if [[ -f "${PANEL_DIR}/.env" ]]; then
    # Extract DB details from .env safely
    DB_DATABASE=$(grep -E '^DB_DATABASE=' "${PANEL_DIR}/.env" | cut -d '=' -f2- | tr -d '"\047')
    DB_USERNAME=$(grep -E '^DB_USERNAME=' "${PANEL_DIR}/.env" | cut -d '=' -f2- | tr -d '"\047')
    DB_PASSWORD=$(grep -E '^DB_PASSWORD=' "${PANEL_DIR}/.env" | cut -d '=' -f2- | tr -d '"\047')
    DB_HOST=$(grep -E '^DB_HOST=' "${PANEL_DIR}/.env" | cut -d '=' -f2- | tr -d '"\047')
    DB_PORT=$(grep -E '^DB_PORT=' "${PANEL_DIR}/.env" | cut -d '=' -f2- | tr -d '"\047')
fi

DB_DATABASE="${DB_DATABASE:-novapanel}"
DB_USERNAME="${DB_USERNAME:-novapanel}"
DB_HOST="${DB_HOST:-127.0.0.1}"
DB_PORT="${DB_PORT:-3306}"

DUMP_CMD="mysqldump"
if command_exists mariadb-dump; then
    DUMP_CMD="mariadb-dump"
fi

if [[ -n "${DB_PASSWORD}" ]]; then
    ${DUMP_CMD} -h "${DB_HOST}" -P "${DB_PORT}" -u "${DB_USERNAME}" -p"${DB_PASSWORD}" "${DB_DATABASE}" > "${WORK_DIR}/database.sql" 2>> "${INSTALL_LOG}" || {
        # Fallback to local socket dump
        ${DUMP_CMD} "${DB_DATABASE}" > "${WORK_DIR}/database.sql" 2>> "${INSTALL_LOG}" || print_warning "Database dump returned non-zero. Check database permissions."
    }
else
    ${DUMP_CMD} "${DB_DATABASE}" > "${WORK_DIR}/database.sql" 2>> "${INSTALL_LOG}" || true
fi

# 2. Back up Configurations
print_info "Archiving configuration files..."
mkdir -p "${WORK_DIR}/configs"

if [[ -f "${PANEL_DIR}/.env" ]]; then
    cp -a "${PANEL_DIR}/.env" "${WORK_DIR}/configs/panel.env"
fi

if [[ -d "/etc/nova-panel" ]]; then
    cp -a "/etc/nova-panel" "${WORK_DIR}/configs/nova-panel"
fi

if [[ -f "/etc/pterodactyl/config.yml" ]]; then
    mkdir -p "${WORK_DIR}/configs/wings"
    cp -a "/etc/pterodactyl/config.yml" "${WORK_DIR}/configs/wings/config.yml"
fi

if [[ -f "/etc/nginx/sites-available/nova-panel.conf" ]]; then
    cp -a "/etc/nginx/sites-available/nova-panel.conf" "${WORK_DIR}/configs/nginx-nova-panel.conf"
fi

# 3. Create Compressed Archive
ARCHIVE_PATH="${BACKUP_DIR}/${BACKUP_NAME}.tar.gz"
print_info "Compressing backup archive to ${ARCHIVE_PATH}..."

tar -czf "${ARCHIVE_PATH}" -C "/tmp" "${BACKUP_NAME}" >> "${INSTALL_LOG}" 2>&1
chmod 600 "${ARCHIVE_PATH}"

# Clean up workdir
rm -rf "${WORK_DIR}"

ARCHIVE_SIZE=$(du -h "${ARCHIVE_PATH}" | awk '{print $1}')
print_success "Backup completed successfully!"
print_info "Archive: ${BOLD}${ARCHIVE_PATH}${RESET} (${ARCHIVE_SIZE})"
echo "${ARCHIVE_PATH}"
