# Nova Panel Troubleshooting Guide

This guide covers common issues, diagnostic procedures, and solutions when operating Nova Panel.

---

## 1. Quick Self-Repair Tool

Nova Panel comes with an automated diagnostic and self-repair command:

```bash
sudo nova repair
```

`nova repair` automatically:
- Tests connectivity to MariaDB, Redis, and Docker.
- Verifies and restores filesystem permissions on `/var/www/nova-panel/storage` and `bootstrap/cache`.
- Clears stale application, configuration, and view caches.
- Restarts stopped or unresponsive services.
- Flags missing files or invalid encryption keys.

---

## 2. Common Issues & Solutions

### A. 502 Bad Gateway
- **Cause**: PHP-FPM service is not running or the Unix socket path does not match Nginx config.
- **Solution**:
  ```bash
  sudo systemctl restart php8.2-fpm
  sudo systemctl restart nginx
  # Check socket location:
  ls -l /run/php/php*-fpm.sock
  ```

### B. Unable to Connect to Wings Daemon (Node Red in Panel)
- **Cause**: Wings service is stopped, SSL certificate mismatch, or port `8080` is blocked by firewall.
- **Diagnostics**:
  ```bash
  sudo systemctl status wings
  sudo journalctl -u wings -n 50 --no-pager
  ```
- **Solution**:
  If using IP mode or HTTP, verify that the Node configuration in the Panel has "Use SSL" set to **No**.
  Ensure port `8080` is open:
  ```bash
  sudo ufw allow 8080/tcp
  sudo ufw allow 2022/tcp
  ```

### C. Queue Worker Stalled / Tasks Pending
- **Cause**: The `pteroq` queue worker service is stopped.
- **Solution**:
  ```bash
  sudo systemctl restart pteroq
  sudo php /var/www/nova-panel/artisan queue:restart
  ```

### D. CSRF Token Mismatch on Login
- **Cause**: Stale cookies, browser caching, or `APP_URL` in `/var/www/nova-panel/.env` does not match the URL accessed in your browser.
- **Solution**:
  Ensure `APP_URL` in `/var/www/nova-panel/.env` matches your address (including `http://` or `https://` exactly).
  Then clear caches:
  ```bash
  cd /var/www/nova-panel
  sudo php artisan config:clear
  sudo php artisan cache:clear
  ```

### E. Let's Encrypt Certificate Renewal Fails
- **Cause**: Port `80` is blocked by a firewall or DNS records do not point to the server IP.
- **Solution**:
  ```bash
  sudo certbot renew --dry-run
  ```
  Ensure firewall allows HTTP:
  ```bash
  sudo ufw allow 80/tcp
  sudo ufw allow 443/tcp
  ```

---

## 3. Log Locations

| Component | Log Path |
| :--- | :--- |
| **Nova Installer** | `/var/log/nova-panel/install.log` |
| **Nova Tunnel** | `/var/log/nova-panel/tunnel.log` |
| **Nova Panel Laravel** | `/var/www/nova-panel/storage/logs/laravel-*.log` |
| **Nginx Access & Error** | `/var/log/nginx/access.log` & `/var/log/nginx/error.log` |
| **Wings Daemon** | `sudo journalctl -u wings -f` or `/var/log/pterodactyl/` |
| **Queue Worker** | `sudo journalctl -u pteroq -f` |
