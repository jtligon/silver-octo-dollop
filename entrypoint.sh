#!/bin/bash
set -e

# Create necessary directories if they don't exist
mkdir -p ${MOTIONEYE_MEDIA_PATH} /var/log/motion ${MOTIONEYE_RUN_PATH}

# Set proper permissions
chown -R root:root ${MOTIONEYE_MEDIA_PATH} /var/log/motion ${MOTIONEYE_RUN_PATH}
chmod -R 755 ${MOTIONEYE_MEDIA_PATH} /var/log/motion ${MOTIONEYE_RUN_PATH}

# Generate motioneye.conf from environment variables
cat > ${MOTIONEYE_CONF_PATH}/motioneye.conf << EOF
[main]
log_level = ${MOTIONEYE_LOG_LEVEL}
log_file = ${MOTIONEYE_LOG_FILE}
conf_path = ${MOTIONEYE_CONF_PATH}
run_path = ${MOTIONEYE_RUN_PATH}
media_path = ${MOTIONEYE_MEDIA_PATH}
port = ${MOTIONEYE_PORT}
EOF

# Update nginx configuration with the correct port
sed -i "s/listen 8765/listen ${MOTIONEYE_PORT}/" /etc/nginx/nginx.conf

# Start supervisord
exec /usr/bin/supervisord -n -c /etc/supervisord.conf 