#!/bin/bash
# Storage Setup Script for Kiln Monitoring System
# Sets up persistent storage volumes and configures data retention policies

set -e  # Exit on any error

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] $1${NC}"
}

warn() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] WARNING: $1${NC}"
}

error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ERROR: $1${NC}"
}

# Check if running as root
if [[ $EUID -eq 0 ]]; then
    error "This script should not be run as root for security reasons"
    exit 1
fi

log "🗄️  Setting up persistent storage for Kiln Monitoring System"

# Create base storage directories
STORAGE_BASE="/var/lib/kiln-monitoring"
BACKUP_BASE="/var/backups/kiln-monitoring"

log "Creating storage directories..."

# Main storage directories
sudo mkdir -p "$STORAGE_BASE"/{frigate,frigate-config,frigate-media,mosquitto,mosquitto-config,kiln-data,logs}
sudo mkdir -p "$BACKUP_BASE"/{daily,weekly,monthly}

# Frigate storage structure
sudo mkdir -p "$STORAGE_BASE"/frigate/{recordings,snapshots,clips,exports,cache}
sudo mkdir -p "$STORAGE_BASE"/frigate/recordings/{kiln_camera}

# MQTT persistent data
sudo mkdir -p "$STORAGE_BASE"/mosquitto/{data,log}

# Kiln historical data
sudo mkdir -p "$STORAGE_BASE"/kiln-data/{temperature-history,firing-logs,ocr-debug,statistics}

# System logs
sudo mkdir -p "$STORAGE_BASE"/logs/{frigate,mosquitto,ocr-processor,system}

# Set proper permissions
log "Setting directory permissions..."
sudo chown -R "$USER:$USER" "$STORAGE_BASE"
sudo chown -R "$USER:$USER" "$BACKUP_BASE"
sudo chmod -R 755 "$STORAGE_BASE"
sudo chmod -R 750 "$BACKUP_BASE"

# Create retention policy configuration
log "Creating data retention policies..."

cat > /tmp/retention-config.yml << 'EOF'
# Data Retention Configuration for Kiln Monitoring
retention_policies:
  frigate_recordings:
    default_days: 7
    high_temp_events: 30    # Keep high temperature events longer
    error_events: 60        # Keep error events even longer
    firing_complete: 30     # Keep complete firing cycles
    
  frigate_snapshots:
    default_days: 30
    ocr_debug: 7           # Debug snapshots
    
  temperature_data:
    raw_readings: 90       # 3 months of raw data
    hourly_aggregates: 365 # 1 year of hourly data
    daily_aggregates: 1095 # 3 years of daily data
    
  mqtt_logs:
    default_days: 30
    
  system_logs:
    default_days: 14
    error_logs: 60

backup_policies:
  daily:
    retention_days: 7
    backup_time: "02:00"
    
  weekly:
    retention_weeks: 4
    backup_day: "sunday"
    backup_time: "03:00"
    
  monthly:
    retention_months: 12
    backup_day: 1
    backup_time: "04:00"

storage_quotas:
  frigate_recordings: "50GB"    # Limit recordings to 50GB
  frigate_snapshots: "10GB"     # Limit snapshots to 10GB
  temperature_data: "5GB"       # Temperature history
  total_system: "100GB"         # Total system limit
EOF

sudo mv /tmp/retention-config.yml "$STORAGE_BASE"/retention-config.yml

# Create backup script
log "Creating backup script..."

cat > /tmp/backup-kiln-data.sh << 'EOF'
#!/bin/bash
# Automated backup script for kiln monitoring data

STORAGE_BASE="/var/lib/kiln-monitoring"
BACKUP_BASE="/var/backups/kiln-monitoring"
DATE=$(date +%Y%m%d_%H%M%S)
BACKUP_TYPE=${1:-daily}

# Create timestamped backup directory
BACKUP_DIR="$BACKUP_BASE/$BACKUP_TYPE/kiln-backup-$DATE"
mkdir -p "$BACKUP_DIR"

echo "Starting $BACKUP_TYPE backup at $(date)"

# Backup critical configuration files
echo "Backing up configurations..."
cp -r /var/lib/kiln-monitoring/frigate-config "$BACKUP_DIR"/frigate_config
cp -r /var/lib/kiln-monitoring/mosquitto-config "$BACKUP_DIR"/mosquitto_config
cp -r /kiln-ocr "$BACKUP_DIR"/ocr_scripts

# Backup kiln historical data (always important)
echo "Backing up kiln data..."
tar -czf "$BACKUP_DIR/kiln-data.tar.gz" -C "$STORAGE_BASE" kiln-data/

# Backup recent temperature readings
echo "Backing up recent temperature data..."
find "$STORAGE_BASE/kiln-data/temperature-history" -name "*.json" -mtime -30 | \
    tar -czf "$BACKUP_DIR/recent-temperature-data.tar.gz" -T -

# Backup important Frigate recordings (firing events, errors)
echo "Backing up important recordings..."
if [ -d "$STORAGE_BASE/frigate/recordings" ]; then
    find "$STORAGE_BASE/frigate/recordings" -name "*firing*" -o -name "*error*" -o -name "*high-temp*" | \
        tar -czf "$BACKUP_DIR/important-recordings.tar.gz" -T - 2>/dev/null || true
fi

# Backup recent snapshots for OCR debugging
echo "Backing up recent snapshots..."
find "$STORAGE_BASE/frigate/snapshots" -mtime -7 | \
    tar -czf "$BACKUP_DIR/recent-snapshots.tar.gz" -T - 2>/dev/null || true

# Create backup manifest
echo "Creating backup manifest..."
cat > "$BACKUP_DIR/backup-manifest.txt" << MANIFEST
Kiln Monitoring System Backup
==============================
Backup Type: $BACKUP_TYPE
Date: $(date)
Hostname: $(hostname)
Storage Base: $STORAGE_BASE

Contents:
- frigate_config/     : Frigate NVR configuration
- mosquitto_config/   : MQTT broker configuration  
- ocr_scripts/        : OCR processing scripts
- kiln-data.tar.gz    : Complete kiln historical data
- recent-temperature-data.tar.gz : Last 30 days temperature readings
- important-recordings.tar.gz    : Critical recording events
- recent-snapshots.tar.gz        : Last 7 days of snapshots

Backup completed at: $(date)
MANIFEST

# Cleanup old backups based on retention policy
echo "Cleaning up old backups..."
case $BACKUP_TYPE in
    daily)
        find "$BACKUP_BASE/daily" -type d -name "kiln-backup-*" -mtime +7 -exec rm -rf {} \; 2>/dev/null || true
        ;;
    weekly)
        find "$BACKUP_BASE/weekly" -type d -name "kiln-backup-*" -mtime +28 -exec rm -rf {} \; 2>/dev/null || true
        ;;
    monthly)
        find "$BACKUP_BASE/monthly" -type d -name "kiln-backup-*" -mtime +365 -exec rm -rf {} \; 2>/dev/null || true
        ;;
esac

echo "Backup completed: $BACKUP_DIR"
echo "Backup size: $(du -sh $BACKUP_DIR | cut -f1)"
EOF

sudo mv /tmp/backup-kiln-data.sh "$STORAGE_BASE"/backup-kiln-data.sh
sudo chmod +x "$STORAGE_BASE"/backup-kiln-data.sh

# Create data cleanup script
log "Creating data cleanup script..."

cat > /tmp/cleanup-kiln-data.sh << 'EOF'
#!/bin/bash
# Data cleanup script based on retention policies

STORAGE_BASE="/var/lib/kiln-monitoring"
CONFIG_FILE="$STORAGE_BASE/retention-config.yml"

echo "Starting data cleanup at $(date)"

# Function to clean files by age
cleanup_by_age() {
    local path="$1"
    local days="$2"
    local description="$3"
    
    if [ -d "$path" ]; then
        local count=$(find "$path" -type f -mtime +$days | wc -l)
        if [ $count -gt 0 ]; then
            echo "Cleaning $count $description files older than $days days..."
            find "$path" -type f -mtime +$days -delete
        fi
    fi
}

# Clean Frigate recordings (keep important events longer)
echo "Cleaning Frigate data..."
cleanup_by_age "$STORAGE_BASE/frigate/recordings" 7 "standard recording"
cleanup_by_age "$STORAGE_BASE/frigate/snapshots" 30 "snapshot"

# Clean OCR debug images (keep recent for troubleshooting)
cleanup_by_age "$STORAGE_BASE/kiln-data/ocr-debug" 7 "OCR debug"

# Clean old temperature readings (but preserve aggregated data)
echo "Cleaning old raw temperature data..."
cleanup_by_age "$STORAGE_BASE/kiln-data/temperature-history" 90 "raw temperature"

# Clean system logs
echo "Cleaning system logs..."
cleanup_by_age "$STORAGE_BASE/logs" 14 "system log"

# Clean MQTT logs
cleanup_by_age "$STORAGE_BASE/mosquitto/log" 30 "MQTT log"

# Check disk usage and warn if getting full
echo "Checking disk usage..."
USAGE=$(df "$STORAGE_BASE" | awk 'NR==2 {print $5}' | sed 's/%//')
if [ $USAGE -gt 80 ]; then
    echo "WARNING: Storage is $USAGE% full. Consider cleaning more aggressively."
    # Send alert via MQTT
    mosquitto_pub -h localhost -t "frigate/kiln/system/storage" \
        -m "{\"usage_percent\": $USAGE, \"warning\": \"high_usage\", \"timestamp\": \"$(date -Iseconds)\"}" || true
fi

echo "Data cleanup completed at $(date)"
EOF

sudo mv /tmp/cleanup-kiln-data.sh "$STORAGE_BASE"/cleanup-kiln-data.sh
sudo chmod +x "$STORAGE_BASE"/cleanup-kiln-data.sh

log "Creating systemd services for data management..."

# Create backup timer service
sudo tee /etc/systemd/system/kiln-backup.service > /dev/null << 'EOF'
[Unit]
Description=Kiln Monitoring Data Backup
After=frigate.service mosquitto.service

[Service]
Type=oneshot
User=jtligon
ExecStart=/var/lib/kiln-monitoring/backup-kiln-data.sh daily
StandardOutput=journal
StandardError=journal
EOF

sudo tee /etc/systemd/system/kiln-backup.timer > /dev/null << 'EOF'
[Unit]
Description=Daily Kiln Monitoring Backup
Requires=kiln-backup.service

[Timer]
OnCalendar=daily
Persistent=true
RandomizedDelaySec=600

[Install]
WantedBy=timers.target
EOF

# Create cleanup timer service
sudo tee /etc/systemd/system/kiln-cleanup.service > /dev/null << 'EOF'
[Unit]
Description=Kiln Monitoring Data Cleanup
After=kiln-backup.service

[Service]
Type=oneshot
User=jtligon
ExecStart=/var/lib/kiln-monitoring/cleanup-kiln-data.sh
StandardOutput=journal
StandardError=journal
EOF

sudo tee /etc/systemd/system/kiln-cleanup.timer > /dev/null << 'EOF'
[Unit]
Description=Daily Kiln Monitoring Cleanup
Requires=kiln-cleanup.service

[Timer]
OnCalendar=02:30:00
Persistent=true

[Install]
WantedBy=timers.target
EOF

# Enable services
log "Enabling backup and cleanup services..."
sudo systemctl daemon-reload
sudo systemctl enable kiln-backup.timer
sudo systemctl enable kiln-cleanup.timer
sudo systemctl start kiln-backup.timer
sudo systemctl start kiln-cleanup.timer

# Create volume mount verification script
log "Creating volume mount verification..."

cat > /tmp/verify-storage.sh << 'EOF'
#!/bin/bash
# Verify all storage mounts and directories are properly configured

STORAGE_BASE="/var/lib/kiln-monitoring"
ERRORS=0

check_directory() {
    local dir="$1"
    local description="$2"
    
    if [ ! -d "$dir" ]; then
        echo "ERROR: $description directory missing: $dir"
        ((ERRORS++))
    elif [ ! -w "$dir" ]; then
        echo "ERROR: $description directory not writable: $dir"
        ((ERRORS++))
    else
        echo "OK: $description directory: $dir"
    fi
}

echo "=== Kiln Monitoring Storage Verification ==="
echo "Date: $(date)"

# Check main directories
check_directory "$STORAGE_BASE" "Main storage"
check_directory "$STORAGE_BASE/frigate" "Frigate data"
check_directory "$STORAGE_BASE/frigate-config" "Frigate configuration"
check_directory "$STORAGE_BASE/frigate-media" "Frigate media"
check_directory "$STORAGE_BASE/mosquitto" "MQTT data"
check_directory "$STORAGE_BASE/mosquitto-config" "MQTT configuration"
check_directory "$STORAGE_BASE/kiln-data" "Kiln data"

# Check container mount points
check_directory "/var/lib/kiln-monitoring/frigate-config" "Frigate config mount"
check_directory "/var/lib/kiln-monitoring/frigate-media" "Frigate media mount" 
check_directory "/var/lib/kiln-monitoring/mosquitto-config" "MQTT config mount"
check_directory "/var/lib/kiln-monitoring/mosquitto/data" "MQTT data mount"

# Check disk space
echo ""
echo "=== Disk Usage ==="
df -h "$STORAGE_BASE" | head -2

# Check backup directories
echo ""
echo "=== Backup Status ==="
if [ -d "/var/backups/kiln-monitoring" ]; then
    echo "Latest backups:"
    find /var/backups/kiln-monitoring -name "kiln-backup-*" -type d | sort | tail -3
else
    echo "WARNING: No backup directory found"
    ((ERRORS++))
fi

echo ""
if [ $ERRORS -eq 0 ]; then
    echo "✅ All storage checks passed!"
    exit 0
else
    echo "❌ Found $ERRORS storage issues"
    exit 1
fi
EOF

sudo mv /tmp/verify-storage.sh "$STORAGE_BASE"/verify-storage.sh
sudo chmod +x "$STORAGE_BASE"/verify-storage.sh

log "Storage setup completed! 🎉"
log ""
log "📁 Storage Structure:"
log "   Main: $STORAGE_BASE"
log "   Backups: $BACKUP_BASE"
log ""
log "🔧 Management Scripts:"
log "   Backup: $STORAGE_BASE/backup-kiln-data.sh"
log "   Cleanup: $STORAGE_BASE/cleanup-kiln-data.sh"
log "   Verify: $STORAGE_BASE/verify-storage.sh"
log ""
log "⏰ Automated Services:"
log "   Daily backups: kiln-backup.timer"
log "   Daily cleanup: kiln-cleanup.timer"
log ""
log "🔍 To verify setup: sudo $STORAGE_BASE/verify-storage.sh"
log "📊 To check services: systemctl status kiln-backup.timer kiln-cleanup.timer" 