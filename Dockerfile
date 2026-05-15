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
FROM golang:1.26-alpine AS builder_dnsproxy

RUN apk add --no-cache git

WORKDIR /src/dnsproxy
# Clone latest source and fetch all tags
RUN git clone https://github.com/AdguardTeam/dnsproxy.git . && \
    git fetch --tags && \
    git pull origin master
# Force update quic-go to fix CVE-2025-64702
RUN --mount=type=cache,target=/go/pkg/mod \
    --mount=type=cache,target=/root/.cache/go-build \
    go get github.com/quic-go/quic-go@latest && go mod tidy
# Extract version info from git and write to a file for label injection
RUN --mount=type=cache,target=/go/pkg/mod \
    --mount=type=cache,target=/root/.cache/go-build \
    VERSION=$(git describe --tags --always --dirty) && \
    REVISION=$(git rev-parse --short HEAD) && \
    BRANCH=$(git rev-parse --abbrev-ref HEAD) && \
    COMMIT_TIME=$(git log -1 --format=%ct) && \
    echo "${VERSION}" > /tmp/dnsproxy_version && \
    echo "${REVISION}" > /tmp/dnsproxy_revision && \
    go build -trimpath -v -ldflags "-s -w \
    -X github.com/AdguardTeam/dnsproxy/internal/version.version=${VERSION} \
    -X github.com/AdguardTeam/dnsproxy/internal/version.revision=${REVISION} \
    -X github.com/AdguardTeam/dnsproxy/internal/version.branch=${BRANCH} \
    -X github.com/AdguardTeam/dnsproxy/internal/version.committime=${COMMIT_TIME}" \
    -o /usr/local/bin/dnsproxy .

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
# Unbound version Latest — extract version string and save for label injection
RUN wget https://www.nlnetlabs.nl/downloads/unbound/unbound-latest.tar.gz \
    && tar -xzf unbound-latest.tar.gz \
    && rm unbound-latest.tar.gz \
    && UNBOUND_DIR=$(ls -d unbound-*/ | head -n1) \
    && UNBOUND_VERSION=$(echo "$UNBOUND_DIR" | sed 's/unbound-//;s|/||') \
    && echo "${UNBOUND_VERSION}" > /tmp/unbound_version \
    && cd "$UNBOUND_DIR" \
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

# Inject component versions captured in builder stages as build args, then as labels
ARG ADGUARDHOME_VERSION="edge"
ARG DNSPROXY_VERSION="unknown"
ARG DNSPROXY_REVISION="unknown"
ARG UNBOUND_VERSION="unknown"
ARG BUILD_DATE
ARG VCS_REF
ARG BRANCH

LABEL maintainer="andrianey"
LABEL name="adguardhome-doh-dot-wolfi-hardened"
LABEL description="Hardened AdGuard Home with DoT/DoH support using dnsproxy, Unbound, Valkey on Wolfi"
LABEL org.opencontainers.image.source="https://github.com/andrianey/adguardhomedotdoh"
LABEL org.opencontainers.image.title="AdGuard Home DoH/DoT (Hardened-Wolfi)"
LABEL org.opencontainers.image.description="Maximum security: Wolfi base + non-root + source builds"

# OCI standard labels
LABEL org.opencontainers.image.title="AdGuardHome DoH/DoT"
LABEL org.opencontainers.image.description="AdGuard Home with Unbound + dnsproxy on Wolfi"
LABEL org.opencontainers.image.source="https://gitlab.com/andrianey/adguardhomedotdoh"
LABEL org.opencontainers.image.licenses="MIT"
LABEL org.opencontainers.image.created="${BUILD_DATE}"
LABEL org.opencontainers.image.revision="${VCS_REF}"
LABEL org.opencontainers.image.ref.name="${BRANCH}"

# Component version labels (inspectable via: docker inspect <image> | grep label)
LABEL org.label-schema.adguardhome.version="${ADGUARDHOME_VERSION}"
LABEL org.label-schema.dnsproxy.version="${DNSPROXY_VERSION}"
LABEL org.label-schema.dnsproxy.revision="${DNSPROXY_REVISION}"
LABEL org.label-schema.unbound.version="${UNBOUND_VERSION}"

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
# Copy version files from builder stages
COPY --from=builder_dnsproxy /tmp/dnsproxy_version /tmp/dnsproxy_version
COPY --from=builder_dnsproxy /tmp/dnsproxy_revision /tmp/dnsproxy_revision
COPY --from=builder_unbound /tmp/unbound_version /tmp/unbound_version

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
    && setcap 'cap_net_bind_service=+ep' /usr/local/bin/dnsproxy && \
    /usr/sbin/unbound -V 2>&1 | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1 > /tmp/unbound_version || echo "unknown" > /tmp/unbound_version

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