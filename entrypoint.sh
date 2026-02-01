#!/bin/sh
set -e

# 1. (Optional) Run Unbound
# Ensure port is NOT 53 in unbound.conf (e.g., 5335)
/usr/sbin/unbound -p -v -d &
/usr/sbin/unbound-anchor -4 -r /var/lib/unbound/root.hints -a /var/lib/unbound/root.key || true

# 2. Run Cloudflare DNS (Cloudflared)
/usr/local/bin/cloudflared proxy-dns --port 5053 --upstream https://1.1.1.1/dns-query --upstream https://1.0.0.1/dns-query --upstream https://2606:4700:4700::1111/dns-query --upstream https://2606:4700:4700::1001/dns-query &

# 3. Run Stubby
/usr/bin/stubby -C /etc/stubby/stubby.yml -l &

# 4. Run AdGuardHome
# Check/Generate config to bypass root check (fixes "must run as administrator" error)
if [ ! -f /opt/adguardhome/conf/AdGuardHome.yaml ]; then
    echo "Config file not found. Creating minimal config to bypass root check..."
    cat <<EOF > /opt/adguardhome/conf/AdGuardHome.yaml
http:
  address: 0.0.0.0:80
dns:
  bind_hosts:
  - 0.0.0.0
  port: 53
EOF
fi

# Removed -h 0.0.0.0 as AdGuard usually reads binding from yaml.
/opt/adguardhome/AdGuardHome --no-check-update -c /opt/adguardhome/conf/AdGuardHome.yaml -w /opt/adguardhome/work

exec "$@"