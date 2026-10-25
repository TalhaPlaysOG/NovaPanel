#!/usr/bin/env bash
# ==============================================================================
# Nova Panel Test Suite - Branding & Licensing Verification
# ==============================================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PANEL_DIR="${SCRIPT_DIR}/../panel"

PASSED=0
FAILED=0

assert_contains() {
    local test_name="$1"
    local file="$2"
    local pattern="$3"
    if grep -qE "${pattern}" "${file}" 2>/dev/null; then
        echo -e "  \033[38;5;48m✔ PASS:\033[0m ${test_name}"
        PASSED=$((PASSED + 1))
    else
        echo -e "  \033[38;5;196m✖ FAIL:\033[0m ${test_name} (Pattern '${pattern}' not found in ${file})"
        FAILED=$((FAILED + 1))
    fi
}

echo -e "\n\033[1m=== Running Branding & Attribution Tests ===\033[0m\n"

# 1. Config branding
echo -e "\033[38;5;45m[Test 1] Configuration Branding\033[0m"
assert_contains "config/app.php: Default app name is Nova Panel" "${PANEL_DIR}/config/app.php" "env\('APP_NAME', 'Nova Panel'\)"
assert_contains "config/nova.php: Exists and has version" "${PANEL_DIR}/config/nova.php" "'version' => '1.0.0'"
assert_contains "config/mail.php: Default mail sender is Nova Panel" "${PANEL_DIR}/config/mail.php" "env\('MAIL_FROM_NAME', 'Nova Panel'\)"

# 2. Blade Views Branding
echo -e "\n\033[38;5;45m[Test 2] Blade Views Branding\033[0m"
assert_contains "wrapper.blade.php: Default title is Nova Panel" "${PANEL_DIR}/resources/views/templates/wrapper.blade.php" "config\('app.name', 'Nova Panel'\)"
assert_contains "admin.blade.php: Logo title is Nova Panel" "${PANEL_DIR}/resources/views/layouts/admin.blade.php" "<span>\{\{ config\('app.name', 'Nova Panel'\) \}\}</span>"
assert_contains "admin.blade.php: Attribution maintained" "${PANEL_DIR}/resources/views/layouts/admin.blade.php" "Powered by <a href=\"https://pterodactyl.io/\">Pterodactyl Software</a>"

# 3. Logos & Graphics
echo -e "\n\033[38;5;45m[Test 3] Logo Assets\033[0m"
if [[ -f "${PANEL_DIR}/public/assets/svgs/nova.svg" ]]; then
    echo -e "  \033[38;5;48m✔ PASS:\033[0m nova.svg exists"
    PASSED=$((PASSED + 1))
else
    echo -e "  \033[38;5;196m✖ FAIL:\033[0m nova.svg missing"
    FAILED=$((FAILED + 1))
fi

if [[ -f "${PANEL_DIR}/public/assets/svgs/nova-mark.svg" ]]; then
    echo -e "  \033[38;5;48m✔ PASS:\033[0m nova-mark.svg exists"
    PASSED=$((PASSED + 1))
else
    echo -e "  \033[38;5;196m✖ FAIL:\033[0m nova-mark.svg missing"
    FAILED=$((FAILED + 1))
fi

# 4. Licensing & Attribution
echo -e "\n\033[38;5;45m[Test 4] Licensing and Copyright Compliance\033[0m"
assert_contains "LICENSE: MIT License declaration" "${PANEL_DIR}/LICENSE.md" "The MIT License"
assert_contains "LICENSE: Nova Panel notice" "${PANEL_DIR}/LICENSE.md" "Nova Panel"
assert_contains "LICENSE: Pterodactyl attribution preserved" "${PANEL_DIR}/LICENSE.md" "Pterodactyl"
assert_contains "LICENSE: Dane Everitt copyright preserved" "${PANEL_DIR}/LICENSE.md" "Dane Everitt"

echo -e "\n------------------------------------------------------------"
echo -e "Branding & Licensing Summary: Passed: \033[38;5;48m${PASSED}\033[0m | Failed: \033[38;5;196m${FAILED}\033[0m"
if [[ $FAILED -gt 0 ]]; then
    exit 1
fi
