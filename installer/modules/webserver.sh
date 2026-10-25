#!/usr/bin/env bash
# ==============================================================================
# Nova Panel Installer - Web Server Module (Dev Server & Nginx)
# ==============================================================================

configure_webserver() {
    print_step "Configuring Web Server Interface..."

    # 1. Development / CodeSandbox Mode (PHP Built-in Server)
    if [[ "${DEPLOY_MODE}" == "development" ]]; then
        print_info "Configuring development web server on port ${DEV_PORT:-8000}..."
        
        local run_script="${RUN_DIR}/serve.sh"
        mkdir -p "${RUN_DIR}"

        cat > "${run_script}" << EOF
#!/usr/bin/env bash
cd "${PANEL_DIR}"
exec php artisan serve --host=0.0.0.0 --port=${DEV_PORT:-8000}
EOF
        chmod +x "${run_script}"

        # Start development server in background
        print_info "Launching Nova Panel development server..."
        nohup "${run_script}" > "${LOG_DIR}/server.log" 2>&1 &
        echo $! > "${RUN_DIR}/server.pid"

        sleep 2
        if kill -0 "$(cat "${RUN_DIR}/server.pid")" 2>/dev/null; then
            print_success "Development server started on http://0.0.0.0:${DEV_PORT:-8000}"
        else
            print_warning "Development server reported an issue. Check ${LOG_DIR}/server.log"
        fi
        return 0
    fi

    # 2. Production VPS Mode (Nginx + PHP-FPM)
    export DEBIAN_FRONTEND=noninteractive
    apt-get install -y nginx >> "${INSTALL_LOG}" 2>&1 || print_fatal "Failed to install Nginx."

    # Detect PHP-FPM socket
    local php_sock=""
    for v in 8.3 8.2 8.1 8.0 ""; do
        if [[ -S "/run/php/php${v}-fpm.sock" ]]; then
            php_sock="/run/php/php${v}-fpm.sock"
            break
        elif [[ -S "/var/run/php/php${v}-fpm.sock" ]]; then
            php_sock="/var/run/php/php${v}-fpm.sock"
            break
        fi
    done

    if [[ -z "$php_sock" ]]; then
        php_sock="/run/php/php${PHP_VERSION:-8.2}-fpm.sock"
    fi

    print_info "Using PHP-FPM socket: ${php_sock}"

    rm -f /etc/nginx/sites-enabled/default

    local nginx_conf="/etc/nginx/sites-available/nova-panel.conf"

    if [[ "${USE_SSL:-0}" -eq 1 && -f "${SSL_CERT_PATH}" && -f "${SSL_KEY_PATH}" ]]; then
        print_info "Generating Nginx HTTPS configuration for ${PANEL_HOST}..."
        cat > "${nginx_conf}" << EOF
server_tokens off;

server {
    listen 80;
    server_name ${PANEL_HOST};
    return 301 https://\$server_name\$request_uri;
}

server {
    listen 443 ssl http2;
    server_name ${PANEL_HOST};

    root ${PANEL_DIR}/public;
    index index.html index.htm index.php;
    charset utf-8;

    ssl_certificate ${SSL_CERT_PATH};
    ssl_certificate_key ${SSL_KEY_PATH};
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers HIGH:!aNULL:!MD5;
    ssl_prefer_server_ciphers on;
    ssl_session_cache shared:SSL:10m;
    ssl_session_timeout 1d;

    client_max_body_size 100m;
    client_body_timeout 120s;
    sendfile off;

    add_header X-Content-Type-Options nosniff;
    add_header X-XSS-Protection "1; mode=block";
    add_header X-Robots-Tag none;
    add_header Content-Security-Policy "frame-ancestors 'self'";
    add_header X-Frame-Options SAMEORIGIN;
    add_header Referrer-Policy same-origin;

    location / {
        try_files \$uri \$uri/ /index.php?\$query_string;
    }

    location ~ \.php$ {
        fastcgi_split_path_info ^(.+\.php)(/.+)$;
        fastcgi_pass unix:${php_sock};
        fastcgi_index index.php;
        include fastcgi_params;
        fastcgi_param SCRIPT_FILENAME \$document_root\$fastcgi_script_name;
        fastcgi_param HTTP_PROXY "";
        fastcgi_intercept_errors off;
        fastcgi_buffer_size 16k;
        fastcgi_buffers 4 16k;
        fastcgi_connect_timeout 300;
        fastcgi_send_timeout 300;
        fastcgi_read_timeout 300;
    }

    location ~ /\.ht {
        deny all;
    }
}
EOF
    else
        print_info "Generating Nginx HTTP configuration for ${PANEL_HOST}..."
        cat > "${nginx_conf}" << EOF
server_tokens off;

server {
    listen 80;
    server_name ${PANEL_HOST} _;

    root ${PANEL_DIR}/public;
    index index.html index.htm index.php;
    charset utf-8;

    client_max_body_size 100m;
    client_body_timeout 120s;
    sendfile off;

    add_header X-Content-Type-Options nosniff;
    add_header X-XSS-Protection "1; mode=block";
    add_header X-Robots-Tag none;
    add_header Content-Security-Policy "frame-ancestors 'self'";
    add_header X-Frame-Options SAMEORIGIN;
    add_header Referrer-Policy same-origin;

    location / {
        try_files \$uri \$uri/ /index.php?\$query_string;
    }

    location ~ \.php$ {
        fastcgi_split_path_info ^(.+\.php)(/.+)$;
        fastcgi_pass unix:${php_sock};
        fastcgi_index index.php;
        include fastcgi_params;
        fastcgi_param SCRIPT_FILENAME \$document_root\$fastcgi_script_name;
        fastcgi_param HTTP_PROXY "";
        fastcgi_intercept_errors off;
        fastcgi_buffer_size 16k;
        fastcgi_buffers 4 16k;
        fastcgi_connect_timeout 300;
        fastcgi_send_timeout 300;
        fastcgi_read_timeout 300;
    }

    location ~ /\.ht {
        deny all;
    }
}
EOF
    fi

    ln -sf "${nginx_conf}" /etc/nginx/sites-enabled/nova-panel.conf

    print_info "Testing Nginx configuration syntax..."
    if nginx -t >> "${INSTALL_LOG}" 2>&1; then
        systemctl enable nginx >> "${INSTALL_LOG}" 2>&1
        systemctl restart nginx >> "${INSTALL_LOG}" 2>&1
        print_success "Nginx successfully configured and reloaded."
    else
        print_error "Nginx configuration test failed!"
        nginx -t
        print_fatal "Please inspect Nginx syntax errors above."
    fi

    local fpm_service="php${PHP_VERSION:-8.2}-fpm"
    systemctl enable "${fpm_service}" >> "${INSTALL_LOG}" 2>&1 || true
    systemctl restart "${fpm_service}" >> "${INSTALL_LOG}" 2>&1 || true
    print_success "Web server configuration complete.\n"
}
