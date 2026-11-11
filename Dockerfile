# ============================================
# Stage 1: Extract AdGuard Home from official image
# ============================================
FROM adguard/adguardhome:latest AS adguard-source

# ============================================
# Stage 2: Helper stage to download dnsproxy
# ============================================
FROM alpine:3.24 AS builder_helpers

# Explicitly upgrade musl to pick up the CVE fix (>= 1.2.6-r6). This is a
# separate layer so it still runs even if other apk layers are cached.
RUN apk add --no-cache --upgrade musl

RUN apk add --no-cache curl jq ca-certificates

# Download dnsproxy
RUN set -eux; \
    ARCH="$(uname -m)"; \
    case "$ARCH" in \
    aarch64|arm64) \
    DNSPROXY_ARCH="linux-arm64"; \
    ;; \
    armv7l|armhf) \
    DNSPROXY_ARCH="linux-armv7"; \
    ;; \
    x86_64|amd64) \
    DNSPROXY_ARCH="linux-amd64"; \
    ;; \
    *) \
    echo "Unsupported architecture: $ARCH"; \
    exit 1; \
    ;; \
    esac; \
    # Fetch latest release URL dynamically
    DNSPROXY_URL=$(curl -s https://api.github.com/repos/AdguardTeam/dnsproxy/releases/latest | \
    jq -r ".assets[] | select(.name | contains(\"${DNSPROXY_ARCH}\") and contains(\".tar.gz\")) | .browser_download_url" | head -n 1); \
    if [ -z "$DNSPROXY_URL" ] || [ "$DNSPROXY_URL" = "null" ]; then \
    if [ "$DNSPROXY_ARCH" = "linux-armv7" ]; then \
    DNSPROXY_URL=$(curl -s https://api.github.com/repos/AdguardTeam/dnsproxy/releases/latest | \
    jq -r ".assets[] | select(.name | contains(\"linux-arm7\") and contains(\".tar.gz\")) | .browser_download_url" | head -n 1); \
    fi; \
    fi; \
    echo "Downloading dnsproxy from: ${DNSPROXY_URL}"; \
    curl -L -o /tmp/dnsproxy.tar.gz "${DNSPROXY_URL}"; \
    tar -xzf /tmp/dnsproxy.tar.gz -C /tmp; \
    # Find binary regardless of directory structure
    find /tmp -name dnsproxy -type f -exec mv {} /usr/local/bin/dnsproxy \; && \
    chmod +x /usr/local/bin/dnsproxy

# Record the dnsproxy version for CI/badges. The output format varies between
# releases, so fall back progressively and only use "unknown" as a last resort.
RUN set -eux; \
    if ! /usr/local/bin/dnsproxy --version > /tmp/dnsproxy_version_raw 2>&1; then \
    echo "WARNING: dnsproxy --version failed"; \
    fi; \
    VER=$(grep -oE 'v[0-9]+\.[0-9]+\.[0-9]+[^ ]*' /tmp/dnsproxy_version_raw | head -n 1 || true); \
    if [ -z "$VER" ]; then \
    VER=$(grep -oE '[0-9]+\.[0-9]+\.[0-9]+[^ ]*' /tmp/dnsproxy_version_raw | head -n 1 || true); \
    fi; \
    if [ -z "$VER" ]; then \
    VER=$(head -n 1 /tmp/dnsproxy_version_raw | tr -s '[:space:]' ' ' | sed 's/^ *//; s/ *$//' || true); \
    fi; \
    if [ -z "$VER" ]; then VER="unknown"; fi; \
    printf '%s\n' "$VER" > /tmp/dnsproxy_version; \
    rm -f /tmp/dnsproxy_version_raw


# ============================================
# Stage 3: Unbound Builder (Compiled with Redis/Valkey support)
# ============================================
FROM alpine:3.24 AS builder_unbound

# Explicitly upgrade musl to pick up the CVE fix (>= 1.2.6-r6). This is a
# separate layer so it still runs even if other apk layers are cached.
RUN apk add --no-cache --upgrade musl

RUN apk add --no-cache \
    build-base \
    libevent-dev \
    expat-dev \
    hiredis-dev \
    openssl-dev \
    bison \
    flex \
    wget \
    ca-certificates

WORKDIR /tmp/unbound
RUN wget https://www.nlnetlabs.nl/downloads/unbound/unbound-latest.tar.gz \
    && tar -xzf unbound-latest.tar.gz \
    && rm unbound-latest.tar.gz \
    && cd unbound-* \
    && ./configure \
    --prefix=/usr \
    --sysconfdir=/etc \
    --localstatedir=/var \
    --with-libevent \
    --with-libhiredis \
    --enable-cachedb \
    --with-pidfile=/var/run/unbound.pid \
    && make -j$(nproc) \
    && make install DESTDIR=/tmp/unbound/install

# ============================================
# Stage 4: Final image (Alpine latest)
# ============================================
FROM alpine:3.24

# The alpine:3.24 tag is a frozen snapshot (built 2026-09-17) that ships
# zlib 1.3.2-r0, while the v3.24 repository now has 1.3.2-r1, which fixes
# CVE-2026-85091. APK_REFRESH is purely a cache key for this RUN layer:
# BuildKit caches a RUN layer by its inputs, so an unchanged value is a
# cache hit (no rebuild) and a changed value forces the upgrade to re-run.
ARG APK_REFRESH=none
RUN apk upgrade --no-cache
# Explicit musl upgrade to pick up the CVE fix (>= 1.2.6-r6); kept in its own
# layer so it is not skipped when the apk upgrade layer is reused from cache.
RUN apk add --no-cache --upgrade musl

# Set labels for the image
LABEL maintainer="andrianey"
LABEL description="AdGuard Home with DoH/DoT support (dnsproxy, Unbound, Valkey)"
LABEL org.opencontainers.image.source="https://github.com/andrianey/adguardhomedotdoh"
LABEL org.opencontainers.image.title="AdGuard Home DoH/DoT (Latest)"
LABEL org.opencontainers.image.description="Standard AdGuard Home with Unbound, dnsproxy, and Valkey"

# 1. Install dependencies
RUN apk add --no-cache \
    libevent \
    hiredis \
    valkey \
    expat \
    ca-certificates \
    tzdata \
    bash \
    netcat-openbsd

# 2. Copy AdGuard Home binary from the official image
COPY --from=adguard-source /opt/adguardhome/AdGuardHome /opt/adguardhome/AdGuardHome

# Record the AdGuard Home version for CI/badges, with progressive fallbacks.
RUN set -eux; \
    if ! /opt/adguardhome/AdGuardHome --version > /tmp/adguardhome_version_raw 2>&1; then \
    echo "WARNING: AdGuardHome --version failed"; \
    fi; \
    VER=$(grep -oE 'v[0-9]+\.[0-9]+\.[0-9]+[^ ]*' /tmp/adguardhome_version_raw | head -n 1 || true); \
    if [ -z "$VER" ]; then \
    VER=$(grep -oE '[0-9]+\.[0-9]+\.[0-9]+[^ ]*' /tmp/adguardhome_version_raw | head -n 1 || true); \
    fi; \
    if [ -z "$VER" ]; then \
    VER=$(head -n 1 /tmp/adguardhome_version_raw | tr -s '[:space:]' ' ' | sed 's/^ *//; s/ *$//' || true); \
    fi; \
    if [ -z "$VER" ]; then VER="unknown"; fi; \
    printf '%s\n' "$VER" > /tmp/adguardhome_version; \
    rm -f /tmp/adguardhome_version_raw

# 3. Copy dnsproxy from helpers
COPY --from=builder_helpers /usr/local/bin/dnsproxy /usr/local/bin/dnsproxy
COPY --from=builder_helpers /tmp/dnsproxy_version /tmp/dnsproxy_version

# 4. Setup AdGuard Home directories and permissions
RUN mkdir -p /opt/adguardhome/conf /opt/adguardhome/work && \
    chmod 700 /opt/adguardhome/work

# 5. Setup Unbound (Copy from builder)
COPY --from=builder_unbound /tmp/unbound/install/usr/sbin/unbound /usr/sbin/unbound
COPY --from=builder_unbound /tmp/unbound/install/usr/sbin/unbound-anchor /usr/sbin/unbound-anchor
COPY --from=builder_unbound /tmp/unbound/install/usr/sbin/unbound-control /usr/sbin/unbound-control
COPY --from=builder_unbound /tmp/unbound/install/usr/sbin/unbound-checkconf /usr/sbin/unbound-checkconf
COPY --from=builder_unbound /tmp/unbound/install/usr/lib/libunbound.so* /usr/lib/
RUN set -eux; \
    mkdir -p /var/lib/unbound/; \
    if ! /usr/sbin/unbound -V > /tmp/unbound_version_raw 2>&1; then \
    echo "WARNING: unbound -V failed"; \
    fi; \
    VER=$(grep -iE '^[[:space:]]*version[[:space:]]+v?[0-9]+(\.[0-9]+)+' /tmp/unbound_version_raw | grep -oE 'v?[0-9]+\.[0-9]+\.[0-9]+[^ ]*' | head -n 1 || true); \
    if [ -z "$VER" ]; then \
    VER=$(grep -oE '[0-9]+\.[0-9]+\.[0-9]+[^ ]*' /tmp/unbound_version_raw | head -n 1 || true); \
    fi; \
    if [ -z "$VER" ]; then \
    VER=$(head -n 1 /tmp/unbound_version_raw | tr -s '[:space:]' ' ' | sed 's/^ *//; s/ *$//' || true); \
    fi; \
    if [ -z "$VER" ]; then VER="unknown"; fi; \
    printf '%s\n' "$VER" > /tmp/unbound_version; \
    rm -f /tmp/unbound_version_raw

COPY unbound/unbound.conf /etc/unbound/unbound.conf
COPY unbound/root.hints /var/lib/unbound/root.hints

# 6. Setup Cron & Permissions
COPY crontab/root /tmp/crontab_root
RUN cat /tmp/crontab_root >> /var/spool/cron/crontabs/root && rm -f /tmp/crontab_root

# 7. Entrypoint script (Ensure it uses /bin/sh)
COPY entrypoint.sh /opt/entrypoint.sh
RUN chmod +x /opt/entrypoint.sh && \
    sed -i 's/\r$//' /opt/entrypoint.sh

# Expose ports
EXPOSE 53/tcp 53/udp 67/udp 68/udp 80/tcp 443/tcp 443/udp 853/tcp 853/udp 3000/tcp 5443/tcp 5443/udp

# Volumes
VOLUME ["/opt/adguardhome/conf", "/opt/adguardhome/work"]

ENTRYPOINT ["/opt/entrypoint.sh"]