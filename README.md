<p align="center">
  <img src="panel/public/assets/svgs/nova.svg" width="460" alt="Nova Panel Logo">
</p>

<p align="center">
  <strong>Next-Generation Game Server Management Platform</strong><br>
  <em>Built upon the battle-tested, open-source Pterodactyl® core engine.</em>
</p>

<p align="center">
  <a href="#quick-start">Quick Start</a> &bull;
  <a href="#features">Features</a> &bull;
  <a href="#access-modes">Access Modes</a> &bull;
  <a href="#cli-management">CLI Management</a> &bull;
  <a href="#documentation">Documentation</a> &bull;
  <a href="#licensing--attribution">License</a>
</p>

---

## Overview

**Nova Panel** is a production-oriented game hosting management platform designed to make installation, networking, maintenance, and node orchestration seamless for both beginners and hosting providers.

Rather than reinventing or breaking the rock-solid game management architecture of Pterodactyl, Nova Panel retains the complete Pterodactyl v1.15.2 core engine, API compatibility, egg ecosystem, and Wings v1.13.4 daemon, while delivering:
- A streamlined **one-command installer** (`install.sh`).
- Automated database, Redis, PHP 8.2, Docker, and Wings provisioning.
- **Three versatile panel access methods**: Direct IP, Custom Domain + Automated Let's Encrypt HTTPS, and Zero-Port-Forwarding Tunnel Access.
- Automated local node registration and default Minecraft port allocations (`25565-25575`).
- A built-in command-line management utility (`nova`).

---

## Quick Start (One-Command Installer)

### Option A: Interactive Setup Menu (Recommended)
Run this on a clean Ubuntu (20.04, 22.04, 24.04 LTS) or Debian (11, 12) server as root:

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/TalhaPlaysOG/NovaPanel/main/install.sh)
```

The menu opens with numbered buttons:

| Button | What it does |
| :--- | :--- |
| `[1] Install Panel` | Runs the full automated panel installation |
| `[2] Install Wings` | Installs Docker + Wings on this machine |
| `[3] Setup Tunnel` | Installs `cloudflared` via APT and asks for your tunnel token |
| `[4] Auto Node` | Asks for an IP, creates the node, seeds ports and brings Wings online |
| `[5] Create User` | Creates a panel account (optionally a root administrator) |
| `[6] Status` | Shows services, nodes and access configuration |
| `[7] Update Panel` | Fetches the latest release, runs migrations and clears caches |
| `[8] Repair Panel` | Runs diagnostics and fixes common service/permission issues |

After installation the same menu is available as `sudo nova menu`. See [`docs/MENU.md`](docs/MENU.md) for details.

> Options 1–4 install system packages and services, so they need an Ubuntu/Debian
> host booted with **systemd** (the default on a VPS). Containers and WSL without
> systemd are detected as development mode; the menu explains what is missing and
> still allows a panel-only install.

### Option B: Automated Install (No Menu)
Skip the menu and run the linear installer with auto-detected settings:

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/TalhaPlaysOG/NovaPanel/main/install.sh) --auto
```

Add `--prod` (or `--dev`) to force a deployment mode: `... --auto --prod`.

### Option C: CodeSandbox & Local Dev Mode
Open this repository in a CodeSandbox Devbox (~8 GiB RAM) or run locally without root permissions:

```bash
bash install.sh --dev
```
- Automatically configures a zero-dependency SQLite database.
- Binds to `0.0.0.0:8000` with automated CodeSandbox HTTPS port preview.
- Enables panel-only testing for accounts, UI, egg management, and APIs without requiring systemd or kernel cgroups. See [`docs/CODESANDBOX.md`](docs/CODESANDBOX.md).

---

## Key Features

- **Production-Ready & Idempotent**: Safe installation workflow that validates prerequisites, warns before destructive changes, and logs all events to `/var/log/nova-panel/install.log`.
- **Automated Wings & Node Orchestration**: Installs official Wings daemon, generates `/etc/pterodactyl/config.yml` via Artisan CLI, configures memory/disk limits, and starts the Wings service.
- **Zero-Config Game Port Seeding**: Automatically provisions default server allocations (`25565-25575`) so you can deploy Minecraft servers immediately.
- **Configurable Branding**: Custom Nova Panel aesthetic with dark mode, modern SVG branding, and configurable branding tokens in `panel/config/nova.php`.
- **100% API & Egg Compatible**: Works out-of-the-box with all community eggs, Docker images, and third-party API integrations (Application API & Client API preserved).
- **Button-Driven Setup Menu**: A single interactive screen for installing the panel or Wings, wiring a Cloudflare tunnel with your token, auto-registering a node from an IP, and creating users (`sudo nova menu`).
- **No Insecure-Form Warning**: Admin forms are submitted through a fetch-based handler, so Chromium no longer interrupts every action with the "information you're about to submit is not secure" interstitial when the panel runs on plain HTTP.

---

## Three Panel Access Methods

During installation, Nova Panel offers three access methods:

```
NOVA PANEL INSTALLER
Select how you want to access your panel:
[1] IP Address
[2] Custom Domain + HTTPS
[3] Tunnel Access
```

1. **IP Address**:
   - Access directly via your server's public IPv4 (e.g. `http://192.0.2.1`).
   - No domain purchase required. Fast setup for private testing or LAN environments.
2. **Custom Domain + HTTPS**:
   - Automated DNS verification and Let's Encrypt SSL certificate issuance via Certbot.
   - Automatic HTTP to HTTPS redirects and modern TLS security headers.
3. **Tunnel Access**:
   - **Temporary Quick Tunnel**: Generates a free, secure `trycloudflare.com` URL without requiring open router ports or a domain.
   - **Permanent Named Tunnel**: Integrates with Cloudflare Zero Trust for persistent domain-based access behind NAT/firewalls.
   - *Note*: Tunnel access routes web panel traffic only; Minecraft and game ports operate directly on your server networking.

---

## CLI Management (`nova`)

Nova Panel includes a system-wide management command installed to `/usr/local/bin/nova`:

```bash
# Open the interactive setup menu (install panel/wings, tunnel, node, user)
sudo nova menu

# Check status of web server, database, Redis, Wings, and tunnels
sudo nova status

# Create a full snapshot (database, .env, SSL certificates, Wings configs)
sudo nova backup

# Restore your installation from a backup archive
sudo nova restore /var/backups/nova-panel/<backup_name>.tar.gz

# Run diagnostics, fix file permissions, and clear stale caches
sudo nova repair

# Check or restart active tunnel connections
sudo nova tunnel status
sudo nova tunnel restart

# Apply updates safely with pre-update backups and migration checks
sudo nova update
```

---

## Repository Structure

```
NovaPanel/
├── panel/                      # Nova Panel application (Pterodactyl Core)
│   ├── app/                    # Laravel application, API controllers, services
│   ├── config/nova.php         # Configurable Nova branding and metadata
│   ├── public/assets/svgs/     # Nova Panel official SVG brand assets
│   └── resources/              # Views, React scripts, and themes
├── installer/                  # Modular installer and maintenance scripts
│   ├── install.sh              # Master installer orchestrator
│   ├── nova-menu.sh            # Interactive setup menu (install panel/wings, tunnel, node, user)
│   ├── update.sh               # Safe update workflow
│   ├── backup.sh               # Automated backup generator
│   ├── restore.sh              # Snapshot restoration utility
│   ├── repair.sh               # Diagnostics & permission fixer
│   ├── nova-cli.sh             # System CLI (/usr/local/bin/nova)
│   ├── helpers/                # PHP helpers used by the menu (auto node, user creation)
│   ├── common.sh               # UI helpers, colors, logging, and prompts
│   └── modules/                # Specialized installation modules
│       ├── system-checks.sh    # Hardware and OS validation
│       ├── dependencies.sh     # PHP 8.2, Composer, Redis
│       ├── database.sh         # MariaDB database provisioning
│       ├── webserver.sh        # Nginx vhosts and SSL redirects
│       ├── docker.sh           # Docker CE engine setup
│       ├── wings.sh            # Official Wings daemon binary & systemd
│       ├── node-registration.sh# Automated node & allocation registration
│       └── access/             # IP, Domain, and Tunnel access modules
│   └── helpers/                # Auto node & create user PHP helpers
├── docs/                       # Comprehensive documentation
│   ├── INSTALL.md
│   ├── MENU.md                 # Interactive setup menu & browser warning fix
│   ├── UPDATE.md
│   ├── BACKUP.md
│   ├── RESTORE.md
│   ├── TUNNEL.md
│   ├── TROUBLESHOOTING.md
│   └── SECURITY.md
├── tests/                      # Verification test suites
│   ├── verify.js               # Cross-platform integration test suite
│   ├── test_installer_modules.sh
│   ├── test_api_compatibility.sh
│   └── test_branding.sh
├── install.sh                  # Root one-command bootstrap script
└── README.md
```

---

## Documentation

Detailed technical documentation is available in the [`docs/`](docs/) directory:
- [Installation Guide](docs/INSTALL.md)
- [Interactive Setup Menu](docs/MENU.md)
- [Update Strategy & Rollback](docs/UPDATE.md)
- [Backup Automation](docs/BACKUP.md)
- [Restoration Procedures](docs/RESTORE.md)
- [Tunnel Architecture & Usage](docs/TUNNEL.md)
- [Troubleshooting & Diagnostics](docs/TROUBLESHOOTING.md)
- [Security Policy & Hardening](docs/SECURITY.md)

---

## Licensing & Attribution

Nova Panel is open-source software licensed under the **[MIT License](panel/LICENSE.md)**.

- **Pterodactyl®**: Copyright © 2015 - 2026 Dane Everitt and contributors.
- **Nova Panel**: Copyright © Nova Panel Contributors.

Nova Panel is an independent open-source downstream project built upon the Pterodactyl foundation. All original licenses, copyrights, and intellectual property attributions are strictly preserved in compliance with the MIT License.
