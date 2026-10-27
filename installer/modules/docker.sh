#!/usr/bin/env bash
# ==============================================================================
# Nova Panel Installer - Docker Module (Dev / CodeSandbox & VPS)
# ==============================================================================

install_docker_engine() {
    print_step "Installing and Configuring Docker Engine..."

    # In Development / CodeSandbox Mode:
    if [[ "${DEPLOY_MODE}" == "development" ]]; then
        if command_exists docker; then
            print_info "Docker client detected in development environment: $(docker --version)"
        else
            print_info "Development / CodeSandbox Mode: Skipping host Docker engine installation."
            print_info "Panel-only development mode active. Docker is not required for testing the web panel."
        fi
        return 0
    fi

    # In Production VPS Mode:
    export DEBIAN_FRONTEND=noninteractive

    if command_exists docker; then
        print_info "Docker is already installed: $(docker --version)"
    else
        print_info "Setting up Docker official repository..."
        install -m 0755 -d /etc/apt/keyrings

        if ! command_exists gpg; then
            apt-get install -y gnupg ca-certificates >> "${INSTALL_LOG}" 2>&1 || true
        fi

        local keyring="/etc/apt/keyrings/docker.gpg"
        if [[ ! -f "$keyring" ]]; then
            curl -fsSL "https://download.docker.com/linux/${OS_ID}/gpg" | gpg --dearmor -o "$keyring" >> "${INSTALL_LOG}" 2>&1 || print_fatal "Failed to download Docker GPG key."
            chmod a+r "$keyring"
        fi

        local os_codename
        os_codename=$(lsb_release -cs 2>/dev/null || true)
        if [[ -z "$os_codename" && -f /etc/os-release ]]; then
            # shellcheck disable=SC1091
            os_codename=$(. /etc/os-release && echo "${VERSION_CODENAME:-stable}")
        fi
        [[ -z "$os_codename" ]] && os_codename="stable"

        echo \
          "deb [arch=$(dpkg --print-architecture) signed-by=${keyring}] https://download.docker.com/linux/${OS_ID} \
          ${os_codename} stable" > /etc/apt/sources.list.d/docker.list

        apt-get update -y >> "${INSTALL_LOG}" 2>&1

        print_info "Installing Docker Engine and containerd packages..."
        apt-get install -y --no-install-recommends \
            docker-ce \
            docker-ce-cli \
            containerd.io \
            docker-buildx-plugin \
            docker-compose-plugin >> "${INSTALL_LOG}" 2>&1 || print_fatal "Failed to install Docker."
    fi

    mkdir -p /etc/docker
    if [[ ! -f /etc/docker/daemon.json ]]; then
        cat > /etc/docker/daemon.json << "EOF"
{
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "10m",
    "max-file": "3"
  }
}
EOF
    fi

    systemctl enable docker >> "${INSTALL_LOG}" 2>&1
    systemctl restart docker >> "${INSTALL_LOG}" 2>&1

    print_info "Testing Docker daemon connectivity..."
    if docker info >> "${INSTALL_LOG}" 2>&1; then
        print_success "Docker Engine is active and responding."
    else
        print_fatal "Docker daemon failed to start. Check 'systemctl status docker' for details."
    fi

    print_success "Docker installation verified.\n"
}
