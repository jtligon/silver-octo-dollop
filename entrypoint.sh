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

# Handle SSL setup
if [ "${MOTIONEYE_SSL_ENABLED}" = "true" ]; then
    # Check if SSL certificates exist
    if [ ! -f "${MOTIONEYE_SSL_CERT}" ] || [ ! -f "${MOTIONEYE_SSL_KEY}" ]; then
        echo "Generating self-signed SSL certificates..."
        openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
            -keyout "${MOTIONEYE_SSL_KEY}" \
            -out "${MOTIONEYE_SSL_CERT}" \
            -subj "/C=US/ST=State/L=City/O=Organization/CN=localhost"
    fi
    
    # Set proper permissions for SSL certificates
    chmod 600 "${MOTIONEYE_SSL_KEY}"
    chmod 644 "${MOTIONEYE_SSL_CERT}"
fi

# Update nginx configuration
sed -i "s/listen 8765/listen ${MOTIONEYE_PORT}/" /etc/nginx/nginx.conf
sed -i "s/\${MOTIONEYE_SSL_CERT}/${MOTIONEYE_SSL_CERT}/g" /etc/nginx/nginx.conf
sed -i "s/\${MOTIONEYE_SSL_KEY}/${MOTIONEYE_SSL_KEY}/g" /etc/nginx/nginx.conf
sed -i "s/\$ssl_enabled/${MOTIONEYE_SSL_ENABLED}/g" /etc/nginx/nginx.conf

# Start supervisord
exec /usr/bin/supervisord -n -c /etc/supervisord.conf 