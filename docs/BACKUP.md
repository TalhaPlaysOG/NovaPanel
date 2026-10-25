# Nova Panel Backup Guide

Nova Panel includes built-in backup automation for the database, application environment, SSL certificates, Nginx configurations, and Wings daemon settings.

---

## Creating a Backup

To create an instant full snapshot of your installation:

```bash
sudo nova backup
```

### Files Included in the Backup Archive:
- **Database Dump**: Complete MySQL/MariaDB database dump (`database.sql`).
- **Application Environment**: `/var/www/nova-panel/.env` (app keys, salts, database credentials).
- **Nova Configuration**: `/etc/nova-panel/` (access modes, domain, tunnel settings).
- **Wings Daemon Config**: `/etc/pterodactyl/config.yml` (tokens, SFTP settings, node UUIDs).
- **Web Server Config**: `/etc/nginx/sites-available/nova-panel.conf`.

All backup archives are saved to:
```
/var/backups/nova-panel/nova_backup_YYYYMMDD_HHMMSS.tar.gz
```
Filesystem permissions on archives are restricted to `600` (root-only access) to safeguard sensitive tokens and keys.

---

## Automating Backups with Cron

To create daily automated backups at 03:00 AM, add a line to root's crontab:

```bash
sudo crontab -e
```
Add:
```cron
0 3 * * * /usr/local/bin/nova backup >> /var/log/nova-panel/cron-backup.log 2>&1
```

### Rotating Old Backups
To automatically delete backups older than 14 days:
```cron
0 4 * * * find /var/backups/nova-panel/ -type f -name "*.tar.gz" -mtime +14 -delete
```
