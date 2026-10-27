# Nova Panel Installation Guide

This document describes how to install **Nova Panel** using both the automated one-command installer and manual step-by-step procedures.

---

## System Requirements

| Component | Minimum Specification | Recommended Specification |
| :--- | :--- | :--- |
| **Operating System** | Ubuntu 20.04/22.04/24.04 LTS, Debian 11/12 | Ubuntu 22.04 or 24.04 LTS |
| **CPU Architecture** | x86_64 / amd64 or aarch64 / arm64 | 2+ cores, x86_64 |
| **RAM** | 1024 MB (1 GB) | 4096 MB (4 GB) or higher |
| **Storage** | 5 GB SSD free space | 20+ GB SSD free space |
| **Network** | Outbound internet access to GitHub & Docker | Static public IPv4 or Domain DNS |

### Required Ports

- **Web Panel**: `80/tcp` (HTTP) and `443/tcp` (HTTPS)
- **Wings Daemon**: `8080/tcp` (API communication with Panel)
- **SFTP Server**: `2022/tcp` (File management)
- **Game Server Ports**: `25565-25575/tcp+udp` (Allocated for Minecraft / games)

---

## Method 1: Automated One-Command Installation (Recommended)

Run the following command as `root` on a fresh server:

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/TalhaPlaysOG/NovaPanel/main/install.sh)
```

This opens the interactive setup menu. Choose `[1] Install Panel` to start the
automated installation, or use any other option (Wings, tunnel, node, user).

To skip the menu entirely and run the automated installer directly, append
`--auto`:

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/TalhaPlaysOG/NovaPanel/main/install.sh) --auto
```

The installer will interactively prompt you for:
1. **Access Mode**:
   - `[1] IP Address`: Direct IP access (e.g. `http://YOUR_SERVER_IP`).
   - `[2] Custom Domain + HTTPS`: Automated Let's Encrypt certificate issuance.
   - `[3] Tunnel Access`: Cloudflare Quick Tunnel (temporary) or Named Tunnel (permanent).
2. **Administrator Account Credentials**:
   - Email address
   - Username
   - Password (masked input, minimum 8 characters)

### What the Automated Installer Does:
1. Validates OS, CPU architecture, RAM, disk space, and open ports.
2. Installs PHP 8.2 and extensions, Composer, MariaDB, and Redis.
3. Automatically provisions a secure MariaDB database and user.
4. Deploys Nova Panel and generates application encryption keys.
5. Runs all database migrations and core nest/egg seeds.
6. Automatically creates the root administrator account.
7. Configures Nginx with optimized fastcgi parameters and security headers.
8. Installs Docker Engine and official Wings daemon (v1.13.4).
9. Automatically registers the local node and generates `/etc/pterodactyl/config.yml`.
10. Pre-seeds default Minecraft port allocations (`25565-25575`).
11. Installs the `/usr/local/bin/nova` CLI utility.

---

## Method 1b: Menu Shortcuts & Non-Interactive Flags

The setup menu shown by Method 1 can also be launched directly, which is handy
after the panel is already installed:

```bash
sudo nova menu
sudo bash installer/nova-menu.sh
```

Directly from the internet (no clone required):

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/TalhaPlaysOG/NovaPanel/main/installer/nova-menu.sh)
```

| Button | Action |
| :--- | :--- |
| `[1] Install Panel` | Complete panel installation (same workflow as Method 1) |
| `[2] Install Wings` | Docker Engine + Wings daemon |
| `[3] Setup Tunnel` | Adds the Cloudflare APT repository, installs `cloudflared`, then asks you to paste your tunnel token |
| `[4] Auto Node` | Asks for the node IP, registers the node, seeds ports and starts Wings so it comes online |
| `[5] Create User` | Creates a panel account (optionally a root administrator) |
| `[6] Status` | Services, access mode and tunnel URL |
| `[7] Update Panel` | Runs `installer/update.sh` (latest release, migrations, caches) |
| `[8] Repair Panel` | Runs `installer/repair.sh` (diagnostics and fixes) |

Each action is also available as a flag (`--panel`, `--wings`, `--tunnel`,
`--node`, `--user`, `--status`, `--update`, `--repair`). Full details:
[MENU.md](MENU.md).

The one-command launcher supports `--menu` (default), `--auto` (automated
install without the menu), `--dev` / `--prod` (forced mode) and `--repo` /
`--branch` (alternative source). Full details: [MENU.md](MENU.md).

---

## Method 2: Manual Installation (Advanced)

For hosting providers or administrators who wish to configure each component manually:

### 1. Install Base Packages
```bash
sudo apt update && sudo apt install -y curl tar unzip git redis-server mariadb-server nginx
```

### 2. Install PHP 8.2 & Composer
```bash
sudo add-apt-repository -y ppa:ondrej/php
sudo apt update
sudo apt install -y php8.2-cli php8.2-fpm php8.2-gd php8.2-mysql php8.2-mbstring php8.2-bcmath php8.2-xml php8.2-curl php8.2-zip php8.2-intl
curl -sS https://getcomposer.org/installer | sudo php -- --install-dir=/usr/local/bin --filename=composer
```

### 3. Setup Database
```sql
CREATE DATABASE novapanel CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
CREATE USER 'novapanel'@'127.0.0.1' IDENTIFIED BY 'YOUR_STRONG_PASSWORD';
GRANT ALL PRIVILEGES ON novapanel.* TO 'novapanel'@'127.0.0.1' WITH GRANT OPTION;
FLUSH PRIVILEGES;
```

### 4. Deploy Nova Panel
```bash
sudo mkdir -p /var/www/nova-panel
cd /var/www/nova-panel
# Clone or extract Nova Panel files
sudo cp .env.example .env
# Edit .env with your database details and APP_URL
sudo composer install --no-dev --optimize-autoloader
sudo php artisan key:generate --force
sudo php artisan migrate --seed --force
sudo php artisan p:user:make --admin=1
sudo chown -R www-data:www-data /var/www/nova-panel
```

### 5. Setup Systemd Queue Worker & Scheduler
Create `/etc/systemd/system/pteroq.service`:
```ini
[Unit]
Description=Nova Panel Queue Worker
After=redis-server.service

[Service]
User=www-data
Group=www-data
Restart=always
ExecStart=/usr/bin/php /var/www/nova-panel/artisan queue:work --queue=high,standard,low --sleep=3 --tries=3

[Install]
WantedBy=multi-user.target
```
```bash
sudo systemctl daemon-reload
sudo systemctl enable --now pteroq.service
```

Add cron entry for scheduled tasks:
```bash
sudo crontab -u www-data -e
# Add:
* * * * * php /var/www/nova-panel/artisan schedule:run >> /dev/null 2>&1
```

---

## Verifying Installation

Verify that all services are operational using the Nova CLI:

```bash
sudo nova status
```
