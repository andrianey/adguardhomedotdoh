#!/bin/bash
set -e

cleanup() {
    echo "==> Shutting down services..."
    [ -n "$DNSPROXY_PID" ] && kill "$DNSPROXY_PID" 2>/dev/null || true
    [ -n "$UNBOUND_PID" ] && kill "$UNBOUND_PID" 2>/dev/null || true
    valkey-cli -s /var/run/redis/redis.sock shutdown nosave 2>/dev/null || true
}
trap cleanup TERM INT

echo "============================================"
echo "  AdGuardHome DoT/DoH Stack - Wolfi Edition"
echo "============================================"

# 1. Fix Permissions
echo "[1/6] Setting up directories and permissions..."
mkdir -p /opt/adguardhome/work
mkdir -p /opt/adguardhome/conf
mkdir -p /var/log
chown -R adguard:adguard /opt/adguardhome
chown -R adguard:adguard /var/lib/unbound
chown -R adguard:adguard /var/log
chmod 700 /opt/adguardhome/work

# 1.2. Initialize unbound anchor for DNSSEC (Required by Stubby)
if [ ! -f /var/lib/unbound/root.key ]; then
    echo "       Initializing DNSSEC root key..."
    LD_LIBRARY_PATH="/usr/local/lib" /usr/sbin/unbound-anchor -4 -r /var/lib/unbound/root.hints -a /var/lib/unbound/root.key || true
    chown adguard:adguard /var/lib/unbound/root.key || true
fi

# 1.5. Start Redis (RAM Cache) using Valkey
echo "[2/7] Starting Valkey (Redis compatible)..."
mkdir -p /var/run/redis
chown adguard:adguard /var/run/redis
# Run valkey as adguard user, listening on unix socket only
su-exec adguard valkey-server --unixsocket /var/run/redis/redis.sock --unixsocketperm 770 --port 0 --save "" --appendonly no --maxmemory 100mb --maxmemory-policy allkeys-lru --daemonize yes

echo "       Waiting for Valkey socket..."
for i in $(seq 1 10); do
    if [ -S /var/run/redis/redis.sock ]; then
        echo "       Valkey socket is ready."
        break
    fi
    sleep 1
done

if [ ! -S /var/run/redis/redis.sock ]; then
    echo "ERROR: Valkey failed to create socket"
    exit 1
fi

# 3. Start dnsproxy (DoH/DoT upstream)
echo "[3/7] Starting dnsproxy (DoH/DoT upstream)..."
# Run dnsproxy as adguard
# Upstreams: Cloudflare DoT and DoH
# Default Upstreams (Cloudflare) if not provided
DNSPROXY_UPSTREAM=${DNSPROXY_UPSTREAM:-"tls://1.1.1.1 tls://1.0.0.1 https://1.1.1.1/dns-query https://1.0.0.1/dns-query"}
# Sanitize: Replace commas with spaces to support comma-separated lists
DNSPROXY_UPSTREAM=$(echo "$DNSPROXY_UPSTREAM" | tr ',' ' ')
# Additional Flags
DNSPROXY_FLAGS=${DNSPROXY_FLAGS:-"--verbose"}

# Build Upstream Arguments
UPSTREAM_ARGS=""
for u in $DNSPROXY_UPSTREAM; do
    UPSTREAM_ARGS="$UPSTREAM_ARGS -u $u"
done

echo "       Configured Upstreams: $DNSPROXY_UPSTREAM"

su-exec adguard /usr/local/bin/dnsproxy \
    -l 127.0.0.1 \
    -p 8053 \
    --cache-size=0 \
    $UPSTREAM_ARGS \
    $DNSPROXY_FLAGS &
DNSPROXY_PID=$!
echo "       Waiting for dnsproxy to be ready..."
for i in $(seq 1 10); do
    if nc -z 127.0.0.1 8053 2>/dev/null; then
        echo "       dnsproxy is ready."
        break
    fi
    if ! kill -0 $DNSPROXY_PID 2>/dev/null; then
        echo "ERROR: dnsproxy failed to start"
        exit 1
    fi
    sleep 1
done

# 4. Start Unbound (DNS resolver with DNSSEC validation)
echo "[4/7] Starting Unbound DNS resolver..."
# Run unbound in background as adguard
su-exec adguard /usr/sbin/unbound -d ${UNBOUND_DEBUG:+-v} &
UNBOUND_PID=$!
echo "       Waiting for Unbound to be ready..."
for i in $(seq 1 15); do
    if nc -z 127.0.0.1 5335 2>/dev/null; then
        echo "       Unbound is ready."
        break
    fi
    if ! kill -0 $UNBOUND_PID 2>/dev/null; then
        echo "ERROR: Unbound failed to start"
        exit 1
    fi
    sleep 1
done

# 5. Show service status
echo "[5/7] All services started:"
echo "       - Valkey (Cache):     Running (Unix Socket)"
echo "       - Unbound (Resolver): PID $UNBOUND_PID (port 5335)"
echo "       - dnsproxy (Upstream): PID $DNSPROXY_PID (port 8053)"


# 6. Start AdGuard Home
# Logic: If config exists, run as non-root. If not (setup), run as root.
CONFIG_FILE="/opt/adguardhome/conf/AdGuardHome.yaml"

if [ ! -f "$CONFIG_FILE" ]; then
    echo "[7/7] Setup mode detected (no config). Starting AdGuard Home as ROOT..."
    echo "      IMPORTANT: Complete the setup wizard, then RESTART this container to switch to hardened non-root mode."
    
    exec /opt/adguardhome/AdGuardHome \
        --no-check-update \
        -c "$CONFIG_FILE" \
        -w /opt/adguardhome/work \
        "$@"
else
    echo "[7/7] Configuration found. Starting AdGuard Home as adguard (non-root)..."
    
    # Fix ownership of files created by Root during setup
    echo "      Enforcing file permissions..."
    chown -R adguard:adguard /opt/adguardhome/conf
    chown -R adguard:adguard /opt/adguardhome/work
    
    exec su-exec adguard /opt/adguardhome/AdGuardHome \
        --no-check-update \
        -c "$CONFIG_FILE" \
        -w /opt/adguardhome/work \
        "$@"
fi