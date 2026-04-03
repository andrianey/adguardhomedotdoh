# ============================================
# Stage 1: Extract AdGuard Home from official image (Edge/Nightly)
# ============================================
FROM adguard/adguardhome:edge AS adguard-source

# ============================================
# Stage 2: Build dnsproxy from source (Fixes CVEs)
# ============================================
FROM golang:alpine3.21 AS builder_dnsproxy

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
# Extract version info from git and build with embedded metadata
RUN --mount=type=cache,target=/go/pkg/mod \
    --mount=type=cache,target=/root/.cache/go-build \
    VERSION=$(git describe --tags --always --dirty) && \
    REVISION=$(git rev-parse --short HEAD) && \
    BRANCH=$(git rev-parse --abbrev-ref HEAD) && \
    COMMIT_TIME=$(git log -1 --format=%ct) && \
    go build -trimpath -v -ldflags "-s -w \
    -X github.com/AdguardTeam/dnsproxy/internal/version.version=${VERSION} \
    -X github.com/AdguardTeam/dnsproxy/internal/version.revision=${REVISION} \
    -X github.com/AdguardTeam/dnsproxy/internal/version.branch=${BRANCH} \
    -X github.com/AdguardTeam/dnsproxy/internal/version.committime=${COMMIT_TIME}" \
    -o /usr/local/bin/dnsproxy . && \
    echo "$VERSION" > /tmp/dnsproxy_version

# Download root.hints for Unbound
RUN wget -O /tmp/root.hints https://www.internic.net/domain/named.root

# ============================================
# Stage 3: Unbound Builder (Compiled with Redis/Valkey support)
# ============================================
FROM alpine:3.21 AS builder_unbound

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
    --with-pidfile=/var/lib/unbound/unbound.pid \
    && make -j$(nproc) \
    && make install DESTDIR=/tmp/unbound/install

# ============================================
# Stage 4: Final image with Alpine 3.21
# ============================================
FROM alpine:3.21

# Set labels for the image
LABEL maintainer="andrianey"
LABEL description="AdGuard Home with DoH/DoT support (dnsproxy, Unbound, Valkey)"
LABEL org.opencontainers.image.source="https://github.com/andrianey/adguardhomedotdoh"
LABEL org.opencontainers.image.title="AdGuard Home DoH/DoT (Hardened)"
LABEL org.opencontainers.image.description="Hardened non-root AdGuard Home with Unbound, dnsproxy, and Valkey"

# 1. Install dependencies
RUN apk add --no-cache \
    libevent \
    hiredis \
    valkey \
    expat \
    ca-certificates \
    tzdata \
    libcap \
    su-exec \
    tini \
    && rm -rf /var/cache/apk/*

# 2. Copy AdGuard Home binary from the official image
COPY --from=adguard-source /opt/adguardhome/AdGuardHome /opt/adguardhome/AdGuardHome

# 3. Create non-root user
RUN adduser -D -u 1000 adguard

# 4. Setup AdGuard Home directories and permissions
RUN mkdir -p /opt/adguardhome/conf /opt/adguardhome/work && \
    mkdir -p /var/log && \
    chown -R adguard:adguard /opt/adguardhome && \
    chown -R adguard:adguard /var/log && \
    chmod 700 /opt/adguardhome/work && \
    setcap 'cap_net_bind_service=+ep' /opt/adguardhome/AdGuardHome

# 5. Copy dnsproxy from builder
COPY --from=builder_dnsproxy /usr/local/bin/dnsproxy /usr/local/bin/dnsproxy
COPY --from=builder_dnsproxy /tmp/dnsproxy_version /tmp/dnsproxy_version
RUN chown adguard:adguard /usr/local/bin/dnsproxy && \
    chmod 755 /usr/local/bin/dnsproxy && \
    setcap 'cap_net_bind_service=+ep' /usr/local/bin/dnsproxy

# 6. Setup Unbound (Copy from builder)
COPY --from=builder_unbound /tmp/unbound/install/usr/sbin/unbound /usr/sbin/unbound
COPY --from=builder_unbound /tmp/unbound/install/usr/sbin/unbound-anchor /usr/sbin/unbound-anchor
COPY --from=builder_unbound /tmp/unbound/install/usr/sbin/unbound-control /usr/sbin/unbound-control
COPY --from=builder_unbound /tmp/unbound/install/usr/sbin/unbound-checkconf /usr/sbin/unbound-checkconf
COPY --from=builder_unbound /tmp/unbound/install/usr/lib/libunbound.so* /usr/lib/
# Copy root hints from dnsproxy builder (helper)
COPY --from=builder_dnsproxy /tmp/root.hints /var/lib/unbound/root.hints

RUN mkdir -p /var/lib/unbound/ /etc/unbound/ && \
    chown -R adguard:adguard /var/lib/unbound /etc/unbound && \
    setcap 'cap_net_bind_service=+ep' /usr/sbin/unbound && \
    /usr/sbin/unbound -V 2>&1 | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1 > /tmp/unbound_version || echo "unknown" > /tmp/unbound_version

COPY unbound/unbound.conf /etc/unbound/unbound.conf

# 7. Entrypoint script (Ensure it uses /bin/sh)
COPY entrypoint.sh /opt/entrypoint.sh
RUN chmod +x /opt/entrypoint.sh && \
    sed -i 's/\r$//' /opt/entrypoint.sh

# Expose ports
EXPOSE 53/tcp 53/udp 67/udp 68/udp 80/tcp 443/tcp 443/udp 853/tcp 853/udp 3000/tcp 5443/tcp 5443/udp

# Volumes
VOLUME ["/opt/adguardhome/conf", "/opt/adguardhome/work"]

# Run as root initially to allow entrypoint to drop privileges
USER root

ENTRYPOINT ["/sbin/tini", "--", "/opt/entrypoint.sh"]