# Nova Panel Interactive Setup Menu

The setup menu is a single screen with numbered "buttons" for the tasks that are
normally spread across several scripts. It is useful on a fresh VPS, and equally
useful later when you want to add a tunnel, register another node, or create an
account without remembering Artisan commands.

---

## Launching the menu

The one-command launcher opens the menu by default:

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/TalhaPlaysOG/NovaPanel/main/install.sh)
```

To run the automated installer without the menu, add `--auto`:

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/TalhaPlaysOG/NovaPanel/main/install.sh) --auto
```

From a cloned repository:

```bash
sudo bash installer/nova-menu.sh
```

Directly from the internet (menu script only, no clone required):

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/TalhaPlaysOG/NovaPanel/main/installer/nova-menu.sh)
```

After Nova Panel is installed:

```bash
sudo nova menu
```

Every entry can also be run non-interactively, which is handy for automation:

| Flag | Action |
| :--- | :--- |
| `--panel` | Install / reconfigure the panel |
| `--wings` | Install Docker + Wings |
| `--tunnel` | Install `cloudflared` and configure a tunnel |
| `--node` | Create a node from an IP |
| `--user` | Create a panel user |
| `--status` | Show service and access status |
| `--update` | Update the panel to the latest release |
| `--repair` | Run diagnostics and fix common issues |

```bash
sudo bash installer/nova-menu.sh --node
```

---

## Environment detection

The menu decides between **production** and **development** mode automatically:

| Detected host | Mode | What works |
| :--- | :--- | :--- |
| Ubuntu/Debian VPS with systemd | `production` | All options |
| VPS started without `sudo` | `production` | All options; install actions ask you to re-run with `sudo` |
| CodeSandbox, Docker container, chroot, WSL without systemd | `development` | Panel-only install (SQLite), user management, status |

Development mode is intentionally limited: Wings, `cloudflared` and Auto Node need
systemd, kernel cgroups and root, so they cannot run inside a container or a
sandbox. The menu shows a short reason above the buttons when this applies. To
get the full feature set, run the menu as root on an Ubuntu/Debian VPS, or enable
systemd in WSL (`[boot] systemd=true` in `/etc/wsl.conf`, then `wsl --shutdown`).

---

## Button reference

```
[1] Install Panel    Full installer: dependencies, database, webserver, admin
[2] Install Wings    Docker engine + Wings daemon
[3] Setup Tunnel     cloudflared via APT + tunnel token
[4] Auto Node        Create a node from an IP and bring it online
[5] Create User      Add a panel account or administrator
[6] Status           Services, nodes and access configuration
[7] Update Panel     Latest release, migrations, caches
[8] Repair Panel     Diagnostics and common fixes
[0] Exit
```

### [1] Install Panel

Runs the standard `installer/install.sh` workflow. If a panel is already present
the menu asks for confirmation before touching it. Nothing is deleted; the
installer is idempotent and preserves an existing database.

### [2] Install Wings

Installs Docker Engine (official repository) and the Wings daemon, creates the
`wings` systemd unit and enables it. If no node configuration exists yet, the
menu offers to jump straight into Auto Node.

Wings requires a production Linux host with root access, systemd and cgroups.
In development / CodeSandbox / container mode the menu explains which
requirement is missing and returns to the button list.

### [3] Setup Tunnel

Installs `cloudflared` using Cloudflare's official APT repository — the same
steps documented by Cloudflare:

```bash
sudo mkdir -p --mode=0755 /usr/share/keyrings
curl -fsSL https://pkg.cloudflare.com/cloudflare-main.gpg \
  | sudo tee /usr/share/keyrings/cloudflare-main.gpg >/dev/null

echo 'deb [signed-by=/usr/share/keyrings/cloudflare-main.gpg] https://pkg.cloudflare.com/cloudflared any main' \
  | sudo tee /etc/apt/sources.list.d/cloudflared.list

sudo apt-get update && sudo apt-get install -y cloudflared
```

The menu then asks you to **paste your tunnel token** (input is hidden). The
token is installed through `cloudflared service install`, saved with mode `600`
in `/etc/nova-panel/tunnel.env`, and the service is enabled and started.

If you already routed a public hostname to the tunnel, the menu can also:

- write `/etc/nova-panel/access.env`,
- set `APP_URL=https://<your-hostname>` in the panel `.env`,
- set `TRUSTED_PROXIES=*` and clear the config cache.

In the Cloudflare dashboard, the public hostname should point to:

```
Service type: HTTP
URL:          localhost:80
```

> See [TUNNEL.md](TUNNEL.md) for the complete tunnel guide.

### [4] Auto Node

Prompts for the node IP (or hostname) and then does everything else:

1. Installs Docker and Wings first if they are missing.
2. Creates the default location when none exists.
3. Creates the node (or updates the existing node with that address).
4. Seeds the requested game ports (`25565-25575` by default).
5. Generates `/etc/pterodactyl/config.yml`.
6. Starts Wings and verifies `GET /api/system` answers with the node token.
7. Leaves the node out of maintenance mode so it shows as online.

If the IP you enter belongs to a different machine, the menu prints the exact
steps to move the generated configuration to that machine instead of starting a
local daemon.

### [5] Create User

Prompts for email, username, name and either a typed or auto-generated
password, then asks whether the account should be a root administrator. Existing
accounts with the same email/username are updated rather than duplicated.

The generated password is printed once at the end of the operation.

### [6] Status

Shortcut for `nova status` — services, access mode and tunnel URL.

### [7] Update Panel

Runs `installer/update.sh`: downloads the latest release, updates Composer
dependencies, runs migrations, rebuilds caches, and restarts services. Requires
a previously installed panel and root on production hosts.

### [8] Repair Panel

Runs `installer/repair.sh`: checks core services, permissions, storage links,
queue workers and configuration, restarting or fixing what it can. Safe to run
repeatedly.

---

## Browser warning: "The information you're about to submit is not secure"

Browsers show this interstitial whenever a form is submitted from a page served
over plain HTTP. There are two complementary fixes in Nova Panel:

1. **Use HTTPS.** The tunnel option routes the panel through Cloudflare's edge,
   so the browser sees `https://` and the warning disappears. Domain access mode
   with Let's Encrypt has the same effect.
2. **Secure form handler.** `panel/public/js/secure-forms.js` is loaded by the
   admin layout. On HTTP origins it submits forms with `fetch()` (keeping the
   CSRF token, the clicked submit button values and normal server-side
   validation), so the browser no longer treats the action as an insecure form
   navigation. On HTTPS it disables itself and forms behave natively.

The handler never weakens validation or CSRF protection; it only changes how the
payload travels. Running the panel over HTTPS remains strongly recommended.

---

## Troubleshooting

| Symptom | Fix |
| :--- | :--- |
| `This action needs a production Linux VPS` | Check the reason printed above the menu: containers, sandboxes and WSL without systemd cannot run Wings or cloudflared. Use an Ubuntu/Debian VPS with systemd, or enable systemd in WSL. |
| `This action requires root privileges` | Re-run the menu with `sudo bash installer/nova-menu.sh` (or `sudo nova menu`). |
| `cloudflared` install fails | Check `/var/log/nova-panel/install.log`; ensure DNS and outbound 443 work |
| Tunnel service inactive | `journalctl -u cloudflared -n 50` |
| Wings service inactive | `journalctl -u wings -n 50`; confirm Docker is running |
| Node shows offline in the panel | Confirm the panel can reach `http(s)://<node>:8080` and that scheme/port match |
| User creation fails | Check `/var/log/nova-panel/install.log`; the helper reports validation errors there |
