#!/usr/bin/env bash
# ==============================================================================
# Nova Panel Installer - Access Mode 3: Tunnel Access (Temporary & Permanent)
# ==============================================================================

install_cloudflared_binary() {
    if ! command_exists cloudflared; then
        print_info "Downloading official cloudflared tunnel client..."
        local arch
        arch=$(get_cpu_arch)
        local cf_url="https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-${arch}"

        curl -fsSL -o /usr/local/bin/cloudflared "${cf_url}" >> "${INSTALL_LOG}" 2>&1 || print_fatal "Failed to download cloudflared."
        chmod +x /usr/local/bin/cloudflared
        case ":${PATH}:" in
            *:/usr/local/bin:*) ;;
            *) export PATH="/usr/local/bin:${PATH}" ;;
        esac
        hash -r 2>/dev/null || true
    fi
    print_success "cloudflared binary ready: $(cloudflared --version | head -n 1)"
}

# Install cloudflared from Cloudflare's official APT repository (recommended).
install_cloudflared_apt() {
    # APT installs to /usr/bin, while the binary fallback uses /usr/local/bin.
    # Make sure both locations are reachable before deciding it is missing.
    case ":${PATH}:" in
        *:/usr/local/bin:*) ;;
        *) export PATH="/usr/local/bin:${PATH}" ;;
    esac
    hash -r 2>/dev/null || true

    if command_exists cloudflared; then
        print_info "cloudflared is already installed: $(cloudflared --version 2>/dev/null | head -n 1)"
        return 0
    fi

    if ! command_exists apt-get; then
        print_warning "APT was not found. Falling back to the official cloudflared binary download."
        install_cloudflared_binary
        return $?
    fi

    export DEBIAN_FRONTEND=noninteractive

    print_info "Adding the Cloudflare APT repository..."
    mkdir -p --mode=0755 /usr/share/keyrings

    if ! curl -fsSL https://pkg.cloudflare.com/cloudflare-main.gpg \
        | tee /usr/share/keyrings/cloudflare-main.gpg >/dev/null; then
        print_error "Could not download the Cloudflare GPG key."
        return 1
    fi

    echo 'deb [signed-by=/usr/share/keyrings/cloudflare-main.gpg] https://pkg.cloudflare.com/cloudflared any main' \
        | tee /etc/apt/sources.list.d/cloudflared.list >/dev/null

    print_info "Refreshing package lists and installing cloudflared..."
    apt-get update >> "${INSTALL_LOG}" 2>&1 || print_warning "apt-get update reported an issue. Continuing anyway."

    if ! apt-get install -y cloudflared >> "${INSTALL_LOG}" 2>&1; then
        print_error "Failed to install cloudflared from APT."
        print_info "Check the log at ${INSTALL_LOG}"
        return 1
    fi

    if ! command_exists cloudflared; then
        print_error "cloudflared is still not available on PATH."
        return 1
    fi

    print_success "cloudflared installed: $(cloudflared --version 2>/dev/null | head -n 1)"
}

configure_tunnel_access() {
    print_step "Configuring Access Mode: Secure Tunnel Access"

    echo -e "${CYAN}${BOLD}Tunnel Setup Information:${RESET}"
    echo -e "  Tunneling creates a secure, encrypted outbound connection to route"
    echo -e "  web traffic to Nova Panel without requiring public open ports (CGNAT/Firewall friendly)."
    echo -e "  ${YELLOW}${BOLD}Security Note:${RESET} This tunnel is ONLY for the Nova Panel web interface."
    echo -e "  It does NOT affect or modify game server ports (e.g. Minecraft 25565).\n"

    echo -e "  ${BOLD}[1] Temporary Tunnel${RESET} (Free instant URL via trycloudflare.com, no domain needed)"
    echo -e "  ${BOLD}[2] Permanent Tunnel${RESET} (Persistent hostname via Cloudflare Tunnel Token & Domain)\n"

    local tunnel_choice=""
    while [[ "$tunnel_choice" != "1" && "$tunnel_choice" != "2" ]]; do
        tunnel_choice=$(prompt_input "Select tunnel type [1 or 2]" "1")
    done

    install_cloudflared_apt || return 1

    CLOUDFLARED_BIN="$(command -v cloudflared 2>/dev/null || true)"
    if [[ -z "${CLOUDFLARED_BIN}" ]]; then
        for candidate in /usr/local/bin/cloudflared /usr/bin/cloudflared; do
            if [[ -x "${candidate}" ]]; then
                CLOUDFLARED_BIN="${candidate}"
                break
            fi
        done
    fi
    if [[ -z "${CLOUDFLARED_BIN}" ]]; then
        print_error "cloudflared was installed but its binary could not be located."
        return 1
    fi

    if [[ "$tunnel_choice" == "1" ]]; then
        configure_temporary_tunnel
    else
        configure_permanent_tunnel
    fi
}

configure_temporary_tunnel() {
    print_step "Setting up Temporary Quick Tunnel (trycloudflare.com)..."

    echo -e "${YELLOW}${BOLD}Notice:${RESET} Temporary tunnels generate a free random URL (e.g. https://xxx.trycloudflare.com)."
    echo -e "        The URL may change if the tunnel service is restarted.\n"

    # Create systemd service for temporary tunnel
    cat > /etc/systemd/system/nova-tunnel.service << EOF
[Unit]
Description=Nova Panel Cloudflare Temporary Quick Tunnel
After=network.target nginx.service

[Service]
Type=simple
User=root
ExecStart=${CLOUDFLARED_BIN:-/usr/bin/cloudflared} tunnel --url http://127.0.0.1:80 --logfile /var/log/nova-panel/tunnel.log --metrics 127.0.0.1:49312
Restart=always
RestartSec=5
StandardOutput=append:/var/log/nova-panel/tunnel.log
StandardError=append:/var/log/nova-panel/tunnel.log

[Install]
WantedBy=multi-user.target
EOF

    touch /var/log/nova-panel/tunnel.log
    chmod 600 /var/log/nova-panel/tunnel.log

    systemctl daemon-reload >> "${INSTALL_LOG}" 2>&1
    systemctl enable nova-tunnel.service >> "${INSTALL_LOG}" 2>&1
    systemctl restart nova-tunnel.service >> "${INSTALL_LOG}" 2>&1

    print_info "Waiting for temporary tunnel connection to establish..."
    local temp_url=""
    local attempts=0
    while [[ $attempts -lt 25 ]]; do
        sleep 2
        temp_url=$(grep -o 'https://[a-zA-Z0-9-]*\.trycloudflare\.com' /var/log/nova-panel/tunnel.log 2>/dev/null | tail -n 1)
        if [[ -n "$temp_url" ]]; then
            break
        fi
        attempts=$((attempts + 1))
    done

    if [[ -z "$temp_url" ]]; then
        print_warning "Tunnel started, but could not parse URL from log immediately."
        temp_url="https://<pending-check-nova-tunnel-status>"
    else
        print_success "Temporary tunnel established at: ${BOLD}${temp_url}${RESET}"
    fi

    PANEL_HOST=$(echo "$temp_url" | sed -e 's|^https://||')
    ACCESS_MODE="tunnel_temporary"
    PANEL_PROTOCOL="https"
    PANEL_PORT=443
    PANEL_URL="${temp_url}"
    USE_SSL=0 # Handled by Cloudflare edge

    # Save Access Config
    cat > "${NOVA_CONFIG_DIR}/access.env" << EOF
ACCESS_MODE=tunnel_temporary
PANEL_HOST=${PANEL_HOST}
PANEL_PROTOCOL=https
PANEL_PORT=443
PANEL_URL=${PANEL_URL}
TUNNEL_SERVICE=nova-tunnel
TUNNEL_TYPE=temporary
USE_SSL=0
EOF
    chmod 600 "${NOVA_CONFIG_DIR}/access.env"
}

configure_permanent_tunnel() {
    print_step "Setting up Permanent Tunnel (Cloudflare Zero Trust / Named Tunnel)..."

    echo -e "To configure a permanent tunnel with a custom domain on Cloudflare:"
    echo -e "1. Visit ${BOLD}Cloudflare Zero Trust Dashboard -> Networks -> Tunnels${RESET}"
    echo -e "2. Create a tunnel, choose 'Cloudflared', and copy the Tunnel Token."
    echo -e "3. In Public Hostname, route your domain to HTTP service: ${BOLD}http://localhost:80${RESET}\n"

    local cf_token=""
    while [[ -z "$cf_token" ]]; do
        cf_token=$(prompt_input "Paste your Cloudflare Tunnel Token")
        if [[ -z "$cf_token" ]]; then
            print_warning "Tunnel token is required for permanent tunnel mode."
        fi
    done

    local perm_domain=""
    while [[ -z "$perm_domain" ]]; do
        perm_domain=$(prompt_input "Enter the configured tunnel hostname (e.g. panel.yourdomain.com)")
        if ! validate_domain_syntax "$perm_domain"; then
            print_warning "Invalid domain format."
            perm_domain=""
        fi
    done

    # Save token in secure file
    cat > "${NOVA_CONFIG_DIR}/tunnel.env" << EOF
TUNNEL_TYPE=permanent
TUNNEL_DOMAIN=${perm_domain}
TUNNEL_TOKEN=${cf_token}
EOF
    chmod 600 "${NOVA_CONFIG_DIR}/tunnel.env"

    # Install cloudflared service with token
    print_info "Installing cloudflared service..."
    if ! "${CLOUDFLARED_BIN:-/usr/bin/cloudflared}" service install "${cf_token}" >> "${INSTALL_LOG}" 2>&1; then
        # Fallback manual systemd service if cloudflared service install fails
        cat > /etc/systemd/system/cloudflared.service << EOF
[Unit]
Description=cloudflared permanent tunnel
After=network.target

[Service]
TimeoutStartSec=0
Type=notify
ExecStart=${CLOUDFLARED_BIN:-/usr/bin/cloudflared} --no-autoupdate tunnel run --token ${cf_token}
Restart=on-failure
RestartSec=5s

[Install]
WantedBy=multi-user.target
EOF
        systemctl daemon-reload >> "${INSTALL_LOG}" 2>&1
    fi

    systemctl enable cloudflared >> "${INSTALL_LOG}" 2>&1
    systemctl restart cloudflared >> "${INSTALL_LOG}" 2>&1

    PANEL_HOST="${perm_domain}"
    ACCESS_MODE="tunnel_permanent"
    PANEL_PROTOCOL="https"
    PANEL_PORT=443
    PANEL_URL="https://${perm_domain}"
    USE_SSL=0 # Edge handles SSL

    # Save Access Config
    cat > "${NOVA_CONFIG_DIR}/access.env" << EOF
ACCESS_MODE=tunnel_permanent
PANEL_HOST=${PANEL_HOST}
PANEL_PROTOCOL=https
PANEL_PORT=443
PANEL_URL=${PANEL_URL}
TUNNEL_SERVICE=cloudflared
TUNNEL_TYPE=permanent
USE_SSL=0
EOF
    chmod 600 "${NOVA_CONFIG_DIR}/access.env"

    print_success "Permanent Cloudflare Tunnel active for: ${BOLD}${PANEL_URL}${RESET}"
}
