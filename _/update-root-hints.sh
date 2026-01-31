#!/bin/bash
# Script to update root.hints for Unbound
# Run this manually or via external cron/scheduler every 6 months

set -e

CONTAINER_NAME="${1:-adguardhome}"

echo "Updating root.hints in container: $CONTAINER_NAME"

docker exec "$CONTAINER_NAME" sh -c '
    wget -qO /tmp/root.hints https://www.internic.net/domain/named.root && \
    mv /tmp/root.hints /var/lib/unbound/root.hints && \
    echo "root.hints updated successfully"
'

echo "Done!"
