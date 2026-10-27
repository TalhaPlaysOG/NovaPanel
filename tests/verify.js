/**
 * Nova Panel - Verification & Test Suite
 * Compatible with Node.js environments (cross-platform)
 */

const fs = require('fs');
const path = require('path');

const ROOT_DIR = path.resolve(__dirname, '..');
const PANEL_DIR = path.join(ROOT_DIR, 'panel');
const INSTALLER_DIR = path.join(ROOT_DIR, 'installer');

let passed = 0;
let failed = 0;

function assert(description, condition, details = '') {
    if (condition) {
        console.log(`  \x1b[32m✔ PASS:\x1b[0m ${description}`);
        passed++;
    } else {
        console.log(`  \x1b[31m✖ FAIL:\x1b[0m ${description} ${details ? `(${details})` : ''}`);
        failed++;
    }
}

console.log('\x1b[1;36m=== NOVA PANEL VERIFICATION & TEST SUITE ===\x1b[0m\n');

// 1. Filesystem & Shell Scripts Structure
console.log('\x1b[35m[1] Shell Script Files Existence & Shebangs\x1b[0m');
const expectedScripts = [
    'install.sh',
    'installer/install.sh',
    'installer/nova-menu.sh',
    'installer/common.sh',
    'installer/backup.sh',
    'installer/restore.sh',
    'installer/update.sh',
    'installer/repair.sh',
    'installer/nova-cli.sh',
    'installer/modules/system-checks.sh',
    'installer/modules/dependencies.sh',
    'installer/modules/database.sh',
    'installer/modules/webserver.sh',
    'installer/modules/docker.sh',
    'installer/modules/wings.sh',
    'installer/modules/node-registration.sh',
    'installer/modules/access/ip.sh',
    'installer/modules/access/domain.sh',
    'installer/modules/access/tunnel.sh',
];

for (const scriptRel of expectedScripts) {
    const fullPath = path.join(ROOT_DIR, scriptRel);
    const exists = fs.existsSync(fullPath);
    assert(`Script exists: ${scriptRel}`, exists);
    if (exists) {
        const content = fs.readFileSync(fullPath, 'utf8');
        assert(`Script has bash shebang: ${scriptRel}`, content.startsWith('#!/usr/bin/env bash') || content.startsWith('#!/bin/bash'));
    }
}

// 2. Line Endings Verification (LF only for shell scripts to avoid CRLF errors on Linux)
console.log('\n\x1b[35m[2] Shell Scripts Line-Ending Normalization (LF)\x1b[0m');
for (const scriptRel of expectedScripts) {
    const fullPath = path.join(ROOT_DIR, scriptRel);
    if (fs.existsSync(fullPath)) {
        const buffer = fs.readFileSync(fullPath);
        const hasCR = buffer.includes(13); // 13 is ASCII \r (CR)
        assert(`Script line endings are LF: ${scriptRel}`, !hasCR);
    }
}

// 3. Domain Regex Validator Test
console.log('\n\x1b[35m[3] Domain Regex Validation Logic\x1b[0m');
const domainRegex = /^([a-zA-Z0-9]([a-zA-Z0-9\-]{0,61}[a-zA-Z0-9])?\.)+[a-zA-Z]{2,}$/;
assert('Valid domain: panel.example.com', domainRegex.test('panel.example.com'));
assert('Valid domain: nova.my-vps.org', domainRegex.test('nova.my-vps.org'));
assert('Valid domain: sub.domain.co.uk', domainRegex.test('sub.domain.co.uk'));
assert('Invalid domain: -invalid.com', !domainRegex.test('-invalid.com'));
assert('Invalid domain: http://example.com', !domainRegex.test('http://example.com'));
assert('Invalid domain: empty string', !domainRegex.test(''));

// 4. Git Repository Integrity & Cleanliness Rules
console.log('\n\x1b[35m[4] Git Repository Configuration (.gitignore & .gitattributes)\x1b[0m');
const rootGitignore = path.join(ROOT_DIR, '.gitignore');
assert('Root .gitignore exists', fs.existsSync(rootGitignore));
if (fs.existsSync(rootGitignore)) {
    const giContent = fs.readFileSync(rootGitignore, 'utf8');
    assert('.gitignore excludes sensitive .env', giContent.includes('.env'));
    assert('.gitignore preserves .env.example', giContent.includes('!.env.example'));
    assert('.gitignore excludes vendor dependencies', giContent.includes('/vendor') || giContent.includes('panel/vendor'));
    assert('.gitignore excludes node_modules', giContent.includes('/node_modules') || giContent.includes('panel/node_modules'));
}

const rootGitattributes = path.join(ROOT_DIR, '.gitattributes');
assert('Root .gitattributes exists', fs.existsSync(rootGitattributes));
if (fs.existsSync(rootGitattributes)) {
    const gaContent = fs.readFileSync(rootGitattributes, 'utf8');
    assert('.gitattributes normalizes text to LF', gaContent.includes('eol=lf'));
    assert('.gitattributes enforces LF for *.sh scripts', gaContent.includes('*.sh text eol=lf'));
}

// 5. Laravel Storage & Cache Directory Structure
console.log('\n\x1b[35m[5] Laravel Directory Structure & Hidden Files\x1b[0m');
const criticalStoragePaths = [
    path.join(PANEL_DIR, 'storage', 'framework', 'cache', 'data', '.gitignore'),
    path.join(PANEL_DIR, 'storage', 'framework', 'sessions', '.gitignore'),
    path.join(PANEL_DIR, 'storage', 'framework', 'views', '.gitignore'),
    path.join(PANEL_DIR, 'storage', 'logs', '.gitignore'),
    path.join(PANEL_DIR, 'storage', 'app', 'public', '.gitignore'),
    path.join(PANEL_DIR, 'bootstrap', 'cache', '.gitignore'),
];

for (const p of criticalStoragePaths) {
    const rel = path.relative(ROOT_DIR, p);
    assert(`Laravel directory tracker exists: ${rel}`, fs.existsSync(p));
}

// 6. Application API Routes & Controllers Integrity
console.log('\n\x1b[35m[6] Application API Routes & Controllers\x1b[0m');
const appRoutesPath = path.join(PANEL_DIR, 'routes', 'api-application.php');
assert('routes/api-application.php exists', fs.existsSync(appRoutesPath));
if (fs.existsSync(appRoutesPath)) {
    const appRoutes = fs.readFileSync(appRoutesPath, 'utf8');
    assert('API has users route group', appRoutes.includes("prefix' => '/users'"));
    assert('API has nodes route group', appRoutes.includes("prefix' => '/nodes'"));
    assert('API has node configuration route', appRoutes.includes("configuration', Application\\Nodes\\NodeConfigurationController::class"));
    assert('API has servers route group', appRoutes.includes("prefix' => '/servers'"));
    assert('API has locations route group', appRoutes.includes("prefix' => '/locations'"));
    assert('API has nests route group', appRoutes.includes("prefix' => '/nests'"));
}

// 7. Client API Routes Integrity
console.log('\n\x1b[35m[7] Client API Routes\x1b[0m');
const clientRoutesPath = path.join(PANEL_DIR, 'routes', 'api-client.php');
assert('routes/api-client.php exists', fs.existsSync(clientRoutesPath));
if (fs.existsSync(clientRoutesPath)) {
    const clientRoutes = fs.readFileSync(clientRoutesPath, 'utf8');
    assert('Client API has account index', clientRoutes.includes("Route::get('/', [Client\\ClientController::class, 'index'])"));
    assert('Client API has server details endpoint', clientRoutes.includes("api:client:server.view"));
    assert('Client API has websocket endpoint', clientRoutes.includes("Client\\Servers\\WebsocketController::class"));
    assert('Client API has power endpoint', clientRoutes.includes("Client\\Servers\\PowerController::class"));
    assert('Client API has file list endpoint', clientRoutes.includes("Client\\Servers\\FileController::class, 'directory'"));
    assert('Client API has backups endpoint', clientRoutes.includes("prefix' => '/backups'"));
}

// 8. Nova Panel Branding & Licensing Integrity
console.log('\n\x1b[35m[8] Nova Panel Branding & Licensing\x1b[0m');
const configApp = fs.readFileSync(path.join(PANEL_DIR, 'config', 'app.php'), 'utf8');
assert("config/app.php default name is 'Nova Panel'", configApp.includes("'name' => env('APP_NAME', 'Nova Panel')"));

const configNova = path.join(PANEL_DIR, 'config', 'nova.php');
assert('config/nova.php exists', fs.existsSync(configNova));
if (fs.existsSync(configNova)) {
    const content = fs.readFileSync(configNova, 'utf8');
    assert("config/nova.php contains version '1.0.0'", content.includes("'version' => '1.0.0'"));
    assert("config/nova.php contains configurable brand fields", content.includes("'name'") && content.includes("'accent_color'"));
}

const adminLayout = fs.readFileSync(path.join(PANEL_DIR, 'resources', 'views', 'layouts', 'admin.blade.php'), 'utf8');
assert('admin.blade.php title references Nova Panel', adminLayout.includes("config('app.name', 'Nova Panel')"));
assert('admin.blade.php logo references Nova Panel', adminLayout.includes("<span>{{ config('app.name', 'Nova Panel') }}</span>"));
assert('admin.blade.php preserves Pterodactyl Software attribution', adminLayout.includes('Powered by <a href="https://pterodactyl.io/">Pterodactyl Software</a>'));

const licenseFile = fs.readFileSync(path.join(PANEL_DIR, 'LICENSE.md'), 'utf8');
assert('LICENSE.md has Nova Panel notice', licenseFile.includes('Nova Panel'));
assert('LICENSE.md preserves Pterodactyl attribution', licenseFile.includes('Pterodactyl'));
assert('LICENSE.md preserves Dane Everitt copyright notice', licenseFile.includes('Dane Everitt'));

const rootLicenseFile = path.join(ROOT_DIR, 'LICENSE.md');
assert('Root LICENSE.md exists', fs.existsSync(rootLicenseFile));

const svgLogo = path.join(PANEL_DIR, 'public', 'assets', 'svgs', 'nova.svg');
assert('nova.svg brand logo exists', fs.existsSync(svgLogo));
const svgMark = path.join(PANEL_DIR, 'public', 'assets', 'svgs', 'nova-mark.svg');
assert('nova-mark.svg brand mark exists', fs.existsSync(svgMark));

// 9. CLI Management Commands Check
console.log('\n\x1b[35m[9] CLI Commands in installer/nova-cli.sh\x1b[0m');
const cliContent = fs.readFileSync(path.join(INSTALLER_DIR, 'nova-cli.sh'), 'utf8');
const requiredCommands = [
    'menu',
    'status',
    'install',
    'update',
    'backup',
    'restore',
    'repair',
    'tunnel',
    'logs',
    'start',
    'stop',
];
for (const cmd of requiredCommands) {
    assert(`CLI implements command: nova ${cmd}`, cliContent.includes(`cmd_${cmd}`) || cliContent.includes(`${cmd})`));
}

// 10. Interactive Setup Menu (buttons) & Secure Form Handling
console.log('\n\x1b[35m[10] Interactive Setup Menu & Secure Form Handling\x1b[0m');
const menuPath = path.join(INSTALLER_DIR, 'nova-menu.sh');
assert('Setup menu exists: installer/nova-menu.sh', fs.existsSync(menuPath));
if (fs.existsSync(menuPath)) {
    const menu = fs.readFileSync(menuPath, 'utf8');
    assert('Menu exposes "Install Panel"', menu.includes('Install Panel'));
    assert('Menu exposes "Install Wings"', menu.includes('Install Wings'));
    assert('Menu exposes "Setup Tunnel"', menu.includes('Setup Tunnel'));
    assert('Menu exposes "Auto Node"', menu.includes('Auto Node'));
    assert('Menu exposes "Create User"', menu.includes('Create User'));
    assert('Menu installs cloudflared via APT', menu.includes('install_cloudflared_apt'));
    assert('Menu prompts for a Cloudflare tunnel token', menu.includes('Paste your Cloudflare Tunnel Token'));
    assert('Menu asks for a node IP address', menu.includes('Node IP address or hostname'));
    assert('Menu provisions nodes through the helper', menu.includes('auto-node.php'));
    assert('Menu creates users through the helper', menu.includes('create-user.php'));
}

const tunnelModule = fs.readFileSync(path.join(INSTALLER_DIR, 'modules', 'access', 'tunnel.sh'), 'utf8');
assert('Cloudflare APT repository is configured', tunnelModule.includes('https://pkg.cloudflare.com/cloudflared any main'));

const autoNodeHelper = path.join(INSTALLER_DIR, 'helpers', 'auto-node.php');
assert('Auto node helper exists', fs.existsSync(autoNodeHelper));
if (fs.existsSync(autoNodeHelper)) {
    const helper = fs.readFileSync(autoNodeHelper, 'utf8');
    assert('Auto node helper boots the Laravel app', helper.includes('bootstrap/app.php'));
    assert('Auto node helper seeds allocations', helper.includes('AssignmentService'));
    assert('Auto node helper leaves the node out of maintenance', helper.includes("'maintenance_mode' => false"));
}

const createUserHelper = path.join(INSTALLER_DIR, 'helpers', 'create-user.php');
assert('Create user helper exists', fs.existsSync(createUserHelper));
if (fs.existsSync(createUserHelper)) {
    const helper = fs.readFileSync(createUserHelper, 'utf8');
    assert('Create user helper uses UserCreationService', helper.includes('UserCreationService'));
    assert('Create user helper hashes updated passwords', helper.includes('Hash::make'));
}

const secureFormsPath = path.join(PANEL_DIR, 'public', 'js', 'secure-forms.js');
assert('Secure form handler exists', fs.existsSync(secureFormsPath));
if (fs.existsSync(secureFormsPath)) {
    const js = fs.readFileSync(secureFormsPath, 'utf8');
    assert('Secure form handler submits with fetch()', js.includes('fetch(action'));
    assert('Secure form handler keeps the FormData payload', js.includes('new FormData(form)'));
    assert('Secure form handler preserves submitter values', js.includes('submitter'));
    assert('admin layout loads secure-forms.js', adminLayout.includes('/js/secure-forms.js'));
}

// 11. CodeSandbox & Development Environment Configurations
console.log('\n\x1b[35m[11] CodeSandbox & Development Configurations\x1b[0m');
const csbTasks = path.join(ROOT_DIR, '.codesandbox', 'tasks.json');
assert('.codesandbox/tasks.json exists', fs.existsSync(csbTasks));
if (fs.existsSync(csbTasks)) {
    try {
        const parsed = JSON.parse(fs.readFileSync(csbTasks, 'utf8'));
        assert('.codesandbox/tasks.json has valid JSON schema', !!parsed.tasks);
        assert('.codesandbox/tasks.json configures port 8000 preview', JSON.stringify(parsed).includes('8000'));
    } catch (e) {
        assert('.codesandbox/tasks.json is valid JSON', false, e.message);
    }
}

const devboxJson = path.join(ROOT_DIR, 'devbox.json');
assert('devbox.json exists', fs.existsSync(devboxJson));
if (fs.existsSync(devboxJson)) {
    try {
        const parsed = JSON.parse(fs.readFileSync(devboxJson, 'utf8'));
        assert('devbox.json has packages defined', Array.isArray(parsed.packages));
    } catch (e) {
        assert('devbox.json is valid JSON', false, e.message);
    }
}

const csbDoc = path.join(ROOT_DIR, 'docs', 'CODESANDBOX.md');
assert('docs/CODESANDBOX.md exists', fs.existsSync(csbDoc));

// Summary
console.log('\n\x1b[1m============================================================\x1b[0m');
console.log(`Total Checks: ${passed + failed} | \x1b[32mPassed: ${passed}\x1b[0m | \x1b[31mFailed: ${failed}\x1b[0m`);
if (failed === 0) {
    console.log('\x1b[1;32m✔ ALL INTEGRATION & VERIFICATION TESTS PASSED!\x1b[0m\n');
    process.exit(0);
} else {
    console.log('\x1b[1;31m✖ VERIFICATION FAILED\x1b[0m\n');
    process.exit(1);
}
