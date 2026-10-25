#!/usr/bin/env bash
# ==============================================================================
# Nova Panel Test Suite - API Compatibility Verification
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

echo -e "\n\033[1m=== Running API Compatibility Tests ===\033[0m\n"

# 1. Application API Endpoints
echo -e "\033[38;5;45m[Test 1] Application API Route Verification\033[0m"
APP_ROUTES="${PANEL_DIR}/routes/api-application.php"

assert_contains "Application API: Users prefix" "${APP_ROUTES}" "prefix' => '/users'"
assert_contains "Application API: Nodes prefix" "${APP_ROUTES}" "prefix' => '/nodes'"
assert_contains "Application API: Node configuration endpoint" "${APP_ROUTES}" "NodeConfigurationController::class"
assert_contains "Application API: Servers prefix" "${APP_ROUTES}" "prefix' => '/servers'"
assert_contains "Application API: Locations prefix" "${APP_ROUTES}" "prefix' => '/locations'"
assert_contains "Application API: Nests prefix" "${APP_ROUTES}" "prefix' => '/nests'"

# 2. Client API Endpoints
echo -e "\n\033[38;5;45m[Test 2] Client API Route Verification\033[0m"
CLIENT_ROUTES="${PANEL_DIR}/routes/api-client.php"

assert_contains "Client API: Account route" "${CLIENT_ROUTES}" "ClientController::class, 'index'"
assert_contains "Client API: Server details route" "${CLIENT_ROUTES}" "api:client:server.view"
assert_contains "Client API: Server websocket route" "${CLIENT_ROUTES}" "WebsocketController::class"
assert_contains "Client API: Server power operations" "${CLIENT_ROUTES}" "PowerController::class"
assert_contains "Client API: File operations directory list" "${CLIENT_ROUTES}" "FileController::class, 'directory'"
assert_contains "Client API: Server backups list" "${CLIENT_ROUTES}" "prefix' => '/backups'"

# 3. Upstream Controllers Check
echo -e "\n\033[38;5;45m[Test 3] Critical Controllers Check\033[0m"
check_file_exists() {
    local test_name="$1"
    local file_path="$2"
    if [[ -f "$file_path" ]]; then
        echo -e "  \033[38;5;48m✔ PASS:\033[0m ${test_name}"
        PASSED=$((PASSED + 1))
    else
        echo -e "  \033[38;5;196m✖ FAIL:\033[0m ${test_name} (Missing: ${file_path})"
        FAILED=$((FAILED + 1))
    fi
}

check_file_exists "Application Node Controller" "${PANEL_DIR}/app/Http/Controllers/Api/Application/Nodes/NodeController.php"
check_file_exists "Application Server Controller" "${PANEL_DIR}/app/Http/Controllers/Api/Application/Servers/ServerController.php"
check_file_exists "Client Server Power Controller" "${PANEL_DIR}/app/Http/Controllers/Api/Client/Servers/PowerController.php"
check_file_exists "Client Server File Controller" "${PANEL_DIR}/app/Http/Controllers/Api/Client/Servers/FileController.php"
check_file_exists "Client Server Websocket Controller" "${PANEL_DIR}/app/Http/Controllers/Api/Client/Servers/WebsocketController.php"

echo -e "\n------------------------------------------------------------"
echo -e "API Compatibility Summary: Passed: \033[38;5;48m${PASSED}\033[0m | Failed: \033[38;5;196m${FAILED}\033[0m"
if [[ $FAILED -gt 0 ]]; then
    exit 1
fi
