# Nova Panel Update Guide

Nova Panel provides a safe, maintainable update strategy that ensures application data, database records, and Wings configurations are backed up before updates are applied.

---

## Updating via Nova CLI (Recommended)

Run the update command as root:

```bash
sudo nova update
```

### What Happens During `nova update`:
1. Identifies the currently installed Nova Panel and Wings versions.
2. Automatically creates a safety backup of your database, `.env`, SSL certificates, and Wings configuration in `/var/backups/nova-panel/`.
3. Puts the panel into maintenance mode (`php artisan down`).
4. Checks free disk space to ensure sufficient storage is available.
5. Pulls or syncs updated application files.
6. Installs or updates Composer PHP dependencies (`composer install --no-dev --optimize-autoloader`).
7. Executes database migrations safely (`php artisan migrate --force`).
8. Clears and rebuilds view, route, and configuration caches.
9. Restores correct file ownership (`www-data:www-data`).
10. Checks Wings daemon binary compatibility and prompts for upgrade if available.
11. Restarts queue workers (`pteroq`) and brings the panel back online (`php artisan up`).

---

## Manual Update Procedure

If you prefer to perform updates manually:

```bash
cd /var/www/nova-panel

# 1. Backup current database and configuration
sudo nova backup

# 2. Enter maintenance mode
sudo php artisan down

# 3. Pull latest files or extract release archive
sudo cp -a /path/to/new_release/. /var/www/nova-panel/

# 4. Update dependencies and database schema
sudo composer install --no-dev --optimize-autoloader
sudo php artisan migrate --force

# 5. Clear caches and fix permissions
sudo php artisan view:clear
sudo php artisan config:clear
sudo chown -R www-data:www-data /var/www/nova-panel

# 6. Restart queue worker and bring online
sudo systemctl restart pteroq
sudo php artisan up
```

---

## Rollback Guidance

If an update fails or is interrupted:
1. Locate the pre-update backup in `/var/backups/nova-panel/`.
2. Run the restore command:
   ```bash
   sudo nova restore /var/backups/nova-panel/<backup_filename>.tar.gz
   ```
3. Run `sudo nova status` to verify service recovery.
