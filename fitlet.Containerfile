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
# - wpa_supplicant: WiFi network authentication daemon
# - iwlwifi-mvm-firmware: Intel WiFi firmware for modern Intel wireless cards
# - git: Version control system (likely needed for configuration management)
# - wget: HTTP/HTTPS/FTP download utility
# Clean package cache to reduce image size
RUN dnf install -y --skip-unavailable cockpit cockpit-ostree cockpit-podman cockpit-storaged cockpit-ws wpa_supplicant cockpit-selinux iwlwifi-mvm-firmware git wget && dnf clean all

# Configure passwordless sudo for wheel group members
# This allows users in the wheel group to run sudo commands without entering a password
# Essential for automated operations and container management
ADD wheel-passwordless-sudo /etc/sudoers.d/wheel-passwordless-sudo

# Create directory structure for MotionEye camera surveillance system
# - /motioneye/config: Configuration files for MotionEye
# - /motioneye/data: Storage for recorded videos and images
# - /data: General data directory (may be used for additional storage)
RUN mkdir -p /motioneye/config /motioneye/data /data

# Enable systemd services to start automatically on boot
# - podman-auto-update.timer: Automatically updates running containers on schedule
# - cockpit.socket: Enables Cockpit web interface (socket activation)
RUN systemctl enable podman-auto-update.timer cockpit.socket

# Install MotionEye container configuration for systemd
# This file defines how the MotionEye container should be run as a systemd service
# Systemd will automatically start/manage the MotionEye container based on this config
COPY ./motioneye.container /etc/containers/systemd/motioneye.container

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
