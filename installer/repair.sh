#!/usr/bin/env bash
# ==============================================================================
# Nova Panel - Diagnostic and Repair Utility
# ==============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "${SCRIPT_DIR}/common.sh" 2>/dev/null || true

require_root
init_logging

print_step "Running Nova Panel Diagnostics & Self-Repair..."

REPAIR_ISSUES=0

# 1. Check Services
print_info "Verifying core service states..."

check_service() {
    local s_name="$1"
    local s_display="$2"
    if systemctl is-active --quiet "${s_name}"; then
        print_success "Service [${s_display}] is RUNNING."
    else
        print_warning "Service [${s_display}] is NOT running."
        REPAIR_ISSUES=$((REPAIR_ISSUES + 1))
        if prompt_confirm "Attempt to restart [${s_display}]?" "Y"; then
            systemctl restart "${s_name}" >> "${INSTALL_LOG}" 2>&1
            if systemctl is-active --quiet "${s_name}"; then
                print_success "Service [${s_display}] successfully restored!"
            else
                print_error "Failed to restore [${s_display}]. Inspect with: journalctl -u ${s_name} -n 30"
            fi
        fi
    fi
}

check_service "nginx" "Nginx Web Server"
check_service "redis-server" "Redis Cache/Queue Store"
if systemctl list-unit-files | grep -q mariadb; then
    check_service "mariadb" "MariaDB Database"
elif systemctl list-unit-files | grep -q mysql; then
    check_service "mysql" "MySQL Database"
fi
check_service "docker" "Docker Engine"
check_service "wings" "Wings Daemon"
check_service "pteroq" "Background Queue Worker"

# Check Tunnel Service if configured
if [[ -f "/etc/nova-panel/access.env" ]]; then
    TUNNEL_SVC=$(grep -E '^TUNNEL_SERVICE=' /etc/nova-panel/access.env 2>/dev/null | cut -d '=' -f2)
    if [[ -n "$TUNNEL_SVC" ]]; then
        check_service "${TUNNEL_SVC}" "Panel Access Tunnel (${TUNNEL_SVC})"
    fi
fi

# 2. Check File Permissions
print_step "Checking filesystem permissions..."
if [[ -d "${PANEL_DIR}" ]]; then
    local bad_perms
    bad_perms=$(find "${PANEL_DIR}/storage" "${PANEL_DIR}/bootstrap/cache" ! -user www-data 2>/dev/null | wc -l)
    if [[ $bad_perms -gt 0 ]]; then
        print_warning "Found ${bad_perms} files with incorrect ownership in storage or cache."
        print_info "Repairing ownership to www-data:www-data..."
        chown -R www-data:www-data "${PANEL_DIR}"
        chmod -R 755 "${PANEL_DIR}/storage" "${PANEL_DIR}/bootstrap/cache"
        print_success "Filesystem permissions corrected."
    else
        print_success "Filesystem permissions are correct."
    fi
else
    print_warning "Panel directory ${PANEL_DIR} not found!"
fi

# 3. Check App Key & Database Connection
print_step "Verifying Laravel environment and database connectivity..."
if [[ -f "${PANEL_DIR}/.env" ]]; then
    cd "${PANEL_DIR}" || true
    
    # Check APP_KEY
    if ! grep -qE '^APP_KEY=base64:' "${PANEL_DIR}/.env"; then
        print_warning "APP_KEY appears unset or invalid in .env."
        if prompt_confirm "Generate fresh APP_KEY?" "Y"; then
            php artisan key:generate --force >> "${INSTALL_LOG}" 2>&1
            print_success "Generated new APP_KEY."
        fi
    fi

    # Check DB Connection
    if php artisan db:monitor >> "${INSTALL_LOG}" 2>&1; then
        print_success "Database connection verified."
    else
        print_warning "Database connection test failed. Inspect .env credentials."
    fi

    # Clear stale caches
    print_info "Clearing application view and config caches..."
    php artisan view:clear >> "${INSTALL_LOG}" 2>&1 || true
    php artisan config:clear >> "${INSTALL_LOG}" 2>&1 || true
    php artisan cache:clear >> "${INSTALL_LOG}" 2>&1 || true
    print_success "Application caches refreshed."
fi

# 4. Storage & Inode Health
print_step "Checking disk and inode availability..."
df -h "${PANEL_DIR}" | awk 'NR==1 || NR==2'
df -i "${PANEL_DIR}" | awk 'NR==1 || NR==2'

# 5. Wings Daemon Configuration & Socket
if [[ -f "/etc/pterodactyl/config.yml" ]]; then
    print_success "Wings configuration file present (/etc/pterodactyl/config.yml)."
else
    print_error "Wings configuration file MISSING (/etc/pterodactyl/config.yml)."
    print_info "Run: php artisan p:node:configuration 1 --format=yaml > /etc/pterodactyl/config.yml"
fi

print_step "Diagnostic and repair run completed."
if [[ $REPAIR_ISSUES -eq 0 ]]; then
    print_success "All systems and services are healthy!"
else
    print_warning "Completed with ${REPAIR_ISSUES} items addressed or flagged."
fi
