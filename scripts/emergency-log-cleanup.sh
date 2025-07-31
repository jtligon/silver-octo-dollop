#!/bin/bash
# Emergency Log Cleanup Script for Kiln Monitoring System
# This script aggressively cleans logs when filesystem is full

set -e

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
log_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# Check if running as root
if [[ $EUID -ne 0 ]]; then
    log_error "This script must be run as root for emergency cleanup"
    exit 1
fi

log_info "🚨 Emergency Log Cleanup for Kiln Monitoring System"
log_info "Date: $(date)"

# Show current disk usage
log_info "Current disk usage:"
df -h

# Emergency cleanup functions
emergency_cleanup() {
    log_warning "Performing emergency cleanup..."
    
    # 1. Clean systemd/journald logs aggressively
    log_info "Cleaning systemd logs..."
    journalctl --vacuum-time=1d
    journalctl --vacuum-size=100M
    
    # 2. Clean container logs
    log_info "Cleaning container logs..."
    if command -v podman &> /dev/null; then
        # Clean podman logs
        podman system prune -a -f --volumes
        
        # Clean individual container logs
        for container in $(podman ps -a --format="{{.Names}}"); do
            log_info "Cleaning logs for container: $container"
            podman logs $container --tail 100 > /tmp/${container}_last_100.log 2>/dev/null || true
        done
    fi
    
    # 3. Clean OCR processor logs
    log_info "Cleaning OCR processor logs..."
    if [ -d "/var/lib/kiln-monitoring/logs/ocr-processor" ]; then
        find /var/lib/kiln-monitoring/logs/ocr-processor -name "*.log" -type f -exec truncate -s 0 {} \;
        find /var/lib/kiln-monitoring/logs/ocr-processor -name "*.log.*" -type f -delete
    fi
    
    # 4. Clean Frigate logs and cache
    log_info "Cleaning Frigate logs and cache..."
    if [ -d "/var/lib/kiln-monitoring/frigate" ]; then
        # Clean cache files
        find /var/lib/kiln-monitoring/frigate/cache -type f -delete 2>/dev/null || true
        
        # Clean old recordings (keep only last 24 hours)
        find /var/lib/kiln-monitoring/frigate/recordings -name "*.mp4" -type f -mtime +1 -delete 2>/dev/null || true
        
        # Clean snapshots older than 3 days
        find /var/lib/kiln-monitoring/frigate/snapshots -name "*.jpg" -type f -mtime +3 -delete 2>/dev/null || true
    fi
    
    # 5. Clean MQTT logs
    log_info "Cleaning MQTT logs..."
    if [ -d "/var/lib/kiln-monitoring/mosquitto/log" ]; then
        find /var/lib/kiln-monitoring/mosquitto/log -name "*.log" -type f -exec truncate -s 0 {} \;
    fi
    
    # 6. Clean system logs
    log_info "Cleaning system logs..."
    if [ -d "/var/lib/kiln-monitoring/logs/system" ]; then
        find /var/lib/kiln-monitoring/logs/system -name "*.log" -type f -exec truncate -s 0 {} \;
    fi
    
    # 7. Clean temporary files
    log_info "Cleaning temporary files..."
    find /tmp -name "*kiln*" -type f -mtime +1 -delete 2>/dev/null || true
    find /tmp -name "*frigate*" -type f -mtime +1 -delete 2>/dev/null || true
    find /tmp -name "*ocr*" -type f -mtime +1 -delete 2>/dev/null || true
    
    # 8. Clean container temporary storage directories (major space consumer)
    log_info "Cleaning container temporary storage directories..."
    # These directories can consume 15GB+ and are often left behind by failed container operations
    find /var/tmp -name "container_images_storage*" -type d -mtime +0 -exec rm -rf {} \; 2>/dev/null || true
    find /var/tmp -name "libpod_tmp_*" -type d -mtime +0 -exec rm -rf {} \; 2>/dev/null || true
    find /var/tmp -name "buildah*" -type d -mtime +0 -exec rm -rf {} \; 2>/dev/null || true
    
    # Clean any container-related temp files
    find /var/tmp -name "*container*" -type f -mtime +1 -delete 2>/dev/null || true
    find /var/tmp -name "*podman*" -type f -mtime +1 -delete 2>/dev/null || true
    
    # 9. Clean old debug images
    log_info "Cleaning debug images..."
    if [ -d "/var/lib/kiln-monitoring/kiln-data/ocr-debug" ]; then
        find /var/lib/kiln-monitoring/kiln-data/ocr-debug -name "*.jpg" -type f -mtime +1 -delete 2>/dev/null || true
        find /var/lib/kiln-monitoring/kiln-data/ocr-debug -name "*.png" -type f -mtime +1 -delete 2>/dev/null || true
    fi
    
    # 10. Clean package cache
    log_info "Cleaning package cache..."
    if command -v dnf &> /dev/null; then
        dnf clean all
    elif command -v apt &> /dev/null; then
        apt clean
    fi
    
    # 11. Clean old backups if space is still critical
    log_info "Checking if backup cleanup is needed..."
    USAGE=$(df / | awk 'NR==2 {print $5}' | sed 's/%//')
    if [ $USAGE -gt 90 ]; then
        log_warning "Disk usage still high ($USAGE%), cleaning old backups..."
        if [ -d "/var/backups/kiln-monitoring" ]; then
            find /var/backups/kiln-monitoring -name "kiln-backup-*" -type d -mtime +3 -exec rm -rf {} \; 2>/dev/null || true
        fi
    fi
}

# Fix log rotation configuration
fix_log_rotation() {
    log_info "Fixing log rotation configuration..."
    
    # Ensure logrotate is installed
    if ! command -v logrotate &> /dev/null; then
        log_warning "logrotate not installed, installing..."
        if command -v dnf &> /dev/null; then
            dnf install -y logrotate
        elif command -v apt &> /dev/null; then
            apt update && apt install -y logrotate
        fi
    fi
    
    # Create aggressive log rotation for emergency situations
    cat > /etc/logrotate.d/kiln-emergency << 'EOF'
# Emergency log rotation for kiln monitoring system
/var/lib/kiln-monitoring/logs/*/*.log {
    daily
    rotate 3
    compress
    delaycompress
    missingok
    notifempty
    create 644 root root
    copytruncate
    maxsize 10M
}

/var/lib/kiln-monitoring/frigate/cache/*.log {
    daily
    rotate 1
    compress
    delaycompress
    missingok
    notifempty
    create 644 root root
    copytruncate
    maxsize 5M
}
EOF
    
    # Create journald configuration for aggressive cleanup
    mkdir -p /etc/systemd/journald.conf.d
    cat > /etc/systemd/journald.conf.d/kiln-emergency.conf << 'EOF'
[Journal]
# Emergency settings to prevent log flooding
Storage=persistent
Compress=yes
Seal=yes

# Aggressive size limits
SystemMaxUse=200M
RuntimeMaxUse=50M
SystemMaxFileSize=20M
RuntimeMaxFileSize=5M

# Short retention
MaxRetentionSec=3day
MaxFileSec=1day

# Strict rate limiting
RateLimitIntervalSec=10s
RateLimitBurst=100
EOF
    
    # Restart journald to apply changes
    systemctl restart systemd-journald
    
    # Force immediate log rotation
    logrotate -f /etc/logrotate.conf
}

# Configure container log limits
configure_container_logs() {
    log_info "Configuring container log limits..."
    
    # Create containers.conf with log limits
    mkdir -p /etc/containers
    cat > /etc/containers/containers.conf << 'EOF'
[containers]
# Log configuration to prevent filesystem issues
log_driver = "journald"
log_size_max = "10MB"
log_tag = "{{.Name}}"

[engine]
# Cleanup configuration
events_logger = "journald"
EOF
    
    # Update systemd container files with log limits
    for container_file in /etc/containers/systemd/*.container; do
        if [ -f "$container_file" ]; then
            # Add log limits to container files
            if ! grep -q "LogDriver" "$container_file"; then
                echo "LogDriver=journald" >> "$container_file"
            fi
            if ! grep -q "LogSizeMax" "$container_file"; then
                echo "LogSizeMax=10MB" >> "$container_file"
            fi
        fi
    done
    
    # Restart containers to apply new settings
    systemctl daemon-reload
    systemctl restart mosquitto.service frigate.service kiln-ocr.service || true
}

# Create monitoring script
create_log_monitor() {
    log_info "Creating log monitoring script..."
    
    cat > /usr/local/bin/kiln-log-monitor.sh << 'EOF'
#!/bin/bash
# Kiln Log Monitoring Script
# Monitors disk usage and triggers cleanup when needed

THRESHOLD=85
EMERGENCY_THRESHOLD=95
STORAGE_BASE="/var/lib/kiln-monitoring"

# Check disk usage
USAGE=$(df / | awk 'NR==2 {print $5}' | sed 's/%//')

if [ $USAGE -gt $EMERGENCY_THRESHOLD ]; then
    echo "CRITICAL: Disk usage at $USAGE%, running emergency cleanup..."
    /usr/local/bin/emergency-log-cleanup.sh
elif [ $USAGE -gt $THRESHOLD ]; then
    echo "WARNING: Disk usage at $USAGE%, running standard cleanup..."
    # Run standard cleanup
    journalctl --vacuum-time=7d
    
    # Clean container temp directories (preventive maintenance)
    find /var/tmp -name "container_images_storage*" -type d -mtime +0 -exec rm -rf {} \; 2>/dev/null || true
    find /var/tmp -name "libpod_tmp_*" -type d -mtime +0 -exec rm -rf {} \; 2>/dev/null || true
    
    if [ -f "$STORAGE_BASE/cleanup-kiln-data.sh" ]; then
        "$STORAGE_BASE/cleanup-kiln-data.sh"
    fi
fi

# Send MQTT alert if usage is high
if [ $USAGE -gt $THRESHOLD ]; then
    mosquitto_pub -h localhost -t "frigate/kiln/system/disk" \
        -m "{\"usage_percent\": $USAGE, \"status\": \"high_usage\", \"timestamp\": \"$(date -Iseconds)\"}" || true
fi
EOF
    
    chmod +x /usr/local/bin/kiln-log-monitor.sh
    
    # Create systemd service for monitoring
    cat > /etc/systemd/system/kiln-log-monitor.service << 'EOF'
[Unit]
Description=Kiln Log Monitoring Service
After=network-online.target

[Service]
Type=oneshot
ExecStart=/usr/local/bin/kiln-log-monitor.sh
StandardOutput=journal
StandardError=journal
EOF
    
    cat > /etc/systemd/system/kiln-log-monitor.timer << 'EOF'
[Unit]
Description=Kiln Log Monitoring Timer
Requires=kiln-log-monitor.service

[Timer]
OnCalendar=*:0/15
Persistent=true

[Install]
WantedBy=timers.target
EOF
    
    systemctl daemon-reload
    systemctl enable kiln-log-monitor.timer
    systemctl start kiln-log-monitor.timer
}

# Main execution
main() {
    log_info "Starting emergency log cleanup..."
    
    # Show initial state
    log_info "Initial disk usage:"
    df -h
    
    # Perform emergency cleanup
    emergency_cleanup
    
    # Fix log rotation
    fix_log_rotation
    
    # Configure container logs
    configure_container_logs
    
    # Create monitoring
    create_log_monitor
    
    # Show final state
    log_success "Emergency cleanup completed!"
    log_info "Final disk usage:"
    df -h
    
    # Calculate space freed
    log_success "Log cleanup completed successfully!"
    log_info "Installed monitoring system to prevent future issues"
    log_info "Monitor logs with: journalctl -u kiln-log-monitor.timer -f"
}

# Run main function
main "$@" 