#!/usr/bin/env bash
# ==============================================================================
# Nova Panel Installer - Access Mode 2: Custom Domain + HTTPS
# ==============================================================================

validate_domain_syntax() {
    local domain="$1"
    local regex="^([a-zA-Z0-9]([a-zA-Z0-9\-]{0,61}[a-zA-Z0-9])?\.)+[a-zA-Z]{2,}$"
    if [[ "$domain" =~ $regex ]]; then
        return 0
    else
        return 1
    fi
}

check_dns_resolution() {
    local domain="$1"
    local public_ip
    public_ip=$(get_public_ip)

    print_info "Verifying DNS records for ${BOLD}${domain}${RESET}..."

    local resolved_ip=""
    if command_exists dig; then
        resolved_ip=$(dig +short A "${domain}" 2>/dev/null | tail -n1)
    elif command_exists getent; then
        resolved_ip=$(getent ahosts "${domain}" 2>/dev/null | awk '{print $1}' | head -n1)
    elif command_exists nslookup; then
        resolved_ip=$(nslookup "${domain}" 2>/dev/null | awk '/^Address: / { print $2 }' | tail -n1)
    fi

    if [[ -z "$resolved_ip" ]]; then
        print_warning "Domain '${domain}' does not appear to resolve to any IP address."
        print_warning "Please ensure an 'A' record pointing to your server IP (${public_ip:-unknown}) has been added in DNS."
        return 1
    fi

    print_info "Domain resolves to: ${resolved_ip}"
    if [[ -n "$public_ip" && "$resolved_ip" != "$public_ip" ]]; then
        print_warning "Domain resolves to ${resolved_ip}, but your detected server public IP is ${public_ip}."
        print_warning "If you are behind Cloudflare Proxy (Orange Cloud), ensure SSL mode is set to 'Full (Strict)'."
    else
        print_success "DNS resolution matches server public IP (${resolved_ip})."
    fi

    return 0
}

configure_domain_access() {
    print_step "Configuring Access Mode: Custom Domain + HTTPS (Let's Encrypt)"

    local domain=""
    while true; do
        domain=$(prompt_input "Enter your fully-qualified domain name (e.g. panel.example.com)")
        if [[ -z "$domain" ]]; then
            print_warning "Domain cannot be empty."
            continue
        fi

        if ! validate_domain_syntax "$domain"; then
            print_warning "Invalid domain format. Example: panel.mydomain.com"
            continue
        fi

        if ! check_dns_resolution "$domain"; then
            if ! prompt_confirm "DNS validation failed or incomplete. Do you still want to proceed?" "N"; then
                print_info "Please update your DNS records and try again."
                continue
            fi
        fi

        break
    done

    PANEL_HOST="${domain}"
    ACCESS_MODE="domain"
    PANEL_PROTOCOL="https"
    PANEL_PORT=443
    PANEL_URL="https://${domain}"
    USE_SSL=1

    # Prompt email for Let's Encrypt expiration notifications
    SSL_EMAIL=$(prompt_input "Enter email for SSL certificate renewal alerts")
    while [[ -z "$SSL_EMAIL" || ! "$SSL_EMAIL" =~ ^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$ ]]; do
        print_warning "Please enter a valid email address."
        SSL_EMAIL=$(prompt_input "Enter email for SSL certificate alerts")
    done

    # Save Access Config
    cat > "${NOVA_CONFIG_DIR}/access.env" << EOF
ACCESS_MODE=domain
PANEL_HOST=${PANEL_HOST}
PANEL_PROTOCOL=${PANEL_PROTOCOL}
PANEL_PORT=${PANEL_PORT}
PANEL_URL=${PANEL_URL}
SSL_EMAIL=${SSL_EMAIL}
USE_SSL=1
EOF
    chmod 600 "${NOVA_CONFIG_DIR}/access.env"

    print_success "Domain and SSL configuration staged for: ${BOLD}${PANEL_URL}${RESET}\n"
}

obtain_letsencrypt_certificate() {
    local domain="$1"
    local email="$2"

    print_step "Obtaining Let's Encrypt SSL/TLS Certificate for ${domain}..."

    export DEBIAN_FRONTEND=noninteractive
    apt-get install -y certbot python3-certbot-nginx >> "${INSTALL_LOG}" 2>&1 || print_fatal "Failed to install certbot."

    # Stop temporary web servers if occupying port 80 during standalone cert generation
    systemctl stop nginx >> "${INSTALL_LOG}" 2>&1 || true

    print_info "Requesting ACME certificate from Let's Encrypt..."
    if certbot certonly --standalone \
        --non-interactive \
        --agree-tos \
        --no-eff-email \
        --email "${email}" \
        -d "${domain}" >> "${INSTALL_LOG}" 2>&1; then
        
        SSL_CERT_PATH="/etc/letsencrypt/live/${domain}/fullchain.pem"
        SSL_KEY_PATH="/etc/letsencrypt/live/${domain}/privkey.pem"
        print_success "SSL certificate successfully obtained for ${domain}!"
    else
        print_error "Failed to obtain certificate from Let's Encrypt."
        print_warning "Check if port 80 is open in firewall (ufw allow 80/tcp) and domain DNS points to this server."
        if prompt_confirm "Would you like to retry obtaining the certificate?" "Y"; then
            obtain_letsencrypt_certificate "${domain}" "${email}"
            return
        else
            print_warning "Falling back to self-signed temporary certificate to allow installation to proceed."
            mkdir -p /etc/nova-panel/ssl
            openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
                -keyout "/etc/nova-panel/ssl/${domain}.key" \
                -out "/etc/nova-panel/ssl/${domain}.crt" \
                -subj "/CN=${domain}" >> "${INSTALL_LOG}" 2>&1
            SSL_CERT_PATH="/etc/nova-panel/ssl/${domain}.crt"
            SSL_KEY_PATH="/etc/nova-panel/ssl/${domain}.key"
        fi
    fi
}
