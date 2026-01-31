#!/bin/bash
set -e

echo "============================================"
echo "  AdGuardHome DoT/DoH Stack - Wolfi Edition"
echo "============================================"

# 1. Fix Permissions
echo "[1/6] Setting up directories and permissions..."
mkdir -p /opt/adguardhome/work
mkdir -p /opt/adguardhome/conf
chmod 700 /opt/adguardhome/work

# 2. Start Unbound (DNS resolver with DNSSEC validation)
echo "[2/6] Starting Unbound DNS resolver..."
# Run unbound in background
/usr/sbin/unbound -d -v &
UNBOUND_PID=$!
sleep 1

# Initialize unbound anchor for DNSSEC (if root.key doesn't exist)
if [ ! -f /var/lib/unbound/root.key ]; then
    echo "       Initializing DNSSEC root key..."
    /usr/sbin/unbound-anchor -4 -r /var/lib/unbound/root.hints -a /var/lib/unbound/root.key || true
fi

# 3. Start Cloudflared (DNS-over-HTTPS proxy)
echo "[3/6] Starting Cloudflared DoH proxy..."
/usr/local/bin/cloudflared proxy-dns \
    --port 5053 \
    --upstream https://1.1.1.1/dns-query \
    --upstream https://1.0.0.1/dns-query \
    --upstream https://2606:4700:4700::1111/dns-query \
    --upstream https://2606:4700:4700::1001/dns-query &
CLOUDFLARED_PID=$!
sleep 1

# 4. Start Stubby (DNS-over-TLS proxy)
echo "[4/6] Starting Stubby DoT proxy..."
/usr/local/bin/stubby -C /etc/stubby/stubby.yml -l &
STUBBY_PID=$!
sleep 1

# 5. Show service status
echo "[5/6] Services started:"
echo "       - Unbound:    PID $UNBOUND_PID (port 53)"
echo "       - Cloudflared: PID $CLOUDFLARED_PID (port 5053)"
echo "       - Stubby:     PID $STUBBY_PID (port 8053)"

# 6. Start AdGuard Home (foreground)
echo "[6/6] Starting AdGuard Home..."
echo "============================================"
echo ""

exec /opt/adguardhome/AdGuardHome \
    --no-check-update \
    -c /opt/adguardhome/conf/AdGuardHome.yaml \
    -w /opt/adguardhome/work \
    "$@"