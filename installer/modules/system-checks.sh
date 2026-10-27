#!/usr/bin/env bash
# ==============================================================================
# Nova Panel Installer - System Checks Module (Dev / CodeSandbox & VPS)
# ==============================================================================

check_system_prerequisites() {
    print_step "Running Environment & System Compatibility Checks..."

    # 1. Environment Mode Check
    if [[ "${DEPLOY_MODE}" == "development" ]]; then
        print_info "Deployment Mode: ${BOLD}${CYAN}Development / CodeSandbox Mode${RESET}"
        if [[ $IS_CODESANDBOX -eq 1 ]]; then
            print_info "Environment: ${BOLD}CodeSandbox Devbox / Cloud VM${RESET}"
        else
            print_info "Environment: ${BOLD}Local / Non-Root Container Environment${RESET}"
        fi
        print_info "Systemd / Privileged Docker requirements are ${GREEN}bypassed${RESET} for testing."
    else
        print_info "Deployment Mode: ${BOLD}${PURPLE}Production VPS Mode${RESET}"
        require_root
    fi

    # 2. OS & Distribution Detection
    if [[ -f /etc/os-release ]]; then
        # shellcheck source=/dev/null
        source /etc/os-release
        OS_ID="${ID:-unknown}"
        OS_VERSION_ID="${VERSION_ID:-unknown}"
        OS_PRETTY="${PRETTY_NAME:-Linux}"
        print_info "Detected OS: ${BOLD}${OS_PRETTY}${RESET} (${OS_ID} ${OS_VERSION_ID})"
    else
        OS_ID="generic"
        OS_PRETTY="Linux"
        print_info "Operating System: ${BOLD}${OS_PRETTY}${RESET}"
    fi

    if [[ "${DEPLOY_MODE}" == "production" ]]; then
        local is_supported=0
        case "${OS_ID}" in
            ubuntu)
                if [[ "${OS_VERSION_ID}" == "20.04" || "${OS_VERSION_ID}" == "22.04" || "${OS_VERSION_ID}" == "24.04" ]]; then
                    is_supported=1
                fi
                ;;
            debian)
                if [[ "${OS_VERSION_ID}" == "11" || "${OS_VERSION_ID}" == "12" ]]; then
                    is_supported=1
                fi
                ;;
        esac

        if [[ $is_supported -ne 1 ]]; then
            print_warning "Your operating system (${OS_PRETTY}) is not officially verified for automated VPS production."
            print_warning "Official verified distributions: Ubuntu 20.04/22.04/24.04 LTS, Debian 11/12."
            if ! prompt_confirm "Do you wish to proceed at your own risk?" "N"; then
                print_fatal "Installation aborted due to unsupported operating system."
            fi
        else
            print_success "Operating system verified for Production VPS: ${OS_PRETTY}"
        fi
    fi

    # 3. CPU Architecture
    ARCH=$(get_cpu_arch)
    print_info "Detected Architecture: ${BOLD}${ARCH}${RESET}"
    if [[ "${ARCH}" != "amd64" && "${ARCH}" != "arm64" ]]; then
        print_fatal "Unsupported architecture: ${ARCH}. Only x86_64/amd64 and aarch64/arm64 are supported."
    fi
    print_success "Architecture supported: ${ARCH}"

    # 4. Available Memory
    local total_mem_kb
    total_mem_kb=$(grep MemTotal /proc/meminfo 2>/dev/null | awk '{print $2}' || echo "2097152")
    local total_mem_mb=$((total_mem_kb / 1024))
    print_info "Available Memory: ${BOLD}${total_mem_mb} MB${RESET}"

    if [[ $total_mem_mb -lt 1000 ]]; then
        print_warning "System has only ${total_mem_mb} MB RAM. Panel will function, but memory is limited."
    else
        print_success "Memory requirements satisfied (${total_mem_mb} MB)."
    fi

    # 5. Disk Space
    local free_disk_kb
    free_disk_kb=$(df -k . 2>/dev/null | awk 'NR==2 {print $4}' || echo "10485760")
    local free_disk_mb=$((free_disk_kb / 1024))
    print_info "Available Storage: ${BOLD}${free_disk_mb} MB${RESET}"

    if [[ $free_disk_mb -lt 2000 ]]; then
        print_warning "Storage space is below 2 GB (${free_disk_mb} MB free)."
    else
        print_success "Storage requirements satisfied (${free_disk_mb} MB free)."
    fi

    # 6. Existing Installations Check
    if [[ -d "${PANEL_DIR}" && -f "${PANEL_DIR}/.env" ]]; then
        print_warning "Existing Nova Panel configuration detected in ${PANEL_DIR}."
        if ! prompt_confirm "Existing installation found. Continue and preserve existing database?" "Y"; then
            print_fatal "Installation aborted by user."
        fi
    fi

    # 7. Port Conflicts Check (Production Mode)
    if [[ "${DEPLOY_MODE}" == "production" ]]; then
        print_info "Checking essential production ports (80, 443, 8080, 2022)..."
        local conflicting_ports=()
        for port in 80 443 8080 2022; do
            if command_exists ss; then
                if ss -tlpn 2>/dev/null | grep -q ":${port} "; then
                    conflicting_ports+=("${port}")
                fi
            elif command_exists netstat; then
                if netstat -tlpn 2>/dev/null | grep -q ":${port} "; then
                    conflicting_ports+=("${port}")
                fi
            fi
        done

        if [[ ${#conflicting_ports[@]} -gt 0 ]]; then
            print_warning "Ports in active use: ${conflicting_ports[*]}"
            print_info "If Nginx or Wings is already installed, this is expected."
            if command_exists ss; then
                ss -tlpn 2>/dev/null | grep -E ':(80|443|8080|2022) ' | sed 's/^/    /' || true
            fi
        else
            print_success "Production ports are available."
        fi
    fi

    print_success "Prerequisite checks completed successfully.\n"
}
