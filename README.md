# AdGuard Home with DoH/DoT Support

This project provides a custom Docker image for [AdGuard Home](https://github.com/AdguardTeam/AdGuardHome) pre-configured with **Unbound** (as a recursive DNS resolver), **dnsproxy** / **Stubby** (for DoT/DoH), and optional **Cloudflared** support.

[GitHub](https://github.com/andrianey/adguardhomedotdoh) · [Docker Hub](https://hub.docker.com/r/andrianey/adguardhomedotdoh)

---

## 🚦 Build Status

| Branch | Pipeline Status |
| :--- | :--- |
| `latest` | [![latest](https://gitlab.com/andrianey/adguardhomedotdoh/badges/latest/pipeline.svg)](https://gitlab.com/andrianey/adguardhomedotdoh/-/pipelines?ref=latest) |
| `latest-wolfi` | [![latest-wolfi](https://gitlab.com/andrianey/adguardhomedotdoh/badges/latest-wolfi/pipeline.svg)](https://gitlab.com/andrianey/adguardhomedotdoh/-/pipelines?ref=latest-wolfi) |
| `hardened` | [![hardened](https://gitlab.com/andrianey/adguardhomedotdoh/badges/hardened/pipeline.svg)](https://gitlab.com/andrianey/adguardhomedotdoh/-/pipelines?ref=hardened) |
| `hardened-wolfi` | [![hardened-wolfi](https://gitlab.com/andrianey/adguardhomedotdoh/badges/hardened-wolfi/pipeline.svg)](https://gitlab.com/andrianey/adguardhomedotdoh/-/pipelines?ref=hardened-wolfi) |

---

## 📦 Component Versions by Image Tag

> 🤖 **Auto-updated by CI** after each successful build. Shows the exact versions compiled/installed in each image.
> `📦 pkg` = installed from OS package repository &nbsp;·&nbsp; `🔨 src` = compiled from source at build time

<!-- VERSIONS_TABLE_START -->
| Tag | AdGuardHome | Unbound | dnsproxy | How Built | Last Built (UTC) |
| :--- | :--- | :--- | :--- | :--- | :--- |
| `latest` | `—` | `—` | `—` | 📦 pkg | `—` |
| `latest-wolfi` | `—` | `—` | `—` | 📦 pkg | `—` |
| `hardened` | `—` | `—` | `—` | 🔨 src | `—` |
| `hardened-wolfi` | `—` | `—` | `—` | 🔨 src | `—` |
<!-- VERSIONS_TABLE_END -->

> 💡 To verify the exact versions baked into any pulled image run:
> ```bash
> docker inspect andrianey/adguardhomedotdoh:<tag> \
>   --format '{{ range $k,$v := .Config.Labels }}{{ $k }}={{ $v }}{{ "\n" }}{{ end }}' \
>   | grep -E 'adguardhome|dnsproxy|unbound'
> ```

---

![Cloudflare-Test](https://raw.githubusercontent.com/andrianey/adguardhomedotdoh/7141b52e7e17ed0264a5a639a610ecd97dccc54e/cloudflare-dns.jpg)

## Available Image Tags

| Tag | Base Image | Security Level | Description |
| :--- | :--- | :--- | :--- |
| `latest` | Alpine Linux | Standard | Standard image running as root. Lightweight and stable. |
| `latest-wolfi` | Wolfi OS | Enhanced | Built with [Wolfi](https://github.com/wolfi-dev) for fewer vulnerabilities. |
| `hardened` | Alpine Linux | **High** | **Non-Root execution**. Runs as `adguard` user with `libcap` capabilities. |
| `hardened-wolfi` | Wolfi OS | **Maximum** | Wolfi base + Non-Root execution for maximum security hardening. |

---

## Quick Start (Hardened Images)

The `hardened` and `hardened-wolfi` images use a **Hybrid Setup Mode** unless you bind the existing AdGuardHome configuration.

1.  **First Run**: The container starts as **Root** to allow you to complete the AdGuard Home "Get Started" wizard (which requires root).
2.  **Setup**: Access `http://localhost:3000` and finish the setup.
3.  **Restart**: **You MUST restart the container** after setup.
4.  **Runtime**: On the second boot, it automatically drops privileges and runs as the **non-root `adguard` user**.
---
### Docker Compose

```yaml
services:
  adguardhome:
    # Choose your preferred tag: 'latest', 'latest-wolfi', 'hardened', or 'hardened-wolfi'
    image: andrianey/adguardhomedotdoh:latest
    container_name: adguardhome
    hostname: adguardhome
    restart: unless-stopped
    
    networks:
      adguard_net:
        ipv4_address: 172.172.0.2
    
    environment:
      - TZ=Asia/Jakarta # Set your timezone
      - PUID=1000       # User ID for file ownership
      - PGID=1000       # Group ID for file ownership
    
    ports:
      # DNS
      - "53:53/tcp"
      - "53:53/udp"
      - "853:853/tcp"
      - "853:853/udp"
      # Web & DoH
      - "80:80/tcp"
      - "443:443/tcp"
      - "443:443/udp"
      - "3000:3000/tcp"
      # DHCP
      - "67:67/udp"
      - "68:68/udp"
    
    volumes:
      # Core AdGuard Home Data for persistent configuration
      - /opt/adguardhome/conf:/opt/adguardhome/conf
      - /opt/adguardhome/work:/opt/adguardhome/work

      # Mount custom SSL certificates resolve over public address https://localhost/dns-query
      # - /opt/adguardhome/certs:/opt/certs
      
      # Optional: Custom Config Overrides
      # Only mount these if you have custom config files you want to inject
      # - /opt/adguardhome/stubby/stubby.yml:/etc/stubby/stubby.yml:ro
      # - /opt/adguardhome/unbound/unbound.conf:/etc/unbound/unbound.conf:ro

networks:
  adguard_net:
    driver: bridge
    ipam:
      config:
        - subnet: 172.172.0.0/24
```

---

## Internal Components
The image comes pre-configured with the following services running internally:

| Component | Internal Port | Description |
| :--- | :--- | :--- |
| **Unbound** | `127.0.0.1:53` | Recursive resolver with DNSSEC validation. |
| **Stubby** | `127.0.0.1:8053` | DNS-over-TLS resolver. |
| **Cloudflared** | `127.0.0.1:5053` | DNS-over-HTTPS tunnel. |

## Configuration

### AdGuard Home Upstream DNS
When configuring AdGuard Home via the web UI (**Settings -> DNS settings**), use these Local Upstreams to leverage the embedded services:

1.  **Upstream DNS servers** & **Bootstrap DNS servers**:
    ```
    # Unbound (Recursive + DNSSEC)
    127.0.0.1:53
    
    # Cloudflared (DoH)
    127.0.0.1:5053
    
    # Stubby (DoT)
    127.0.0.1:8053
    ```

2.  **Settings**:
    *   Check **"Parallel requests"** (Query all upstreams simultaneously).
    *   **Cache size**: `0` (Let Unbound/Stubby handle caching, or set low if preferred).

---

## Hardening features
The `hardened` tags implement best practices for container security:
*   **Non-Root User**: Runs as a dedicated `adguard` user (UID 1000).
*   **Capabilities**: Uses `libcap` to bind to privileged ports (53, 80) without full root access.
*   **Minimal Base**: Wolfi edition offers a software supply chain secure base image.
*   **Permission Fixer**: The entrypoint automatically corrects permissions on mounted volumes.

**Note**: Since the process runs as UID 1000, ensure your host volumes are writable by this user or let Docker automatically handle the ownership (which the entrypoint facilitates).
