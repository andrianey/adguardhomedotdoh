# ============================================================================
# AdGuardHome + DoT + DoH using Wolfi Base Image
# Components: AdGuard Home, Stubby (DoT), Unbound, Cloudflared (DoH)
# 
# Uses Debian for builder stages (glibc compatible) and Wolfi for final image
# ============================================================================

# -----------------------------------------------------------------------------
# Stage 1: Source for AdGuard Home (Edge/Nightly for latest fixes)
# -----------------------------------------------------------------------------
FROM adguard/adguardhome:edge AS adguard_source

# -----------------------------------------------------------------------------
# Stage 2: Build dnsproxy from source (Fixes CVEs in deps and Go stdlib)
# -----------------------------------------------------------------------------
FROM golang:alpine AS builder_dnsproxy

RUN apk add --no-cache git

WORKDIR /src/dnsproxy
# Clone latest source
RUN git clone https://github.com/AdguardTeam/dnsproxy.git .
# Force update quic-go to fix CVE-2025-64702
RUN go get github.com/quic-go/quic-go@latest && go mod tidy
# Build binary
RUN go build -v -ldflags "-s -w" -o /usr/local/bin/dnsproxy .

# Download root.hints for Unbound
RUN wget -O /tmp/root.hints https://www.internic.net/domain/named.root

# -----------------------------------------------------------------------------
# Stage 3: Builder stage for Unbound (compiled with Redis cachedb support)
# -----------------------------------------------------------------------------
FROM debian:bookworm-slim AS builder_unbound

RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential \
    libssl-dev \
    libevent-dev \
    libexpat1-dev \
    libhiredis-dev \
    bison \
    flex \
    wget \
    ca-certificates \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /tmp/unbound
# Unbound version Latest
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
    --with-pidfile=/run/unbound.pid \
    && make -j$(nproc) \
    && make install DESTDIR=/tmp/unbound/install

# Prepare libraries for copy (handle multi-arch path)
RUN mkdir -p /output/lib \
    && cp /usr/lib/*/libhiredis.so* /output/lib/ \
    && cp /usr/lib/*/libevent* /output/lib/

# -----------------------------------------------------------------------------
# Stage 4: Final image using Wolfi
# -----------------------------------------------------------------------------
FROM cgr.dev/chainguard/wolfi-base:latest AS final

LABEL maintainer="andrianey"
LABEL name="adguardhome-doh-dot-wolfi"
LABEL description="AdGuard Home with DoT/DoH support using dnsproxy and Unbound on Wolfi"

# Install runtime dependencies from Wolfi repos with retry
RUN apk update && apk add --no-cache \
    bash \
    ca-certificates \
    openssl \
    libevent \
    valkey \
    tini \
    tzdata \
    libssl3 \
    libcap-utils \
    libexpat1 \
    shadow \
    su-exec

# Create non-root user
RUN groupadd -r adguard && \
    useradd --no-log-init -r -g adguard -u 1000 adguard

# Create necessary directories and device nodes
RUN mkdir -p /opt/adguardhome/conf \
    && mkdir -p /opt/adguardhome/work \
    && mkdir -p /var/lib/unbound \
    && mkdir -p /usr/local/var/run \
    && mkdir -p /var/log \
    && mkdir -p /usr/local/lib \
    && mkdir -p /dev \
    && mknod -m 666 /dev/null c 1 3 2>/dev/null || true

# Copy AdGuard Home from source stage
COPY --from=adguard_source /opt/adguardhome/AdGuardHome /opt/adguardhome/AdGuardHome

# Copy dnsproxy from builder_dnsproxy
COPY --from=builder_dnsproxy /usr/local/bin/dnsproxy /usr/local/bin/dnsproxy

# Copy root.hints for Unbound
COPY --from=builder_dnsproxy /tmp/root.hints /var/lib/unbound/root.hints

# Copy Unbound from builder_unbound
COPY --from=builder_unbound /tmp/unbound/install/usr/sbin/unbound /usr/sbin/unbound
COPY --from=builder_unbound /tmp/unbound/install/usr/sbin/unbound-anchor /usr/sbin/unbound-anchor
COPY --from=builder_unbound /tmp/unbound/install/usr/sbin/unbound-control /usr/sbin/unbound-control
COPY --from=builder_unbound /tmp/unbound/install/usr/sbin/unbound-checkconf /usr/sbin/unbound-checkconf
COPY --from=builder_unbound /tmp/unbound/install/usr/lib/libunbound.so* /usr/local/lib/
COPY --from=builder_unbound /output/lib/libhiredis.so* /usr/local/lib/
COPY --from=builder_unbound /output/lib/libevent* /usr/local/lib/

# Copy configuration files
COPY unbound/unbound.conf /etc/unbound/unbound.conf

# Check configuration files for windows line endings
RUN sed -i 's/\r$//' /etc/unbound/unbound.conf

# Copy entrypoint script
COPY entrypoint.sh /opt/entrypoint.sh
RUN sed -i 's/\r$//' /opt/entrypoint.sh && chmod +x /opt/entrypoint.sh

# Set permissions and capabilities
RUN chown -R adguard:adguard /opt/adguardhome \
    && chown -R adguard:adguard /var/lib/unbound \
    && chown -R adguard:adguard /etc/unbound \
    && chown -R adguard:adguard /var/log \
    && chown adguard:adguard /opt/entrypoint.sh \
    && chmod 700 /opt/adguardhome/work \
    && chmod 755 /opt/adguardhome/AdGuardHome \
    && chmod 755 /usr/local/bin/dnsproxy \
    && setcap 'cap_net_bind_service=+ep' /opt/adguardhome/AdGuardHome \
    && setcap 'cap_net_bind_service=+ep' /usr/sbin/unbound \
    && setcap 'cap_net_bind_service=+ep' /usr/local/bin/dnsproxy

# Expose ports
# DNS (TCP/UDP)
EXPOSE 53/tcp 53/udp \
    67/udp \
    68/udp \
    80/tcp \
    443/tcp 443/udp \
    853/tcp 853/udp \
    3000/tcp 3000/udp \
    5443/tcp 5443/udp \
    6060/tcp

# Volumes for persistent data
VOLUME ["/opt/adguardhome/conf", "/opt/adguardhome/work"]

# Run as root initially to allow entrypoint to drop privileges
USER root

# Use tini as init system
ENTRYPOINT ["/sbin/tini", "--", "/opt/entrypoint.sh"]