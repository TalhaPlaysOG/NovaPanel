#!/usr/bin/env bash
# ==============================================================================
# Nova Panel CLI - Unified Management Interface (/usr/local/bin/nova)
# Supports: Production VPS Mode & Development / CodeSandbox Mode
# ==============================================================================

set -e

# Detect user / directory context
if [[ -d "/var/www/nova-panel" && -f "/var/www/nova-panel/.env" ]]; then
    PANEL_DIR="/var/www/nova-panel"
    NOVA_CONFIG_DIR="/etc/nova-panel"
    LOG_DIR="/var/log/nova-panel"
    RUN_DIR="/var/run/nova-panel"
    DEPLOY_MODE="production"
elif [[ -d "${HOME}/.nova-panel" || -f "${HOME}/nova-panel/.env" ]]; then
    PANEL_DIR="${HOME}/nova-panel"
    NOVA_CONFIG_DIR="${HOME}/.nova-panel/config"
    LOG_DIR="${HOME}/.nova-panel/logs"
    RUN_DIR="${HOME}/.nova-panel/run"
    DEPLOY_MODE="development"
elif [[ -d "./panel" && -f "./panel/.env" ]]; then
    PANEL_DIR="$(pwd)/panel"
    NOVA_CONFIG_DIR="$(pwd)/.nova-config"
    LOG_DIR="$(pwd)/logs"
    RUN_DIR="$(pwd)/run"
    DEPLOY_MODE="development"
else
    PANEL_DIR="/var/www/nova-panel"
    NOVA_CONFIG_DIR="/etc/nova-panel"
    LOG_DIR="/var/log/nova-panel"
    RUN_DIR="/var/run/nova-panel"
    DEPLOY_MODE="production"
fi

INSTALLER_DIR="${PANEL_DIR}/installer"

# Text Styling
BOLD="\033[1m"
DIM="\033[2m"
RESET="\033[0m"
CYAN="\033[38;5;45m"
GREEN="\033[38;5;48m"
YELLOW="\033[38;5;220m"
RED="\033[38;5;196m"
GRAY="\033[38;5;244m"

print_header() {
    echo -e "${CYAN}${BOLD}NOVA PANEL${RESET} ${DIM}CLI Management Suite (v1.0.0) [${DEPLOY_MODE}]${RESET}"
    echo -e "${GRAY}------------------------------------------------------------${RESET}"
}

require_root_if_prod() {
    if [[ "${DEPLOY_MODE}" == "production" && $EUID -ne 0 ]]; then
        echo -e "${RED}Error:${RESET} This command requires root privileges in Production VPS mode. (Run: sudo nova $1)" >&2
        exit 1
    fi
}

# Command: Status
cmd_status() {
    print_header
    echo -e "${BOLD}System & Service Status:${RESET}\n"

    status_badge() {
        local unit="$1"
        local label="$2"
        if command -v systemctl >/dev/null 2>&1 && systemctl is-active --quiet "$unit" 2>/dev/null; then
            echo -e "  [${GREEN}RUNNING${RESET}]  ${label}"
        else
            echo -e "  [${RED}STOPPED${RESET}]  ${label}"
        fi
    }

    if [[ "${DEPLOY_MODE}" == "development" ]]; then
        # Check Dev Server Process
        local pid_file="${RUN_DIR}/server.pid"
        if [[ -f "$pid_file" ]] && kill -0 "$(cat "$pid_file")" 2>/dev/null; then
            echo -e "  [${GREEN}RUNNING${RESET}]  Development Web Server (PID $(cat "$pid_file"))"
        else
            echo -e "  [${RED}STOPPED${RESET}]  Development Web Server (Run: nova start)"
        fi

        # Check SQLite DB
        if [[ -f "${PANEL_DIR}/database/database.sqlite" ]]; then
            local db_size
            db_size=$(du -h "${PANEL_DIR}/database/database.sqlite" | awk '{print $1}')
            echo -e "  [${GREEN}READY${RESET}]    SQLite Database (${db_size})"
        fi

        echo -e "  [${YELLOW}DEV-MODE${RESET}] Wings & Docker virtualization disabled (Dev / CodeSandbox Mode)"
    else
        status_badge "nginx" "Nginx Web Server"

        local php_unit=""
        for v in 8.3 8.2 8.1 8.0; do
            if command -v systemctl >/dev/null 2>&1 && systemctl list-unit-files 2>/dev/null | grep -q "php${v}-fpm"; then
                php_unit="php${v}-fpm"
                break
            fi
        done
        if [[ -n "$php_unit" ]]; then
            status_badge "${php_unit}" "PHP FastCGI Process Manager (${php_unit})"
        fi

        if command -v systemctl >/dev/null 2>&1 && systemctl list-unit-files 2>/dev/null | grep -q mariadb; then
            status_badge "mariadb" "MariaDB Server"
        elif command -v systemctl >/dev/null 2>&1 && systemctl list-unit-files 2>/dev/null | grep -q mysql; then
            status_badge "mysql" "MySQL Server"
        fi

        status_badge "redis-server" "Redis Server"
        status_badge "docker" "Docker Runtime Engine"
        status_badge "wings" "Wings Daemon"
        status_badge "pteroq" "Background Queue Worker (pteroq)"
    fi

    # Access Configuration
    echo ""
    echo -e "${BOLD}Access Configuration:${RESET}"
    if [[ -f "${NOVA_CONFIG_DIR}/access.env" ]]; then
        # shellcheck source=/dev/null
        source "${NOVA_CONFIG_DIR}/access.env"
        echo -e "  Access Mode : ${CYAN}${ACCESS_MODE}${RESET}"
        echo -e "  Configured  : ${BOLD}${PANEL_URL}${RESET}"

        if [[ -n "${TUNNEL_SERVICE:-}" ]]; then
            if command -v systemctl >/dev/null 2>&1 && systemctl is-active --quiet "${TUNNEL_SERVICE}" 2>/dev/null; then
                echo -e "  Tunnel Svc  : [${GREEN}RUNNING${RESET}] (${TUNNEL_SERVICE})"
                if [[ "${TUNNEL_TYPE:-}" == "temporary" ]]; then
                    local live_url
                    live_url=$(grep -o 'https://[a-zA-Z0-9-]*\.trycloudflare\.com' "${LOG_DIR}/tunnel.log" 2>/dev/null | tail -n 1)
                    if [[ -n "$live_url" ]]; then
                        echo -e "  Live URL    : ${GREEN}${BOLD}${live_url}${RESET}"
                    fi
                fi
            else
                echo -e "  Tunnel Svc  : [${RED}STOPPED${RESET}] (${TUNNEL_SERVICE})"
            fi
        fi
    elif [[ -f "${PANEL_DIR}/.env" ]]; then
        local app_url
        app_url=$(grep -E '^APP_URL=' "${PANEL_DIR}/.env" | cut -d '=' -f2-)
        echo -e "  Panel URL   : ${BOLD}${app_url}${RESET}"
    fi

    echo ""
}

# Command: Logs
cmd_logs() {
    local target="${1:-panel}"
    print_header

    case "$target" in
        panel)
            echo -e "Streaming Nova Panel application logs...\n"
            local log_file
            log_file=$(find "${PANEL_DIR}/storage/logs" -name "laravel*.log" 2>/dev/null | tail -n1)
            if [[ -f "$log_file" ]]; then
                tail -n 50 -f "$log_file"
            else
                echo -e "${YELLOW}No application logs found in ${PANEL_DIR}/storage/logs${RESET}"
            fi
            ;;
        wings)
            echo -e "Streaming Wings daemon logs...\n"
            if command -v journalctl >/dev/null 2>&1; then
                journalctl -u wings -n 50 -f
            elif [[ -f "/var/log/pterodactyl/wings.log" ]]; then
                tail -n 50 -f "/var/log/pterodactyl/wings.log"
            else
                echo -e "${YELLOW}Wings log not found or environment does not support systemd journal.${RESET}"
            fi
            ;;
        nginx)
            echo -e "Streaming Nginx web server logs...\n"
            if [[ -f "/var/log/nginx/error.log" ]]; then
                tail -n 50 -f "/var/log/nginx/error.log"
            else
                echo -e "${YELLOW}Nginx error log not found at /var/log/nginx/error.log${RESET}"
            fi
            ;;
        tunnel)
            echo -e "Streaming Tunnel logs...\n"
            if [[ -f "${LOG_DIR}/tunnel.log" ]]; then
                tail -n 50 -f "${LOG_DIR}/tunnel.log"
            else
                echo -e "${YELLOW}Tunnel log not found at ${LOG_DIR}/tunnel.log${RESET}"
            fi
            ;;
        queue)
            echo -e "Streaming Queue Worker logs...\n"
            if command -v journalctl >/dev/null 2>&1; then
                journalctl -u pteroq -n 50 -f
            else
                echo -e "${YELLOW}Queue logs unavailable via journalctl.${RESET}"
            fi
            ;;
        install)
            echo -e "Streaming Installation log...\n"
            if [[ -f "${LOG_DIR}/install.log" ]]; then
                tail -n 50 -f "${LOG_DIR}/install.log"
            elif [[ -f "/tmp/nova-panel-install.log" ]]; then
                tail -n 50 -f "/tmp/nova-panel-install.log"
            else
                echo -e "${YELLOW}Install log not found.${RESET}"
            fi
            ;;
        *)
            echo -e "${RED}Unknown log target: ${target}${RESET}"
            echo -e "Available targets: panel, wings, nginx, tunnel, queue, install"
            echo -e "Usage: nova logs [target]"
            exit 1
            ;;
    esac
}

# Command: Tunnel
cmd_tunnel() {
    local subcmd="${1:-status}"
    shift || true

    case "$subcmd" in
        status)
            print_header
            echo -e "${BOLD}Tunnel Status & Diagnostics:${RESET}\n"
            if [[ ! -f "${NOVA_CONFIG_DIR}/access.env" ]]; then
                echo -e "${YELLOW}No access configuration found in ${NOVA_CONFIG_DIR}/access.env${RESET}"
                exit 0
            fi

            # shellcheck source=/dev/null
            source "${NOVA_CONFIG_DIR}/access.env"
            if [[ -z "${TUNNEL_SERVICE:-}" ]]; then
                echo -e "${YELLOW}Tunnel mode is not currently configured for this installation.${RESET}"
                echo -e "Current access mode: ${BOLD}${ACCESS_MODE:-standard}${RESET}"
                exit 0
            fi

            echo -e "Service: ${BOLD}${TUNNEL_SERVICE}${RESET}"
            if command -v systemctl >/dev/null 2>&1 && systemctl is-active --quiet "${TUNNEL_SERVICE}" 2>/dev/null; then
                echo -e "State  : ${GREEN}Active (Running)${RESET}"
                if [[ "${TUNNEL_TYPE:-}" == "temporary" ]]; then
                    local live_url
                    live_url=$(grep -o 'https://[a-zA-Z0-9-]*\.trycloudflare\.com' "${LOG_DIR}/tunnel.log" 2>/dev/null | tail -n 1)
                    echo -e "URL    : ${CYAN}${BOLD}${live_url:-https://<generating...>}${RESET}"
                else
                    echo -e "URL    : ${CYAN}${BOLD}${PANEL_URL}${RESET}"
                fi
            else
                echo -e "State  : ${RED}Inactive (Stopped)${RESET}"
            fi
            ;;

        restart)
            require_root_if_prod "tunnel restart"
            print_header
            echo -e "Restarting panel tunnel service..."
            if [[ ! -f "${NOVA_CONFIG_DIR}/access.env" ]]; then
                echo -e "${RED}Access config missing.${RESET}"
                exit 1
            fi
            # shellcheck source=/dev/null
            source "${NOVA_CONFIG_DIR}/access.env"
            if [[ -n "${TUNNEL_SERVICE:-}" ]]; then
                systemctl restart "${TUNNEL_SERVICE}"
                sleep 2
                if systemctl is-active --quiet "${TUNNEL_SERVICE}"; then
                    echo -e "${GREEN}✔ Tunnel service restarted successfully.${RESET}"
                    if [[ "${TUNNEL_TYPE:-}" == "temporary" ]]; then
                        local live_url
                        live_url=$(grep -o 'https://[a-zA-Z0-9-]*\.trycloudflare\.com' "${LOG_DIR}/tunnel.log" 2>/dev/null | tail -n 1)
                        echo -e "New Live URL: ${CYAN}${BOLD}${live_url}${RESET}"
                    fi
                else
                    echo -e "${RED}✖ Failed to restart ${TUNNEL_SERVICE}.${RESET}"
                fi
            else
                echo -e "${YELLOW}No tunnel service is configured.${RESET}"
            fi
            ;;

        disable)
            require_root_if_prod "tunnel disable"
            print_header
            if [[ ! -f "${NOVA_CONFIG_DIR}/access.env" ]]; then
                echo -e "${YELLOW}No tunnel configured.${RESET}"
                exit 0
            fi
            # shellcheck source=/dev/null
            source "${NOVA_CONFIG_DIR}/access.env"
            if [[ -n "${TUNNEL_SERVICE:-}" ]]; then
                echo -e "Disabling and stopping tunnel service (${TUNNEL_SERVICE})..."
                systemctl stop "${TUNNEL_SERVICE}" 2>/dev/null || true
                systemctl disable "${TUNNEL_SERVICE}" 2>/dev/null || true
                echo -e "${GREEN}✔ Tunnel service stopped and disabled.${RESET}"
            else
                echo -e "${YELLOW}No tunnel service active.${RESET}"
            fi
            ;;

        *)
            echo -e "${RED}Unknown tunnel command: ${subcmd}${RESET}"
            echo -e "Usage: nova tunnel [status|restart|disable]"
            exit 1
            ;;
    esac
}

# Command: Backup
cmd_backup() {
    require_root_if_prod "backup"
    if [[ -x "${INSTALLER_DIR}/backup.sh" ]]; then
        "${INSTALLER_DIR}/backup.sh" "$@"
    elif [[ -x "./installer/backup.sh" ]]; then
        "./installer/backup.sh" "$@"
    else
        echo -e "${RED}Backup script not found.${RESET}"
        exit 1
    fi
}

# Command: Restore
cmd_restore() {
    require_root_if_prod "restore"
    if [[ -x "${INSTALLER_DIR}/restore.sh" ]]; then
        "${INSTALLER_DIR}/restore.sh" "$@"
    elif [[ -x "./installer/restore.sh" ]]; then
        "./installer/restore.sh" "$@"
    else
        echo -e "${RED}Restore script not found.${RESET}"
        exit 1
    fi
}

# Command: Update
cmd_update() {
    require_root_if_prod "update"
    if [[ -x "${INSTALLER_DIR}/update.sh" ]]; then
        "${INSTALLER_DIR}/update.sh" "$@"
    elif [[ -x "./installer/update.sh" ]]; then
        "./installer/update.sh" "$@"
    else
        echo -e "${RED}Update script not found.${RESET}"
        exit 1
    fi
}

# Command: Repair
cmd_repair() {
    require_root_if_prod "repair"
    if [[ -x "${INSTALLER_DIR}/repair.sh" ]]; then
        "${INSTALLER_DIR}/repair.sh" "$@"
    elif [[ -x "./installer/repair.sh" ]]; then
        "./installer/repair.sh" "$@"
    else
        echo -e "${RED}Repair script not found.${RESET}"
        exit 1
    fi
}

# Command: Install
cmd_install() {
    if [[ -x "${INSTALLER_DIR}/install.sh" ]]; then
        "${INSTALLER_DIR}/install.sh" "$@"
    elif [[ -x "./installer/install.sh" ]]; then
        "./installer/install.sh" "$@"
    elif [[ -x "./install.sh" ]]; then
        "./install.sh" "$@"
    else
        echo -e "${RED}Install script not found.${RESET}"
        exit 1
    fi
}

# Command: Start / Stop (Development Mode)
cmd_start() {
    print_header
    echo -e "Starting Nova Panel web server..."
    cd "${PANEL_DIR}" || exit 1
    local pid_file="${RUN_DIR}/server.pid"
    mkdir -p "${RUN_DIR}" "${LOG_DIR}"

    if [[ -f "$pid_file" ]] && kill -0 "$(cat "$pid_file")" 2>/dev/null; then
        echo -e "${YELLOW}Server is already running with PID $(cat "$pid_file").${RESET}"
        exit 0
    fi

    nohup php artisan serve --host=0.0.0.0 --port=8000 > "${LOG_DIR}/server.log" 2>&1 &
    echo $! > "$pid_file"
    sleep 2
    if kill -0 "$(cat "$pid_file")" 2>/dev/null; then
        echo -e "${GREEN}✔ Server started at http://0.0.0.0:8000 (PID $(cat "$pid_file"))${RESET}"
    else
        echo -e "${RED}✖ Failed to start server. Review ${LOG_DIR}/server.log${RESET}"
    fi
}

cmd_stop() {
    print_header
    local pid_file="${RUN_DIR}/server.pid"
    if [[ -f "$pid_file" ]] && kill -0 "$(cat "$pid_file")" 2>/dev/null; then
        echo -e "Stopping server PID $(cat "$pid_file")..."
        kill "$(cat "$pid_file")" 2>/dev/null || true
        rm -f "$pid_file"
        echo -e "${GREEN}✔ Server stopped.${RESET}"
    else
        echo -e "${YELLOW}No running development server found.${RESET}"
    fi
}

# Usage Help
usage() {
    print_header
    echo -e "${BOLD}Usage:${RESET} nova <command> [arguments]\n"
    echo -e "${BOLD}Available Commands:${RESET}"
    echo -e "  ${CYAN}nova status${RESET}          Show operational status of services and access modes"
    echo -e "  ${CYAN}nova install${RESET}         Execute or reconfigure Nova Panel installation"
    echo -e "  ${CYAN}nova update${RESET}          Safely update Nova Panel, migrations, and Wings"
    echo -e "  ${CYAN}nova backup${RESET}          Create a full snapshot (database, .env, SSL, configs)"
    echo -e "  ${CYAN}nova restore${RESET}         Safely restore database and configuration from backup"
    echo -e "  ${CYAN}nova repair${RESET}          Diagnose services, fix permissions, and clear caches"
    echo -e "  ${CYAN}nova logs [target]${RESET}   Tail logs (panel, wings, nginx, tunnel, queue, install)"
    echo -e "  ${CYAN}nova tunnel status${RESET}   Check active Cloudflare/Quick tunnel connection and URL"
    echo -e "  ${CYAN}nova tunnel restart${RESET}  Restart tunnel agent and refresh connection"
    echo -e "  ${CYAN}nova tunnel disable${RESET}  Disable and stop tunnel agent"
    echo -e "  ${CYAN}nova start | stop${RESET}    Start/Stop development server (Dev / CodeSandbox Mode)"
    echo -e "\n  ${DIM}Documentation: https://github.com/NovaPanel or local docs/ folder${RESET}\n"
}

case "${1:-}" in
    status)
        cmd_status
        ;;
    install)
        shift
        cmd_install "$@"
        ;;
    update)
        shift
        cmd_update "$@"
        ;;
    backup)
        shift
        cmd_backup "$@"
        ;;
    restore)
        shift
        cmd_restore "$@"
        ;;
    repair)
        shift
        cmd_repair "$@"
        ;;
    tunnel)
        shift
        cmd_tunnel "$@"
        ;;
    logs)
        shift
        cmd_logs "${1:-panel}"
        ;;
    start)
        cmd_start
        ;;
    stop)
        cmd_stop
        ;;
    -h|--help|help)
        usage
        ;;
    -v|--version|version)
        echo "Nova Panel CLI v1.0.0 (Core Engine: Pterodactyl v1.15.2)"
        ;;
    *)
        usage
        exit 1
        ;;
esac
