#!/usr/bin/env bash
# ==============================================================================
# Nova Panel Installer - Dependencies Module (Dev / CodeSandbox & VPS)
# ==============================================================================

install_system_dependencies() {
    print_step "Verifying Application Dependencies..."

    if [[ "${DEPLOY_MODE}" == "development" ]]; then
        # Development / CodeSandbox Mode: User-level dependencies
        print_info "Checking PHP availability (PHP >= 8.2 required)..."
        local need_php_install=0
        if ! command_exists php; then
            need_php_install=1
        else
            if ! php -r 'exit(version_compare(PHP_VERSION, "8.2.0", ">=") ? 0 : 1);'; then
                print_warning "Installed PHP ($(php -r 'echo PHP_VERSION;')) is below required version 8.2."
                need_php_install=1
            fi
        fi

        if [[ $need_php_install -eq 1 ]]; then
            if command_exists apt-get; then
                print_info "Configuring PHP 8.2 repository via apt..."
                local SUDO_CMD=""
                if [[ $EUID -ne 0 ]] && command_exists sudo; then SUDO_CMD="sudo"; fi
                $SUDO_CMD apt-get update -y >> "${INSTALL_LOG}" 2>&1 || true
                $SUDO_CMD apt-get install -y software-properties-common ca-certificates lsb-release >> "${INSTALL_LOG}" 2>&1 || true
                if command_exists add-apt-repository; then
                    $SUDO_CMD add-apt-repository -y ppa:ondrej/php >> "${INSTALL_LOG}" 2>&1 || true
                fi
                $SUDO_CMD apt-get update -y >> "${INSTALL_LOG}" 2>&1 || true
                $SUDO_CMD apt-get install -y php8.2 php8.2-cli php8.2-common php8.2-mbstring php8.2-xml php8.2-curl php8.2-zip php8.2-sqlite3 php8.2-mysql php8.2-bcmath php8.2-intl >> "${INSTALL_LOG}" 2>&1 || true
                if command_exists update-alternatives && [[ -f /usr/bin/php8.2 ]]; then
                    $SUDO_CMD update-alternatives --set php /usr/bin/php8.2 >/dev/null 2>&1 || true
                fi
            elif command_exists nix-env; then
                print_info "Installing PHP 8.2 via Nix..."
                nix-env -iA nixpkgs.php82 >> "${INSTALL_LOG}" 2>&1 || true
            fi
        fi

        if ! command_exists php; then
            print_fatal "PHP is not available in your PATH. Please install PHP 8.2+ in this environment."
        fi

        PHP_VER=$(php -r 'echo PHP_MAJOR_VERSION . "." . PHP_MINOR_VERSION;')
        print_success "PHP ${PHP_VER} is available: $(command -v php)"

        # Check Composer through the shared bootstrap so PATH issues are fixed.
        print_info "Checking Composer..."
        if ! ensure_composer; then
            print_fatal "Composer is required to install PHP dependencies."
        fi
        print_success "Composer is available: $(composer --version 2>/dev/null | head -n1)"

        # Check SQLite or MySQL
        print_info "Checking database driver support..."
        if php -m | grep -qi sqlite; then
            print_success "SQLite PHP extension is enabled (ideal for development)."
        fi
        if php -m | grep -qi pdo_mysql; then
            print_success "MySQL/MariaDB PHP extension is enabled."
        fi

        print_success "Development dependencies verified.\n"
        return 0
    fi

    # Production VPS Mode: Full system package installation
    export DEBIAN_FRONTEND=noninteractive

    # Update package lists
    print_info "Updating apt package index..."
    apt-get update -y >> "${INSTALL_LOG}" 2>&1 || print_fatal "Failed to update package lists."

    # Install core utilities
    print_info "Installing core system utilities..."
    apt-get install -y --no-install-recommends \
        curl \
        tar \
        unzip \
        git \
        jq \
        dnsutils \
        software-properties-common \
        apt-transport-https \
        ca-certificates \
        gnupg \
        lsb-release \
        cron \
        ufw >> "${INSTALL_LOG}" 2>&1 || print_fatal "Failed to install core utilities."

    # Setup PHP repository
    PHP_VERSION="8.2"
    print_info "Configuring PHP ${PHP_VERSION} repository..."
    if [[ "${OS_ID}" == "ubuntu" ]]; then
        LC_ALL=C.UTF-8 add-apt-repository -y ppa:ondrej/php >> "${INSTALL_LOG}" 2>&1 || {
            print_warning "Failed to add ppa:ondrej/php, falling back to distribution PHP packages."
        }
    elif [[ "${OS_ID}" == "debian" ]]; then
        if [[ ! -f /etc/apt/trusted.gpg.d/php.gpg ]]; then
            curl -sSLo /etc/apt/trusted.gpg.d/php.gpg https://packages.sury.org/php/apt.gpg >> "${INSTALL_LOG}" 2>&1
            echo "deb https://packages.sury.org/php/ $(lsb_release -sc) main" > /etc/apt/sources.list.d/php.list
        fi
    fi

    apt-get update -y >> "${INSTALL_LOG}" 2>&1

    if ! apt-cache show "php${PHP_VERSION}-fpm" >/dev/null 2>&1; then
        PHP_VERSION="8.1"
    fi

    print_info "Installing PHP ${PHP_VERSION} with required extensions..."
    apt-get install -y --no-install-recommends \
        "php${PHP_VERSION}" \
        "php${PHP_VERSION}-cli" \
        "php${PHP_VERSION}-common" \
        "php${PHP_VERSION}-fpm" \
        "php${PHP_VERSION}-gd" \
        "php${PHP_VERSION}-mysql" \
        "php${PHP_VERSION}-mbstring" \
        "php${PHP_VERSION}-bcmath" \
        "php${PHP_VERSION}-xml" \
        "php${PHP_VERSION}-curl" \
        "php${PHP_VERSION}-zip" \
        "php${PHP_VERSION}-intl" >> "${INSTALL_LOG}" 2>&1 || print_fatal "Failed to install PHP and extensions."

    print_success "PHP ${PHP_VERSION} installed successfully."

    # Prefer the PHP version we just installed when several versions exist.
    if command_exists update-alternatives && [[ -x "/usr/bin/php${PHP_VERSION}" ]]; then
        update-alternatives --set php "/usr/bin/php${PHP_VERSION}" >/dev/null 2>&1 || true
    fi

    # Install Composer (handles minimal PATHs and installer failures)
    print_info "Checking Composer installation..."
    if ! ensure_composer; then
        print_fatal "Failed to install Composer. Install it manually from https://getcomposer.org/download/ and re-run the installer."
    fi
    print_success "Composer is ready: $(composer --version 2>/dev/null | head -n 1)"

    # Install and configure Redis
    print_info "Installing Redis server..."
    apt-get install -y redis-server >> "${INSTALL_LOG}" 2>&1 || print_fatal "Failed to install Redis server."
    systemctl enable redis-server >> "${INSTALL_LOG}" 2>&1
    systemctl restart redis-server >> "${INSTALL_LOG}" 2>&1

    if systemctl is-active --quiet redis-server; then
        print_success "Redis server is active and running."
    else
        print_warning "Redis server could not be confirmed active."
    fi

    print_success "System dependencies, PHP, Composer, and Redis installed.\n"
}
