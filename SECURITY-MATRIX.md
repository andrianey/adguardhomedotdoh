# 🔐 AdGuard Home Multi-Branch Security Matrix

**Build Date**: 2026-02-10  
**Repository**: andrianey/adguardhomedotdoh

## 📊 Branch Overview

| Branch | Base Image | User | Upstream | Security Level | Status |
|--------|------------|------|----------|----------------|--------|
| **`latest`** | Alpine 3.23 | Root | **dnsproxy** (Release) | ⭐ Standard | ✅ **Migrated** |
| **`latest-wolfi`** | Wolfi OS | Root | **dnsproxy** (Release) | ⭐⭐ Enhanced (Wolfi) | ✅ **Migrated** |
| **`hardened`** | Alpine Edge | adguard | Stubby + Cloudflared | ⭐⭐⭐ High | ⏳ Pending? |
| **`hardened-wolfi`** | Wolfi OS | adguard | **dnsproxy** (Source) | ⭐⭐⭐⭐ Maximum | ✅ **Zero CVE** |

---

## 🔍 Detailed Branch Comparison

### 1. `latest` - Alpine Root (Standard)

**Tag**: `andrianey/adguardhomedotdoh:latest`

**Configuration**:
```yaml
Base: Alpine Linux 3.23
User: root
AdGuard Home: Stable (Latest Release)
Upstream: dnsproxy (Latest Release)
Unbound: Custom Build (Alpine)
Valkey: ✅ Enabled
CVE Status: Expected (Standard binaries)
```
**Architecture**: Replaces Stubby+Cloudflared with single `dnsproxy` binary for simpler management.

---

### 2. `latest-wolfi` - Wolfi Root (Enhanced)

**Tag**: `andrianey/adguardhomedotdoh:latest-wolfi`

**Configuration**:
```yaml
Base: Wolfi OS (Chainguard)
User: root
AdGuard Home: Stable (Latest Release)
Upstream: dnsproxy (Latest Release)
Unbound: Custom Build (Debian Builder -> Wolfi compatible)
Valkey: ✅ Enabled
CVE Status: Reduced (Wolfi base), but standard app binaries used.
```
**Architecture**: Same simple `dnsproxy` architecture as `latest`, but on secure Wolfi base.

---

### 3. `hardened` - Alpine Non-Root (Legacy High Security)

**Tag**: `andrianey/adguardhomedotdoh:hardened`

**Configuration**:
```yaml
Base: Alpine Edge
User: adguard (UID 1000)
Upstream: Stubby + Cloudflared
Privilege Drop: su-exec
Capabilities: CAP_NET_BIND_SERVICE
```
*(Currently maintains the classic dual-proxy architecture)*

---

### 4. `hardened-wolfi` - Wolfi Non-Root (Maximum Security) 🏆

**Tag**: `andrianey/adguardhomedotdoh:hardened-wolfi`

**Configuration**:
```yaml
Base: Wolfi OS (Chainguard)
User: adguard (UID 1000)
AdGuard Home: **Edge/Nightly** (Fixes CVE-2022-32175)
Upstream: **dnsproxy** (Built from Source/Go 1.25.7)
Unbound: Built from source (Debian builder)
Valkey: ✅ Enabled
Privilege Drop: su-exec
CVE Status: **Fully Patched (Zero CVE target)**
```

**🛡️ CVE Remediation**:
- **Go Stdlib/quic-go**: Fixed by compiling `dnsproxy` from source with latest Go and deps.
- **AdGuard Home**: Fixed by using Edge builds.

---

## 🎯 DNS Resolution Flow (New Architecture)

For `latest`, `latest-wolfi`, and `hardened-wolfi`:

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
(Handles DoH and DoT concurrently)
```

## ⚙️ Common Configuration

### AdGuard Home Upstream DNS Setting:
For all branches, configure AdGuard Home to use:
```
127.0.0.1:5335
```

---

## 🔧 Build Commands

### Latest (Alpine Root)
```bash
git checkout latest
docker buildx build --platform linux/amd64 \
  -t andrianey/adguardhomedotdoh:latest --load .
```

### Latest-Wolfi (Wolfi Root)
```bash
git checkout latest-wolfi
docker buildx build --platform linux/amd64 \
  -t andrianey/adguardhomedotdoh:latest-wolfi --load .
```

### Hardened-Wolfi (Wolfi Non-Root) - RECOMMENDED
```bash
git checkout hardened-wolfi
docker buildx build --platform linux/amd64 \
  -t andrianey/adguardhomedotdoh:hardened-wolfi --load .
```

---

**Last Updated**: 2026-02-10  
**Verified**: ✅
