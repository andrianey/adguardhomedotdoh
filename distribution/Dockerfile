# ============================================================================
# AdGuardHome + DoT + DoH using Wolfi Base Image
# Components: AdGuard Home, Stubby (DoT), Unbound, Cloudflared (DoH)
# 
# Uses Debian for builder stages (glibc compatible) and Wolfi for final image
# ============================================================================

# -----------------------------------------------------------------------------
# Stage 1: Builder stage for Stubby (using Debian for glibc compatibility)
# -----------------------------------------------------------------------------
FROM debian:bookworm-slim AS builder_stubby

# Install build dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential \
    cmake \
    git \
    libssl-dev \
    libevent-dev \
    libyaml-dev \
    check \
    libidn2-dev \
    gettext \
    ca-certificates \
    && rm -rf /var/lib/apt/lists/*

# Clone and build getdns with stubby
RUN git clone https://github.com/getdnsapi/getdns.git /tmp/getdns \
    && cd /tmp/getdns \
    && git checkout master \
    && git submodule update --init \
    && mkdir build && cd build \
    && cmake -DBUILD_STUBBY=ON \
             -DCMAKE_INSTALL_PREFIX=/usr/local \
             -DENABLE_STUB_ONLY=ON \
             .. \
    && make -j$(nproc) \
    && make install

# -----------------------------------------------------------------------------
# Stage 2: Builder stage for AdGuard Home (using Alpine for speed)
# -----------------------------------------------------------------------------
FROM alpine:latest AS builder_adguard

RUN apk update && apk add --no-cache \
    wget \
    ca-certificates

# Download AdGuard Home based on architecture
RUN set -eux; \
    ARCH="$(uname -m)"; \
    echo "Detected architecture: $ARCH"; \
    case "$ARCH" in \
        aarch64|arm64) \
            AGH_URL="https://static.adguard.com/adguardhome/release/AdGuardHome_linux_arm64.tar.gz"; \
            ;; \
        armv7l|armhf) \
            AGH_URL="https://static.adguard.com/adguardhome/release/AdGuardHome_linux_armv7.tar.gz"; \
            ;; \
        x86_64|amd64) \
            AGH_URL="https://static.adguard.com/adguardhome/release/AdGuardHome_linux_amd64.tar.gz"; \
            ;; \
        *) \
            echo "Unsupported architecture: $ARCH"; \
            exit 1; \
            ;; \
    esac; \
    echo "Downloading AdGuard Home from: ${AGH_URL}"; \
    wget -O /tmp/adguardhome.tar.gz "${AGH_URL}"; \
    tar -xzf /tmp/adguardhome.tar.gz -C /tmp; \
    mv /tmp/AdGuardHome/AdGuardHome /usr/local/bin/AdGuardHome; \
    chmod +x /usr/local/bin/AdGuardHome; \
    echo "AdGuard Home installed successfully"

# -----------------------------------------------------------------------------
# Stage 3: Cloudflared and resources downloader (using Alpine)
# -----------------------------------------------------------------------------
FROM alpine:latest AS builder_cloudflared

RUN apk update && apk add --no-cache wget ca-certificates

# Download Cloudflared based on architecture
RUN set -eux; \
    ARCH="$(uname -m)"; \
    case "$ARCH" in \
        aarch64|arm64) \
            CL_URL="https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-arm64"; \
            ;; \
        armv7l|armhf) \
            CL_URL="https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-arm"; \
            ;; \
        x86_64|amd64) \
            CL_URL="https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64"; \
            ;; \
        *) \
            echo "Unsupported architecture: $ARCH"; \
            exit 1; \
            ;; \
    esac; \
    wget -O /usr/local/bin/cloudflared "${CL_URL}"; \
    chmod +x /usr/local/bin/cloudflared

# Download root.hints for Unbound
RUN wget -O /tmp/root.hints https://www.internic.net/domain/named.root

# -----------------------------------------------------------------------------
# Stage 4: Final image using Wolfi
# -----------------------------------------------------------------------------
FROM cgr.dev/chainguard/wolfi-base:latest AS final

LABEL maintainer="Your Name <your@email.com>"
LABEL name="adguardhome-doh-dot-wolfi"
LABEL description="AdGuard Home with DoT/DoH support using Stubby, Unbound, and Cloudflared on Wolfi"

# Install runtime dependencies from Wolfi repos with retry
RUN set -e; \
    for i in 1 2 3 4 5; do \
        echo "Attempt $i: Installing runtime dependencies..."; \
        apk add --no-cache --repository https://packages.wolfi.dev/os \
            --allow-untrusted \
            bash \
            ca-certificates \
            openssl \
            libevent \
            yaml \
            libidn2 \
            unbound \
            tini \
            tzdata \
            glibc \
            libssl3 && break || \
        (echo "Retry $i failed, waiting 15s..."; sleep 15); \
    done

# Create necessary directories and device nodes
RUN mkdir -p /opt/adguardhome/conf \
    && mkdir -p /opt/adguardhome/work \
    && mkdir -p /var/lib/unbound \
    && mkdir -p /etc/stubby \
    && mkdir -p /usr/local/var/run \
    && mkdir -p /var/log \
    && mkdir -p /usr/local/lib \
    && mkdir -p /dev \
    && mknod -m 666 /dev/null c 1 3 2>/dev/null || true

# Copy Stubby libraries and binary from Debian builder
COPY --from=builder_stubby /usr/local/lib/libgetdns* /usr/local/lib/
COPY --from=builder_stubby /usr/local/bin/stubby /usr/local/bin/stubby

# Copy AdGuard Home from Alpine builder
COPY --from=builder_adguard /usr/local/bin/AdGuardHome /opt/adguardhome/AdGuardHome

# Copy Cloudflared from Alpine builder
COPY --from=builder_cloudflared /usr/local/bin/cloudflared /usr/local/bin/cloudflared

# Copy root.hints for Unbound
COPY --from=builder_cloudflared /tmp/root.hints /var/lib/unbound/root.hints

# Set library path for stubby
ENV LD_LIBRARY_PATH="/usr/local/lib"

# Copy configuration files
COPY unbound/unbound.conf /etc/unbound/unbound.conf
COPY stubby/stubby.yml /etc/stubby/stubby.yml

# Copy entrypoint script
COPY distribution/entrypoint.sh /opt/entrypoint.sh
RUN chmod +x /opt/entrypoint.sh

# Set permissions
RUN chmod 700 /opt/adguardhome/work \
    && chmod 755 /opt/adguardhome/AdGuardHome \
    && chmod 755 /usr/local/bin/cloudflared \
    && chmod 755 /usr/local/bin/stubby 2>/dev/null || true

# Expose ports
# DNS (TCP/UDP)
EXPOSE 53/tcp 53/udp
# DNS-over-TLS
EXPOSE 853/tcp
# DNS-over-HTTPS
EXPOSE 443/tcp
# DNS-over-QUIC
EXPOSE 784/udp 8853/udp
# AdGuard Home Admin Panel
EXPOSE 3000/tcp
# DHCP (optional)
EXPOSE 67/udp 68/udp

# Volumes for persistent data
VOLUME ["/opt/adguardhome/conf", "/opt/adguardhome/work"]

# Use tini as init system
ENTRYPOINT ["/sbin/tini", "--", "/opt/entrypoint.sh"]
