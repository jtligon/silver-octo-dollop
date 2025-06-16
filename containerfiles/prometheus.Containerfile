FROM quay.io/prometheus/prometheus:v2.45.0

# Copy Prometheus configuration
COPY config/prometheus.yml /etc/prometheus/prometheus.yml

# Set up volumes
VOLUME ["/etc/prometheus", "/var/lib/prometheus"]

# Expose Prometheus port
EXPOSE 9090

# Start Prometheus
CMD ["--config.file=/etc/prometheus/prometheus.yml", \
     "--storage.tsdb.path=/var/lib/prometheus", \
     "--web.console.libraries=/usr/share/prometheus/console_libraries", \
     "--web.console.templates=/usr/share/prometheus/consoles"] 