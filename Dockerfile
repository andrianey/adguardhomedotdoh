# ============================================================================
# AdGuardHome + DoT + DoH using Wolfi Base Image
# Components: AdGuard Home, Stubby (DoT), Unbound, Cloudflared (DoH)
# 
# Uses Debian for builder stages (glibc compatible) and Wolfi for final image
# ============================================================================

# -----------------------------------------------------------------------------
# Stage 1: Builder stage for Stubby (using Debian for glibc compatibility)
# -----------------------------------------------------------------------------
# ============================================================================
# Stage 1: Builder stage for AdGuard Home (using Alpine for speed)
# ============================================================================
FROM alpine:3.24 AS builder_adguard

RUN apk add --no-cache \
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

# ============================================
# Stage 2: Helper stage to download dnsproxy
# ============================================
FROM alpine:3.24 AS builder_helpers

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
    chmod +x /usr/local/bin/dnsproxy && \
    /usr/local/bin/dnsproxy --version 2>&1 | grep -oE 'v[0-9]+\.[0-9]+\.[0-9]+[^ ]*' | head -1 > /tmp/dnsproxy_version || echo "unknown" > /tmp/dnsproxy_version


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

# --- Image metadata -------------------------------------------------------
# Version ARGs are supplied by CI from the inspect-image built just before this
# one, so the labels carry real versions instead of "unknown". The defaults let
# a plain `docker build .` still work without them.
ARG ADGUARDHOME_VERSION="unknown"
ARG DNSPROXY_VERSION="unknown"
ARG DNSPROXY_REVISION="unknown"
ARG UNBOUND_VERSION="unknown"
ARG BUILD_DATE=""
ARG VCS_REF=""
ARG BRANCH=""

# Exactly one key per label. Docker keeps the LAST occurrence of a duplicated
# key, which is how this image previously shipped the wrong title and a
# gitlab.com source. The wolfi base also carries Chainguard's own vendor /
# authors / url labels; they are re-declared here so `docker inspect` attributes
# the image to us rather than to Chainguard.
LABEL maintainer="andrianey"
LABEL org.opencontainers.image.title="AdGuard Home DoH/DoT (Latest-Wolfi)"
LABEL org.opencontainers.image.description="Wolfi-based AdGuard Home with Unbound, dnsproxy, and Valkey"
LABEL org.opencontainers.image.source="https://github.com/andrianey/adguardhomedotdoh"
LABEL org.opencontainers.image.url="https://github.com/andrianey/adguardhomedotdoh"
LABEL org.opencontainers.image.documentation="https://github.com/andrianey/adguardhomedotdoh"
LABEL org.opencontainers.image.vendor="andrianey"
LABEL org.opencontainers.image.authors="andrianey"
LABEL org.opencontainers.image.licenses="MIT"
LABEL org.opencontainers.image.version="${ADGUARDHOME_VERSION}"
LABEL org.opencontainers.image.revision="${VCS_REF}"
LABEL org.opencontainers.image.created="${BUILD_DATE}"
LABEL org.opencontainers.image.ref.name="${BRANCH}"
LABEL org.label-schema.adguardhome.version="${ADGUARDHOME_VERSION}"
LABEL org.label-schema.dnsproxy.version="${DNSPROXY_VERSION}"
LABEL org.label-schema.dnsproxy.revision="${DNSPROXY_REVISION}"
LABEL org.label-schema.unbound.version="${UNBOUND_VERSION}"

# Install runtime dependencies from Wolfi repos
RUN apk add --no-cache \
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
    su-exec \
    netcat-openbsd

# Create necessary directories and device nodes
RUN mkdir -p /opt/adguardhome/conf \
    && mkdir -p /opt/adguardhome/work \
    && mkdir -p /var/lib/unbound \
    && mkdir -p /usr/local/var/run \
    && mkdir -p /var/log \
    && mkdir -p /usr/local/lib \
    && mkdir -p /dev \
    && mknod -m 666 /dev/null c 1 3 2>/dev/null || true

# Copy AdGuard Home from Alpine builder
COPY --from=builder_adguard /usr/local/bin/AdGuardHome /opt/adguardhome/AdGuardHome

# Capture AdGuard Home version for CI/badge metadata (must never fail the build).
RUN AGH_OUT=$(/opt/adguardhome/AdGuardHome --version 2>&1 || true); \
    AGH_VER=$(printf '%s\n' "$AGH_OUT" | grep -oE 'v[0-9]+\.[0-9]+\.[0-9]+[^ ]*' | head -n1 || true); \
    [ -n "$AGH_VER" ] || AGH_VER=$(printf '%s\n' "$AGH_OUT" | grep -oE '[0-9]+\.[0-9]+\.[0-9]+[^ ]*' | head -n1 || true); \
    [ -n "$AGH_VER" ] || AGH_VER=$(printf '%s\n' "$AGH_OUT" | grep -m1 -E '[^[:space:]]' || true); \
    [ -n "$AGH_VER" ] || AGH_VER="unknown"; \
    printf '%s\n' "$AGH_VER" > /tmp/adguardhome_version; \
    echo "AdGuardHome version: $AGH_VER"

# Copy dnsproxy from helpers builder
COPY --from=builder_helpers /usr/local/bin/dnsproxy /usr/local/bin/dnsproxy
COPY --from=builder_helpers /tmp/dnsproxy_version /tmp/dnsproxy_version

# Copy root.hints for Unbound
COPY unbound/root.hints /var/lib/unbound/root.hints

# Copy Unbound from builder_unbound
COPY --from=builder_unbound /tmp/unbound/install/usr/sbin/unbound /usr/sbin/unbound
COPY --from=builder_unbound /tmp/unbound/install/usr/sbin/unbound-anchor /usr/sbin/unbound-anchor
COPY --from=builder_unbound /tmp/unbound/install/usr/sbin/unbound-control /usr/sbin/unbound-control
COPY --from=builder_unbound /tmp/unbound/install/usr/sbin/unbound-checkconf /usr/sbin/unbound-checkconf
COPY --from=builder_unbound /tmp/unbound/install/usr/lib/libunbound.so* /usr/local/lib/
COPY --from=builder_unbound /output/lib/libhiredis.so* /usr/local/lib/
COPY --from=builder_unbound /output/lib/libevent* /usr/local/lib/

# Set library path
ENV LD_LIBRARY_PATH="/usr/local/lib"

# Copy configuration files
COPY unbound/unbound.conf /etc/unbound/unbound.conf

# Check configuration files for windows line endings
RUN sed -i 's/\r$//' /etc/unbound/unbound.conf

# Copy entrypoint script
COPY entrypoint.sh /opt/entrypoint.sh
RUN sed -i 's/\r$//' /opt/entrypoint.sh && chmod +x /opt/entrypoint.sh

# Set permissions and capabilities
RUN chmod 700 /opt/adguardhome/work \
    && chmod 755 /opt/adguardhome/AdGuardHome \
    && chmod 755 /usr/local/bin/dnsproxy \
    && setcap 'cap_net_bind_service=+ep' /opt/adguardhome/AdGuardHome \
    && setcap 'cap_net_bind_service=+ep' /usr/sbin/unbound \
    && setcap 'cap_net_bind_service=+ep' /usr/local/bin/dnsproxy && \
    /usr/sbin/unbound -V 2>&1 | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1 > /tmp/unbound_version || echo "unknown" > /tmp/unbound_version

# Expose ports
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

# Run as root explicitly
USER root

# Use tini as init system
ENTRYPOINT ["/sbin/tini", "--", "/opt/entrypoint.sh"]