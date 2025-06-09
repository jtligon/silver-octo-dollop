# Use Fedora as base image since it's commonly used with bootc
FROM registry.fedoraproject.org/fedora:latest

# Set environment variables
ENV MOTIONEYE_VERSION=0.42.1
ENV PYTHONUNBUFFERED=1

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
    && dnf clean all

# Create necessary directories
RUN mkdir -p /var/lib/motioneye /var/log/motion /var/run/motion

# Install motioneye
RUN pip3 install motioneye==${MOTIONEYE_VERSION}

# Copy configuration files
COPY config/motioneye.conf /etc/motioneye/motioneye.conf
COPY config/nginx.conf /etc/nginx/nginx.conf
COPY config/supervisord.conf /etc/supervisord.conf

# Expose ports
EXPOSE 8765

# Set up entrypoint
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

# Set up volumes
VOLUME ["/var/lib/motioneye", "/var/log/motion"]

# Set up healthcheck
HEALTHCHECK --interval=30s --timeout=10s --start-period=5s --retries=3 \
    CMD curl -f http://localhost:8765/ || exit 1

ENTRYPOINT ["/entrypoint.sh"] 