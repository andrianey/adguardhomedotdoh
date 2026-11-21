# ============================================
# Stage 1: Extract AdGuard Home from official image (Edge/Nightly)
# ============================================
FROM adguard/adguardhome:edge AS adguard-source

# ============================================
# Stage 2: Build dnsproxy from source (Fixes CVEs)
# ============================================
FROM golang:1.27-alpine AS builder_dnsproxy

# Allow the toolchain to auto-upgrade if upstream go.mod requires a newer Go
ENV GOTOOLCHAIN=auto

RUN apk add --no-cache git

WORKDIR /src/dnsproxy
# Clone latest source and fetch all tags.
# Capture version metadata here, before go get/go mod tidy touch go.mod and
# go.sum: those edits dirty the work tree, which would append "-dirty" to
# git describe and leak into the version reported by the image and the README.
RUN git clone https://github.com/AdguardTeam/dnsproxy.git . && \
    git fetch --tags && \
    git pull origin master && \
    git describe --tags --always > /tmp/dnsproxy_version && \
    git rev-parse --short HEAD > /tmp/dnsproxy_revision && \
    git rev-parse --abbrev-ref HEAD > /tmp/dnsproxy_branch && \
    git log -1 --format=%ct > /tmp/dnsproxy_committime && \
    [ -s /tmp/dnsproxy_version ] && \
    [ -s /tmp/dnsproxy_revision ] && \
    [ -s /tmp/dnsproxy_branch ] && \
    [ -s /tmp/dnsproxy_committime ]
# Force update quic-go to fix CVE-2025-64702
RUN --mount=type=cache,target=/go/pkg/mod \
    --mount=type=cache,target=/root/.cache/go-build \
    go get github.com/quic-go/quic-go@latest && go mod tidy
# Extract version info from git and build with embedded metadata
RUN --mount=type=cache,target=/go/pkg/mod \
    --mount=type=cache,target=/root/.cache/go-build \
    VERSION=$(cat /tmp/dnsproxy_version) && \
    REVISION=$(cat /tmp/dnsproxy_revision) && \
    BRANCH=$(cat /tmp/dnsproxy_branch) && \
    COMMIT_TIME=$(cat /tmp/dnsproxy_committime) && \
    go build -trimpath -v -ldflags "-s -w \
    -X github.com/AdguardTeam/golibs/version.version=${VERSION} \
    -X github.com/AdguardTeam/golibs/version.revision=${REVISION} \
    -X github.com/AdguardTeam/golibs/version.branch=${BRANCH} \
    -X github.com/AdguardTeam/golibs/version.committime=${COMMIT_TIME}" \
    -o /usr/local/bin/dnsproxy .

# Download root.hints for Unbound
RUN wget -O /tmp/root.hints https://www.internic.net/domain/named.root

# ============================================
# Stage 3: Unbound Builder (Compiled with Redis/Valkey support)
# ============================================
FROM alpine:latest AS builder_unbound

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
# Stage 4: Final image (Alpine latest)
# ============================================
FROM alpine:latest

# Use alpine:latest so musl (and other libs) pick up the latest security fixes.
# APK_REFRESH is purely a cache key for this RUN layer.
ARG APK_REFRESH=none
RUN echo "Alpine package refresh: ${APK_REFRESH}" && \
    apk upgrade --no-cache && \
    apk add --no-cache --upgrade musl && \
    apk info -v musl

# Set labels for the image
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
LABEL org.opencontainers.image.title="AdGuard Home DoH/DoT (Hardened)"
LABEL org.opencontainers.image.description="Hardened non-root AdGuard Home with Unbound, dnsproxy, and Valkey"
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
    netcat-openbsd

# 2. Copy AdGuard Home binary from the official image
COPY --from=adguard-source /opt/adguardhome/AdGuardHome /opt/adguardhome/AdGuardHome

# Capture AdGuard Home version for CI/badge metadata (must never fail the build).
RUN AGH_OUT=$(/opt/adguardhome/AdGuardHome --version 2>&1 || true); \
    AGH_VER=$(printf '%s\n' "$AGH_OUT" | grep -oE 'v[0-9]+\.[0-9]+\.[0-9]+[^ ]*' | head -n1 || true); \
    [ -n "$AGH_VER" ] || AGH_VER=$(printf '%s\n' "$AGH_OUT" | grep -oE '[0-9]+\.[0-9]+\.[0-9]+[^ ]*' | head -n1 || true); \
    [ -n "$AGH_VER" ] || AGH_VER=$(printf '%s\n' "$AGH_OUT" | grep -m1 -E '[^[:space:]]' || true); \
    [ -n "$AGH_VER" ] || AGH_VER="unknown"; \
    printf '%s\n' "$AGH_VER" > /tmp/adguardhome_version; \
    echo "AdGuardHome version: $AGH_VER"

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
# The revision is written by the builder next to the version; without this
# COPY the CI probe reads nothing and the label falls back to "unknown".
COPY --from=builder_dnsproxy /tmp/dnsproxy_revision /tmp/dnsproxy_revision
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
    { /usr/sbin/unbound -V 2>&1 || true; } > /tmp/unbound_version.log && \
    sed -n 's/^[Vv]ersion[[:space:]]\+\([0-9][0-9.]*\).*/\1/p' /tmp/unbound_version.log | head -n 1 > /tmp/unbound_version && \
    { [ -s /tmp/unbound_version ] || grep -oE '[0-9]+\.[0-9]+\.[0-9]+' /tmp/unbound_version.log | head -n 1 > /tmp/unbound_version || true; } && \
    { [ -s /tmp/unbound_version ] || printf 'unknown\n' > /tmp/unbound_version; } && \
    rm -f /tmp/unbound_version.log

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