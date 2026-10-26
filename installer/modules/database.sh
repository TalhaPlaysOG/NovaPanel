#!/usr/bin/env bash
# ==============================================================================
# Nova Panel Installer - Database Module (MariaDB / MySQL / SQLite)
# ==============================================================================

configure_database() {
    print_step "Configuring Application Database..."

    export DEBIAN_FRONTEND=noninteractive

    local can_use_mysql=0
    if command_exists mariadb || command_exists mysql; then
        can_use_mysql=1
    elif command_exists apt-get; then
        can_use_mysql=1
    fi

    if [[ $can_use_mysql -eq 1 ]]; then
        print_info "Provisioning MariaDB server for Nova Panel..."
        local SUDO_CMD=""
        if [[ $EUID -ne 0 ]] && command_exists sudo; then SUDO_CMD="sudo"; fi

        if ! command_exists mariadb && ! command_exists mysql; then
            $SUDO_CMD apt-get update -y >> "${INSTALL_LOG}" 2>&1 || true
            $SUDO_CMD apt-get install -y mariadb-server mariadb-client >> "${INSTALL_LOG}" 2>&1 || print_fatal "Failed to install MariaDB."
        fi

        # Kill any zombie/orphaned mysqld instances and clean stale socket/lock files
        $SUDO_CMD pkill -9 -f mysqld 2>/dev/null || true
        $SUDO_CMD pkill -9 -f mariadb 2>/dev/null || true
        $SUDO_CMD rm -f /run/mysqld/mysqld.sock /run/mysqld/mysqld.sock.lock /run/mysqld/mysqld.pid 2>/dev/null || true
        $SUDO_CMD rm -f /var/run/mysqld/mysqld.sock /var/run/mysqld/mysqld.sock.lock /var/run/mysqld/mysqld.pid 2>/dev/null || true
        $SUDO_CMD rm -f /var/lib/mysql/*.pid /var/lib/mysql/mysql.sock 2>/dev/null || true

        # Ensure required MariaDB runtime directories exist with full read/write permissions
        $SUDO_CMD mkdir -p /run/mysqld /var/run/mysqld /var/lib/mysql /var/log/mysql
        $SUDO_CMD chown -R mysql:mysql /run/mysqld /var/run/mysqld /var/lib/mysql /var/log/mysql 2>/dev/null || true
        $SUDO_CMD chmod 777 /run/mysqld /var/run/mysqld /var/log/mysql 2>/dev/null || true
        $SUDO_CMD touch /var/log/mysql/error.log 2>/dev/null || true
        $SUDO_CMD chown mysql:mysql /var/log/mysql/error.log 2>/dev/null || true

        # Container & cloud virtualization config override (disables native AIO to prevent OS errno 22 crashes)
        $SUDO_CMD mkdir -p /etc/mysql/mariadb.conf.d /etc/mysql/conf.d 2>/dev/null || true
        cat << 'EOF' | $SUDO_CMD tee /etc/mysql/mariadb.conf.d/99-novapanel.cnf >/dev/null 2>&1 || true
[mysqld]
innodb_use_native_aio = 0
bind-address = 0.0.0.0
socket = /run/mysqld/mysqld.sock
skip-name-resolve
EOF
        cat << 'EOF' | $SUDO_CMD tee /etc/mysql/conf.d/99-novapanel.cnf >/dev/null 2>&1 || true
[mysqld]
innodb_use_native_aio = 0
bind-address = 0.0.0.0
socket = /run/mysqld/mysqld.sock
skip-name-resolve
EOF

        # Initialize data directory if absent
        if [[ ! -d /var/lib/mysql/mysql ]]; then
            $SUDO_CMD mariadb-install-db --user=mysql --datadir=/var/lib/mysql >> "${INSTALL_LOG}" 2>&1 || \
            $SUDO_CMD mysql_install_db --user=mysql --datadir=/var/lib/mysql >> "${INSTALL_LOG}" 2>&1 || true
            $SUDO_CMD chown -R mysql:mysql /var/lib/mysql 2>/dev/null || true
        fi

        # Start MariaDB service (supports systemd and container sysvinit)
        if command_exists systemctl && [[ ${HAS_SYSTEMD:-0} -eq 1 ]]; then
            $SUDO_CMD systemctl enable mariadb >> "${INSTALL_LOG}" 2>&1 || $SUDO_CMD systemctl enable mysql >> "${INSTALL_LOG}" 2>&1 || true
            $SUDO_CMD systemctl restart mariadb >> "${INSTALL_LOG}" 2>&1 || $SUDO_CMD systemctl restart mysql >> "${INSTALL_LOG}" 2>&1 || true
        fi

        if ! mariadb-admin ping --silent 2>/dev/null && ! mysqladmin ping --silent 2>/dev/null; then
            if command_exists service; then
                $SUDO_CMD service mariadb restart >> "${INSTALL_LOG}" 2>&1 || $SUDO_CMD service mysql restart >> "${INSTALL_LOG}" 2>&1 || true
            fi
            if ! mariadb-admin ping --silent 2>/dev/null && ! mysqladmin ping --silent 2>/dev/null; then
                if [[ -x /etc/init.d/mariadb ]]; then
                    $SUDO_CMD /etc/init.d/mariadb restart >> "${INSTALL_LOG}" 2>&1 || true
                elif [[ -x /etc/init.d/mysql ]]; then
                    $SUDO_CMD /etc/init.d/mysql restart >> "${INSTALL_LOG}" 2>&1 || true
                fi
            fi
        fi

        # Standalone daemon fallback for container/cloud dev environments (Docker, CodeSandbox, Devbox)
        sleep 2
        if ! mariadb-admin ping --silent 2>/dev/null && ! mysqladmin ping --silent 2>/dev/null; then
            print_info "Starting MariaDB in container background mode..."
            if command_exists mariadbd; then
                $SUDO_CMD nohup mariadbd --user=mysql --innodb-use-native-aio=0 --skip-name-resolve --log-error=/var/log/mysql/error.log >> "${INSTALL_LOG}" 2>&1 &
            elif command_exists mysqld; then
                $SUDO_CMD nohup mysqld --user=mysql --innodb-use-native-aio=0 --skip-name-resolve --log-error=/var/log/mysql/error.log >> "${INSTALL_LOG}" 2>&1 &
            elif command_exists mysqld_safe; then
                $SUDO_CMD nohup mysqld_safe --user=mysql --skip-syslog --innodb-use-native-aio=0 --log-error=/var/log/mysql/error.log >> "${INSTALL_LOG}" 2>&1 &
            fi
        fi

        # Wait up to 25 seconds for MariaDB socket to become active
        print_info "Waiting for MariaDB server daemon to be ready..."
        local max_tries=25
        while [[ $max_tries -gt 0 ]]; do
            # Bridge socket locations between /run/mysqld and /var/run/mysqld
            if [[ -S /run/mysqld/mysqld.sock && ! -e /var/run/mysqld/mysqld.sock ]]; then
                $SUDO_CMD ln -sf /run/mysqld/mysqld.sock /var/run/mysqld/mysqld.sock 2>/dev/null || true
            elif [[ -S /var/run/mysqld/mysqld.sock && ! -e /run/mysqld/mysqld.sock ]]; then
                $SUDO_CMD ln -sf /var/run/mysqld/mysqld.sock /run/mysqld/mysqld.sock 2>/dev/null || true
            fi

            if mariadb-admin ping --silent 2>/dev/null || mysqladmin ping --silent 2>/dev/null || \
               mariadb -u root -e "SELECT 1;" >/dev/null 2>&1 || mysql -u root -e "SELECT 1;" >/dev/null 2>&1 || \
               mariadb -h 127.0.0.1 -u root -e "SELECT 1;" >/dev/null 2>&1 || \
               mysql -h 127.0.0.1 -u root -e "SELECT 1;" >/dev/null 2>&1 || \
               $SUDO_CMD mysql -e "SELECT 1;" >/dev/null 2>&1; then
                break
            fi
            sleep 1
            max_tries=$((max_tries - 1))
        done

        # Database parameters
        DB_CONNECTION="mysql"
        DB_NAME="${DB_NAME:-novapanel}"
        DB_USER="${DB_USER:-novapanel}"
        DB_HOST="${DB_HOST:-127.0.0.1}"
        DB_PORT="${DB_PORT:-3306}"

        if [[ -z "${DB_PASSWORD:-}" ]]; then
            DB_PASSWORD=$(generate_random_token 32)
        fi

        print_info "Configuring database '${DB_NAME}' and user '${DB_USER}'..."

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

        local db_configured=0

        # Method A: Debian/Ubuntu system maintenance credentials
        if [[ -f /etc/mysql/debian.cnf ]]; then
            if $SUDO_CMD mariadb --defaults-file=/etc/mysql/debian.cnf -e "${sql_query}" >> "${INSTALL_LOG}" 2>&1; then
                db_configured=1
            elif $SUDO_CMD mysql --defaults-file=/etc/mysql/debian.cnf -e "${sql_query}" >> "${INSTALL_LOG}" 2>&1; then
                db_configured=1
            fi
        fi

        # Method B: Direct socket / root authentication
        if [[ $db_configured -eq 0 ]]; then
            if mariadb -u root -e "${sql_query}" >> "${INSTALL_LOG}" 2>&1; then
                db_configured=1
            elif mysql -u root -e "${sql_query}" >> "${INSTALL_LOG}" 2>&1; then
                db_configured=1
            elif $SUDO_CMD mariadb -u root -e "${sql_query}" >> "${INSTALL_LOG}" 2>&1; then
                db_configured=1
            elif $SUDO_CMD mysql -u root -e "${sql_query}" >> "${INSTALL_LOG}" 2>&1; then
                db_configured=1
            elif mariadb -u root --socket=/run/mysqld/mysqld.sock -e "${sql_query}" >> "${INSTALL_LOG}" 2>&1; then
                db_configured=1
            elif mariadb -u root --socket=/var/run/mysqld/mysqld.sock -e "${sql_query}" >> "${INSTALL_LOG}" 2>&1; then
                db_configured=1
            elif mysql -u root --socket=/run/mysqld/mysqld.sock -e "${sql_query}" >> "${INSTALL_LOG}" 2>&1; then
                db_configured=1
            elif mysql -u root --socket=/var/run/mysqld/mysqld.sock -e "${sql_query}" >> "${INSTALL_LOG}" 2>&1; then
                db_configured=1
            elif mariadb -h 127.0.0.1 -u root -e "${sql_query}" >> "${INSTALL_LOG}" 2>&1; then
                db_configured=1
            elif mysql -h 127.0.0.1 -u root -e "${sql_query}" >> "${INSTALL_LOG}" 2>&1; then
                db_configured=1
            fi
        fi

        # Method C: Interactive password prompt if passwordless was explicitly revoked
        if [[ $db_configured -eq 0 ]]; then
            if mariadb-admin ping --silent 2>/dev/null || mysqladmin ping --silent 2>/dev/null || \
               nc -z 127.0.0.1 3306 2>/dev/null; then
                print_warning "Passwordless root database access was refused."
                echo -ne " ${CYAN}?${RESET} Enter MySQL/MariaDB root password (leave blank if none): " >&2
                read -s -r db_root_pw
                echo "" >&2

                if [[ -z "$db_root_pw" ]]; then
                    if mariadb -u root -e "${sql_query}" >> "${INSTALL_LOG}" 2>&1 || \
                       $SUDO_CMD mysql -e "${sql_query}" >> "${INSTALL_LOG}" 2>&1; then
                        db_configured=1
                    fi
                else
                    if mariadb -u root -p"${db_root_pw}" -e "${sql_query}" >> "${INSTALL_LOG}" 2>&1 || \
                       mysql -u root -p"${db_root_pw}" -e "${sql_query}" >> "${INSTALL_LOG}" 2>&1; then
                        db_configured=1
                    fi
                fi
            fi
        fi

        if [[ $db_configured -eq 1 ]]; then
            print_success "Database '${DB_NAME}' and user '${DB_USER}' successfully configured."
        else
            echo -e "\033[38;5;196m--- MariaDB Diagnostic Log ---\033[0m" >&2
            if [[ -f /var/log/mysql/error.log ]]; then
                echo -e "\033[38;5;220m[Last error.log lines]:\033[0m" >&2
                tail -n 15 /var/log/mysql/error.log 2>/dev/null || true
            fi
            tail -n 25 "${INSTALL_LOG}" 2>/dev/null || true
            echo -e "\033[38;5;196m-------------------------------\033[0m" >&2
            print_fatal "Could not configure database. Please verify MariaDB service status."
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
        chmod 600 "${NOVA_CONFIG_DIR}/database.env" 2>/dev/null || true
        print_success "Database configuration verified.\n"
        return 0
    fi

    # Fallback only for restricted environments without apt or mysql
    print_info "Setting up local SQLite database..."
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
    print_success "SQLite database initialized: ${DB_DATABASE}\n"
}
