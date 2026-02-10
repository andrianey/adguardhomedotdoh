# 🔐 AdGuard Home Multi-Branch Security Matrix

**Build Date**: 2026-02-10  
**Repository**: andrianey/adguardhomedotdoh

## 📊 Branch Overview

| Branch | Base Image | User | Upstream | Security Level | Status |
|--------|------------|------|----------|----------------|--------|
| **`latest`** | Alpine 3.23 | Root | **dnsproxy** (Release) | ⭐ Standard | ✅ **Migrated** |
| **`latest-wolfi`** | Wolfi OS | Root | **dnsproxy** (Release) | ⭐⭐ Enhanced | ✅ **Migrated** |
| **`hardened`** | Alpine Edge | adguard | **dnsproxy** (Source) | ⭐⭐⭐ High | ✅ **Zero CVE** |
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

### 2. `latest-wolfi` - Wolfi Root (Enhanced)
**Tag**: `andrianey/adguardhomedotdoh:latest-wolfi`
**Configuration**:
```yaml
Base: Wolfi OS (Chainguard)
User: root
AdGuard Home: Stable (Latest Release)
Upstream: dnsproxy (Latest Release)
Unbound: Custom Build (Debian Builder -> Wolfi)
Valkey: ✅ Enabled
CVE Status: Reduced (Wolfi base)
```

### 3. `hardened` - Alpine Non-Root (High Security)
**Tag**: `andrianey/adguardhomedotdoh:hardened`
**Configuration**:
```yaml
Base: Alpine Edge
User: adguard (UID 1000)
AdGuard Home: **Edge/Nightly** (Fixes CVE-2022-32175)
Upstream: **dnsproxy** (Built from Source/Go 1.25.7)
Unbound: Built from source (Alpine builder)
Valkey: ✅ Enabled
Privilege Drop: su-exec
Capabilities: CAP_NET_BIND_SERVICE
CVE Status: **Fully Patched (Zero CVE target)**
```

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
Capabilities: CAP_NET_BIND_SERVICE
CVE Status: **Fully Patched (Zero CVE target)**
```

---

## ⚙️ Upstream Configuration (All Branches)

All branches now use **dnsproxy** listening on `127.0.0.1:8053`.
AdGuard Home should be configured to upstream to Unbound (`127.0.0.1:5335`), which forwards to dnsproxy.

---

**Last Updated**: 2026-02-10  
**Verified**: ✅
