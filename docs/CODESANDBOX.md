# CodeSandbox & Development Environment Guide

Nova Panel provides automated support for **CodeSandbox Devbox / VM environments** with ~8 GiB RAM and rootless container tooling.

---

## 1. Development Mode vs Production VPS Mode

Nova Panel's installer automatically detects whether it is running inside CodeSandbox or a standard Linux VPS:

| Feature | Development / CodeSandbox Mode | Production VPS Mode |
| :--- | :--- | :--- |
| **Target Environment** | CodeSandbox Devbox, local dev containers | Ubuntu 20.04/22.04/24.04 LTS, Debian |
| **Permissions** | Rootless (no `sudo` required) | Root / sudo required |
| **Web Server** | PHP built-in server (`0.0.0.0:8000`) | Nginx + PHP 8.2 FastCGI |
| **Database** | SQLite zero-config (`database.sqlite`) | MariaDB 10.5+ / MySQL 8.0 |
| **Cache & Queue** | File cache / synchronous queue | Redis 6/7 & background `pteroq` worker |
| **Port Access** | CodeSandbox automated HTTPS forwarded preview | Port 80/443 direct, domain SSL, or tunnel |
| **Wings / Docker** | **Panel-Only Testing** (Virtualization disabled) | Full Wings daemon & Docker engine |

---

## 2. Quick Setup in CodeSandbox

When opening the repository in CodeSandbox:

1. **Automatic Initialization**:
   - The `.codesandbox/tasks.json` configuration will automatically run `bash install.sh --dev`.
2. **Interactive Prompts**:
   - Enter your preferred administrator email, username, and password.
3. **Automatic Port Preview**:
   - The development server will bind to `0.0.0.0:8000`.
   - CodeSandbox will detect port 8000 and display the live HTTPS preview URL (`https://...-8000.csb.app`).
4. **Log In**:
   - Use the administrator credentials configured during setup to log into the Nova Panel dashboard.

---

## 3. Manual Installation inside CodeSandbox Terminal

To run the installation manually inside CodeSandbox:

```bash
bash install.sh --dev
```

To start or stop the background server:
```bash
nova start
nova stop
```

To tail application logs:
```bash
nova logs panel
```

---

## 4. Environment Limitations in CodeSandbox

> [!NOTE]
> **Why is Wings disabled in CodeSandbox?**
> The Wings daemon requires:
> 1. Unrestricted root privileges.
> 2. Linux kernel cgroup v1/v2 control for CPU, memory, and blkio limits.
> 3. Direct access to `/var/run/docker.sock`.
>
> In CodeSandbox and nested non-root cloud containers, full kernel virtualization is unavailable. Therefore, Nova Panel operates in **Panel-Only Development Mode**. You can fully test:
> - User authentication, roles, and subusers.
> - Administrative settings, locations, and node configurations.
> - Egg parsing, Docker image definitions, and startup variable templates.
> - Client and Application REST APIs.
>
> To test live Minecraft server execution and container power controls, deploy to a **Production Linux VPS** using `bash install.sh --prod`.
