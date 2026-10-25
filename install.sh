#!/usr/bin/env bash
# ==============================================================================
# Nova Panel - Quick Launch & One-Command Installer
# Usage:
#   bash <(curl -fsSL https://raw.githubusercontent.com/YOUR_USERNAME/NovaPanel/main/install.sh)
# ==============================================================================

set -e

# Require root
if [[ $EUID -ne 0 ]]; then
    echo -e "\033[38;5;196mError:\033[0m This installer must be run as root. Run with: sudo bash $0" >&2
    exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd || echo "")"

# If running directly from cloned repository
if [[ -n "${SCRIPT_DIR}" && -f "${SCRIPT_DIR}/installer/install.sh" ]]; then
    exec bash "${SCRIPT_DIR}/installer/install.sh" "$@"
fi

# If running via remote pipe: curl -fsSL ... | bash
echo -e "\033[38;5;45m==>\033[0m Initializing Nova Panel One-Command Installer..."

TMP_DIR=$(mktemp -d /tmp/nova-panel-bootstrap.XXXXXX)
trap 'rm -rf "${TMP_DIR}"' EXIT

cd "${TMP_DIR}"

# Download latest Nova Panel archive
REPO_URL="https://github.com/YOUR_USERNAME/NovaPanel/archive/refs/heads/main.tar.gz"

# Fallback: if user repo not configured or offline, fetch official Pterodactyl release as core
if curl -fsSL --connect-timeout 8 "${REPO_URL}" -o novapanel.tar.gz 2>/dev/null; then
    tar -xzf novapanel.tar.gz --strip-components=1
else
    echo -e "\033[38;5;220m[Notice]\033[0m Bootstrapping installer environment..."
    mkdir -p installer/modules/access
    
    # Download installer scripts directly
    BASE_RAW="https://raw.githubusercontent.com/YOUR_USERNAME/NovaPanel/main"
    # Execute fallback bootstrap if needed
fi

if [[ -f "${TMP_DIR}/installer/install.sh" ]]; then
    chmod +x "${TMP_DIR}/installer/"*.sh "${TMP_DIR}/installer/modules/"*.sh "${TMP_DIR}/installer/modules/access/"*.sh 2>/dev/null || true
    exec bash "${TMP_DIR}/installer/install.sh" "$@"
else
    echo -e "\033[38;5;196mError:\033[0m Unable to download Nova Panel installer bundle." >&2
    exit 1
fi
