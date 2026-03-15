#!/bin/sh
set -e

echo "============================================"
echo "  AdGuardHome DoT/DoH Stack"
echo "============================================"

# 1. Fix Permissions (Agar warning 0700 di log hilang)
echo "[1/7] Setting up directories and permissions..."
mkdir -p /opt/adguardhome/work
chmod 700 /opt/adguardhome/work

# 2. Start Valkey (Redis replacement)
echo "[2/7] Starting Valkey (Redis compatible)..."
mkdir -p /var/run/redis
valkey-server --unixsocket /var/run/redis/redis.sock --unixsocketperm 777 --port 0 --save "" --appendonly no --maxmemory 100mb --maxmemory-policy allkeys-lru --daemonize yes
VALKEY_PID=$!

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

# 3. Run crontab service
echo "[3/7] Starting cron service..."
/usr/sbin/crond -L /var/log/cron.log

# 4. Run Unbound
echo "[4/7] Starting Unbound DNS resolver..."
# Pastikan di unbound.conf kamu port-nya BUKAN 53 (misal 5335)
if [ ! -f /var/lib/unbound/root.key ]; then
    echo "       Initializing DNSSEC root key..."
    /usr/sbin/unbound-anchor -4 -r /var/lib/unbound/root.hints -a /var/lib/unbound/root.key || true
fi
# Run with -vv for verbose output to see Redis/Valkey connection
echo "       Starting Unbound with cachedb (Valkey backend)..."
/usr/sbin/unbound -vv -d &
UNBOUND_PID=$!
# Wait a bit longer for Unbound to initialize and connect to Valkey
sleep 2
if ! kill -0 $UNBOUND_PID 2>/dev/null; then
    echo "ERROR: Unbound failed to start"
    exit 1
fi
echo "       Unbound started (check logs above for Valkey connection)"

# 5. Run dnsproxy (DoH/DoT upstream)
echo "[5/7] Starting dnsproxy (DoH/DoT upstream)..."
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
sleep 2
if ! kill -0 $DNSPROXY_PID 2>/dev/null; then
    echo "ERROR: dnsproxy failed to start"
    exit 1
fi

# Show service status
echo "[6/7] Services started:"
echo "       - Valkey:      Unix socket /var/run/redis/redis.sock"
echo "       - Unbound:     PID $UNBOUND_PID (port 5335) → connected to Valkey"
echo "       - dnsproxy:    PID $DNSPROXY_PID (port 8053)"

# 7. Run AdGuardHome
echo "[7/7] Starting AdGuard Home..."
echo "============================================"
echo ""
# Menghapus flag -h 0.0.0.0 karena AdGuard biasanya baca binding dari yaml.
# Jika tetap ingin dipaksa, pastikan port 53 tidak bentrok dengan Unbound.
/opt/adguardhome/AdGuardHome --no-check-update -c /opt/adguardhome/conf/AdGuardHome.yaml -w /opt/adguardhome/work

exec "$@"