#!/usr/bin/env bash
# ==============================================================================
# Nova Panel - Master Automated Installation Script
# Supports: Production VPS Mode & Development / CodeSandbox Mode
# ==============================================================================

set -o pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Parse optional command-line flags
for arg in "$@"; do
    case "$arg" in
        --dev|--development)
            DEPLOY_MODE="development"
            ;;
        --prod|--production)
            DEPLOY_MODE="production"
            ;;
        --help|-h)
            echo "Nova Panel Installer"
            echo "Usage: bash install.sh [--dev|--prod]"
            echo "  --dev   Force Development / CodeSandbox Mode (rootless, SQLite, built-in server)"
            echo "  --prod  Force Production VPS Mode (systemd, Nginx, MariaDB, Docker, Wings)"
            exit 0
            ;;
    esac
done

# Source all modules
# shellcheck source=/dev/null
source "${SCRIPT_DIR}/common.sh"
# shellcheck source=/dev/null
source "${SCRIPT_DIR}/modules/system-checks.sh"
# shellcheck source=/dev/null
source "${SCRIPT_DIR}/modules/dependencies.sh"
# shellcheck source=/dev/null
source "${SCRIPT_DIR}/modules/database.sh"
# shellcheck source=/dev/null
source "${SCRIPT_DIR}/modules/webserver.sh"
# shellcheck source=/dev/null
source "${SCRIPT_DIR}/modules/docker.sh"
# shellcheck source=/dev/null
source "${SCRIPT_DIR}/modules/wings.sh"
# shellcheck source=/dev/null
source "${SCRIPT_DIR}/modules/node-registration.sh"
# shellcheck source=/dev/null
source "${SCRIPT_DIR}/modules/access/ip.sh"
# shellcheck source=/dev/null
source "${SCRIPT_DIR}/modules/access/domain.sh"
# shellcheck source=/dev/null
source "${SCRIPT_DIR}/modules/access/tunnel.sh"

init_logging
print_banner

print_info "Beginning Nova Panel setup. Mode: ${BOLD}${DEPLOY_MODE}${RESET}"
print_info "Install log: ${INSTALL_LOG}"

# 1. System Compatibility Checks
check_system_prerequisites

# 2. Access Method Selection
if [[ "${DEPLOY_MODE}" == "development" ]]; then
    # In Development / CodeSandbox Mode, default to direct port 8000
    print_info "Using local development port access mode."
    configure_ip_access
else
    echo -e "${PURPLE}${BOLD}NOVA PANEL INSTALLER${RESET}"
    echo -e "Select how you want to access your panel:"
    echo -e "  ${BOLD}[1] IP Address${RESET}           (Fast, direct access without requiring a domain)"
    echo -e "  ${BOLD}[2] Custom Domain + HTTPS${RESET} (Production recommended with Let's Encrypt SSL)"
    echo -e "  ${BOLD}[3] Tunnel Access${RESET}         (Cloudflare Quick/Named Tunnel - CGNAT & Firewall friendly)\n"

    ACCESS_CHOICE="${ACCESS_CHOICE:-}"
    while [[ "$ACCESS_CHOICE" != "1" && "$ACCESS_CHOICE" != "2" && "$ACCESS_CHOICE" != "3" ]]; do
        ACCESS_CHOICE=$(prompt_input "Enter choice [1, 2, or 3]" "1")
    done

    case "$ACCESS_CHOICE" in
        1) configure_ip_access ;;
        2) configure_domain_access ;;
        3) configure_tunnel_access ;;
    esac
fi

# 3. Administrator Account Configuration
print_step "Administrator Account Setup"

if [[ -n "${ADMIN_EMAIL:-}" && -n "${ADMIN_USERNAME:-}" && -n "${ADMIN_PASSWORD:-}" ]]; then
    print_info "Using unattended administrator credentials from environment."
    ADMIN_FIRST_NAME="${ADMIN_FIRST_NAME:-Nova}"
    ADMIN_LAST_NAME="${ADMIN_LAST_NAME:-Admin}"
else
    echo -e "Configure your initial root administrator account:\n"

    ADMIN_EMAIL=""
    while [[ -z "$ADMIN_EMAIL" || ! "$ADMIN_EMAIL" =~ ^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$ ]]; do
        ADMIN_EMAIL=$(prompt_input "Administrator Email Address" "admin@example.com")
        if [[ ! "$ADMIN_EMAIL" =~ ^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$ ]]; then
            print_warning "Invalid email format. Please try again."
        fi
    done

    ADMIN_USERNAME=""
    while [[ -z "$ADMIN_USERNAME" || ! "$ADMIN_USERNAME" =~ ^[a-zA-Z0-9_.-]+$ ]]; do
        ADMIN_USERNAME=$(prompt_input "Administrator Username" "admin")
        if [[ ! "$ADMIN_USERNAME" =~ ^[a-zA-Z0-9_.-]+$ ]]; then
            print_warning "Username can only contain alphanumeric characters, underscores, and dashes."
        fi
    done

    ADMIN_FIRST_NAME=$(prompt_input "Administrator First Name" "Nova")
    ADMIN_LAST_NAME=$(prompt_input "Administrator Last Name" "Admin")
    ADMIN_PASSWORD=$(prompt_password "Administrator Password (minimum 8 characters)")
fi

# 4. Install Dependencies
install_system_dependencies

# 5. Configure Database
configure_database

# 6. Deploy Nova Panel Files
print_step "Deploying Nova Panel Application Files..."
mkdir -p "${PANEL_DIR}"

if [[ -d "${SCRIPT_DIR}/../panel" && -f "${SCRIPT_DIR}/../panel/artisan" ]]; then
    print_info "Syncing from repository panel files..."
    cp -a "${SCRIPT_DIR}/../panel/." "${PANEL_DIR}/"
else
    print_info "Downloading Nova Panel release archive..."
    curl -sSLo /tmp/panel.tar.gz "https://github.com/pterodactyl/panel/releases/download/v1.15.2/panel.tar.gz" >> "${INSTALL_LOG}" 2>&1 || print_fatal "Failed to download panel release."
    tar -xzf /tmp/panel.tar.gz -C "${PANEL_DIR}/"
    rm -f /tmp/panel.tar.gz

    # Overlay any local or bootstrapped Nova customizations
    if [[ -d "${SCRIPT_DIR}/../panel" ]]; then
        cp -a "${SCRIPT_DIR}/../panel/." "${PANEL_DIR}/" 2>/dev/null || true
    fi

    # Ensure Nova branding files exist if bootstrapped in minimal mode
    GITHUB_REPO="${NOVA_REPO:-TalhaPlaysOG/NovaPanel}"
    GITHUB_BRANCH="${NOVA_BRANCH:-main}"
    RAW_BASE="https://raw.githubusercontent.com/${GITHUB_REPO}/${GITHUB_BRANCH}"
    if [[ ! -f "${PANEL_DIR}/config/nova.php" ]]; then
        curl -fsSL --connect-timeout 5 -m 15 -H "User-Agent: NovaInstaller" \
            "${RAW_BASE}/panel/config/nova.php" -o "${PANEL_DIR}/config/nova.php" 2>/dev/null || true
    fi
    mkdir -p "${PANEL_DIR}/public/assets/svgs"
    if [[ ! -f "${PANEL_DIR}/public/assets/svgs/nova.svg" ]]; then
        curl -fsSL --connect-timeout 5 -m 15 -H "User-Agent: NovaInstaller" \
            "${RAW_BASE}/panel/public/assets/svgs/nova.svg" -o "${PANEL_DIR}/public/assets/svgs/nova.svg" 2>/dev/null || true
    fi
    if [[ ! -f "${PANEL_DIR}/public/assets/svgs/nova-mark.svg" ]]; then
        curl -fsSL --connect-timeout 5 -m 15 -H "User-Agent: NovaInstaller" \
            "${RAW_BASE}/panel/public/assets/svgs/nova-mark.svg" -o "${PANEL_DIR}/public/assets/svgs/nova-mark.svg" 2>/dev/null || true
    fi
fi

# Sync custom images from img/ directory to public web assets
if [[ -d "${SCRIPT_DIR}/../img" ]]; then
    print_info "Syncing custom branding images from img/ directory..."
    mkdir -p "${PANEL_DIR}/public/assets/svgs" "${PANEL_DIR}/public/assets/img"
    cp -a "${SCRIPT_DIR}/../img/." "${PANEL_DIR}/public/assets/img/" 2>/dev/null || true
    cp -a "${SCRIPT_DIR}/../img/"*.svg "${PANEL_DIR}/public/assets/svgs/" 2>/dev/null || true
    if [[ -f "${SCRIPT_DIR}/../img/favicon.ico" ]]; then
        cp -f "${SCRIPT_DIR}/../img/favicon.ico" "${PANEL_DIR}/public/favicons/favicon.ico" 2>/dev/null || true
    fi
fi

cd "${PANEL_DIR}" || print_fatal "Could not access ${PANEL_DIR}"

# Ensure required Laravel framework storage directories exist with full read/write permissions
mkdir -p "${PANEL_DIR}/storage/framework/views" \
         "${PANEL_DIR}/storage/framework/cache/data" \
         "${PANEL_DIR}/storage/framework/sessions" \
         "${PANEL_DIR}/storage/logs" \
         "${PANEL_DIR}/storage/app/public" \
         "${PANEL_DIR}/bootstrap/cache"

# Clean any stale compiled bootstrap/cache files
rm -f "${PANEL_DIR}/storage/framework/views/"*.php 2>/dev/null || true
rm -f "${PANEL_DIR}/bootstrap/cache/"*.php 2>/dev/null || true

# Set permissions
if [[ "${DEPLOY_MODE}" == "production" ]]; then
    chown -R www-data:www-data "${PANEL_DIR}" 2>/dev/null || true
fi
chmod -R 777 "${PANEL_DIR}/storage" "${PANEL_DIR}/bootstrap/cache" 2>/dev/null || true

# Generate .env
print_info "Generating application configuration (.env)..."

if [[ "${DEPLOY_MODE}" == "development" ]]; then
    cat > "${PANEL_DIR}/.env" << EOF
APP_NAME="Nova Panel"
APP_ENV=local
APP_DEBUG=true
APP_KEY=base64:$(openssl rand -base64 32)
APP_THEME=pterodactyl
APP_TIMEZONE=UTC
APP_URL=${PANEL_URL}
APP_LOCALE=en
APP_ENVIRONMENT_ONLY=true

LOG_CHANNEL=single
LOG_DEPRECATIONS_CHANNEL=null
LOG_LEVEL=debug

DB_CONNECTION=${DB_CONNECTION:-mysql}
DB_HOST=${DB_HOST:-127.0.0.1}
DB_PORT=${DB_PORT:-3306}
DB_DATABASE=${DB_DATABASE:-${DB_NAME:-novapanel}}
DB_USERNAME=${DB_USER:-novapanel}
DB_PASSWORD=${DB_PASSWORD:-}

VIEW_COMPILED_PATH=${PANEL_DIR}/storage/framework/views

CACHE_DRIVER=file
QUEUE_CONNECTION=sync
SESSION_DRIVER=file

HASHIDS_SALT=$(generate_random_token 20)
HASHIDS_LENGTH=8

MAIL_MAILER=log
MAIL_FROM_ADDRESS=no-reply@novapanel.local
MAIL_FROM_NAME="Nova Panel"

NOVA_NAME="Nova Panel"
NOVA_LOGO="/assets/svgs/nova.svg"
NOVA_ACCENT_COLOR="#6366f1"
EOF
else
    cat > "${PANEL_DIR}/.env" << EOF
APP_NAME="Nova Panel"
APP_ENV=production
APP_DEBUG=false
APP_KEY=base64:$(openssl rand -base64 32)
APP_THEME=pterodactyl
APP_TIMEZONE=UTC
APP_URL=${PANEL_URL}
APP_LOCALE=en
APP_ENVIRONMENT_ONLY=true

LOG_CHANNEL=daily
LOG_DEPRECATIONS_CHANNEL=null
LOG_LEVEL=info

DB_CONNECTION=mysql
DB_HOST=${DB_HOST}
DB_PORT=${DB_PORT}
DB_DATABASE=${DB_NAME}
DB_USERNAME=${DB_USER}
DB_PASSWORD=${DB_PASSWORD}

VIEW_COMPILED_PATH=${PANEL_DIR}/storage/framework/views

REDIS_HOST=127.0.0.1
REDIS_PASSWORD=null
REDIS_PORT=6379

CACHE_DRIVER=redis
QUEUE_CONNECTION=redis
SESSION_DRIVER=redis

HASHIDS_SALT=$(generate_random_token 20)
HASHIDS_LENGTH=8

MAIL_MAILER=smtp
MAIL_HOST=smtp.example.com
MAIL_PORT=25
MAIL_USERNAME=
MAIL_PASSWORD=
MAIL_ENCRYPTION=tls
MAIL_FROM_ADDRESS=no-reply@${PANEL_HOST}
MAIL_FROM_NAME="Nova Panel"

NOVA_NAME="Nova Panel"
NOVA_LOGO="/assets/svgs/nova.svg"
NOVA_ACCENT_COLOR="#6366f1"
EOF
    chmod 600 "${PANEL_DIR}/.env"
    chown www-data:www-data "${PANEL_DIR}/.env" 2>/dev/null || true
fi

# Install Composer Dependencies
print_info "Installing PHP application dependencies..."
export COMPOSER_ALLOW_SUPERUSER=1

# Ensure cache directories exist before composer hooks
mkdir -p "${PANEL_DIR}/storage/framework/views" \
         "${PANEL_DIR}/storage/framework/cache/data" \
         "${PANEL_DIR}/storage/framework/sessions" \
         "${PANEL_DIR}/storage/logs" \
         "${PANEL_DIR}/bootstrap/cache"
chmod -R 777 "${PANEL_DIR}/storage" "${PANEL_DIR}/bootstrap/cache" 2>/dev/null || true

# Attempt Composer installation
if [[ ! -f "${PANEL_DIR}/vendor/autoload.php" ]]; then
    composer install --no-dev --optimize-autoloader --no-interaction >> "${INSTALL_LOG}" 2>&1 || {
        print_warning "Standard composer install reported issues. Retrying with platform bypass..."
        composer install --no-dev --optimize-autoloader --no-interaction --ignore-platform-req=php >> "${INSTALL_LOG}" 2>&1 || true
    }
fi

# Resilient fallback: If vendor/autoload.php is still missing, extract official pre-built vendor package
if [[ ! -f "${PANEL_DIR}/vendor/autoload.php" ]]; then
    print_info "Restoring verified vendor dependencies from release bundle..."
    curl -fsSLo /tmp/panel-vendor.tar.gz "https://github.com/pterodactyl/panel/releases/download/v1.15.2/panel.tar.gz" >> "${INSTALL_LOG}" 2>&1 || true
    if [[ -f /tmp/panel-vendor.tar.gz ]]; then
        tar -xzf /tmp/panel-vendor.tar.gz -C "${PANEL_DIR}" vendor 2>/dev/null || true
        rm -f /tmp/panel-vendor.tar.gz
    fi
fi

if [[ ! -f "${PANEL_DIR}/vendor/autoload.php" ]]; then
    print_fatal "Could not install or locate PHP vendor dependencies (vendor/autoload.php missing)."
fi
print_success "PHP dependencies verified."

# Ensure runtime framework cache directories are intact before artisan commands
mkdir -p "${PANEL_DIR}/storage/framework/views" \
         "${PANEL_DIR}/storage/framework/cache/data" \
         "${PANEL_DIR}/storage/framework/sessions" \
         "${PANEL_DIR}/storage/logs" \
         "${PANEL_DIR}/bootstrap/cache"
chmod -R 777 "${PANEL_DIR}/storage" "${PANEL_DIR}/bootstrap/cache" 2>/dev/null || true
rm -f "${PANEL_DIR}/bootstrap/cache/config.php" "${PANEL_DIR}/bootstrap/cache/services.php" 2>/dev/null || true

# Verify Application Encryption Key
print_info "Verifying application encryption key..."
if ! grep -q "^APP_KEY=base64:" "${PANEL_DIR}/.env"; then
    FALLBACK_KEY="base64:$(openssl rand -base64 32)"
    sed -i "s|^APP_KEY=.*|APP_KEY=${FALLBACK_KEY}|" "${PANEL_DIR}/.env" || echo "APP_KEY=${FALLBACK_KEY}" >> "${PANEL_DIR}/.env"
fi
print_success "Application encryption key ready."

# Run Migrations & Seeds
print_info "Executing database migrations and seeds..."
if ! php artisan migrate --seed --force --no-interaction >> "${INSTALL_LOG}" 2>&1; then
    echo -e "\033[38;5;196m--- Database Migration Error Output ---\033[0m" >&2
    tail -n 25 "${INSTALL_LOG}" 2>/dev/null || true
    echo -e "\033[38;5;196m---------------------------------------\033[0m" >&2
    print_fatal "Failed to migrate database."
fi

# Ensure users.external_id is nullable (resolves Doctrine DBAL strict-mode constraint)
php artisan tinker --execute="try { \Illuminate\Support\Facades\DB::statement('ALTER TABLE users MODIFY external_id VARCHAR(191) NULL DEFAULT NULL'); } catch (\Throwable \$e) {}" >> "${INSTALL_LOG}" 2>&1 || true

# Create Administrator User
print_info "Creating administrator user account (${ADMIN_USERNAME})..."

create_admin_success=0

# Attempt 1: Standard artisan p:user:make
if php artisan p:user:make \
    --email="${ADMIN_EMAIL}" \
    --username="${ADMIN_USERNAME}" \
    --name-first="${ADMIN_FIRST_NAME}" \
    --name-last="${ADMIN_LAST_NAME}" \
    --password="${ADMIN_PASSWORD}" \
    --admin=1 \
    --no-interaction >> "${INSTALL_LOG}" 2>&1; then
    create_admin_success=1
fi

# Attempt 2: Resilient framework fallback (handles existing users, updates password, sets root_admin)
if [[ $create_admin_success -eq 0 ]]; then
    print_info "Resolving user account via application framework..."
    local_tinker_code="
\$email = addslashes('${ADMIN_EMAIL}');
\$username = addslashes('${ADMIN_USERNAME}');
\$first = addslashes('${ADMIN_FIRST_NAME}');
\$last = addslashes('${ADMIN_LAST_NAME}');
\$pw = addslashes('${ADMIN_PASSWORD}');

\$user = \Pterodactyl\Models\User::where('email', \$email)->orWhere('username', \$username)->first();
if (\$user) {
    \$user->forceFill([
        'email' => \$email,
        'username' => \$username,
        'name_first' => \$first,
        'name_last' => \$last,
        'password' => Illuminate\Support\Facades\Hash::make(\$pw),
        'root_admin' => true,
    ])->skipValidation()->save();
    echo 'ADMIN_READY';
} else {
    \$user = new \Pterodactyl\Models\User([
        'uuid' => Ramsey\Uuid\Uuid::uuid4()->toString(),
        'email' => \$email,
        'username' => \$username,
        'name_first' => \$first,
        'name_last' => \$last,
        'password' => Illuminate\Support\Facades\Hash::make(\$pw),
        'root_admin' => true,
        'language' => 'en',
    ]);
    \$user->skipValidation()->save();
    echo 'ADMIN_READY';
}
"
    if php artisan tinker --execute="${local_tinker_code}" >> "${INSTALL_LOG}" 2>&1; then
        if grep -q "ADMIN_READY" "${INSTALL_LOG}"; then
            create_admin_success=1
        fi
    fi
fi

if [[ $create_admin_success -eq 1 ]]; then
    print_success "Administrator account verified and ready."
else
    echo -e "\033[38;5;196m--- User Creation Error Output ---\033[0m" >&2
    tail -n 25 "${INSTALL_LOG}" 2>/dev/null || true
    echo -e "\033[38;5;196m----------------------------------\033[0m" >&2
    print_fatal "Failed to create administrator account."
fi

# Setup Queue Worker
if [[ "${DEPLOY_MODE}" == "production" ]]; then
    print_info "Setting up production background queue worker (pteroq.service)..."
    cat > /etc/systemd/system/pteroq.service << EOF
[Unit]
Description=Nova Panel Queue Worker
After=redis-server.service

[Service]
User=www-data
Group=www-data
Restart=always
ExecStart=/usr/bin/php ${PANEL_DIR}/artisan queue:work --queue=high,standard,low --sleep=3 --tries=3
StartLimitInterval=180
StartLimitBurst=30
RestartSec=5s

[Install]
WantedBy=multi-user.target
EOF
    systemctl daemon-reload >> "${INSTALL_LOG}" 2>&1
    systemctl enable pteroq.service >> "${INSTALL_LOG}" 2>&1
    systemctl restart pteroq.service >> "${INSTALL_LOG}" 2>&1

    # Scheduled Tasks Cron
    print_info "Configuring scheduled cron worker..."
    (crontab -l -u www-data 2>/dev/null | grep -v "artisan schedule:run"; echo "* * * * * php ${PANEL_DIR}/artisan schedule:run >> /dev/null 2>&1") | crontab -u www-data - 2>/dev/null || true
else
    print_info "Development Mode: Synchronous queue configured. (Run 'nova queue' for background worker)."
fi

# 7. Web Server Configuration
if [[ "${DEPLOY_MODE}" == "production" && "${ACCESS_CHOICE:-1}" == "2" ]]; then
    obtain_letsencrypt_certificate "${PANEL_HOST}" "${SSL_EMAIL}"
fi
configure_webserver

# 8. Docker Engine & Wings Setup
install_docker_engine
install_wings_binary

# 9. Node Registration
register_local_node

# 10. Install Nova CLI
print_step "Installing Nova Panel CLI..."
mkdir -p "${PANEL_DIR}/installer"
cp -a "${SCRIPT_DIR}/." "${PANEL_DIR}/installer/" 2>/dev/null || true
chmod +x "${PANEL_DIR}/installer/"*.sh "${PANEL_DIR}/installer/modules/"*.sh "${PANEL_DIR}/installer/modules/access/"*.sh 2>/dev/null || true

CLI_TARGET="/usr/local/bin/nova"
if [[ ! -w "/usr/local/bin" ]]; then
    mkdir -p "${HOME}/.local/bin"
    CLI_TARGET="${HOME}/.local/bin/nova"
    export PATH="${HOME}/.local/bin:${PATH}"
fi

cp -f "${SCRIPT_DIR}/nova-cli.sh" "${CLI_TARGET}"
chmod +x "${CLI_TARGET}"
print_success "Nova CLI installed at: ${CLI_TARGET}"

# Final Permissions in Production
if [[ "${DEPLOY_MODE}" == "production" ]]; then
    chown -R www-data:www-data "${PANEL_DIR}" 2>/dev/null || true
fi

# 11. Final Installation Summary
print_step "Installation Complete"
echo -e "${GREEN}${BOLD}============================================================${RESET}"
echo -e "       ${GREEN}${BOLD}✔ NOVA PANEL SUCCESSFULLY INSTALLED${RESET}"
echo -e "${GREEN}${BOLD}============================================================${RESET}\n"

echo -e "  ${BOLD}Deployment Mode :${RESET} ${CYAN}${DEPLOY_MODE}${RESET}"
echo -e "  ${BOLD}Panel URL       :${RESET} ${CYAN}${PANEL_URL}${RESET}"
echo -e "  ${BOLD}Admin Username  :${RESET} ${ADMIN_USERNAME}"
echo -e "  ${BOLD}Admin Email     :${RESET} ${ADMIN_EMAIL}"
echo -e "  ${BOLD}Admin Password  :${RESET} [Protected - configured during setup]"

if [[ "${DEPLOY_MODE}" == "development" ]]; then
    echo -e "\n  ${YELLOW}${BOLD}CodeSandbox / Development Mode Information:${RESET}"
    echo -e "  - Server is running on: ${BOLD}http://0.0.0.0:${DEV_PORT:-8000}${RESET}"
    echo -e "  - CodeSandbox will forward this port automatically to a preview URL."
    echo -e "  - Database engine: SQLite (${DB_DATABASE})"
    echo -e "  - Wings virtualization: ${DIM}Disabled (Requires Production Linux VPS host)${RESET}"
else
    echo -e "  ${BOLD}Wings Status    :${RESET} Active & Registered to Local Node"
    echo -e "  ${BOLD}Default Ports   :${RESET} Allocations seeded (25565-25575)"
fi

echo -e "\n${BOLD}Management Commands:${RESET}"
echo -e "  - Check status:            ${CYAN}nova status${RESET}"
echo -e "  - View service logs:       ${CYAN}nova logs [panel|wings|nginx|tunnel|install]${RESET}"
echo -e "  - Create a full backup:    ${CYAN}nova backup${RESET}"
echo -e "  - Self-repair/diagnostics: ${CYAN}nova repair${RESET}"
echo -e "  - Apply safe updates:      ${CYAN}nova update${RESET}\n"

echo -e "${DIM}Detailed installation log: ${INSTALL_LOG}${RESET}\n"
