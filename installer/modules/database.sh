#!/usr/bin/env bash
# ==============================================================================
# Nova Panel Installer - Database Module (SQLite / MariaDB / MySQL)
# ==============================================================================

configure_database() {
    print_step "Configuring Application Database..."

    # 1. Development / CodeSandbox Mode
    if [[ "${DEPLOY_MODE}" == "development" ]]; then
        print_info "Development environment detected. Setting up zero-config SQLite database..."
        
        DB_CONNECTION="sqlite"
        DB_DATABASE="${PANEL_DIR}/database/database.sqlite"
        mkdir -p "${PANEL_DIR}/database"
        touch "${DB_DATABASE}"
        chmod 664 "${DB_DATABASE}"

        mkdir -p "${NOVA_CONFIG_DIR}"
        cat > "${NOVA_CONFIG_DIR}/database.env" << EOF
DB_CONNECTION=sqlite
DB_DATABASE=${DB_DATABASE}
EOF
        print_success "Development SQLite database initialized: ${DB_DATABASE}\n"
        return 0
    fi

    # 2. Production VPS Mode (MariaDB / MySQL)
    export DEBIAN_FRONTEND=noninteractive

    if ! command_exists mariadb && ! command_exists mysql; then
        print_info "Installing MariaDB server..."
        apt-get install -y mariadb-server mariadb-client >> "${INSTALL_LOG}" 2>&1 || print_fatal "Failed to install MariaDB."
    else
        print_info "Existing database server detected. Using existing service."
    fi

    systemctl enable mariadb >> "${INSTALL_LOG}" 2>&1 || systemctl enable mysql >> "${INSTALL_LOG}" 2>&1
    systemctl start mariadb >> "${INSTALL_LOG}" 2>&1 || systemctl start mysql >> "${INSTALL_LOG}" 2>&1

    # Database parameters
    DB_CONNECTION="mysql"
    DB_NAME="${DB_NAME:-novapanel}"
    DB_USER="${DB_USER:-novapanel}"
    DB_HOST="${DB_HOST:-127.0.0.1}"
    DB_PORT="${DB_PORT:-3306}"

    # Generate secure password if not set
    if [[ -z "${DB_PASSWORD}" ]]; then
        DB_PASSWORD=$(generate_random_token 32)
    fi

    print_info "Configuring production database '${DB_NAME}' and user '${DB_USER}'..."

    local sql_query="
CREATE DATABASE IF NOT EXISTS \`${DB_NAME}\` DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
CREATE USER IF NOT EXISTS '${DB_USER}'@'127.0.0.1' IDENTIFIED BY '${DB_PASSWORD}';
ALTER USER '${DB_USER}'@'127.0.0.1' IDENTIFIED BY '${DB_PASSWORD}';
GRANT ALL PRIVILEGES ON \`${DB_NAME}\`.* TO '${DB_USER}'@'127.0.0.1' WITH GRANT OPTION;
CREATE USER IF NOT EXISTS '${DB_USER}'@'localhost' IDENTIFIED BY '${DB_PASSWORD}';
ALTER USER '${DB_USER}'@'localhost' IDENTIFIED BY '${DB_PASSWORD}';
GRANT ALL PRIVILEGES ON \`${DB_NAME}\`.* TO '${DB_USER}'@'localhost' WITH GRANT OPTION;
FLUSH PRIVILEGES;
"

    if mariadb -u root -e "${sql_query}" >> "${INSTALL_LOG}" 2>&1; then
        print_success "Database and user successfully provisioned."
    elif mysql -u root -e "${sql_query}" >> "${INSTALL_LOG}" 2>&1; then
        print_success "Database and user successfully provisioned."
    else
        print_warning "Unable to connect to database root without password."
        print_info "Prompting for database root password to create application credentials..."
        local db_root_pw
        db_root_pw=$(prompt_password "Enter MySQL/MariaDB root password")
        mariadb -u root -p"${db_root_pw}" -e "${sql_query}" >> "${INSTALL_LOG}" 2>&1 || \
        mysql -u root -p"${db_root_pw}" -e "${sql_query}" >> "${INSTALL_LOG}" 2>&1 || \
        print_fatal "Could not configure database. Please verify credentials."
    fi

    mkdir -p "${NOVA_CONFIG_DIR}"
    cat > "${NOVA_CONFIG_DIR}/database.env" << EOF
DB_CONNECTION=mysql
DB_HOST=${DB_HOST}
DB_PORT=${DB_PORT}
DB_DATABASE=${DB_NAME}
DB_USERNAME=${DB_USER}
DB_PASSWORD=${DB_PASSWORD}
EOF
    chmod 600 "${NOVA_CONFIG_DIR}/database.env"

    print_success "Database configuration saved securely.\n"
}
