# AdGuardHome DoH/DoT - Wolfi Edition 🐺

## 💻 Introduction

AdGuardHome Docker image with **DoH** (DNS over HTTPS) and **DoT** (DNS over TLS) clients, built on [Wolfi](https://wolfi.dev/) - a lightweight, secure-by-default Linux distribution designed for containers.

### Why Wolfi?

- **Security-focused**: Minimal attack surface with distroless-like images
- **No CVEs**: Built with the latest packages to minimize vulnerabilities
- **Small footprint**: Lighter than traditional base images
- **SBOM support**: Full Software Bill of Materials for supply chain security

### Components

| Component | Purpose | Port |
|-----------|---------|------|
| **AdGuard Home** | DNS server with ad-blocking | 53, 3000 (admin) |
| **Unbound** | Recursive DNS resolver with DNSSEC | 5335 |
| **Cloudflared** | DNS-over-HTTPS tunnel | 5053 |
| **Stubby** | DNS-over-TLS resolver | 8053 |

## 🏗️ Architecture

```
                    ┌─────────────────────────────────────────────────────┐
                    │              Wolfi Container                        │
                    │                                                     │
   Client DNS ──────┼──► AdGuard Home (:53) ──► Unbound (:5335)          │
   Requests         │         │                    │                      │
                    │         │                    ├──► Cloudflared (:5053) ──► 1.1.1.1 (DoH)
                    │         │                    │                      │
                    │         │                    └──► Stubby (:8053) ────► 1.1.1.1 (DoT)
                    │         │                                           │
                    │         └──► Admin Panel (:3000)                   │
                    └─────────────────────────────────────────────────────┘
```

## 🚀 Quick Start

### Build and Run

```bash
# Clone the repository
git clone https://github.com/yourusername/adguardhome-doh-dot-wolfi.git
cd adguardhome-doh-dot-wolfi

# Build and run with Docker Compose
docker compose up -d

# Or build manually
docker build -t adguardhome-wolfi .
docker run -d --name adguardhome \
  -p 53:53/tcp -p 53:53/udp \
  -p 3000:3000 \
  -v ./adguardhome/conf:/opt/adguardhome/conf \
  -v ./adguardhome/work:/opt/adguardhome/work \
  adguardhome-wolfi
```

### Initial Setup

1. Access the AdGuard Home admin panel: `http://localhost:3000`
2. Complete the setup wizard
3. Configure DNS settings (see below)

## 📝 Configuration

### Docker Compose

Edit `docker-compose.yml` to customize:

```yaml
version: "3.8"

services:
  adguardhome:
    build: .
    image: adguardhome-doh-dot-wolfi:latest
    container_name: adguardhome
    environment:
      - TZ=Asia/Jakarta  # Your timezone
    volumes:
      - ./adguardhome/conf:/opt/adguardhome/conf
      - ./adguardhome/work:/opt/adguardhome/work
    ports:
      - "53:53/tcp"
      - "53:53/udp"
      - "853:853/tcp"      # DNS-over-TLS
      - "443:443/tcp"      # DNS-over-HTTPS
      - "3000:3000/tcp"    # Admin Panel
    restart: unless-stopped
```

### AdGuard Home DNS Settings

In the AdGuard Home admin panel, go to **Settings → DNS settings**:

**Upstream DNS servers:**
```
# Unbound (local recursive resolver with DNSSEC)
127.0.0.1:5335

# Cloudflared (DNS-over-HTTPS to Cloudflare)
127.0.0.1:5053

# Stubby (DNS-over-TLS to Cloudflare)
127.0.0.1:8053
```

**Bootstrap DNS servers:**
```
1.1.1.1
1.0.0.1
```

**Recommended settings:**
- ✅ Enable "Parallel requests" - uses all upstream servers simultaneously
- Set DNS cache size to **0** (Unbound handles caching)
- Set Query logs retention to **24 hours**

### Macvlan Network (Optional)

For advanced networking with a dedicated IP:

```yaml
services:
  adguardhome:
    networks:
      macvlan0:
        ipv4_address: 192.168.1.110

networks:
  macvlan0:
    driver: macvlan
    driver_opts:
      parent: eth0
    ipam:
      config:
        - subnet: 192.168.1.0/24
          gateway: 192.168.1.1
          ip_range: 192.168.1.100/28
```

## 🔧 Port Reference

| Port | Protocol | Service |
|------|----------|---------|
| 53 | TCP/UDP | DNS |
| 853 | TCP | DNS-over-TLS |
| 443 | TCP | DNS-over-HTTPS |
| 784 | UDP | DNS-over-QUIC |
| 8853 | UDP | DNS-over-QUIC |
| 3000 | TCP | AdGuard Home Admin |
| 5053 | TCP | Cloudflared (internal) |
| 5335 | TCP | Unbound (internal) |
| 8053 | TCP | Stubby (internal) |

## 🔒 Security Features

### Wolfi Base Image
- Minimal base image from Chainguard
- Regular security updates
- SBOM (Software Bill of Materials) available
- No shell by default (added for compatibility)

### Multi-stage Build
- Build dependencies not included in final image
- Smaller attack surface
- Reduced image size

### Container Hardening
```yaml
security_opt:
  - no-new-privileges:true
```

## 📊 Comparison: Alpine vs Wolfi

| Feature | Alpine | Wolfi |
|---------|--------|-------|
| Base Size | ~5MB | ~12MB |
| Package Manager | apk | apk |
| SBOM Support | Limited | Full |
| CVE Policy | Reactive | Proactive |
| Init System | OpenRC | Distroless-like |

## 🛠️ Troubleshooting

### Check Services Status
```bash
docker exec adguardhome ps aux
docker logs adguardhome
```

### Test DNS Resolution
```bash
# Test Unbound
docker exec adguardhome dig @127.0.0.1 -p 5335 google.com

# Test Cloudflared
docker exec adguardhome dig @127.0.0.1 -p 5053 google.com

# Test Stubby
docker exec adguardhome dig @127.0.0.1 -p 8053 google.com
```

### Common Issues

1. **Port 53 already in use**: Stop systemd-resolved or other DNS services
   ```bash
   sudo systemctl stop systemd-resolved
   ```

2. **Permission denied on /opt/adguardhome/work**: The entrypoint automatically fixes this

3. **Stubby fails to start**: Check LD_LIBRARY_PATH is set correctly

## 📫 Credits

- [Wolfi](https://wolfi.dev/) - Secure container base image
- [Chainguard](https://chainguard.dev/) - Wolfi maintainers
- [AdGuard Home](https://github.com/AdguardTeam/AdGuardHome)
- [Unbound](https://nlnetlabs.nl/projects/unbound/)
- [Cloudflared](https://developers.cloudflare.com/cloudflare-one/connections/connect-apps/)
- [Stubby](https://github.com/getdnsapi/stubby)
- Original Alpine version by [oijkn](https://github.com/oijkn/adguardhome-doh-dot)

## 📜 License

This project is licensed under the GPL-3.0 License - see the [LICENSE](LICENSE) file for details.

## ✍️ Feedback

If you have any problems or questions, please open a [GitHub issue](https://github.com/yourusername/adguardhome-doh-dot-wolfi/issues).