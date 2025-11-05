# Windscribe VPN Proxy (Docker + SwiftBar)

This repository provides a ready-to-run **Docker Compose configuration** that sets up a local **SOCKS5 proxy server** behind a secure **VPN connection via Windscribe**.
Optionally, a **SwiftBar plugin** is included for convenient control and monitoring directly from the macOS menu bar.

---

## 🧩 Overview

The setup consists of two Docker services:

1. **`windscribe-vpn`** — the VPN container based on [wiorca/docker-windscribe](https://hub.docker.com/r/wiorca/docker-windscribe).
   It manages the Windscribe connection and handles the firewall.

2. **`socks5-via-vpn`** — a lightweight SOCKS5 proxy container that shares the same network namespace as the VPN.
   Any traffic through this proxy is routed securely via Windscribe.

This configuration is useful when you need a **system-independent, containerized proxy** to route specific applications or development tools through a VPN — without installing a VPN client on the host.

---

## ⚙️ Quick start

### 1. Clone the repository

```bash
git clone https://github.com/<your-org-or-user>/<repo-name>.git
cd <repo-name>
```

### 2. Configure your Windscribe credentials

Copy the environment example file and fill in your own credentials:

```bash
cp .env.example .env
```

Then edit `.env`:

```bash
WINDSCRIBE_USERNAME=<your_windscribe_username>
WINDSCRIBE_PASSWORD=<your_windscribe_password>

# Optional customizations
PROXY_PORT=8888
PROXY_USER=proxyuser
PROXY_PASSWORD=proxypass
```

> ⚠️ Never commit your `.env` file to version control — it contains sensitive credentials.

---

### 3. Launch the proxy

Start the stack with Docker Compose:

```bash
docker compose up -d
```

After startup, your local SOCKS5 proxy will be available at:

```
socks5h://127.0.0.1:8888
```

You can test the connection:

```bash
curl -x socks5h://127.0.0.1:8888 https://ifconfig.me
```

The IP returned should differ from your host’s IP — indicating that traffic is going through the VPN.

---

### 4. Stop or remove the proxy

To stop the containers (keeping their state):

```bash
docker compose stop
```

To remove them completely:

```bash
docker compose down
```

---

## 💻 Optional: SwiftBar integration (macOS)

If you use macOS, the repository includes an optional **SwiftBar plugin** for convenient control of the proxy and VPN from the menu bar.

### Features

* Start / Stop / Restart the proxy stack.
* View live container logs in Terminal.
* Display direct and VPN IP addresses.
* Show your Windscribe account information.
* Cached network state to reduce traffic.

### Installation

1. **Install SwiftBar** (if not yet installed):

   ```bash
   brew install --cask swiftbar
   ```

2. **Run the setup script:**

   ```bash
   bash SwiftBar/install-swiftbar-plugin.sh
   ```

   This will:

   * Create a config file at `~/.config/swiftbar-vpn/config`
     with your project path (`COMPOSE_DIR`).
   * Symlink the plugin to the SwiftBar plugins folder.
   * Make it visible in the menu bar.

3. **Restart SwiftBar** (or choose *Refresh All* from its menu).

You should see a small indicator (🟢/🟡/🔴) showing the VPN status.

---

## 📂 Project structure

```
.
├── docker-compose.yml
├── .env.example
├── SwiftBar/
│   ├── plugin/
│   │   └── vpn-proxy.30s.sh       # SwiftBar plugin
│   └── install-swiftbar-plugin.sh # Setup script for macOS
└── README.md
```

---

## 🧠 Notes

* The proxy works independently of your system network — perfect for isolating network environments.
* You can use any app that supports SOCKS5 (browsers, terminals, IDEs, etc.).
* Logs and IP data are cached locally under `~/.cache/swiftbar-vpn/`.
* The plugin reads its settings from `~/.config/swiftbar-vpn/config`, which is created automatically during installation.

---

## 🛑 Security reminder

Keep your `.env` and `~/.config/swiftbar-vpn/config` private.
They contain your Windscribe credentials and paths on your system.
