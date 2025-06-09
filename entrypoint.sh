#!/bin/bash
set -e

# Create necessary directories if they don't exist
mkdir -p /var/lib/motioneye /var/log/motion /var/run/motion

# Set proper permissions
chown -R root:root /var/lib/motioneye /var/log/motion /var/run/motion
chmod -R 755 /var/lib/motioneye /var/log/motion /var/run/motion

# Start supervisord
exec /usr/bin/supervisord -n -c /etc/supervisord.conf 