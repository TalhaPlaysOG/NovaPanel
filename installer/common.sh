#!/usr/bin/env bash
# ==============================================================================
# Nova Panel Installer - Common Functions, Environment Detection & Helpers
# ==============================================================================

# Strict mode
set -o pipefail

# Text styles and colors
BOLD="\033[1m"
DIM="\033[2m"
ITALIC="\033[3m"
UNDERLINE="\033[4m"
RESET="\033[0m"

# Palette
CYAN="\033[38;5;45m"
BLUE="\033[38;5;33m"
PURPLE="\033[38;5;141m"
GREEN="\033[38;5;48m"
YELLOW="\033[38;5;220m"
RED="\033[38;5;196m"
GRAY="\033[38;5;244m"
WHITE="\033[38;5;255m"

# Detect Execution Environment (CodeSandbox vs Production VPS)
detect_environment() {
    IS_CODESANDBOX=0
    IS_WSL=0
    HAS_SYSTEMD=0
    HAS_ROOT=0
    SYSTEMD_PID1=""

    # CodeSandbox / Cloud VM heuristics
    if [[ -n "${CODESANDBOX_HOST:-}" || -n "${CODESANDBOX_SSE:-}" || -n "${CSB:-}" || -n "${SANDBOX_ID:-}" || -f "/etc/sandbox" ]]; then
        IS_CODESANDBOX=1
    fi

    # WSL heuristics (systemd is opt-in on WSL)
    if [[ -n "${WSL_DISTRO_NAME:-}" || -f "/proc/sys/fs/binfmt_misc/WSLInterop" ]]; then
        IS_WSL=1
    fi

    # Systemd init check
    SYSTEMD_PID1="$(ps -p 1 -o comm= 2>/dev/null | tr -d '[:space:]')"
    if [[ -d "/run/systemd/system" ]] && [[ "${SYSTEMD_PID1}" =~ ^(systemd|init)$ ]]; then
        HAS_SYSTEMD=1
    fi

    # Root privileges check
    if [[ $EUID -eq 0 ]]; then
        HAS_ROOT=1
    fi

    # Determine default mode if not explicitly set via --dev or --prod.
    # Root is checked separately by each action (with a "use sudo" hint), so a
    # normal VPS started without sudo is still recognized as production instead
    # of silently falling back to panel-only development mode.
    if [[ -z "${DEPLOY_MODE:-}" ]]; then
        if [[ $IS_CODESANDBOX -eq 1 || $HAS_SYSTEMD -eq 0 ]]; then
            DEPLOY_MODE="development"
        else
            DEPLOY_MODE="production"
        fi
    fi

    # Directory configuration based on mode
    if [[ "${DEPLOY_MODE}" == "development" ]]; then
        USER_HOME="${HOME:-/home/node}"
        LOG_DIR="${USER_HOME}/.nova-panel/logs"
        INSTALL_LOG="${LOG_DIR}/install.log"
        PANEL_DIR="${PANEL_DIR:-${USER_HOME}/nova-panel}"
        BACKUP_DIR="${USER_HOME}/.nova-panel/backups"
        NOVA_CONFIG_DIR="${USER_HOME}/.nova-panel/config"
        RUN_DIR="${USER_HOME}/.nova-panel/run"
        DEV_PORT="${DEV_PORT:-8000}"
    else
        LOG_DIR="/var/log/nova-panel"
        INSTALL_LOG="${LOG_DIR}/install.log"
        PANEL_DIR="/var/www/nova-panel"
        BACKUP_DIR="/var/backups/nova-panel"
        WINGS_CONFIG_DIR="/etc/pterodactyl"
        NOVA_CONFIG_DIR="/etc/nova-panel"
        RUN_DIR="/var/run/nova-panel"
    fi
}

# Run initial detection
detect_environment

# Ensure log and config directories exist
init_logging() {
    mkdir -p "${LOG_DIR}" "${NOVA_CONFIG_DIR}" "${BACKUP_DIR}" "${RUN_DIR}" 2>/dev/null || true
    touch "${INSTALL_LOG}" 2>/dev/null || true
    if [[ $EUID -eq 0 ]]; then
        chmod 600 "${INSTALL_LOG}" 2>/dev/null || true
    fi
}

# Logging Functions
log() {
    local level="$1"
    shift
    local msg="$*"
    local timestamp
    timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[${timestamp}] [${level}] ${msg}" >> "${INSTALL_LOG}" 2>/dev/null || true
}

print_info() {
    echo -e " ${CYAN}ℹ${RESET}  $*"
    log "INFO" "$*"
}

print_success() {
    echo -e " ${GREEN}✔${RESET}  ${GREEN}$*${RESET}"
    log "SUCCESS" "$*"
}

print_warning() {
    echo -e " ${YELLOW}⚠${RESET}  ${YELLOW}$*${RESET}"
    log "WARN" "$*"
}

print_error() {
    echo -e " ${RED}✖${RESET}  ${RED}$*${RESET}" >&2
    log "ERROR" "$*"
}

print_step() {
    echo -e "\n${PURPLE}==>${RESET} ${BOLD}$*${RESET}"
    log "STEP" "$*"
}

print_fatal() {
    echo -e "\n${RED}${BOLD}[FATAL ERROR]${RESET} ${RED}$*${RESET}" >&2
    log "FATAL" "$*"
    echo -e "${GRAY}View full logs at: ${INSTALL_LOG}${RESET}" >&2
    exit 1
}

# Banner
print_banner() {
    echo -e "${CYAN}"
    cat << "EOF"
  _   _  _____      __   _____        _   _ ______ _      
 | \ | |/ _ \ \    / //\ |  __ \ /\   | \ | |  ____| |     
 |  \| | | | \ \  / //  \| |__) /  \  |  \| | |__  | |     
 | . ` | | | |\ \/ // /\ \  ___/ /\ \ | . ` |  __| | |     
 | |\  | |_| | \  // ____ \ |  / ____ \| |\  | |____| |____ 
 |_| \_|\___/   \//_/    \_\_| /_/    \_\_| \_|______|______|
EOF
    echo -e "${RESET}"
    echo -e "  ${PURPLE}${BOLD}Next-Gen Game Hosting Management Platform${RESET}"
    echo -e "  ${DIM}Base: Pterodactyl Core Engine | Open Source & Production Ready${RESET}"
    echo -e "  ${GRAY}------------------------------------------------------------${RESET}\n"
}

# Root check enforcement (Production Mode only)
require_root() {
    if [[ "${DEPLOY_MODE}" == "production" && $EUID -ne 0 ]]; then
        print_fatal "Production VPS installation requires root. Run with: sudo bash $0"
    fi
}

command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Read a value from a dotenv-style file without executing it.
# Usage: read_env_value /path/to/.env APP_KEY
read_env_value() {
    local file="$1"
    local key="$2"
    local value=""

    [[ -f "${file}" ]] || return 1

    value=$(grep -m1 -E "^${key}=" "${file}" 2>/dev/null | cut -d '=' -f2- | tr -d '\r')
    value="${value%\"}"
    value="${value#\"}"
    value="${value%\'}"
    value="${value#\'}"

    printf '%s' "${value}"
}

# Install Composer and make it reachable even from minimal root shells.
# Uses /usr/local/bin for root and ~/.local/bin for unprivileged environments.
# Returns 1 when Composer could not be installed.
ensure_composer() {
    local install_dir=""
    local target=""
    local php_bin=""
    local installer=""
    local sudo_cmd=""

    # Some VPS images start root with a PATH that omits /usr/local/bin, and
    # sandbox images omit ~/.local/bin.
    case ":${PATH}:" in
        *:/usr/local/bin:*) ;;
        *) export PATH="/usr/local/bin:${PATH}" ;;
    esac
    case ":${PATH}:" in
        *:"${HOME}/.local/bin":*) ;;
        *) export PATH="${HOME}/.local/bin:${PATH}" ;;
    esac
    case ":${PATH}:" in
        *:/usr/sbin:*) ;;
        *) export PATH="${PATH}:/usr/sbin:/sbin" ;;
    esac
    hash -r 2>/dev/null || true

    export COMPOSER_ALLOW_SUPERUSER=1
    export COMPOSER_MEMORY_LIMIT=-1

    if command_exists composer && composer --version >/dev/null 2>&1; then
        return 0
    fi

    if [[ $EUID -eq 0 ]]; then
        install_dir="/usr/local/bin"
    else
        install_dir="${HOME}/.local/bin"
    fi
    target="${install_dir}/composer"
    mkdir -p "${install_dir}" 2>/dev/null || true

    # A previous attempt may have installed Composer outside PATH.
    if [[ -x "${target}" ]] && "${target}" --version >/dev/null 2>&1; then
        print_info "Using existing Composer at ${target}."
        return 0
    fi

    php_bin="$(command -v php || command -v php8.2 || true)"
    if [[ -z "${php_bin}" ]]; then
        print_warning "PHP CLI is not available, so Composer cannot be installed."
        return 1
    fi

    print_info "Downloading and installing Composer 2..."
    installer="$(mktemp /tmp/nova-composer-setup.XXXXXX 2>/dev/null || echo /tmp/nova-composer-setup.php)"
    if curl -fsSL --connect-timeout 15 -m 120 https://getcomposer.org/installer -o "${installer}" \
        && "${php_bin}" "${installer}" --install-dir="${install_dir}" --filename=composer >> "${INSTALL_LOG:-/dev/null}" 2>&1 \
        && chmod 755 "${target}" 2>/dev/null \
        && "${target}" --version >/dev/null 2>&1; then
        rm -f "${installer}"
        hash -r 2>/dev/null || true
        print_success "Composer installed: $("${target}" --version 2>/dev/null | head -n 1)"
        return 0
    fi
    rm -f "${installer}"

    print_warning "The Composer installer failed; downloading composer.phar directly..."
    if curl -fsSL --connect-timeout 15 -m 120 https://getcomposer.org/download/latest-stable/composer.phar -o "${target}" \
        && chmod 755 "${target}" \
        && "${target}" --version >/dev/null 2>&1; then
        hash -r 2>/dev/null || true
        print_success "Composer installed from composer.phar."
        return 0
    fi

    if command_exists apt-get; then
        print_warning "Trying the distribution Composer package..."
        if [[ $EUID -ne 0 ]] && command_exists sudo; then
            sudo_cmd="sudo"
        fi
        ${sudo_cmd} apt-get install -y composer >> "${INSTALL_LOG:-/dev/null}" 2>&1 || true
        hash -r 2>/dev/null || true
        if command_exists composer && composer --version >/dev/null 2>&1; then
            print_success "Composer installed from APT."
            return 0
        fi
    fi

    print_warning "Composer could not be installed automatically."
    return 1
}

get_public_ip() {
    local ip=""
    ip=$(curl -s --connect-timeout 4 https://api.ipify.org 2>/dev/null)
    if [[ -z "$ip" ]]; then
        ip=$(curl -s --connect-timeout 4 https://checkip.amazonaws.com 2>/dev/null)
    fi
    if [[ -z "$ip" ]]; then
        ip=$(curl -s --connect-timeout 4 https://icanhazip.com 2>/dev/null | tr -d '\n')
    fi
    echo "$ip"
}

get_local_ip() {
    ip route get 1.1.1.1 2>/dev/null | awk '{print $7}' | tr -d '\n'
}

get_cpu_arch() {
    local arch
    arch=$(uname -m)
    case "$arch" in
        x86_64|amd64) echo "amd64" ;;
        aarch64|arm64) echo "arm64" ;;
        *) echo "$arch" ;;
    esac
}

prompt_input() {
    local prompt_text="$1"
    local default_val="$2"
    local user_val=""

    if [[ -n "$default_val" ]]; then
        echo -ne " ${CYAN}?${RESET} ${prompt_text} [${GREEN}${default_val}${RESET}]: " >&2
    else
        echo -ne " ${CYAN}?${RESET} ${prompt_text}: " >&2
    fi
    read -r user_val
    if [[ -z "$user_val" ]]; then
        echo "$default_val"
    else
        echo "$user_val"
    fi
}

prompt_password() {
    local prompt_text="$1"
    local pw=""
    local pw_confirm=""

    while true; do
        echo -ne " ${CYAN}?${RESET} ${prompt_text}: " >&2
        read -s -r pw
        echo "" >&2
        if [[ -z "$pw" ]]; then
            print_warning "Password cannot be empty. Please try again."
            continue
        fi
        if [[ ${#pw} -lt 8 ]]; then
            print_warning "Password must be at least 8 characters. Please try again."
            continue
        fi
        echo -ne " ${CYAN}?${RESET} Confirm ${prompt_text}: " >&2
        read -s -r pw_confirm
        echo "" >&2
        if [[ "$pw" != "$pw_confirm" ]]; then
            print_warning "Passwords do not match. Please try again."
            continue
        fi
        break
    done
    echo "$pw"
}

prompt_confirm() {
    local prompt_text="$1"
    local default_choice="${2:-Y}"
    local choice=""

    if [[ "$default_choice" =~ ^[Yy]$ ]]; then
        echo -ne " ${CYAN}?${RESET} ${prompt_text} [${GREEN}Y${RESET}/n]: " >&2
    else
        echo -ne " ${CYAN}?${RESET} ${prompt_text} [y/${RED}N${RESET}]: " >&2
    fi
    read -r choice
    choice="${choice:-$default_choice}"
    if [[ "$choice" =~ ^[Yy]$ ]]; then
        return 0
    else
        return 1
    fi
}

generate_random_password() {
    local length="${1:-32}"
    LC_ALL=C tr -dc 'A-Za-z0-9!@#$%^&*()_+=' </dev/urandom 2>/dev/null | head -c "$length" || true
}

generate_random_token() {
    local length="${1:-32}"
    LC_ALL=C tr -dc 'A-Za-z0-9' </dev/urandom 2>/dev/null | head -c "$length" || true
}
