#!/bin/sh
set -e

echo "============================================"
echo "  AdGuardHome DoT/DoH Stack - Alpine Edition"
echo "============================================"

# 1. Fix Permissions
echo "[1/6] Setting up directories and permissions..."
mkdir -p /opt/adguardhome/work
mkdir -p /opt/adguardhome/conf
mkdir -p /var/log
chown -R adguard:adguard /opt/adguardhome
chown -R adguard:adguard /var/lib/unbound
chown -R adguard:adguard /etc/stubby
chown -R adguard:adguard /var/log
chmod 700 /opt/adguardhome/work

# 1.5. Start Valkey (Redis replacement)
echo "[2/7] Starting Valkey (Redis compatible)..."
mkdir -p /var/run/redis
chown adguard:adguard /var/run/redis
# Run valkey as adguard user, listening on unix socket only
# Alpine's su-exec takes 'user:group' or just 'user'
su-exec adguard valkey-server --unixsocket /var/run/redis/redis.sock --unixsocketperm 770 --port 0 --save "" --appendonly no --maxmemory 100mb --maxmemory-policy allkeys-lru --daemonize yes
sleep 1

# 2. Initialize Unbound Anchor (Required for DNSSEC)
if [ ! -f /var/lib/unbound/root.key ]; then
    echo "[2.5/7] Initializing DNSSEC root key..."
    su-exec adguard /usr/sbin/unbound-anchor -4 -r /var/lib/unbound/root.hints -a /var/lib/unbound/root.key || true
fi

# 3. Start Cloudflared (DNS-over-HTTPS proxy)
echo "[3/7] Starting Cloudflared DoH proxy..."
su-exec adguard /usr/local/bin/cloudflared proxy-dns \
    --port 5053 \
    --upstream https://1.1.1.1/dns-query \
    --upstream https://1.0.0.1/dns-query \
    --upstream https://2606:4700:4700::1111/dns-query \
    --upstream https://2606:4700:4700::1001/dns-query &
CLOUDFLARED_PID=$!
sleep 1

# 4. Start Stubby (DNS-over-TLS proxy)
echo "[4/7] Starting Stubby DoT proxy..."
su-exec adguard /usr/bin/stubby -C /etc/stubby/stubby.yml -l &
STUBBY_PID=$!
sleep 1

# 5. Start Unbound DNS Resolver
echo "[5/7] Starting Unbound DNS resolver..."
su-exec adguard /usr/sbin/unbound -d -v &
UNBOUND_PID=$!
sleep 1

# 5.5. Show status
echo "[6/7] Services started:"
echo "       - Unbound:    PID $UNBOUND_PID (port 5335)"
echo "       - Cloudflared: PID $CLOUDFLARED_PID (port 5053)"
echo "       - Stubby:     PID $STUBBY_PID (port 8053)"

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