FROM ccrisan/motioneye:master-amd64

# Set environment variables
ENV MOTIONEYE_VERSION=0.42.1

# Copy configuration files
COPY motioneye.conf /etc/motioneye/motioneye.conf
COPY motion.conf /etc/motioneye/motion.conf

# Set up volumes
VOLUME ["/etc/motioneye", "/var/lib/motioneye"]

# Expose ports
EXPOSE 8765

# Start MotionEye
CMD ["motioneye", "start"] 