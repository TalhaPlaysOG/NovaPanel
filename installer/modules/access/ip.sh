#!/usr/bin/env bash
# ==============================================================================
# Nova Panel Installer - Access Mode 1: IP Address & Forwarded Port
# ==============================================================================

configure_ip_access() {
    print_step "Configuring Access Mode: IP Address & Application Port"

    if [[ "${DEPLOY_MODE}" == "development" ]]; then
        PANEL_PORT="${DEV_PORT:-8000}"
        PANEL_PROTOCOL="http"
        PANEL_HOST="localhost"
        PANEL_URL="http://localhost:${PANEL_PORT}"

        if [[ $IS_CODESANDBOX -eq 1 ]]; then
            print_info "CodeSandbox environment detected."
            print_info "The application will bind to ${BOLD}0.0.0.0:${PANEL_PORT}${RESET}."
            print_info "CodeSandbox will automatically create a secure HTTPS forwarded preview URL."
        else
            print_info "Local development mode active on port ${PANEL_PORT}."
        fi

        USE_SSL=0
        ACCESS_MODE="ip_dev"
        mkdir -p "${NOVA_CONFIG_DIR}"
        cat > "${NOVA_CONFIG_DIR}/access.env" << EOF
ACCESS_MODE=ip_dev
PANEL_HOST=0.0.0.0
PANEL_PROTOCOL=http
PANEL_PORT=${PANEL_PORT}
PANEL_URL=${PANEL_URL}
USE_SSL=0
EOF
        print_success "Configured development URL: ${BOLD}${PANEL_URL}${RESET} (Port ${PANEL_PORT})\n"
        return 0
    fi

    # Production VPS Mode
    local detected_ip
    detected_ip=$(get_public_ip)

    if [[ -z "$detected_ip" ]]; then
        detected_ip=$(get_local_ip)
    fi

    echo -e "${YELLOW}${BOLD}Note:${RESET} Standard IP-based HTTP access does not provide TLS encryption."
    echo -e "      For public production deployments, a Custom Domain with HTTPS is strongly recommended.\n"

    PANEL_HOST=$(prompt_input "Enter public IP or hostname for the panel" "${detected_ip}")
    ACCESS_MODE="ip"
    PANEL_PROTOCOL="http"
    PANEL_PORT=80
    PANEL_URL="http://${PANEL_HOST}"

    if prompt_confirm "Do you have an existing SSL/TLS certificate for this IP?" "N"; then
        local cert_path
        local key_path
        cert_path=$(prompt_input "Enter path to SSL certificate (.crt/.pem)")
        key_path=$(prompt_input "Enter path to SSL private key (.key)")

        if [[ -f "$cert_path" && -f "$key_path" ]]; then
            PANEL_PROTOCOL="https"
            PANEL_PORT=443
            PANEL_URL="https://${PANEL_HOST}"
            SSL_CERT_PATH="$cert_path"
            SSL_KEY_PATH="$key_path"
            USE_SSL=1
            print_success "Custom SSL certificate loaded for IP access."
        else
            print_warning "Certificate files not found. Continuing with standard HTTP (port 80)."
            USE_SSL=0
        fi
    else
        USE_SSL=0
    fi

    mkdir -p "${NOVA_CONFIG_DIR}"
    cat > "${NOVA_CONFIG_DIR}/access.env" << EOF
ACCESS_MODE=ip
PANEL_HOST=${PANEL_HOST}
PANEL_PROTOCOL=${PANEL_PROTOCOL}
PANEL_PORT=${PANEL_PORT}
PANEL_URL=${PANEL_URL}
USE_SSL=${USE_SSL:-0}
EOF
    chmod 600 "${NOVA_CONFIG_DIR}/access.env"

    print_success "Configured Panel URL: ${BOLD}${PANEL_URL}${RESET}\n"
}
