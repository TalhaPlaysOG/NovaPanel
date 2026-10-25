#!/usr/bin/env bash
# ==============================================================================
# Nova Panel Installer - Dependencies Module (Dev / CodeSandbox & VPS)
# ==============================================================================

install_system_dependencies() {
    print_step "Verifying Application Dependencies..."

    if [[ "${DEPLOY_MODE}" == "development" ]]; then
        # Development / CodeSandbox Mode: User-level dependencies
        print_info "Checking PHP availability..."
        if ! command_exists php; then
            if command_exists sudo && command_exists apt-get; then
                print_info "Installing PHP via apt..."
                sudo apt-get update -y >> "${INSTALL_LOG}" 2>&1
                sudo apt-get install -y php-cli php-mbstring php-xml php-curl php-zip php-sqlite3 php-mysql php-bcmath >> "${INSTALL_LOG}" 2>&1 || true
            elif command_exists nix-env; then
                print_info "Installing PHP via Nix..."
                nix-env -iA nixpkgs.php82 >> "${INSTALL_LOG}" 2>&1 || true
            fi
        fi

        if ! command_exists php; then
            print_fatal "PHP is not available in your PATH. Please install PHP 8.1+ in this environment."
        fi

        PHP_VER=$(php -r 'echo PHP_MAJOR_VERSION . "." . PHP_MINOR_VERSION;')
        print_success "PHP ${PHP_VER} is available: $(command -v php)"

        # Check Composer
        print_info "Checking Composer..."
        if ! command_exists composer; then
            print_info "Installing Composer locally..."
            mkdir -p "${HOME}/.local/bin"
            curl -sS https://getcomposer.org/installer | php -- --install-dir="${HOME}/.local/bin" --filename=composer >> "${INSTALL_LOG}" 2>&1 || true
            export PATH="${HOME}/.local/bin:${PATH}"
        fi

        if command_exists composer; then
            print_success "Composer is available: $(composer --version 2>/dev/null | head -n1)"
        else
            print_fatal "Composer is required to install PHP dependencies."
        fi

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

    # Install Composer
    print_info "Checking Composer installation..."
    if ! command_exists composer; then
        print_info "Downloading and installing Composer 2..."
        curl -sS https://getcomposer.org/installer | php -- --install-dir=/usr/local/bin --filename=composer >> "${INSTALL_LOG}" 2>&1 || print_fatal "Failed to install Composer."
    fi
    print_success "Composer is ready: $(composer --version | head -n 1)"

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
