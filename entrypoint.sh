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
chmod 700 /opt/adguardhome/work

# 1.5. Start Valkey (Redis replacement)
echo "[1.5/6] Starting Valkey (Redis compatible)..."
mkdir -p /var/run/redis
# Run valkey, listening on unix socket only
valkey-server --unixsocket /var/run/redis/redis.sock --unixsocketperm 777 --port 0 --save "" --appendonly no --maxmemory 100mb --maxmemory-policy allkeys-lru --daemonize yes

# Wait for valkey socket to be ready
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

# 2. Initialize Unbound Anchor (Required for DNSSEC)
if [ ! -f /var/lib/unbound/root.key ]; then
    echo "       Initializing DNSSEC root key..."
    /usr/sbin/unbound-anchor -4 -r /var/lib/unbound/root.hints -a /var/lib/unbound/root.key || true
fi

# 3. Start Unbound (DNS resolver with DNSSEC validation)
echo "[2/6] Starting Unbound DNS resolver..."
# Run unbound in background
/usr/sbin/unbound -d ${UNBOUND_DEBUG:+-v} &
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

# 3. Start dnsproxy (DoH/DoT upstream)
echo "[3/6] Starting dnsproxy (DoH/DoT upstream)..."
# Default Upstreams (Cloudflare) if not provided
DNSPROXY_UPSTREAM=${DNSPROXY_UPSTREAM:-"tls://1.1.1.1 tls://1.0.0.1 https://1.1.1.1/dns-query https://1.0.0.1/dns-query"}
# Sanitize: Replace commas with spaces
DNSPROXY_UPSTREAM=$(echo "$DNSPROXY_UPSTREAM" | tr ',' ' ')
# Additional Flags
DNSPROXY_FLAGS=${DNSPROXY_FLAGS:-"--verbose"}

# Build Upstream Arguments
UPSTREAM_ARGS=""
for u in $DNSPROXY_UPSTREAM; do
    UPSTREAM_ARGS="$UPSTREAM_ARGS -u $u"
done

echo "       Configured Upstreams: $DNSPROXY_UPSTREAM"

/usr/local/bin/dnsproxy \
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

# 5. Show service status
echo "[5/6] Services started:"
echo "       - Valkey:     Running (Unix Socket)"
echo "       - Unbound:    PID $UNBOUND_PID (port 5335)"
echo "       - dnsproxy:   PID $DNSPROXY_PID (port 8053)"

# 6. Start AdGuard Home (foreground)
echo "[6/6] Starting AdGuard Home..."
echo "============================================"
echo ""

exec /opt/adguardhome/AdGuardHome \
    --no-check-update \
    -c /opt/adguardhome/conf/AdGuardHome.yaml \
    -w /opt/adguardhome/work \
    "$@"
