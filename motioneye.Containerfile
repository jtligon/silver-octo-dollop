# Modern MotionEye Container for quay.io/jtligon/motioneye
# Based on Ubuntu for better package availability
FROM ubuntu:22.04

# Prevent interactive prompts during package installation
ENV DEBIAN_FRONTEND=noninteractive

# Install system dependencies and MotionEye
# - motion: The core motion detection software
# - python3 and pip: Required for MotionEye web interface
# - ffmpeg: Video processing and streaming
# - curl: For health checks and downloads
RUN apt-get update && apt-get install -y \
    motion \
    python3 \
    python3-pip \
    python3-dev \
    python3-setuptools \
    python3-wheel \
    ffmpeg \
    curl \
    v4l-utils \
    build-essential \
    libcurl4-openssl-dev \
    libssl-dev \
    && pip3 install --no-cache-dir motioneye \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# Create motioneye user and directories
RUN groupadd -g 1000 motioneye \
    && useradd -u 1000 -g motioneye -d /var/lib/motioneye -m motioneye \
    && mkdir -p /etc/motioneye /var/lib/motioneye /var/run/motion \
    && chown -R motioneye:motioneye /etc/motioneye /var/lib/motioneye /var/run/motion

# Create default configuration file
RUN mkdir -p /etc/motioneye && \
    echo "# MotionEye Configuration" > /etc/motioneye/motioneye.conf && \
    echo "port 8765" >> /etc/motioneye/motioneye.conf && \
    echo "motion_binary /usr/bin/motion" >> /etc/motioneye/motioneye.conf && \
    echo "media_path /var/lib/motioneye" >> /etc/motioneye/motioneye.conf && \
    echo "log_level info" >> /etc/motioneye/motioneye.conf && \
    echo "log_file /var/log/motioneye.log" >> /etc/motioneye/motioneye.conf

# Set up volumes for persistent data
VOLUME ["/etc/motioneye", "/var/lib/motioneye"]

# Expose MotionEye web interface port
EXPOSE 8765

# Health check to ensure MotionEye is running
HEALTHCHECK --interval=30s --timeout=10s --start-period=5s --retries=3 \
    CMD curl -f http://localhost:8765/ || exit 1

# Switch to motioneye user for security
USER motioneye

# Set working directory
WORKDIR /var/lib/motioneye

# Start MotionEye
CMD ["meyectl", "startserver", "-c", "/etc/motioneye/motioneye.conf"]
