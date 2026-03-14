# AdGuard Home with DoH/DoT Support

This project provides a custom Docker image for [AdGuard Home](https://github.com/AdguardTeam/AdGuardHome) pre-configured with **Unbound** (as a recursive DNS resolver with DNSSEC), **dnsproxy** (for DNS-over-TLS and DNS-over-HTTPS), and **Valkey** (Redis-compatible cache for Unbound).

[GitHub](https://github.com/andrianey/adguardhomedotdoh)

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
| **Unbound** | `127.0.0.1:5335` | Recursive resolver with DNSSEC validation and Valkey caching. |
| **dnsproxy** | `127.0.0.1:8053` | DNS-over-TLS and DNS-over-HTTPS upstream resolver. |
| **Valkey** | Unix Socket | Redis-compatible cache backend for Unbound. |

## Configuration

### AdGuard Home Upstream DNS
When configuring AdGuard Home via the web UI (**Settings -> DNS settings**), use these Local Upstreams to leverage the embedded services:

1.  **Upstream DNS servers** & **Bootstrap DNS servers**:
    ```
    # Unbound (Recursive + DNSSEC + Valkey Cache)
    127.0.0.1:5335
    ```

2.  **Settings**:
    *   **Cache size**: `0` (Let Unbound handle caching with Valkey backend).
    *   Unbound forwards to dnsproxy (127.0.0.1:8053) which handles DoH/DoT to upstream providers.

3.  **Customizing dnsproxy Upstreams**:
    Set the `DNSPROXY_UPSTREAM` environment variable to use different providers:
    ```yaml
    environment:
      - DNSPROXY_UPSTREAM=tls://9.9.9.9 tls://149.112.112.112  # Quad9
    ```

---

## Hardening features
The `hardened` tags implement best practices for container security:
*   **Non-Root User**: Runs as a dedicated `adguard` user (UID 1000).
*   **Capabilities**: Uses `libcap` to bind to privileged ports (53, 80) without full root access.
*   **Minimal Base**: Wolfi edition offers a software supply chain secure base image.
*   **Permission Fixer**: The entrypoint automatically corrects permissions on mounted volumes.

**Note**: Since the process runs as UID 1000, ensure your host volumes are writable by this user or let Docker automatically handle the ownership (which the entrypoint facilitates).
