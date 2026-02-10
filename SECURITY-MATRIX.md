# 🔐 AdGuard Home Multi-Branch Security Matrix

**Build Date**: 2026-02-10  
**Repository**: andrianey/adguardhomedotdoh

## 📊 Branch Overview

| Branch | Base Image | User | Upstream DNS | Security Level | Status |
|--------|------------|------|--------------|----------------|--------|
| **`latest`** | Alpine 3.23 | Root | Stubby + Cloudflared | ⭐ Standard | ✅ **Verified** |
| **`latest-wolfi`** | Wolfi OS | Root | Stubby + Cloudflared | ⭐⭐ Enhanced | ✅ **Verified** |
| **`hardened`** | Alpine 3.23 | adguard | Stubby + Cloudflared | ⭐⭐⭐ High | ✅ **Verified** |
| **`hardened-wolfi`** | Wolfi OS | adguard | **dnsproxy** (New!) | ⭐⭐⭐⭐ Maximum | ✅ **Verified** |

---

## 🔍 Detailed Branch Comparison

### 1. `latest` - Alpine Root (Standard Security)

**Tag**: `andrianey/adguardhomedotdoh:latest`

**Configuration**:
```yaml
Base: Alpine Linux 3.23
User: root
Upstreams: Stubby (DoT) + Cloudflared (DoH)
Unbound: Custom build (with Valkey cachedb)
Valkey: ✅ Enabled  
Paths: /var/lib/unbound/
```

**Services**:
- ✅ Valkey (Unix Socket)
- ✅ Unbound (Port 5335)
- ✅ Cloudflared (Port 5053)
- ✅ Stubby (Port 8053)
- ✅ AdGuard Home (Port 53, 3000)

**Best For**:
- Simple deployments
- Development/testing

---

### 2. `latest-wolfi` - Wolfi Root (Enhanced Security)

**Tag**: `andrianey/adguardhomedotdoh:latest-wolfi`

**Configuration**:
```yaml
Base: Wolfi OS (Chainguard)
User: root
Upstreams: Stubby + Cloudflared (Built from source)
Unbound: Built from source on Wolfi
Valkey: ✅ Enabled
Paths: /var/lib/unbound/
```

**Services**:
- ✅ Valkey (Unix Socket)
- ✅ Unbound (Port 5335)
- ✅ Cloudflared (Port 5053)
- ✅ Stubby (Port 8053)
- ✅ AdGuard Home (Port 53, 3000)

**Best For**:
- Production with CVE concerns
- Root execution acceptable

---

### 3. `hardened` - Alpine Non-Root (High Security)

**Tag**: `andrianey/adguardhomedotdoh:hardened`

**Configuration**:
```yaml
Base: Alpine Edge
User: adguard (UID 1000)
Upstreams: Stubby + Cloudflared
Privilege Drop: su-exec
Capabilities: CAP_NET_BIND_SERVICE
Paths: /var/lib/unbound/
```

**Services** (Run as `adguard`):
- ✅ Valkey
- ✅ Unbound (Port 5335)
- ✅ Cloudflared (Port 5053)
- ✅ Stubby (Port 8053)
- ✅ AdGuard Home

**Best For**:
- Production environments
- Non-root requirement

---

### 4. `hardened-wolfi` - Wolfi Non-Root (Maximum Security) 🏆

**Tag**: `andrianey/adguardhomedotdoh:hardened-wolfi`

**Configuration**:
```yaml
Base: Wolfi OS (Chainguard)
User: adguard (UID 1000)
Upstream: **dnsproxy** (Built from source)
Unbound: Built from source (Debian builder)
Valkey: ✅ Enabled
AdGuard Home: **Edge/Nightly** (Latest fixes)
Privilege Drop: su-exec
Capabilities: CAP_NET_BIND_SERVICE
Paths: /var/lib/unbound/
```

**Services** (All run as `adguard`):
- ✅ Valkey (Unix Socket)
- ✅ Unbound (Port 5335) → Forwards to dnsproxy
- ✅ **dnsproxy** (Port 8053) → Handles DoT/DoH to Cloudflare
- ✅ AdGuard Home (Port 53, 3000)

**🛡️ CVE Remediation (Feb 2026)**:
- **Go Stdlib CVEs (CVE-2025-61726/61728/61730/68121)**: Fixed by building `dnsproxy` from source using `golang:alpine` (Go 1.25.7+).
- **quic-go CVE (CVE-2025-64702)**: Fixed by forcing update to `quic-go` v0.59.0+ during build.
- **AdGuard Home CVE (CVE-2022-32175)**: Fixed by using `adguard/adguardhome:edge` (Nightly build).

**Why dnsproxy?**
- Single binary handles both DoH and DoT
- Faster, lighter, and more robust
- Simpler configuration than managing two separate proxies
- Native support for multiple upstreams (QUIC, HTTP/3, etc.)

**Best For**:
- **Maximum security production deployments** ⭐
- Minimal footprint
- High performance
- **Zero-CVE compliance**

---

## 🎯 DNS Resolution Flow (`hardened-wolfi`)

```
Client Query
    ↓
AdGuard Home (Port 53)
    ↓
Unbound (Port 5335)
    ↓
Valkey Cache Check
    ↓ (if miss)
dnsproxy (Port 8053)
    ↓
Cloudflare DNS (1.1.1.1)
(via DoH or DoT with fallback)
```

## ⚙️ Common Configuration

### AdGuard Home Upstream DNS Setting:
For all branches, configure AdGuard Home to use:
```
127.0.0.1:5335
```

This routes through Unbound → Valkey cache → Upstream Proxy.

---

## 🔧 Build Commands

### Hardened-Wolfi (Wolfi Non-Root) - RECOMMENDED
```bash
git checkout hardened-wolfi
docker buildx build --platform linux/amd64 \
  -t andrianey/adguardhomedotdoh:hardened-wolfi --load .
```

---

## 📦 Deployment Example

### Docker Run
```bash
docker run -d \
  --name adguardhome \
  -p 53:53/tcp -p 53:53/udp \
  -p 80:80/tcp \
  -p 443:443/tcp \
  -p 3000:3000/tcp \
  -v ./adguard-conf:/opt/adguardhome/conf \
  -v ./adguard-work:/opt/adguardhome/work \
  andrianey/adguardhomedotdoh:hardened-wolfi
```

---

**Last Updated**: 2026-02-10  
**All Branches Verified**: ✅
