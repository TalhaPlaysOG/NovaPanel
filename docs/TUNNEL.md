# Nova Panel Tunnel Access Guide

Nova Panel includes a modular tunneling subsystem designed for users hosting on home connections, behind CGNAT, or in firewalled environments without port-forwarding capabilities.

> [!IMPORTANT]
> **Strict Port Isolation**: Tunnel access is strictly for accessing the **Nova Panel web interface** (HTTP/HTTPS). It does **NOT** proxy, tunnel, or modify Minecraft or game server ports (e.g. `25565+`), nor does it alter Wings daemon ports (`8080`, `2022`). Game server traffic connects directly to your node's IP or allocation address.

---

## 1. Temporary Quick Tunnel (trycloudflare.com)

Temporary tunnels use Cloudflare's Quick Tunnel technology (`cloudflared tunnel --url http://127.0.0.1:80`).

### Features:
- **Instant Setup**: No domain, Cloudflare account, or credit card required.
- **Free TLS Encryption**: Automatically issued HTTPS edge certificate.
- **Systemd Managed**: Runs as a persistent background service (`nova-tunnel.service`).

### Limitations:
- The generated public URL (`https://random-words.trycloudflare.com`) may change if the tunnel service or server restarts.
- Intended for development, testing, or quick evaluation rather than public commercial hosting.

### Checking Tunnel URL:
```bash
sudo nova tunnel status
```

### Restarting / Refreshing:
```bash
sudo nova tunnel restart
```

---

## 2. Permanent Tunnel (Cloudflare Zero Trust / Named Tunnel)

For persistent, professional domain-based access without opening incoming firewall ports, use a Permanent Cloudflare Tunnel.

### Prerequisites:
1. A domain name added to a free Cloudflare account.
2. Access to **Cloudflare Zero Trust Dashboard** (`https://one.dash.cloudflare.com`).

### Fast setup with the menu (recommended)

```bash
sudo nova menu --tunnel
```

The menu performs Cloudflare's official APT installation:

```bash
sudo mkdir -p --mode=0755 /usr/share/keyrings
curl -fsSL https://pkg.cloudflare.com/cloudflare-main.gpg \
  | sudo tee /usr/share/keyrings/cloudflare-main.gpg >/dev/null

echo 'deb [signed-by=/usr/share/keyrings/cloudflare-main.gpg] https://pkg.cloudflare.com/cloudflared any main' \
  | sudo tee /etc/apt/sources.list.d/cloudflared.list

sudo apt-get update && sudo apt-get install -y cloudflared
```

It then prompts:

```
? Paste your Cloudflare Tunnel Token (input hidden):
```

Paste the token from step 3 below. The service is installed, enabled and
started automatically (`systemctl status cloudflared`). If you already created
the public hostname, the menu can also set `APP_URL` and `TRUSTED_PROXIES` for
you.

### Setup Steps:
1. Navigate to **Networks** -> **Tunnels** -> **Create a Tunnel**.
2. Select **Cloudflared** and name your tunnel (e.g. `nova-panel`).
3. Under "Install and run a connector", choose **Debian/Ubuntu** and copy the **Tunnel Token** string:
   ```
   eyJhIjoi...
   ```
4. In the **Public Hostnames** tab of Cloudflare, add a route:
   - **Subdomain**: `panel` (or whatever you prefer)
   - **Domain**: `yourdomain.com`
   - **Service Type**: `HTTP`
   - **URL**: `127.0.0.1:80` (or `localhost:80`)
5. During `nova install` (or when reconfiguring), choose **Option 3 -> Permanent Tunnel** and paste your token when prompted.

---

## 3. Tunnel CLI Commands

Nova Panel includes dedicated tunnel management commands:

| Command | Description |
| :--- | :--- |
| `nova tunnel status` | Displays active tunnel service state and current public URL |
| `nova tunnel restart` | Restarts the tunnel daemon and reconnects to Cloudflare edge |
| `nova tunnel disable` | Stops and permanently disables the background tunnel service |

---

## 4. Security Architecture

1. **Authentication Preserved**: Enabling a tunnel does **not** bypass or disable Nova Panel authentication, 2FA, or permission checks.
2. **CSRF Protection**: Laravel CSRF token verification remains active.
3. **Encrypted Egress**: The `cloudflared` client communicates over outbound TLS (port 7844 / 443) to Cloudflare's global edge network. No inbound router ports need to be forwarded.
4. **Credential Protection**: Tunnel tokens are stored with restricted `600` permissions in `/etc/nova-panel/tunnel.env`.
5. **No insecure-form warning**: Because Cloudflare terminates TLS at its edge, the panel is served to the browser over `https://`, so browsers no longer show the "information you're about to submit is not secure" interstitial. If the panel is exposed over plain HTTP, `panel/public/js/secure-forms.js` submits admin forms with `fetch()` so the warning does not interrupt normal operation.
