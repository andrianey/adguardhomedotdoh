#!/bin/sh
set -e

echo "============================================"
echo "  AdGuardHome DoT/DoH Stack - Wolfi Edition"
echo "  Running as user: $(whoami)"
echo "============================================"

# 1. Environment Check
echo "[1/6] Checking environment..."
# Note: As we run as non-root, we cannot create global directories or mknod here.
# Directories should be pre-created in Dockerfile or mounted with correct permissions.
# Requisite: Volumes mounted to /opt/adguardhome/work must be writable by uid 1000.

if [ ! -w "/opt/adguardhome/work" ]; then
    echo "WARNING: /opt/adguardhome/work is not writable. Persistence may fail."
fi

# Ensure root.hints exists
if [ ! -f /var/lib/unbound/root.hints ]; then
    echo "       Downloading root.hints..."
    wget -qO /var/lib/unbound/root.hints https://www.internic.net/domain/named.root || \
    echo "       Warning: Could not download root.hints"
fi

# 2. Start Unbound (DNS resolver with DNSSEC validation)
echo "[2/6] Starting Unbound DNS resolver..."
# Run unbound in background
/usr/sbin/unbound -d &
UNBOUND_PID=$!
sleep 2

# Initialize unbound anchor for DNSSEC (if root.key doesn't exist)
if [ ! -f /var/lib/unbound/root.key ]; then
    echo "       Initializing DNSSEC root key..."
    # unbound-anchor might need write access to /var/lib/unbound
    /usr/sbin/unbound-anchor -4 -r /var/lib/unbound/root.hints -a /var/lib/unbound/root.key 2>/dev/null || true
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
echo "       - Unbound:    PID $UNBOUND_PID"
echo "       - Cloudflared: PID $CLOUDFLARED_PID (port 5053)"
echo "       - Stubby:     PID $STUBBY_PID (port 8053)"

# 5.5. Generate default config if missing (to bypass root check)
CONF_FILE="/opt/adguardhome/conf/AdGuardHome.yaml"
if [ ! -f "$CONF_FILE" ]; then
    echo "[5.5/6] Generating default AdGuardHome.yaml..."
    cat <<EOF > "$CONF_FILE"
http:
  address: 0.0.0.0:3000
dns:
  bind_hosts:
  - 0.0.0.0
  port: 53
  upstream_dns:
  - 127.0.0.1:53
  bootstrap_dns:
  - 1.1.1.1
  - 8.8.8.8
schema_version: 27
EOF
fi

# 6. Start AdGuard Home (foreground)
echo "[6/6] Starting AdGuard Home..."
echo "============================================"
echo ""

exec /opt/adguardhome/AdGuardHome \
    --no-check-update \
    -c /opt/adguardhome/conf/AdGuardHome.yaml \
    -w /opt/adguardhome/work \
    "$@"