#!/usr/bin/env bash
# ==============================================================================
# Nova Panel Installer - Wings Daemon Module (Dev / CodeSandbox & VPS)
# ==============================================================================

WINGS_VERSION="v1.13.4"

install_wings_binary() {
    print_step "Installing Official Wings Daemon (${WINGS_VERSION})..."

    # In Development / CodeSandbox Mode:
    if [[ "${DEPLOY_MODE}" == "development" ]]; then
        print_info "Development / CodeSandbox Mode: Skipping background Wings daemon installation."
        print_info "Wings requires root privileges, Linux kernel cgroups, and a production host."
        print_info "Panel-only testing mode will be used."
        return 0
    fi

    # In Production VPS Mode:
    mkdir -p /etc/pterodactyl /var/log/pterodactyl /var/lib/pterodactyl/volumes /var/lib/pterodactyl/backups
    chmod 755 /var/lib/pterodactyl/volumes

    local arch
    arch=$(get_cpu_arch)

    local wings_download_url="https://github.com/pterodactyl/wings/releases/download/${WINGS_VERSION}/wings_linux_${arch}"
    print_info "Downloading Wings ${WINGS_VERSION} for ${arch}..."

    curl -sSLo /usr/local/bin/wings "${wings_download_url}" >> "${INSTALL_LOG}" 2>&1 || print_fatal "Failed to download Wings daemon."
    chmod +x /usr/local/bin/wings

    print_success "Wings binary installed: $(/usr/local/bin/wings version 2>/dev/null || echo "${WINGS_VERSION}")"

    print_info "Creating Wings systemd service..."
    cat > /etc/systemd/system/wings.service << "EOF"
[Unit]
Description=Wings Daemon
After=docker.service
Requires=docker.service
PartOf=docker.service

[Service]
User=root
WorkingDirectory=/etc/pterodactyl
LimitNOFILE=4096
PIDFile=/var/run/wings/daemon.pid
ExecStart=/usr/local/bin/wings
Restart=on-failure
StartLimitInterval=180
StartLimitBurst=30
RestartSec=5s

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload >> "${INSTALL_LOG}" 2>&1
    systemctl enable wings >> "${INSTALL_LOG}" 2>&1

    print_success "Wings daemon service installed and enabled.\n"
}
