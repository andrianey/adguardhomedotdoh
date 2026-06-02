# AdGuard Home with DoH/DoT Support

### ℹ️ Since [cloudflared](https://developers.cloudflare.com/changelog/2025-11-11-cloudflared-proxy-dns/) `proxy-dns`  command is deprecated, Stubby & cloudflared are now replaced with dnsproxy ℹ️

![Tech Logo](https://raw.githubusercontent.com/andrianey/adguardhomedotdoh/refs/heads/latest/tech-logo.png)

This project provides a custom Docker image for [AdGuard Home](https://github.com/AdguardTeam/AdGuardHome) pre-configured with **Unbound** (as a recursive DNS resolver) with Valkey in-memory cache (Redis replacement), and **dnsproxy** (for unified DoH/DoT upstream handling).

[GitHub](https://github.com/andrianey/adguardhomedotdoh) · [Docker Hub](https://hub.docker.com/r/andrianey/adguardhomedotdoh)

[![Docker Pulls (realtime)](https://img.shields.io/badge/dynamic/json?url=https%3A%2F%2Fhub.docker.com%2Fv2%2Frepositories%2Fandrianey%2Fadguardhomedotdoh&query=%24.pull_count&label=docker%20pulls&logo=docker&logoColor=white&color=0077CC&cacheSeconds=300)](https://hub.docker.com/r/andrianey/adguardhomedotdoh)

![dns-test](https://raw.githubusercontent.com/andrianey/adguardhomedotdoh/refs/heads/latest/dns-test.jpg)

---

## Available Image Tags


<!-- VERSIONS_TABLE_START -->
| Tag | AdGuardHome | Unbound | dnsproxy | Image Size | Description |
| :--- | :---: | :--- | :--- | :--- | :--- |
| `latest` | ![v0.107.77](https://img.shields.io/badge/-v0.107.77-6ABF4B) | ![1.25.1](https://img.shields.io/badge/-1.25.1-0077CC) | ![v0.81.4](https://img.shields.io/badge/-v0.81.4-6ABF4B) |      [![Image Size](https://img.shields.io/docker/image-size/andrianey/adguardhomedotdoh/latest?style=flat-square&logo=docker&logoColor=%23ffffff&label=%20)](https://hub.docker.com/layers/andrianey/adguardhomedotdoh/latest) |      Standard security level. Image running on Alpine Linux as root. Lightweight and stable. |
| `latest-wolfi` | ![v0.107.76](https://img.shields.io/badge/-v0.107.76-6ABF4B) | ![1.25.1](https://img.shields.io/badge/-1.25.1-0077CC) | ![v0.81.4](https://img.shields.io/badge/-v0.81.4-6ABF4B) |     [![Image Size](https://img.shields.io/docker/image-size/andrianey/adguardhomedotdoh/latest-wolfi?style=flat-square&logo=docker&logoColor=%23ffffff&label=%20)](https://hub.docker.com/layers/andrianey/adguardhomedotdoh/latest-wolfi) |     Enhanced security level. Built with [Wolfi](https://github.com/wolfi-dev) for a distroless image. |
| `hardened` | ![v0.108.0-a.1309+d4dbf9ce](https://img.shields.io/badge/-v0.108.0--a.1309+d4dbf9ce-6ABF4B) | ![1.25.1](https://img.shields.io/badge/-1.25.1-0077CC) | ![v0.81.4-dirty](https://img.shields.io/badge/-v0.81.4--dirty-6ABF4B) |           [![Image Size](https://img.shields.io/docker/image-size/andrianey/adguardhomedotdoh/hardened?style=flat-square&logo=docker&logoColor=%23ffffff&label=%20)](https://hub.docker.com/layers/andrianey/adguardhomedotdoh/hardened) |        High security level. **Non-Root execution** on Alpine Linux. Runs as `adguard` user with `libcap` capabilities built from source for fewer CVEs. |
| `hardened-wolfi` | ![v0.108.0-a.1309+d4dbf9ce](https://img.shields.io/badge/-v0.108.0--a.1309+d4dbf9ce-6ABF4B) | ![1.25.1](https://img.shields.io/badge/-1.25.1-0077CC) | ![v0.81.4-dirty](https://img.shields.io/badge/-v0.81.4--dirty-6ABF4B) |             [![Image Size](https://img.shields.io/docker/image-size/andrianey/adguardhomedotdoh/hardened-wolfi?style=flat-square&logo=docker&logoColor=%23ffffff&label=%20)](https://hub.docker.com/layers/andrianey/adguardhomedotdoh/hardened-wolfi) |           Maximum security level. Wolfi base + Non-Root execution built from source for fewer CVEs. |
<!-- VERSIONS_TABLE_END -->

---

## Quick Start (Hardened Images)

The `hardened` and `hardened-wolfi` images use a **Hybrid Setup Mode** unless you bind an existing AdGuardHome configuration.

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
      # Optional: Custom DNS Proxy Settings
      # - DNSPROXY_UPSTREAM=tls://1.1.1.1 tls://1.0.0.1 https://1.1.1.1/dns-query https://1.0.0.1/dns-query tls://[2606:4700:4700::1111] tls://[2606:4700:4700::1001] https://[2606:4700:4700::1111]/dns-query https://[2606:4700:4700::1001]/dns-query tls://9.9.9.9 tls://149.112.112.112 tls://[2620:fe::fe] tls://[2620:fe::9] https://dns9.quad9.net/dns-query
      # - DNSPROXY_FLAGS=--upstream-mode=parallel --cache --cache-optimistic --cache-size=4194304 --cache-min-ttl=600
      
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

      # Mount custom SSL certificates to enable encryption
      # - /opt/adguardhome/certs:/opt/certs
      
      # Optional: Custom Config Overrides
      # - /opt/adguardhome/unbound/unbound.conf:/etc/unbound/unbound.conf

networks:
  adguard_net:
    driver: bridge
    ipam:
      config:
        - subnet: 172.172.0.0/24
```

---

## Environment Variables

You can customize the `dnsproxy` configuration using environment variables in your `docker-compose.yml`:

| Variable | Default | Description |
| :--- | :--- | :--- |
| `DNSPROXY_UPSTREAM` | Cloudflare DoT/DoH | Space-separated list of upstream servers (e.g., `tls://1.1.1.1 https://1.1.1.1/dns-query`). |
| `DNSPROXY_FLAGS` | `--verbose` | Additional flags for dnsproxy (e.g., `--cache-optimistic`). |

---

## Internal Components
The image comes pre-configured with the following services running internally:

| Component | Internal Port | Description |
| :--- | :--- | :--- |
| **Unbound** | `127.0.0.1:5335` | Recursive resolver with DNSSEC validation + Valkey Cache. |
| **dnsproxy** | `127.0.0.1:8053` | Upstream DoH/DoT proxy (replaces Stubby/Cloudflared). |

## Configuration

### AdGuard Home Upstream DNS
The architecture is designed to chain requests:
`Client -> AdGuard Home -> Unbound -> Valkey Cache -> dnsproxy -> Configured upstreams (DoH, DoT, DoQ and DNSCrypt support)`

Configure **Settings -> DNS settings** with:

1.  **Upstream DNS servers**:
    ```
    127.0.0.1:5335
    ```


2.  **Verify**:
    *   Click "Test upstreams" to ensure connectivity.
    *   **Cache size**: You may set this to `0` in AdGuard Home to rely on Unbound's efficient caching paired with Valkey.

---

## Hardening features
The `hardened` tags implement best practices for container security:
*   **Non-Root User**: Runs as a dedicated `adguard` user (UID 1000).
*   **Capabilities**: Uses `libcap` to bind to privileged ports (53, 80) without full root access.
*   **Minimal Base**: Wolfi edition offers a software supply chain secure base image.
*   **Permission Fixer**: The entrypoint automatically corrects permissions on mounted volumes.

**Note**: Since the process runs as UID 1000, ensure your host volumes are writable by this user or let Docker automatically handle the ownership (which the entrypoint facilitates).
