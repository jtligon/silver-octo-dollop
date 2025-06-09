# Use Fedora as base image since it's commonly used with bootc
FROM registry.fedoraproject.org/fedora:latest

# Set environment variables
ENV MOTIONEYE_VERSION=0.42.1
ENV PYTHONUNBUFFERED=1

# MotionEye configuration environment variables
ENV MOTIONEYE_PORT=8765
ENV MOTIONEYE_USERNAME=admin
ENV MOTIONEYE_PASSWORD=admin
ENV MOTIONEYE_CONF_PATH=/etc/motioneye
ENV MOTIONEYE_RUN_PATH=/var/run/motion
ENV MOTIONEYE_MEDIA_PATH=/var/lib/motioneye
ENV MOTIONEYE_LOG_LEVEL=info
ENV MOTIONEYE_LOG_FILE=/var/log/motion/motioneye.log

# SSL/TLS environment variables
ENV MOTIONEYE_SSL_CERT=/etc/motioneye/ssl/cert.pem
ENV MOTIONEYE_SSL_KEY=/etc/motioneye/ssl/key.pem
ENV MOTIONEYE_SSL_ENABLED=false

# Monitoring environment variables
ENV MOTIONEYE_METRICS_PORT=9090
ENV MOTIONEYE_METRICS_ENABLED=false
ENV MOTIONEYE_LOG_RETENTION_DAYS=30

# Install system dependencies
RUN dnf update -y && \
    dnf install -y \
    python3-pip \
    python3-devel \
    v4l-utils \
    ffmpeg \
    motion \
    nginx \
    supervisor \
    openssl \
    prometheus-node-exporter \
    logrotate \
    && dnf clean all

# Create necessary directories
RUN mkdir -p /var/lib/motioneye /var/log/motion /var/run/motion /etc/motioneye/ssl /etc/motioneye/metrics

# Install motioneye and monitoring dependencies
RUN pip3 install motioneye==${MOTIONEYE_VERSION} \
    prometheus-client \
    python-json-logger

# Copy configuration files
COPY config/motioneye.conf /etc/motioneye/motioneye.conf
COPY config/nginx.conf /etc/nginx/nginx.conf
COPY config/supervisord.conf /etc/supervisord.conf
COPY config/logrotate.conf /etc/logrotate.d/motioneye
COPY config/prometheus.yml /etc/motioneye/metrics/prometheus.yml

# Expose ports
EXPOSE ${MOTIONEYE_PORT}
EXPOSE 8766
EXPOSE ${MOTIONEYE_METRICS_PORT}

# Set up entrypoint
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

# Set up volumes
VOLUME ["/var/lib/motioneye", "/var/log/motion", "/etc/motioneye/ssl", "/etc/motioneye/metrics"]

# Set up healthcheck
HEALTHCHECK --interval=30s --timeout=10s --start-period=5s --retries=3 \
    CMD curl -f http://localhost:${MOTIONEYE_PORT}/ || exit 1

ENTRYPOINT ["/entrypoint.sh"] 