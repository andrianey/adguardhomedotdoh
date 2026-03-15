# ============================================
# Stage 1: Extract AdGuard Home from official image
# ============================================
FROM adguard/adguardhome:latest AS adguard-source

# ============================================
# Stage 2: Helper stage to download dnsproxy
# ============================================
FROM alpine:latest AS builder_helpers

RUN apk update && apk add --no-cache curl jq ca-certificates

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
    chmod +x /usr/local/bin/dnsproxy && \
    /usr/local/bin/dnsproxy --version 2>&1 | grep -oE 'v[0-9]+\.[0-9]+\.[0-9]+[^ ]*' | head -1 > /tmp/dnsproxy_version || echo "unknown" > /tmp/dnsproxy_version


# ============================================
# Stage 3: Unbound Builder (Compiled with Redis/Valkey support)
# ============================================
FROM alpine:3.23 AS builder_unbound

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
# Stage 4: Final image with Alpine 3.23
# ============================================
FROM alpine:3.23

# Set labels for the image
LABEL maintainer="andrianey"
LABEL description="AdGuard Home with DoH/DoT support (dnsproxy, Unbound, Valkey)"
LABEL org.opencontainers.image.source="https://github.com/andrianey/adguardhomedotdoh"
LABEL org.opencontainers.image.title="AdGuard Home DoH/DoT (Latest)"
LABEL org.opencontainers.image.description="Standard AdGuard Home with Unbound, dnsproxy, and Valkey"

# 1. Install dependencies
RUN apk update && apk add --no-cache \
    libevent \
    hiredis \
    valkey \
    expat \
    ca-certificates \
    tzdata \
    bash \
    && rm -rf /var/cache/apk/*

# 2. Copy AdGuard Home binary from the official image
COPY --from=adguard-source /opt/adguardhome/AdGuardHome /opt/adguardhome/AdGuardHome

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
# Copy required libs
COPY --from=builder_unbound /usr/lib/libhiredis.so* /usr/lib/
COPY --from=builder_unbound /usr/lib/libevent* /usr/lib/

RUN mkdir -p /var/lib/unbound/ && \
    wget -O /var/lib/unbound/root.hints https://www.internic.net/domain/named.root && \
    /usr/sbin/unbound -V 2>&1 | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1 > /tmp/unbound_version || echo "unknown" > /tmp/unbound_version

COPY unbound/unbound.conf /etc/unbound/unbound.conf

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