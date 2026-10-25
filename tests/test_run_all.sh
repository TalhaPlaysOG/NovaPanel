#!/usr/bin/env bash
# ==============================================================================
# Nova Panel Test Suite - Master Test Runner
# ==============================================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo -e "\033[1;38;5;45m"
cat << "EOF"
  _   _  ______      __     _______ ______  _____ _______ 
 | \ | |/ __ \ \    / /\   |__   __|  ____|/ ____|__   __|
 |  \| | |  | \ \  / /  \     | |  | |__  | (___    | |   
 | . ` | |  | |\ \/ / /\ \    | |  |  __|  \___ \   | |   
 | |\  | |__| | \  / ____ \   | |  | |____ ____) |  | |   
 |_| \_|\____/   \/_/    \_\  |_|  |______|_____/   |_|   
EOF
echo -e "\033[0m"
echo -e "Executing Nova Panel Automated Verification Suite...\n"

FAIL_COUNT=0

run_test() {
    local test_script="$1"
    local desc="$2"
    echo -e "\033[1;38;5;141m>>> Running: ${desc} (${test_script})\033[0m"
    if bash "${SCRIPT_DIR}/${test_script}"; then
        echo -e "\033[38;5;48m>>> COMPLETED: ${desc}\033[0m\n"
    else
        echo -e "\033[38;5;196m>>> FAILED: ${desc}\033[0m\n"
        FAIL_COUNT=$((FAIL_COUNT + 1))
    fi
}

run_test "test_installer_modules.sh" "Installer Modules & Syntax Tests"
run_test "test_api_compatibility.sh" "Application & Client API Compatibility"
run_test "test_branding.sh" "Nova Branding & License Attribution"

echo -e "\033[1m============================================================\033[0m"
if [[ $FAIL_COUNT -eq 0 ]]; then
    echo -e "\033[38;5;48m✔ ALL NOVA PANEL TESTS PASSED SUCCESSFULLY!\033[0m"
    exit 0
else
    echo -e "\033[38;5;196m✖ ${FAIL_COUNT} TEST SUITE(S) FAILED. Please review the output above.\033[0m"
    exit 1
fi
