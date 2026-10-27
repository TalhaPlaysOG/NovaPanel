#!/usr/bin/env bash
# ==============================================================================
# Nova Panel - Quick Launch & One-Command Installer
# Usage:
#   bash <(curl -fsSL .../install.sh)          # interactive setup menu (default)
#   bash <(curl -fsSL .../install.sh) --auto   # automated install, no menu
#   bash <(curl -fsSL .../install.sh) --dev    # development / CodeSandbox install
# ==============================================================================

set -eo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd || echo "")"

print_launcher_help() {
    cat << 'EOF'
Nova Panel - One-Command Launcher

Usage: bash install.sh [OPTIONS]

With no options the interactive setup menu opens, where you can install the
panel, install Wings, set up a Cloudflare tunnel, add a node, or create a user.

Options:
  --menu             Open the interactive setup menu (default)
  --auto             Run the full automated installer (auto-detected mode)
  --dev              Run the automated installer in development mode
  --prod             Run the automated installer in production mode
  --repo owner/repo  Override the GitHub repository (default: TalhaPlaysOG/NovaPanel)
  --branch name      Override the git branch (default: main)
  --panel, --wings, --tunnel, --node, --user, --status, --update, --repair
                     Run a single menu action directly
  -h, --help         Show this help
EOF
}

# Choose what to launch:
#   no flags      -> interactive setup menu ("buttons")
#   --auto        -> automated linear installer
#   --dev/--prod  -> automated linear installer with a forced mode
LAUNCH_SCRIPT="installer/nova-menu.sh"
INTERACTIVE_MENU=1

for arg in "$@"; do
    case "$arg" in
        --menu)
            LAUNCH_SCRIPT="installer/nova-menu.sh"
            INTERACTIVE_MENU=1
            ;;
        --auto|--install|--classic|--dev|--development|--prod|--production)
            LAUNCH_SCRIPT="installer/install.sh"
            INTERACTIVE_MENU=0
            ;;
        -h|--help)
            print_launcher_help
            exit 0
            ;;
    esac
done

# Root is mandatory for the linear installer. The menu opens for everyone, and
# each action validates the privileges it needs (so status still works).
if [[ $EUID -ne 0 ]]; then
    if [[ $INTERACTIVE_MENU -eq 0 ]]; then
        echo -e "\033[38;5;196mError:\033[0m This installer must be run as root. Run with: sudo bash $0" >&2
        exit 1
    fi
    echo -e "\033[38;5;220mNote:\033[0m Menu actions that install or change services need root. Re-run with sudo for full access."
fi

# If running directly from a cloned local repository
if [[ -n "${SCRIPT_DIR}" && -f "${SCRIPT_DIR}/${LAUNCH_SCRIPT}" ]]; then
    exec bash "${SCRIPT_DIR}/${LAUNCH_SCRIPT}" "$@"
fi

# If running via remote pipe: curl -fsSL ... | bash
echo -e "\033[38;5;45m==>\033[0m Initializing Nova Panel..."

GITHUB_REPO="${NOVA_REPO:-TalhaPlaysOG/NovaPanel}"
GITHUB_BRANCH="${NOVA_BRANCH:-main}"

# Allow overriding repository or branch from CLI flags
for ((i=1; i<=$#; i++)); do
    case "${!i}" in
        --repo)
            next=$((i+1))
            GITHUB_REPO="${!next}"
            ;;
        --branch)
            next=$((i+1))
            GITHUB_BRANCH="${!next}"
            ;;
    esac
done

export NOVA_REPO="${GITHUB_REPO}"
export NOVA_BRANCH="${GITHUB_BRANCH}"

TMP_DIR=$(mktemp -d /tmp/nova-panel-bootstrap.XXXXXX)
trap 'rm -rf "${TMP_DIR}"' EXIT

cd "${TMP_DIR}"

DOWNLOAD_SUCCESS=false

# Method 1: Fast tarball archive download
echo -e "\033[38;5;45m==>\033[0m Fetching Nova Panel bundle from ${GITHUB_REPO} (${GITHUB_BRANCH})..."
ARCHIVE_URLS=(
    "https://codeload.github.com/${GITHUB_REPO}/tar.gz/refs/heads/${GITHUB_BRANCH}"
    "https://github.com/${GITHUB_REPO}/archive/refs/heads/${GITHUB_BRANCH}.tar.gz"
)

for URL in "${ARCHIVE_URLS[@]}"; do
    if curl -fsSL --connect-timeout 10 -m 60 -H "User-Agent: NovaInstaller" "${URL}" -o novapanel.tar.gz 2>/dev/null; then
        if tar -tzf novapanel.tar.gz >/dev/null 2>&1; then
            tar -xzf novapanel.tar.gz --strip-components=1 2>/dev/null || true
            rm -f novapanel.tar.gz
            if [[ -f "${TMP_DIR}/installer/install.sh" ]]; then
                DOWNLOAD_SUCCESS=true
                break
            fi
        fi
    fi
done

# Method 2: Resilient modular file stream fallback (if GitHub tarball generation is delayed or blocked)
if [[ "${DOWNLOAD_SUCCESS}" != "true" ]]; then
    echo -e "\033[38;5;220m[Notice]\033[0m Bootstrapping installer modules directly..."
    
    mkdir -p installer/modules/access panel/config panel/public/assets/svgs
    
    RAW_BASE="https://raw.githubusercontent.com/${GITHUB_REPO}/${GITHUB_BRANCH}"
    
    BOOTSTRAP_FILES=(
        "installer/install.sh"
        "installer/nova-menu.sh"
        "installer/helpers/auto-node.php"
        "installer/helpers/create-user.php"
        "installer/common.sh"
        "installer/backup.sh"
        "installer/restore.sh"
        "installer/update.sh"
        "installer/repair.sh"
        "installer/nova-cli.sh"
        "installer/modules/system-checks.sh"
        "installer/modules/dependencies.sh"
        "installer/modules/database.sh"
        "installer/modules/webserver.sh"
        "installer/modules/docker.sh"
        "installer/modules/wings.sh"
        "installer/modules/node-registration.sh"
        "installer/modules/access/ip.sh"
        "installer/modules/access/domain.sh"
        "installer/modules/access/tunnel.sh"
        "panel/config/nova.php"
        "panel/public/assets/svgs/nova.svg"
        "panel/public/assets/svgs/nova-mark.svg"
    )
    
    for FILE in "${BOOTSTRAP_FILES[@]}"; do
        mkdir -p "$(dirname "${TMP_DIR}/${FILE}")"
        curl -fsSL --connect-timeout 8 -m 20 -H "User-Agent: NovaInstaller" \
            "${RAW_BASE}/${FILE}" -o "${TMP_DIR}/${FILE}" 2>/dev/null || true
    done
    
    if [[ -f "${TMP_DIR}/installer/install.sh" ]]; then
        DOWNLOAD_SUCCESS=true
    fi
fi

if [[ "${DOWNLOAD_SUCCESS}" == "true" && -f "${TMP_DIR}/${LAUNCH_SCRIPT}" ]]; then
    chmod +x "${TMP_DIR}/installer/"*.sh "${TMP_DIR}/installer/modules/"*.sh "${TMP_DIR}/installer/modules/access/"*.sh 2>/dev/null || true
    exec bash "${TMP_DIR}/${LAUNCH_SCRIPT}" "$@"
else
    echo -e "\033[38;5;196mError:\033[0m Unable to download Nova Panel installer bundle from https://github.com/${GITHUB_REPO}." >&2
    echo -e "Please ensure the repository is public and accessible, or clone it manually:" >&2
    echo -e "  git clone https://github.com/${GITHUB_REPO}.git && cd NovaPanel && sudo bash install.sh" >&2
    exit 1
fi
