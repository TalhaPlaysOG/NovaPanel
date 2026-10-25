# Nova Panel Security Guide & Policy

Nova Panel places the highest priority on server security, data protection, and isolation between the web panel and underlying host infrastructure.

---

## Security Model & Hardening

### 1. Database Isolation
- MariaDB/MySQL is bound exclusively to `127.0.0.1` and `localhost`.
- Remote database network access is disabled by default.
- Application credentials use randomly generated 32-character tokens.

### 2. File & Configuration Protection
- The application environment file (`/var/www/nova-panel/.env`) is locked to permissions `600` and owned by `www-data:www-data`.
- Wings daemon configuration (`/etc/pterodactyl/config.yml`) is locked to `600` and owned by `root:root`.
- Installer logs (`/var/log/nova-panel/install.log`) sanitize sensitive passwords and tokens so plaintext credentials are never written to disk or terminal output.

### 3. Web & HTTP Security Headers
The Nginx configuration provisioned by Nova Panel enforces modern HTTP security headers:
- `X-Content-Type-Options: nosniff` (Prevents MIME sniffing attacks)
- `X-XSS-Protection: 1; mode=block` (Browser XSS mitigation)
- `X-Frame-Options: SAMEORIGIN` & `Content-Security-Policy: frame-ancestors 'self'` (Clickjacking prevention)
- `Referrer-Policy: same-origin` (Protects referrer data)
- HSTS enabled when custom domain SSL is configured.

### 4. Container & Game Server Isolation
- All game server instances run inside isolated Docker containers managed by Wings.
- CPU, memory, and disk usage are enforced at the Linux cgroup and kernel level.
- Container root privileges and host access are blocked by default.

---

## Inspecting Installer Scripts Before Running

Running remote scripts via `curl | bash` should always be reviewed before execution on production systems.

To inspect the installer prior to execution:

```bash
# 1. Download installer script
curl -fsSL https://raw.githubusercontent.com/YOUR_USERNAME/NovaPanel/main/install.sh -o install.sh

# 2. Inspect the script content
less install.sh

# 3. Execute locally once verified
sudo bash install.sh
```

---

## Reporting Security Vulnerabilities

If you discover a potential security vulnerability within Nova Panel:
- **Do not open a public issue.**
- Submit details privately to the security team or maintainers.
- Upstream Pterodactyl engine vulnerabilities should also be coordinated with [security@pterodactyl.io](mailto:security@pterodactyl.io).
