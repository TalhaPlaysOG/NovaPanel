# Nova Panel Restore Guide

This guide details how to restore a Nova Panel installation from a previously created `.tar.gz` backup snapshot.

---

## Restoring via Nova CLI

Run the restore command:

```bash
sudo nova restore
```

If run without arguments, `nova restore` will list all available archives in `/var/backups/nova-panel/` and prompt you to select one.

Alternatively, specify the full path directly:

```bash
sudo nova restore /var/backups/nova-panel/nova_backup_20261025_201500.tar.gz
```

---

## Restoration Workflow

1. **Integrity Validation**: Verifies that the `.tar.gz` archive is uncorrupted and readable.
2. **Explicit Confirmation**: Prompts the user before making any changes. No data is overwritten without confirmation.
3. **Configuration Restoration**:
   - Restores `.env` with correct ownership (`www-data:www-data`).
   - Restores `/etc/nova-panel/` configuration files.
   - Restores `/etc/pterodactyl/config.yml` for Wings.
   - Restores `/etc/nginx/sites-available/nova-panel.conf`.
4. **Database Restoration**: Imports `database.sql` into the configured MariaDB/MySQL database.
5. **Cache Refresh**: Clears compiled Blade views, route caches, and Redis application caches.
6. **Service Restarts**: Restarts Nginx, the queue worker (`pteroq`), and Wings daemon.

---

## Post-Restoration Health Check

After restoring, verify system health:

```bash
sudo nova status
sudo nova repair
```
