#!/usr/bin/env bash
# ==============================================================================
# Nova Panel - Interactive Setup Menu
#
# A button-driven control surface for the most common deployment tasks:
#   1) Install Panel          - full automated panel installation
#   2) Install Wings          - Docker + Wings daemon on this machine
#   3) Setup Tunnel           - Cloudflare cloudflared (APT) + tunnel token
#   4) Auto Node              - create a node from an IP and bring it online
#   5) Create User            - add a new panel account / administrator
#   6) Status                 - show services and access configuration
#   7) Update Panel           - pull the latest release and migrate
#   8) Repair Panel           - diagnostics and common fixes
#
# Usage:
#   sudo bash installer/nova-menu.sh          # interactive menu
#   sudo bash installer/nova-menu.sh --tunnel # run a single action
#   sudo nova menu                            # after installation
# ==============================================================================

set -o pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

print_plain_help() {
    cat << 'EOF'
Nova Panel - Interactive Setup Menu

Usage: bash installer/nova-menu.sh [OPTIONS]

Options:
  --menu            Open the interactive menu (default)
  --panel           Install Nova Panel
  --wings           Install Docker + Wings on this machine
  --tunnel          Install cloudflared and configure a Cloudflare tunnel
  --node            Create a node from an IP address and bring it online
  --user            Create a new panel user
  --status          Show service and access status
  --update          Update Nova Panel to the latest release
  --repair          Run diagnostics and fix common issues
  --dev             Force development / CodeSandbox mode
  --prod            Force production VPS mode
  -h, --help        Show this help

Examples:
  sudo bash installer/nova-menu.sh
  sudo bash installer/nova-menu.sh --tunnel
  sudo bash installer/nova-menu.sh --node
  bash <(curl -fsSL https://raw.githubusercontent.com/TalhaPlaysOG/NovaPanel/main/installer/nova-menu.sh)
EOF
}

# ------------------------------------------------------------------------------
# Self bootstrap: allow "bash <(curl ...)" execution without a cloned repo
# ------------------------------------------------------------------------------
if [[ ! -f "${SCRIPT_DIR}/common.sh" ]]; then
    NOVA_REPO="${NOVA_REPO:-TalhaPlaysOG/NovaPanel}"
    NOVA_BRANCH="${NOVA_BRANCH:-main}"
    BOOTSTRAP_DIR="/tmp/nova-panel-src"

    echo -e "\033[38;5;45m==>\033[0m Downloading Nova Panel installer bundle from ${NOVA_REPO} (${NOVA_BRANCH})..."
    rm -rf "${BOOTSTRAP_DIR}"
    mkdir -p "${BOOTSTRAP_DIR}"

    if curl -fsSL --connect-timeout 10 -m 90 -H "User-Agent: NovaMenuInstaller" \
        "https://codeload.github.com/${NOVA_REPO}/tar.gz/refs/heads/${NOVA_BRANCH}" \
        -o "${BOOTSTRAP_DIR}/src.tar.gz" 2>/dev/null \
        && tar -xzf "${BOOTSTRAP_DIR}/src.tar.gz" -C "${BOOTSTRAP_DIR}" --strip-components=1 2>/dev/null \
        && [[ -f "${BOOTSTRAP_DIR}/installer/nova-menu.sh" ]]; then
        rm -f "${BOOTSTRAP_DIR}/src.tar.gz"
        exec bash "${BOOTSTRAP_DIR}/installer/nova-menu.sh" "$@"
    fi

    echo -e "\033[38;5;196mError:\033[0m Unable to download the Nova Panel installer bundle." >&2
    echo -e "Clone the repository and run: sudo bash installer/nova-menu.sh" >&2
    exit 1
fi

# ------------------------------------------------------------------------------
# Argument parsing
# ------------------------------------------------------------------------------
REQUESTED_ACTION=""
FORWARD_ARGS=()

while [[ $# -gt 0 ]]; do
    case "$1" in
        --panel|--install-panel)
            REQUESTED_ACTION="panel"
            ;;
        --wings|--install-wings)
            REQUESTED_ACTION="wings"
            ;;
        --tunnel|--setup-tunnel)
            REQUESTED_ACTION="tunnel"
            ;;
        --node|--auto-node)
            REQUESTED_ACTION="node"
            ;;
        --user|--create-user)
            REQUESTED_ACTION="user"
            ;;
        --status)
            REQUESTED_ACTION="status"
            ;;
        --update|--upgrade)
            REQUESTED_ACTION="update"
            ;;
        --repair|--doctor)
            REQUESTED_ACTION="repair"
            ;;
        --menu)
            REQUESTED_ACTION=""
            ;;
        --repo|--branch)
            # Consumed by install.sh before the menu is launched; ignore the value.
            shift || true
            ;;
        --dev|--development)
            export DEPLOY_MODE="development"
            ;;
        --prod|--production)
            export DEPLOY_MODE="production"
            ;;
        -h|--help|help)
            print_plain_help
            exit 0
            ;;
        *)
            echo "Unknown option: $1" >&2
            print_plain_help >&2
            exit 1
            ;;
    esac
    shift
done

# ------------------------------------------------------------------------------
# Load installer framework
# ------------------------------------------------------------------------------
# shellcheck source=/dev/null
source "${SCRIPT_DIR}/common.sh"
# shellcheck source=/dev/null
source "${SCRIPT_DIR}/modules/docker.sh"
# shellcheck source=/dev/null
source "${SCRIPT_DIR}/modules/wings.sh"
# shellcheck source=/dev/null
source "${SCRIPT_DIR}/modules/access/domain.sh"
# shellcheck source=/dev/null
source "${SCRIPT_DIR}/modules/access/tunnel.sh"

# ------------------------------------------------------------------------------
# Environment
# ------------------------------------------------------------------------------
detect_environment

# Keep the log file writable when the menu is used as a non-root user.
if [[ ${EUID} -ne 0 && "${DEPLOY_MODE}" == "production" ]]; then
    LOG_DIR="${TMPDIR:-/tmp}/nova-panel-logs"
    INSTALL_LOG="${LOG_DIR}/install.log"
fi

init_logging

# The Docker module relies on the OS identifier, which is normally populated by
# the system-checks module. Detect it here so standalone actions also work.
if [[ -z "${OS_ID:-}" && -f /etc/os-release ]]; then
    # shellcheck disable=SC1091
    source /etc/os-release
    OS_ID="${ID:-unknown}"
    OS_VERSION_ID="${VERSION_ID:-unknown}"
fi

# Resolve the panel directory (installed location first, then repository copy)
if [[ -f "/var/www/nova-panel/artisan" ]]; then
    PANEL_DIR="/var/www/nova-panel"
elif [[ -f "${SCRIPT_DIR}/../panel/artisan" ]]; then
    PANEL_DIR="$(cd "${SCRIPT_DIR}/../panel" && pwd)"
fi

HELPERS_DIR="${SCRIPT_DIR}/helpers"

# ------------------------------------------------------------------------------
# Small helpers
# ------------------------------------------------------------------------------
pause_menu() {
    echo ""
    read -r -p "  Press Enter to return to the menu..." _ || true
}

is_root() {
    [[ ${EUID} -eq 0 ]]
}

is_sandbox() {
    [[ -n "${CODESANDBOX_HOST:-}${CODESANDBOX_SSE:-}${CSB:-}${SANDBOX_ID:-}" || -f "/etc/sandbox" ]]
}

require_production() {
    if [[ "${DEPLOY_MODE}" != "production" ]]; then
        print_warning "This action requires a production Linux host (root, systemd and APT packages)."
        if ! is_root; then
            print_info "Re-run the menu as root: sudo bash ${BASH_SOURCE[0]}"
        fi
        print_info "Current mode: ${DEPLOY_MODE} (development / CodeSandbox)."
        return 1
    fi
    return 0
}

panel_is_installed() {
    [[ -f "${PANEL_DIR}/artisan" && -f "${PANEL_DIR}/.env" && -f "${PANEL_DIR}/vendor/autoload.php" ]]
}

require_panel_installed() {
    if ! panel_is_installed; then
        print_warning "Nova Panel is not installed on this machine yet (${PANEL_DIR})."
        print_info "Use option [1] Install Panel first."
        return 1
    fi
    return 0
}

fix_panel_permissions() {
    if [[ "${DEPLOY_MODE}" == "production" ]] && is_root; then
        chown -R www-data:www-data "${PANEL_DIR}/storage" "${PANEL_DIR}/bootstrap/cache" 2>/dev/null || true
        if [[ -f "${PANEL_DIR}/.env" ]]; then
            chown www-data:www-data "${PANEL_DIR}/.env" 2>/dev/null || true
        fi
    fi
}

prompt_new_password() {
    local prompt_text="$1"
    local pw=""
    local confirm_value=""

    while true; do
        echo -ne " ${CYAN}?${RESET} ${prompt_text}: " >&2
        read -r -s pw
        echo "" >&2

        if [[ -z "$pw" ]]; then
            echo -e " ${YELLOW}⚠${RESET}  ${YELLOW}Password cannot be empty.${RESET}" >&2
            continue
        fi

        if [[ ${#pw} -lt 8 ]]; then
            echo -e " ${YELLOW}⚠${RESET}  ${YELLOW}Password must be at least 8 characters.${RESET}" >&2
            continue
        fi

        echo -ne " ${CYAN}?${RESET} Confirm password: " >&2
        read -r -s confirm_value
        echo "" >&2

        if [[ "$pw" != "$confirm_value" ]]; then
            echo -e " ${YELLOW}⚠${RESET}  ${YELLOW}Passwords do not match. Please try again.${RESET}" >&2
            continue
        fi

        break
    done

    printf '%s' "$pw"
}

prompt_token() {
    local prompt_text="$1"
    local value=""

    while [[ -z "$value" ]]; do
        echo -ne " ${CYAN}?${RESET} ${prompt_text} (input hidden): " >&2
        read -r -s value
        echo "" >&2

        if [[ -z "$value" ]]; then
            echo -e " ${YELLOW}⚠${RESET}  ${YELLOW}The tunnel token cannot be empty.${RESET}" >&2
        fi
    done

    printf '%s' "$value"
}

is_valid_host() {
    local candidate="$1"
    if [[ "$candidate" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]]; then
        return 0
    fi
    if [[ "$candidate" =~ ^[a-zA-Z0-9]([a-zA-Z0-9.-]*[a-zA-Z0-9])?$ ]]; then
        return 0
    fi
    return 1
}

is_valid_port_spec() {
    [[ "$1" =~ ^[0-9]{4,5}(-[0-9]{4,5})?(,[0-9]{4,5}(-[0-9]{4,5})?)*$ ]]
}

load_access_config() {
    ACCESS_MODE="${ACCESS_MODE:-}"
    PANEL_HOST="${PANEL_HOST:-}"
    USE_SSL="${USE_SSL:-0}"

    if [[ -f "${NOVA_CONFIG_DIR}/access.env" ]]; then
        # shellcheck disable=SC1090
        source "${NOVA_CONFIG_DIR}/access.env"
    fi
}

update_env_value() {
    local key="$1"
    local value="$2"
    local env_file="${PANEL_DIR}/.env"

    [[ -f "$env_file" ]] || return 1

    if grep -qE "^${key}=" "$env_file"; then
        awk -v k="$key" -v v="$value" '$0 ~ "^"k"=" { print k "=" v; next } { print }' "$env_file" > "${env_file}.tmp" \
            && mv "${env_file}.tmp" "$env_file"
    else
        printf '%s=%s\n' "$key" "$value" >> "$env_file"
    fi

    chmod 600 "$env_file" 2>/dev/null || true
}

detect_safe_memory() {
    local total_mb safe_mb
    total_mb=$(free -m 2>/dev/null | awk '/^Mem:/{print $2}')
    [[ -z "$total_mb" ]] && total_mb=1024
    safe_mb=$((total_mb - 512))
    [[ $safe_mb -lt 512 ]] && safe_mb=512
    echo "$safe_mb"
}

detect_safe_disk() {
    local free_mb safe_mb
    free_mb=$(df -m /var/lib/pterodactyl/volumes 2>/dev/null | awk 'NR==2 {print $4}')
    if [[ -z "$free_mb" ]]; then
        free_mb=$(df -m / 2>/dev/null | awk 'NR==2 {print $4}')
    fi
    [[ -z "$free_mb" ]] && free_mb=4096
    safe_mb=$((free_mb - 2048))
    [[ $safe_mb -lt 1024 ]] && safe_mb=1024
    echo "$safe_mb"
}

node_api_token() {
    local config="/etc/pterodactyl/config.yml"
    [[ -f "$config" ]] || return 1

    local token_id token
    token_id=$(awk -F': ' '/^token_id:/{print $2; exit}' "$config")
    token=$(awk -F': ' '/^token:/{print $2; exit}' "$config")

    [[ -n "$token_id" && -n "$token" ]] || return 1
    printf '%s.%s' "$token_id" "$token"
}

verify_wings_api() {
    local scheme="${1:-http}"
    local token
    token=$(node_api_token) || return 1

    local url
    for url in "${scheme}://127.0.0.1:8080/api/system" "http://127.0.0.1:8080/api/system"; do
        if curl -fsS -k --max-time 6 -H "Authorization: Bearer ${token}" "$url" >/dev/null 2>&1; then
            return 0
        fi
    done

    return 1
}

# ------------------------------------------------------------------------------
# Action 1: Install Panel
# ------------------------------------------------------------------------------
menu_install_panel() {
    print_step "Install Nova Panel"

    if ! is_root && ! is_sandbox; then
        print_error "Installing the panel requires root privileges."
        print_info "Re-run with: sudo bash ${BASH_SOURCE[0]} --panel"
        return 1
    fi

    if panel_is_installed; then
        print_warning "Nova Panel already looks installed at ${PANEL_DIR}."
        if ! prompt_confirm "Run the installer again and reconfigure the panel?" "N"; then
            print_info "Cancelled. Nothing was changed."
            return 0
        fi
    fi

    if [[ "${DEPLOY_MODE}" == "production" ]] && ! is_root; then
        print_fatal "Production installation requires root. Run: sudo bash ${BASH_SOURCE[0]}"
    fi

    print_info "Launching the automated installer..."
    if bash "${SCRIPT_DIR}/install.sh" "${FORWARD_ARGS[@]}"; then
        print_success "Panel installation finished."
    else
        print_error "The installer reported an error. Review ${INSTALL_LOG}"
        return 1
    fi
}

# ------------------------------------------------------------------------------
# Action 2: Install Wings
# ------------------------------------------------------------------------------
menu_install_wings() {
    print_step "Install Wings Daemon"

    require_production || return 1
    require_root

    install_docker_engine
    install_wings_binary

    if ! panel_is_installed; then
        print_warning "Nova Panel is not installed on this machine."
        print_info "Wings is installed, but it still needs a node configuration from your panel."
        print_info "Copy it to /etc/pterodactyl/config.yml, then run: systemctl enable --now wings"
        return 0
    fi

    if [[ ! -f /etc/pterodactyl/config.yml ]]; then
        print_warning "Wings is installed, but it has no node configuration yet."
        if prompt_confirm "Create and configure a node now (Auto Node)?" "Y"; then
            menu_auto_node
        else
            print_info "Configure a node later from the panel or with option [4] Auto Node."
        fi
        return 0
    fi

    systemctl daemon-reload >> "${INSTALL_LOG}" 2>&1 || true
    systemctl enable wings >> "${INSTALL_LOG}" 2>&1 || true
    systemctl restart wings >> "${INSTALL_LOG}" 2>&1 || true
    sleep 3

    if systemctl is-active --quiet wings; then
        print_success "Wings daemon is installed and running."
        if verify_wings_api "http"; then
            print_success "Wings API is responding. The node is online."
        else
            print_warning "Wings is running but the API health check failed. See: journalctl -u wings -n 50"
        fi
    else
        print_warning "Wings was installed but is not running. See: journalctl -u wings -n 50"
    fi
}

# ------------------------------------------------------------------------------
# Action 3: Setup Tunnel (cloudflared via APT + token)
# ------------------------------------------------------------------------------
menu_setup_tunnel() {
    print_step "Setup Cloudflare Tunnel"

    require_production || return 1
    require_root

    print_info "This installs the cloudflared client and connects it with your tunnel token."
    print_info "Create the tunnel in Cloudflare Zero Trust -> Networks -> Tunnels and copy its token."

    install_cloudflared_apt || return 1

    local token
    token=$(prompt_token "Paste your Cloudflare Tunnel Token")

    if [[ "$token" != eyJ* ]]; then
        print_warning "That token does not look like a Cloudflare tunnel token (expected it to start with 'eyJ')."
        if ! prompt_confirm "Use it anyway?" "N"; then
            print_info "Cancelled. Nothing was changed."
            return 0
        fi
    fi

    mkdir -p /etc/cloudflared
    chmod 755 /etc/cloudflared

    print_info "Installing the cloudflared system service..."
    if ! cloudflared service install "$token" >> "${INSTALL_LOG}" 2>&1; then
        print_warning "cloudflared service install failed. Writing a systemd unit fallback..."
        local cf_bin
        cf_bin=$(command -v cloudflared 2>/dev/null || echo "/usr/local/bin/cloudflared")
        cat > /etc/systemd/system/cloudflared.service << EOF
[Unit]
Description=Cloudflare Tunnel
After=network.target

[Service]
Type=notify
TimeoutStartSec=0
ExecStart=${cf_bin} --no-autoupdate tunnel run --token ${token}
Restart=on-failure
RestartSec=5s

[Install]
WantedBy=multi-user.target
EOF
        systemctl daemon-reload >> "${INSTALL_LOG}" 2>&1 || true
    fi

    systemctl enable cloudflared >> "${INSTALL_LOG}" 2>&1 || true
    systemctl restart cloudflared >> "${INSTALL_LOG}" 2>&1 || true
    sleep 3

    mkdir -p "${NOVA_CONFIG_DIR}"
    cat > "${NOVA_CONFIG_DIR}/tunnel.env" << EOF
TUNNEL_TYPE=token
TUNNEL_TOKEN=${token}
EOF
    chmod 600 "${NOVA_CONFIG_DIR}/tunnel.env"

    if systemctl is-active --quiet cloudflared; then
        print_success "cloudflared is running and connected to Cloudflare."
    else
        print_warning "cloudflared was installed but the service is not active."
        print_info "Inspect the logs with: journalctl -u cloudflared -n 50"
    fi

    echo ""
    print_info "Last step in the Cloudflare dashboard:"
    print_info "  Public Hostname -> Service: HTTP -> localhost:80 (or http://127.0.0.1:80)"
    echo ""

    if prompt_confirm "Do you already have a public hostname routed to this tunnel?" "N"; then
        local hostname=""
        while [[ -z "$hostname" ]]; do
            hostname=$(prompt_input "Tunnel hostname (e.g. panel.yourdomain.com)")
            if ! validate_domain_syntax "$hostname"; then
                print_warning "Invalid domain format."
                hostname=""
            fi
        done

        configure_tunnel_panel_url "$hostname"
        print_success "Panel URL set to https://${hostname}"
        print_info "Open that address in your browser - HTTPS from Cloudflare also removes the"
        print_info "'information you're about to submit is not secure' browser warning."
    else
        print_info "When your hostname is ready, run: sudo nova menu --tunnel"
    fi
}

configure_tunnel_panel_url() {
    local hostname="$1"

    mkdir -p "${NOVA_CONFIG_DIR}"
    cat > "${NOVA_CONFIG_DIR}/access.env" << EOF
ACCESS_MODE=tunnel_permanent
PANEL_HOST=${hostname}
PANEL_PROTOCOL=https
PANEL_PORT=443
PANEL_URL=https://${hostname}
TUNNEL_SERVICE=cloudflared
TUNNEL_TYPE=permanent
USE_SSL=0
EOF
    chmod 600 "${NOVA_CONFIG_DIR}/access.env"

    if [[ -f "${PANEL_DIR}/.env" ]]; then
        update_env_value "APP_URL" "https://${hostname}"
        update_env_value "TRUSTED_PROXIES" "*"
        ( cd "${PANEL_DIR}" && php artisan config:clear >/dev/null 2>&1 ) || true
        fix_panel_permissions
    fi
}

# ------------------------------------------------------------------------------
# Action 4: Auto Node
# ------------------------------------------------------------------------------
menu_auto_node() {
    print_step "Automatic Node Setup"

    require_production || return 1
    require_panel_installed || return 1
    require_root

    # Auto Node is a one-shot setup: make sure the daemon is actually present.
    if ! command_exists docker; then
        print_info "Docker is not installed yet. Installing Docker Engine first..."
        install_docker_engine || print_warning "Docker installation reported an issue. Continuing anyway."
    fi

    if ! command_exists wings; then
        print_info "Wings is not installed yet. Installing the Wings daemon..."
        install_wings_binary
    fi

    load_access_config

    local default_scheme="http"
    if [[ "${USE_SSL:-0}" == "1" && "${ACCESS_MODE:-}" == "domain" ]]; then
        default_scheme="https"
    fi

    local node_ip=""
    local detected_ip
    detected_ip=$(get_public_ip)

    while true; do
        node_ip=$(prompt_input "Node IP address or hostname" "${detected_ip}")
        node_ip="${node_ip#http://}"
        node_ip="${node_ip#https://}"
        node_ip="${node_ip%%/*}"

        if is_valid_host "$node_ip"; then
            break
        fi
        print_warning "Please enter a valid IPv4 address or hostname."
    done

    local node_name
    node_name=$(prompt_input "Node name" "Nova-Node-1")
    node_name="${node_name:-Nova-Node-1}"

    local node_scheme
    node_scheme=$(prompt_input "Daemon scheme (http or https)" "${default_scheme}")
    if [[ "$node_scheme" != "https" ]]; then
        node_scheme="http"
    fi

    local default_memory default_disk
    default_memory=$(detect_safe_memory)
    default_disk=$(detect_safe_disk)

    local node_memory node_disk node_ports
    node_memory=$(prompt_input "Maximum memory for this node (MB)" "${default_memory}")
    node_disk=$(prompt_input "Maximum disk for this node (MB)" "${default_disk}")

    while true; do
        node_ports=$(prompt_input "Game port range to seed" "25565-25575")
        if is_valid_port_spec "$node_ports"; then
            break
        fi
        print_warning "Use a single port or a range such as 25565-25575."
    done

    print_info "Registering node '${node_name}' -> ${node_ip} (${node_scheme})..."

    local node_json
    if ! node_json=$(php "${HELPERS_DIR}/auto-node.php" \
        --panel="${PANEL_DIR}" \
        --ip="${node_ip}" \
        --name="${node_name}" \
        --scheme="${node_scheme}" \
        --memory="${node_memory}" \
        --disk="${node_disk}" \
        --ports="${node_ports}" \
        --proxy=0 2>> "${INSTALL_LOG}"); then
        print_error "Node registration failed. See ${INSTALL_LOG}"
        return 1
    fi

    local node_id
    node_id=$(printf '%s' "$node_json" | grep -o '"node_id":[0-9]*' | cut -d: -f2)

    if [[ -z "$node_id" ]]; then
        print_error "Could not determine the new node ID."
        return 1
    fi

    print_success "Node #${node_id} is registered in the panel."
    fix_panel_permissions

    print_info "Generating the Wings configuration (/etc/pterodactyl/config.yml)..."
    mkdir -p /etc/pterodactyl /var/lib/pterodactyl/volumes /var/log/pterodactyl
    chmod 755 /var/lib/pterodactyl/volumes 2>/dev/null || true

    if ( cd "${PANEL_DIR}" && php artisan p:node:configuration "${node_id}" --format=yaml ) \
        > /etc/pterodactyl/config.yml 2>> "${INSTALL_LOG}"; then
        chmod 600 /etc/pterodactyl/config.yml
        print_success "Wings configuration written."
    else
        print_error "Could not generate the Wings configuration."
        print_info "Try manually: cd ${PANEL_DIR} && php artisan p:node:configuration ${node_id} --format=yaml"
        return 1
    fi
    fix_panel_permissions

    local local_ip
    local_ip=$(get_local_ip)
    local node_is_local=0
    if [[ "$node_ip" == "${detected_ip}" || "$node_ip" == "${local_ip}" || "$node_ip" == "127.0.0.1" || "$node_ip" == "localhost" ]]; then
        node_is_local=1
    fi

    if [[ $node_is_local -eq 1 ]]; then
        print_info "Starting the Wings daemon..."
        systemctl daemon-reload >> "${INSTALL_LOG}" 2>&1 || true
        systemctl enable wings >> "${INSTALL_LOG}" 2>&1 || true
        systemctl restart wings >> "${INSTALL_LOG}" 2>&1 || true

        local attempts=0
        while [[ $attempts -lt 12 ]]; do
            sleep 2
            if systemctl is-active --quiet wings && verify_wings_api "${node_scheme}"; then
                break
            fi
            attempts=$((attempts + 1))
        done

        if systemctl is-active --quiet wings && verify_wings_api "${node_scheme}"; then
            print_success "Wings is online and answering the panel API."
        elif systemctl is-active --quiet wings; then
            print_warning "Wings is running, but the API health check failed."
            print_info "Check the node scheme/port and: journalctl -u wings -n 50"
        else
            print_error "Wings did not start. Review: journalctl -u wings -n 50"
        fi
    else
        print_info "Remote node detected (${node_ip})."
        print_info "Copy /etc/pterodactyl/config.yml to that machine, install Wings there and run:"
        print_info "  systemctl enable --now wings"
    fi

    echo ""
    echo -e "  ${BOLD}Node ID       :${RESET} ${node_id}"
    echo -e "  ${BOLD}Node Name     :${RESET} ${node_name}"
    echo -e "  ${BOLD}Node Address  :${RESET} ${node_scheme}://${node_ip}:8080"
    echo -e "  ${BOLD}Allocations   :${RESET} ${node_ports} @ ${node_ip}"
    echo ""
}

# ------------------------------------------------------------------------------
# Action 5: Create User
# ------------------------------------------------------------------------------
menu_create_user() {
    print_step "Create Panel User"

    require_panel_installed || return 1

    local email=""
    while true; do
        email=$(prompt_input "User email address")
        if [[ "$email" =~ ^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$ ]]; then
            break
        fi
        print_warning "Invalid email format. Please try again."
    done

    local username=""
    while true; do
        username=$(prompt_input "Username")
        if [[ "$username" =~ ^[a-zA-Z0-9][a-zA-Z0-9_.-]+[a-zA-Z0-9]$ ]]; then
            break
        fi
        print_warning "Username must be at least 3 characters, start and end with a letter or number,"
        print_warning "and may only contain letters, numbers, underscores, dots and dashes."
    done

    local first last
    first=$(prompt_input "First name" "Nova")
    last=$(prompt_input "Last name" "User")

    local password=""
    if prompt_confirm "Generate a random password automatically?" "N"; then
        password=$(generate_random_password 16)
    else
        password=$(prompt_new_password "Password (minimum 8 characters)")
    fi

    local is_admin=0
    if prompt_confirm "Grant root administrator access?" "N"; then
        is_admin=1
    fi

    print_info "Creating account '${username}'..."

    local result
    if ! result=$(NOVA_USER_PASSWORD="${password}" php "${HELPERS_DIR}/create-user.php" \
        --panel="${PANEL_DIR}" \
        --email="${email}" \
        --username="${username}" \
        --first="${first}" \
        --last="${last}" \
        --admin="${is_admin}" 2>> "${INSTALL_LOG}"); then
        print_error "User creation failed. See ${INSTALL_LOG}"
        return 1
    fi

    fix_panel_permissions

    local state
    state=$(printf '%s' "$result" | grep -o '"state":"[a-z]*"' | cut -d'"' -f4)
    [[ "$state" == "updated" ]] && print_warning "An account with that email or username already existed and was updated."
    [[ -z "$state" ]] && state="created"

    echo ""
    echo -e "  ${BOLD}Account         :${RESET} ${username} (${email})"
    echo -e "  ${BOLD}Password        :${RESET} ${password}"
    echo -e "  ${BOLD}Root Admin      :${RESET} $([[ $is_admin -eq 1 ]] && echo "Yes" || echo "No")"
    echo -e "  ${BOLD}Result          :${RESET} ${state}"
    echo -e "  ${DIM}Store the password now - it is not shown again.${RESET}"
    echo ""
}

# ------------------------------------------------------------------------------
# Action 6: Status
# ------------------------------------------------------------------------------
menu_status() {
    if [[ -f "${SCRIPT_DIR}/nova-cli.sh" ]]; then
        bash "${SCRIPT_DIR}/nova-cli.sh" status
    else
        print_warning "Status helper not found."
    fi
}

# ------------------------------------------------------------------------------
# Action 7: Update Panel
# ------------------------------------------------------------------------------
menu_update_panel() {
    print_step "Update Nova Panel"

    require_panel_installed || return 1

    if [[ "${DEPLOY_MODE}" == "production" ]] && ! is_root; then
        print_error "Updating a production panel requires root privileges."
        print_info "Re-run with: sudo bash ${BASH_SOURCE[0]} --update"
        return 1
    fi

    if bash "${SCRIPT_DIR}/update.sh"; then
        print_success "Update finished."
    else
        print_error "The update script reported an error. Review ${INSTALL_LOG}"
        return 1
    fi
}

# ------------------------------------------------------------------------------
# Action 8: Repair Panel
# ------------------------------------------------------------------------------
menu_repair_panel() {
    print_step "Repair Nova Panel"

    if [[ "${DEPLOY_MODE}" == "production" ]] && ! is_root; then
        print_error "Repairing a production panel requires root privileges."
        print_info "Re-run with: sudo bash ${BASH_SOURCE[0]} --repair"
        return 1
    fi

    if bash "${SCRIPT_DIR}/repair.sh"; then
        print_success "Repair finished."
    else
        print_error "The repair script reported an error. Review ${INSTALL_LOG}"
        return 1
    fi
}

# ------------------------------------------------------------------------------
# Menu
# ------------------------------------------------------------------------------
print_menu() {
    print_banner
    echo -e "${PURPLE}${BOLD}NOVA PANEL CONTROL MENU${RESET}  ${DIM}[${DEPLOY_MODE} mode]${RESET}"
    echo -e "${GRAY}------------------------------------------------------------${RESET}"

    if panel_is_installed; then
        echo -e " ${GREEN}●${RESET} Panel detected at ${BOLD}${PANEL_DIR}${RESET}"
    else
        echo -e " ${YELLOW}●${RESET} Panel not installed on this machine yet"
    fi

    echo ""
    echo -e "  ${BOLD}[1]${RESET}  Install Panel       ${DIM}Dependencies, database, webserver, admin account${RESET}"
    echo -e "  ${BOLD}[2]${RESET}  Install Wings       ${DIM}Docker engine + Wings daemon${RESET}"
    echo -e "  ${BOLD}[3]${RESET}  Setup Tunnel        ${DIM}cloudflared via APT + tunnel token${RESET}"
    echo -e "  ${BOLD}[4]${RESET}  Auto Node           ${DIM}Create a node from an IP and bring it online${RESET}"
    echo -e "  ${BOLD}[5]${RESET}  Create User         ${DIM}Add a panel account or administrator${RESET}"
    echo -e "  ${BOLD}[6]${RESET}  Status              ${DIM}Services, nodes and access configuration${RESET}"
    echo -e "  ${BOLD}[7]${RESET}  Update Panel        ${DIM}Fetch the latest release, migrate and clear caches${RESET}"
    echo -e "  ${BOLD}[8]${RESET}  Repair Panel        ${DIM}Diagnose services and fix common issues${RESET}"
    echo -e "  ${BOLD}[0]${RESET}  Exit"
    echo ""
}

run_menu() {
    while true; do
        print_menu
        local choice=""
        read -r -p "  Select an option: " choice || exit 0
        echo ""

        case "$choice" in
            1) menu_install_panel; pause_menu ;;
            2) menu_install_wings; pause_menu ;;
            3) menu_setup_tunnel; pause_menu ;;
            4) menu_auto_node; pause_menu ;;
            5) menu_create_user; pause_menu ;;
            6) menu_status; pause_menu ;;
            7) menu_update_panel; pause_menu ;;
            8) menu_repair_panel; pause_menu ;;
            0|q|Q|exit|quit) exit 0 ;;
            *) print_warning "Invalid selection '${choice}'."; sleep 1 ;;
        esac
    done
}

# ------------------------------------------------------------------------------
# Entry point
# ------------------------------------------------------------------------------
if ! is_root && ! is_sandbox; then
    print_warning "Running without root: actions that install or change services will need sudo."
fi

case "${REQUESTED_ACTION}" in
    panel) menu_install_panel ;;
    wings) menu_install_wings ;;
    tunnel) menu_setup_tunnel ;;
    node) menu_auto_node ;;
    user) menu_create_user ;;
    status) menu_status ;;
    update) menu_update_panel ;;
    repair) menu_repair_panel ;;
    *) run_menu ;;
esac
