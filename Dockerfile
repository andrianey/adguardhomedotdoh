# ============================================
# Stage 1: Extract AdGuard Home from official image
# ============================================
FROM adguard/adguardhome:latest AS adguard-source

# ============================================
# Stage 2: Final image with Alpine 3.23
# ============================================
FROM alpine:3.23

# Set labels for the image
LABEL maintainer="andrianey"
LABEL description="AdGuard Home with DoH/DoT support (Stubby, Unbound, Cloudflared)"

# 1. Install dependencies
# - Added: libcap (for setcap), removed explicit unnecessary packages
RUN apk update && apk add --no-cache \
    stubby \
    unbound \
    ca-certificates \
    tzdata \
    libcap \
    && rm -rf /var/cache/apk/*

# 2. Copy AdGuard Home binary from the official image
COPY --from=adguard-source /opt/adguardhome/AdGuardHome /opt/adguardhome/AdGuardHome

# 3. Create non-root user
RUN adduser -D -u 1000 adguard

# 4. Setup AdGuard Home directories and permissions
RUN mkdir -p /opt/adguardhome/conf /opt/adguardhome/work && \
    chown -R adguard:adguard /opt/adguardhome && \
    chmod 700 /opt/adguardhome/work && \
    setcap 'cap_net_bind_service=+ep' /opt/adguardhome/AdGuardHome

# 5. Setup Unbound
RUN mkdir -p /var/lib/unbound/ && \
    wget -O /var/lib/unbound/root.hints https://www.internic.net/domain/named.root && \
    chown -R adguard:adguard /var/lib/unbound /etc/unbound

COPY unbound/unbound.conf /etc/unbound/unbound.conf

# 6. Setup Stubby
RUN mkdir -p /etc/stubby/ && \
    chown -R adguard:adguard /etc/stubby
COPY stubby/stubby.yml /etc/stubby/stubby.yml

# 7. Install Cloudflared
RUN set -eux; \
    arch="$(uname -m)"; \
    case "$arch" in \
    aarch64) CL_ARCH="arm64" ;; \
    x86_64)  CL_ARCH="amd64" ;; \
    armv7l)  CL_ARCH="arm" ;; \
    armhf)   CL_ARCH="arm" ;; \
    *) echo "Unsupported architecture: $arch"; exit 1 ;; \
    esac; \
    echo "Downloading Cloudflared for $CL_ARCH..."; \
    wget -qO /usr/local/bin/cloudflared "https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-${CL_ARCH}" && \
    chmod +x /usr/local/bin/cloudflared && \
    chown adguard:adguard /usr/local/bin/cloudflared

# 8. Entrypoint script (Ensure it uses /bin/sh)
COPY entrypoint.sh /opt/entrypoint.sh
RUN chmod +x /opt/entrypoint.sh && \
    sed -i 's/\r$//' /opt/entrypoint.sh && \
    chown adguard:adguard /opt/entrypoint.sh

# Expose ports
EXPOSE 53/tcp 53/udp 67/udp 68/udp 80/tcp 443/tcp 443/udp 853/tcp 853/udp 3000/tcp 5443/tcp 5443/udp

# Volumes
VOLUME ["/opt/adguardhome/conf", "/opt/adguardhome/work"]

USER adguard

ENTRYPOINT ["/opt/entrypoint.sh"]