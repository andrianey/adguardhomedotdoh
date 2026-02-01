#!/bin/sh
set -e

# 1. (Optional) Run Unbound
# Ensure port is NOT 53 in unbound.conf (e.g., 5335)
su-exec adguard:adguard /usr/sbin/unbound -p -v -d &
/usr/sbin/unbound-anchor -4 -r /var/lib/unbound/root.hints -a /var/lib/unbound/root.key || true

# 2. Run Cloudflare DNS (Cloudflared)
su-exec adguard:adguard /usr/local/bin/cloudflared proxy-dns --port 5053 --upstream https://1.1.1.1/dns-query --upstream https://1.0.0.1/dns-query --upstream https://2606:4700:4700::1111/dns-query --upstream https://2606:4700:4700::1001/dns-query &

# 3. Run Stubby
su-exec adguard:adguard /usr/bin/stubby -C /etc/stubby/stubby.yml -l &

# 4. Fix permissions for AdGuard Home work directory (if mounted as volume)
# This ensures that if the previous run was as root (setup mode), the files are now owned by adguard
chown -R adguard:adguard /opt/adguardhome

# 5. Run AdGuardHome
# Logic: First run requires root for the "Wizard". Subsequent runs (safe mode) use non-root.
if [ ! -f /opt/adguardhome/conf/AdGuardHome.yaml ]; then
    echo "---------------------------------------------------"
    echo " FIRST RUN DETECTED: STARTING AS ROOT FOR SETUP WIZARD "
    echo " Please access http://localhost:3000 to configure."
    echo " NOTE: After setup is complete, RESTART this container"
    echo "       to switch to hardened non-root mode."
    echo "---------------------------------------------------"
    exec /opt/adguardhome/AdGuardHome --no-check-update -c /opt/adguardhome/conf/AdGuardHome.yaml -w /opt/adguardhome/work
else
    echo "---------------------------------------------------"
    echo " CONFIG FOUND: STARTING IN HARDENED NON-ROOT MODE "
    echo "---------------------------------------------------"
    exec su-exec adguard:adguard /opt/adguardhome/AdGuardHome --no-check-update -c /opt/adguardhome/conf/AdGuardHome.yaml -w /opt/adguardhome/work
fi