#!/usr/bin/env bash
# ==============================================================================
# Nova Panel Test Suite - Installer Modules Unit & Validation Tests
# ==============================================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="${SCRIPT_DIR}/.."
INSTALLER_DIR="${REPO_ROOT}/installer"

# Test counter
PASSED=0
FAILED=0

assert_equal() {
    local test_name="$1"
    local expected="$2"
    local actual="$3"
    if [[ "$expected" == "$actual" ]]; then
        echo -e "  \033[38;5;48m✔ PASS:\033[0m ${test_name}"
        PASSED=$((PASSED + 1))
    else
        echo -e "  \033[38;5;196m✖ FAIL:\033[0m ${test_name} (Expected: '${expected}', Got: '${actual}')"
        FAILED=$((FAILED + 1))
    fi
}

assert_true() {
    local test_name="$1"
    local condition="$2"
    if eval "$condition"; then
        echo -e "  \033[38;5;48m✔ PASS:\033[0m ${test_name}"
        PASSED=$((PASSED + 1))
    else
        echo -e "  \033[38;5;196m✖ FAIL:\033[0m ${test_name}"
        FAILED=$((FAILED + 1))
    fi
}

echo -e "\n\033[1m=== Running Installer Modules Tests ===\033[0m\n"

# 1. Bash Syntax Validation
echo -e "\033[38;5;45m[Test 1] Bash Syntax Check on All Scripts\033[0m"
for script in \
    "${REPO_ROOT}/install.sh" \
    "${INSTALLER_DIR}/install.sh" \
    "${INSTALLER_DIR}/common.sh" \
    "${INSTALLER_DIR}/backup.sh" \
    "${INSTALLER_DIR}/restore.sh" \
    "${INSTALLER_DIR}/update.sh" \
    "${INSTALLER_DIR}/repair.sh" \
    "${INSTALLER_DIR}/nova-cli.sh" \
    "${INSTALLER_DIR}/nova-menu.sh" \
    "${INSTALLER_DIR}/modules/system-checks.sh" \
    "${INSTALLER_DIR}/modules/dependencies.sh" \
    "${INSTALLER_DIR}/modules/database.sh" \
    "${INSTALLER_DIR}/modules/webserver.sh" \
    "${INSTALLER_DIR}/modules/docker.sh" \
    "${INSTALLER_DIR}/modules/wings.sh" \
    "${INSTALLER_DIR}/modules/node-registration.sh" \
    "${INSTALLER_DIR}/modules/access/ip.sh" \
    "${INSTALLER_DIR}/modules/access/domain.sh" \
    "${INSTALLER_DIR}/modules/access/tunnel.sh"; do
    
    if bash -n "$script" 2>/dev/null; then
        assert_equal "Syntax: $(basename "$script")" "0" "0"
    else
        assert_equal "Syntax: $(basename "$script")" "0" "1"
    fi
done

# 2. Domain Regex Validator Test
echo -e "\n\033[38;5;45m[Test 2] Domain Syntax Validation\033[0m"
# shellcheck source=/dev/null
source "${INSTALLER_DIR}/modules/access/domain.sh" 2>/dev/null || true

assert_true "Valid domain: panel.example.com" 'validate_domain_syntax "panel.example.com"'
assert_true "Valid domain: nova.my-server.net" 'validate_domain_syntax "nova.my-server.net"'
assert_true "Invalid domain: -bad-domain" '! validate_domain_syntax "-bad-domain"'
assert_true "Invalid domain: http://example.com" '! validate_domain_syntax "http://example.com"'
assert_true "Invalid domain: empty string" '! validate_domain_syntax ""'

# 3. CPU Architecture Helper Test
echo -e "\n\033[38;5;45m[Test 3] CPU Architecture Normalization\033[0m"
# shellcheck source=/dev/null
source "${INSTALLER_DIR}/common.sh" 2>/dev/null || true

arch_detected=$(get_cpu_arch)
assert_true "Architecture detected (${arch_detected})" '[[ "$arch_detected" =~ ^(amd64|arm64|x86_64|aarch64) ]]'

# 4. Token & Password Generation
echo -e "\n\033[38;5;45m[Test 4] Random Token & Password Generation\033[0m"
token_32=$(generate_random_token 32)
assert_equal "Generate 32-char token length" "32" "${#token_32}"
token_64=$(generate_random_token 64)
assert_equal "Generate 64-char token length" "64" "${#token_64}"

# 5. Menu Helper Integrity
echo -e "\n\033[38;5;45m[Test 5] Setup Menu & Helper Integrity\033[0m"

assert_true "nova-menu.sh exists" '[[ -f "${INSTALLER_DIR}/nova-menu.sh" ]]'
assert_true "auto-node helper exists" '[[ -f "${INSTALLER_DIR}/helpers/auto-node.php" ]]'
assert_true "create-user helper exists" '[[ -f "${INSTALLER_DIR}/helpers/create-user.php" ]]'
assert_true "Menu installs cloudflared via APT" 'grep -q "install_cloudflared_apt" "${INSTALLER_DIR}/nova-menu.sh"'
assert_true "Tunnel module configures the Cloudflare APT repo" 'grep -q "https://pkg.cloudflare.com/cloudflared any main" "${INSTALLER_DIR}/modules/access/tunnel.sh"'

assert_true "One-command launcher opens the menu by default" 'grep -q "LAUNCH_SCRIPT=\"installer/nova-menu.sh\"" "${REPO_ROOT}/install.sh"'
assert_true "One-command launcher supports --auto" 'grep -q -- "--auto|--install|--classic" "${REPO_ROOT}/install.sh"'
assert_true "Menu requires root for panel installation" 'grep -q "Installing the panel requires root privileges" "${INSTALLER_DIR}/nova-menu.sh"'

if command -v php >/dev/null 2>&1; then
    for helper in "${INSTALLER_DIR}/helpers/auto-node.php" "${INSTALLER_DIR}/helpers/create-user.php"; do
        if php -l "$helper" >/dev/null 2>&1; then
            assert_equal "PHP syntax: $(basename "$helper")" "0" "0"
        else
            assert_equal "PHP syntax: $(basename "$helper")" "0" "1"
        fi
    done
else
    echo -e "  \033[38;5;244m- PHP not available, skipping helper lint\033[0m"
fi

# 6. Summary
echo -e "\n------------------------------------------------------------"
echo -e "Modules Test Summary: Passed: \033[38;5;48m${PASSED}\033[0m | Failed: \033[38;5;196m${FAILED}\033[0m"
if [[ $FAILED -gt 0 ]]; then
    exit 1
fi
