# Base image: Fedora bootc (bootable container) version 42 for x86_64 architecture
# This provides a minimal, immutable OS foundation designed for containerized workloads
FROM quay.io/fedora/fedora-bootc:42-x86_64

# Install essential packages for system management and wireless connectivity
# - cockpit*: Web-based server management interface and its modules
#   - cockpit: Core web management interface
#   - cockpit-ostree: OSTree/rpm-ostree management (for immutable OS updates)
#   - cockpit-podman: Container management through Cockpit
#   - cockpit-storaged: Storage/disk management interface
#   - cockpit-ws: WebSocket proxy for Cockpit
#   - cockpit-selinux: SELinux management interface
# - openssh-server: SSH daemon for remote access
# - openssh-clients: SSH client tools
# - wpa_supplicant: WiFi network authentication daemon
# - iwlwifi-mvm-firmware: Intel WiFi firmware for modern Intel wireless cards
# - git: Version control system (likely needed for configuration management)
# - wget: HTTP/HTTPS/FTP download utility
# - intel-media-driver: Intel GPU hardware acceleration for video processing
# - libva-intel-driver: Video Acceleration API for Intel GPUs
# - mesa-dri-drivers: Mesa DRI drivers for GPU acceleration
# - python3-pip: Python package manager for OCR dependencies
# - tesseract-ocr: OCR engine for text recognition
# Clean package cache to reduce image size
RUN dnf install -y --skip-unavailable cockpit cockpit-ostree cockpit-podman cockpit-storaged cockpit-ws openssh-server openssh-clients wpa_supplicant cockpit-selinux iwlwifi-mvm-firmware git wget intel-media-driver libva-intel-driver mesa-dri-drivers python3-pip tesseract-ocr && dnf clean all

# Configure passwordless sudo for wheel group members
# This allows users in the wheel group to run sudo commands without entering a password
# Essential for automated operations and container management
ADD wheel-passwordless-sudo /etc/sudoers.d/wheel-passwordless-sudo

# Create directory structure for Frigate NVR, MQTT broker, and OCR processing
# - /frigate/config: Configuration files for Frigate NVR
# - /frigate/media: Storage for recorded videos and snapshots
# - /mosquitto/config: MQTT broker configuration
# - /mosquitto/data: MQTT broker persistent data
# - /mosquitto/log: MQTT broker logs
# - /kiln-ocr: OCR processing scripts and dependencies
# - /data: General data directory (may be used for additional storage)
RUN mkdir -p /frigate/config /frigate/media /mosquitto/config /mosquitto/data /mosquitto/log /kiln-ocr /data

# Create user account for remote SSH access
# - Creates user 'jtligon' with home directory
# - Adds user to wheel group for sudo access
# - Sets up proper home directory permissions
RUN useradd -m -G wheel jtligon

# Enable systemd services to start automatically on boot
# - podman-auto-update.timer: Automatically updates running containers on schedule
# - cockpit.socket: Enables Cockpit web interface (socket activation)
# - sshd.service: SSH daemon for remote access
RUN systemctl enable podman-auto-update.timer cockpit.socket sshd.service

# Install container configurations for systemd
# These files define how the containers should be run as systemd services
# Systemd will automatically start/manage the containers based on these configs
COPY ./frigate.container /etc/containers/systemd/frigate.container
COPY ./mosquitto.container /etc/containers/systemd/mosquitto.container
COPY ./kiln-ocr.container /etc/containers/systemd/kiln-ocr.container

# Install configuration files for services
# Frigate configuration for kiln monitoring with OCR zones
COPY ./frigate.yml /frigate/config/config.yml
COPY ./labels.txt /frigate/config/labels.txt

# Mosquitto MQTT broker configuration
COPY ./mosquitto.conf /mosquitto/config/mosquitto.conf

# OCR processing scripts and dependencies
COPY ./ocr-processor.py /kiln-ocr/ocr_processor.py
COPY ./frigate-ocr-integration.py /kiln-ocr/frigate-ocr-integration.py
COPY ./temperature-logger.py /kiln-ocr/temperature-logger.py
COPY ./requirements.txt /kiln-ocr/requirements.txt

# Install Python dependencies for OCR processing
RUN pip3 install -r /kiln-ocr/requirements.txt

# Install storage setup script and data management tools
COPY ./storage-setup.sh /usr/local/bin/storage-setup.sh
RUN chmod +x /usr/local/bin/storage-setup.sh

# Install network security setup scripts
COPY ./firewall-setup.sh /usr/local/bin/firewall-setup.sh
COPY ./ssl-setup.sh /usr/local/bin/ssl-setup.sh
COPY ./mqtt-auth-setup.sh /usr/local/bin/mqtt-auth-setup.sh
RUN chmod +x /usr/local/bin/firewall-setup.sh /usr/local/bin/ssl-setup.sh /usr/local/bin/mqtt-auth-setup.sh

<<<<<<< HEAD
=======
# Install system integration script
COPY ./systemd-integration.sh /usr/local/bin/systemd-integration.sh
RUN chmod +x /usr/local/bin/systemd-integration.sh

# Install testing and validation scripts
COPY ./testing-validation.sh /usr/local/bin/testing-validation.sh
COPY ./performance-test.sh /usr/local/bin/performance-test.sh
RUN chmod +x /usr/local/bin/testing-validation.sh /usr/local/bin/performance-test.sh

>>>>>>> claude
# Install SSH key import service for automatic passwordless SSH access
# This one-shot service downloads the user's SSH public key from GitHub on first boot
# - Runs once after network is available during system startup
# - Creates .ssh directory with proper permissions (700) if it doesn't exist
# - Downloads SSH public key from GitHub (https://github.com/jtligon.keys)
# - Prevents duplicate entries by checking if key already exists
# - Sets correct ownership (jtligon:jtligon) and permissions (600) for security
# - Enables passwordless SSH access for remote management and automation
COPY ./oneShot.unit /etc/systemd/system/ssh-key-import.service
RUN systemctl enable ssh-key-import.service
