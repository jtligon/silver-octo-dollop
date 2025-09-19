#!/bin/bash
# System Integration Setup for Kiln Monitoring System
# Configures systemd services, logging, and service interdependencies

set -e

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

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
if [[ $EUID -ne 0 ]]; then
    error "This script must be run as root or with sudo"
    exit 1
fi

log "🔧 Configuring system integration for Kiln Monitoring System"

# Configure systemd container services
log "Configuring systemd container services..."

# Create systemd drop-in directories for container services
mkdir -p /etc/systemd/system/mosquitto.service.d
mkdir -p /etc/systemd/system/frigate.service.d
mkdir -p /etc/systemd/system/kiln-ocr.service.d

# Configure Mosquitto service dependencies and ordering
cat > /etc/systemd/system/mosquitto.service.d/10-kiln-dependencies.conf << 'EOF'
[Unit]
Description=Mosquitto MQTT Broker for Kiln Monitoring
After=network-online.target
Wants=network-online.target
Before=frigate.service kiln-ocr.service

[Service]
Restart=always
RestartSec=10
StandardOutput=journal
StandardError=journal
TimeoutStartSec=60
TimeoutStopSec=30

[Install]
WantedBy=multi-user.target
EOF

# Configure Frigate service dependencies
cat > /etc/systemd/system/frigate.service.d/10-kiln-dependencies.conf << 'EOF'
[Unit]
Description=Frigate NVR for Kiln Monitoring
After=network-online.target mosquitto.service
Wants=network-online.target
Requires=mosquitto.service
Before=kiln-ocr.service

[Service]
Restart=always
RestartSec=15
StandardOutput=journal
StandardError=journal
TimeoutStartSec=120
TimeoutStopSec=60

[Install]
WantedBy=multi-user.target
EOF

# Configure OCR service dependencies
cat > /etc/systemd/system/kiln-ocr.service.d/10-kiln-dependencies.conf << 'EOF'
[Unit]
Description=Kiln OCR Processing Service
After=network-online.target mosquitto.service frigate.service
Wants=network-online.target
Requires=mosquitto.service frigate.service

[Service]
Restart=always
RestartSec=20
StandardOutput=journal
StandardError=journal
TimeoutStartSec=60
TimeoutStopSec=30

[Install]
WantedBy=multi-user.target
EOF

# Configure log rotation for all services
log "Configuring log rotation..."

# Frigate log rotation
cat > /etc/logrotate.d/frigate << 'EOF'
/var/lib/kiln-monitoring/logs/frigate/*.log {
    daily
    rotate 30
    compress
    delaycompress
    missingok
    notifempty
    create 644 root root
    copytruncate
    postrotate
        systemctl reload frigate.service > /dev/null 2>&1 || true
    endscript
}

/var/lib/kiln-monitoring/frigate/cache/*.log {
    daily
    rotate 7
    compress
    delaycompress
    missingok
    notifempty
    create 644 root root
    copytruncate
}
EOF

# MQTT log rotation
cat > /etc/logrotate.d/mosquitto-kiln << 'EOF'
/var/lib/kiln-monitoring/mosquitto/log/*.log {
    daily
    rotate 30
    compress
    delaycompress
    missingok
    notifempty
    create 644 mosquitto mosquitto
    copytruncate
    postrotate
        systemctl reload mosquitto.service > /dev/null 2>&1 || true
    endscript
}
EOF

# OCR processor log rotation
cat > /etc/logrotate.d/kiln-ocr << 'EOF'
/var/lib/kiln-monitoring/logs/ocr-processor/*.log {
    daily
    rotate 14
    compress
    delaycompress
    missingok
    notifempty
    create 644 root root
    copytruncate
}
EOF

# System logs for kiln monitoring
cat > /etc/logrotate.d/kiln-system << 'EOF'
/var/lib/kiln-monitoring/logs/system/*.log {
    daily
    rotate 14
    compress
    delaycompress
    missingok
    notifempty
    create 644 root root
    copytruncate
}
EOF

# Configure container auto-update policies
log "Configuring container auto-update policies..."

# Create auto-update configuration for kiln containers
cat > /etc/systemd/system/podman-auto-update-kiln.service << 'EOF'
[Unit]
Description=Podman auto-update for Kiln Monitoring containers
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
ExecStart=/usr/bin/podman auto-update --label=io.containers.autoupdate=registry
ExecStartPost=/usr/bin/systemctl restart mosquitto.service frigate.service kiln-ocr.service
StandardOutput=journal
StandardError=journal
EOF

cat > /etc/systemd/system/podman-auto-update-kiln.timer << 'EOF'
[Unit]
Description=Podman auto-update timer for Kiln Monitoring
Requires=podman-auto-update-kiln.service

[Timer]
OnCalendar=Sun 03:00:00
Persistent=true
RandomizedDelaySec=3600

[Install]
WantedBy=timers.target
EOF

# Create container cleanup service to prevent temp directory accumulation
cat > /etc/systemd/system/container-cleanup-kiln.service << 'EOF'
[Unit]
Description=Container Cleanup for Kiln Monitoring
Documentation=https://github.com/jtligon/silver-octo-dollop

[Service]
Type=oneshot
ExecStart=/bin/bash -c 'echo "Running container cleanup..."; \
    find /var/tmp -name "container_images_storage*" -type d -mtime +0 -exec rm -rf {} \; 2>/dev/null || true; \
    find /var/tmp -name "libpod_tmp_*" -type d -mtime +0 -exec rm -rf {} \; 2>/dev/null || true; \
    find /var/tmp -name "buildah*" -type d -mtime +0 -exec rm -rf {} \; 2>/dev/null || true; \
    podman system prune -f --filter until=24h 2>/dev/null || true; \
    echo "Container cleanup completed"'
StandardOutput=journal
StandardError=journal
EOF

cat > /etc/systemd/system/container-cleanup-kiln.timer << 'EOF'
[Unit]
Description=Container Cleanup Timer for Kiln Monitoring
Requires=container-cleanup-kiln.service

[Timer]
OnCalendar=daily
Persistent=true
RandomizedDelaySec=1800

[Install]
WantedBy=timers.target
EOF

# Configure journald for better container logging
log "Configuring journald for container logging..."

# Create journald configuration for kiln monitoring
cat > /etc/systemd/journald.conf.d/kiln-monitoring.conf << 'EOF'
[Journal]
# Storage settings for kiln monitoring logs
Storage=persistent
Compress=yes
Seal=yes

# Size limits to prevent disk space issues
SystemMaxUse=500M
RuntimeMaxUse=100M
SystemMaxFileSize=50M
RuntimeMaxFileSize=10M

# Retention settings
MaxRetentionSec=30day
MaxFileSec=1day

# Rate limiting to prevent log flooding
RateLimitIntervalSec=30s
RateLimitBurst=1000
EOF

# Create Cockpit integration for kiln monitoring
log "Configuring Cockpit integration..."

# Create Cockpit application for kiln monitoring
mkdir -p /usr/share/cockpit/kiln-monitoring

cat > /usr/share/cockpit/kiln-monitoring/manifest.json << 'EOF'
{
    "version": 0,
    "requires": {
        "cockpit": "0"
    },
    "menu": {
        "index": {
            "label": "Kiln Monitoring",
            "order": 30,
            "docs": [
                {
                    "label": "Kiln Monitoring",
                    "url": "https://github.com/jtligon/silver-octo-dollop"
                }
            ]
        }
    }
}
EOF

cat > /usr/share/cockpit/kiln-monitoring/index.html << 'EOF'
<!DOCTYPE html>
<html>
<head>
    <title>Kiln Monitoring System</title>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <link href="../base1/cockpit.css" type="text/css" rel="stylesheet">
    <script src="../base1/cockpit.js"></script>
</head>
<body>
    <div class="container-fluid">
        <div class="row">
            <div class="col-md-12">
                <h1>Kiln Monitoring System</h1>
                <p>Comprehensive kiln monitoring with Frigate NVR, OCR processing, and Home Assistant integration.</p>
            </div>
        </div>
        
        <div class="row">
            <div class="col-md-6">
                <div class="card">
                    <div class="card-header">
                        <h3>Services Status</h3>
                    </div>
                    <div class="card-body">
                        <div id="services-status">
                            <p>Loading service status...</p>
                        </div>
                    </div>
                </div>
            </div>
            
            <div class="col-md-6">
                <div class="card">
                    <div class="card-header">
                        <h3>Quick Actions</h3>
                    </div>
                    <div class="card-body">
                        <button class="btn btn-primary" onclick="openFrigate()">Open Frigate</button>
                        <button class="btn btn-info" onclick="viewLogs()">View Logs</button>
                        <button class="btn btn-warning" onclick="restartServices()">Restart Services</button>
                    </div>
                </div>
            </div>
        </div>
        
        <div class="row">
            <div class="col-md-12">
                <div class="card">
                    <div class="card-header">
                        <h3>System Information</h3>
                    </div>
                    <div class="card-body">
                        <div id="system-info">
                            <p>Loading system information...</p>
                        </div>
                    </div>
                </div>
            </div>
        </div>
    </div>

    <script>
        function openFrigate() {
            window.open('http://localhost:5000', '_blank');
        }
        
        function viewLogs() {
            cockpit.location.go('/logs');
        }
        
        function restartServices() {
            if (confirm('Restart all kiln monitoring services?')) {
                cockpit.spawn(['systemctl', 'restart', 'mosquitto.service', 'frigate.service', 'kiln-ocr.service'])
                    .then(() => {
                        alert('Services restarted successfully');
                        location.reload();
                    })
                    .catch(err => alert('Error restarting services: ' + err));
            }
        }
        
        function updateServiceStatus() {
            const services = ['mosquitto.service', 'frigate.service', 'kiln-ocr.service'];
            let statusHtml = '<table class="table table-sm"><thead><tr><th>Service</th><th>Status</th></tr></thead><tbody>';
            
            Promise.all(services.map(service =>
                cockpit.spawn(['systemctl', 'is-active', service])
                    .catch(() => 'failed')
            )).then(statuses => {
                services.forEach((service, i) => {
                    const status = statuses[i].trim();
                    const statusClass = status === 'active' ? 'success' : 'danger';
                    statusHtml += `<tr><td>${service}</td><td><span class="badge badge-${statusClass}">${status}</span></td></tr>`;
                });
                statusHtml += '</tbody></table>';
                document.getElementById('services-status').innerHTML = statusHtml;
            });
        }
        
        function updateSystemInfo() {
            Promise.all([
                cockpit.spawn(['df', '-h', '/var/lib/kiln-monitoring']).catch(() => 'N/A'),
                cockpit.spawn(['uptime']).catch(() => 'N/A'),
                cockpit.spawn(['podman', 'ps', '--format', 'table']).catch(() => 'No containers')
            ]).then(([disk, uptime, containers]) => {
                const infoHtml = `
                    <strong>Disk Usage:</strong><br><pre>${disk}</pre>
                    <strong>Uptime:</strong><br><pre>${uptime}</pre>
                    <strong>Containers:</strong><br><pre>${containers}</pre>
                `;
                document.getElementById('system-info').innerHTML = infoHtml;
            });
        }
        
        // Update status every 30 seconds
        updateServiceStatus();
        updateSystemInfo();
        setInterval(updateServiceStatus, 30000);
        setInterval(updateSystemInfo, 60000);
    </script>
</body>
</html>
EOF

# Create service health check script
log "Creating service health check script..."

cat > /usr/local/bin/kiln-health-check.sh << 'EOF'
#!/bin/bash
# Comprehensive health check for kiln monitoring system

echo "=== Kiln Monitoring System Health Check ==="
echo "Date: $(date)"
echo "Hostname: $(hostname)"
echo ""

# Function to check service status
check_service() {
    local service="$1"
    local status=$(systemctl is-active "$service" 2>/dev/null)
    local enabled=$(systemctl is-enabled "$service" 2>/dev/null)
    
    if [ "$status" = "active" ]; then
        echo "✅ $service: $status (enabled: $enabled)"
    else
        echo "❌ $service: $status (enabled: $enabled)"
    fi
}

# Check core services
echo "=== Service Status ==="
check_service "mosquitto.service"
check_service "frigate.service"
check_service "kiln-ocr.service"
check_service "cockpit.service"
check_service "ssh.service"

echo ""
echo "=== Container Status ==="
if command -v podman &> /dev/null; then
    podman ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"
else
    echo "❌ Podman not available"
fi

echo ""
echo "=== Network Connectivity ==="
# Test internal connectivity
services=("localhost:1883" "localhost:5000" "localhost:9090")
for service in "${services[@]}"; do
    if nc -z ${service/:/ } 2>/dev/null; then
        echo "✅ $service: Accessible"
    else
        echo "❌ $service: Not accessible"
    fi
done

echo ""
echo "=== Storage Health ==="
# Check disk usage
df -h /var/lib/kiln-monitoring 2>/dev/null || echo "⚠️  Storage directory not found"

# Check log sizes
if [ -d /var/lib/kiln-monitoring/logs ]; then
    echo "Log directory sizes:"
    du -sh /var/lib/kiln-monitoring/logs/* 2>/dev/null || echo "No logs found"
fi

# Check container temp directories (major space consumer)
echo ""
echo "Container temp directories:"
if ls /var/tmp/container_images_storage* >/dev/null 2>&1; then
    TEMP_COUNT=$(ls -1d /var/tmp/container_images_storage* 2>/dev/null | wc -l)
    TEMP_SIZE=$(du -sh /var/tmp/container_images_storage* 2>/dev/null | awk '{sum+=$1} END {print sum"M"}' 2>/dev/null || echo "0M")
    echo "⚠️  $TEMP_COUNT container temp directories using ~$TEMP_SIZE"
    echo "Run: /usr/local/bin/cleanup-container-temps.sh"
else
    echo "✅ No container temp directories found"
fi

echo ""
echo "=== Recent Errors ==="
# Check for recent service failures
journalctl --since "1 hour ago" --priority err --no-pager --lines 5 2>/dev/null || echo "No recent errors"

echo ""
echo "=== System Resources ==="
echo "Memory usage:"
free -h
echo ""
echo "CPU load:"
uptime

echo ""
echo "=== Security Status ==="
# Check firewall
if command -v firewall-cmd &> /dev/null; then
    echo "Firewall: $(systemctl is-active firewalld)"
elif command -v ufw &> /dev/null; then
    echo "Firewall: $(ufw status | head -1)"
else
    echo "Firewall: Unknown"
fi

# Check SSL certificates
if [ -f /ssl/cert-info.txt ]; then
    echo "SSL certificates: Available"
    # Check expiration
    if openssl x509 -checkend 2592000 -noout -in /ssl/certs/server-cert.pem &>/dev/null; then
        echo "SSL certificate: Valid (>30 days)"
    else
        echo "SSL certificate: ⚠️  Expires soon (<30 days)"
    fi
else
    echo "SSL certificates: Not configured"
fi

echo ""
echo "Health check completed at $(date)"
EOF

chmod +x /usr/local/bin/kiln-health-check.sh

# Create service restart script
log "Creating service restart script..."

cat > /usr/local/bin/restart-kiln-services.sh << 'EOF'
#!/bin/bash
# Restart kiln monitoring services in proper order

echo "Restarting Kiln Monitoring Services..."
echo "Date: $(date)"

# Stop services in reverse dependency order
echo "Stopping services..."
systemctl stop kiln-ocr.service || true
systemctl stop frigate.service || true
systemctl stop mosquitto.service || true

# Wait for clean shutdown
sleep 5

# Start services in dependency order
echo "Starting mosquitto..."
systemctl start mosquitto.service
sleep 3

echo "Starting frigate..."
systemctl start frigate.service
sleep 5

echo "Starting kiln-ocr..."
systemctl start kiln-ocr.service
sleep 3

# Check status
echo ""
echo "Service Status:"
systemctl is-active mosquitto.service frigate.service kiln-ocr.service

echo ""
echo "Kiln services restart completed at $(date)"
EOF

chmod +x /usr/local/bin/restart-kiln-services.sh

# Create manual container cleanup script
log "Creating manual container cleanup script..."

cat > /usr/local/bin/cleanup-container-temps.sh << 'EOF'
#!/bin/bash
# Manual Container Temporary Directory Cleanup
# Prevents the accumulation of container_images_storage* directories that can consume 15GB+

echo "🧹 Container Temporary Directory Cleanup"
echo "Date: $(date)"
echo ""

# Check current disk usage
echo "Current disk usage:"
df -h / | grep -E "(Filesystem|/)"
echo ""

# Check temp directory sizes before cleanup
echo "Container temp directories before cleanup:"
if ls /var/tmp/container_images_storage* >/dev/null 2>&1; then
    du -sh /var/tmp/container_images_storage* 2>/dev/null | head -10
    TEMP_COUNT=$(ls -1d /var/tmp/container_images_storage* 2>/dev/null | wc -l)
    echo "Found $TEMP_COUNT container temp directories"
else
    echo "No container temp directories found"
fi
echo ""

# Perform cleanup
echo "Cleaning container temporary directories..."
find /var/tmp -name "container_images_storage*" -type d -exec rm -rf {} \; 2>/dev/null || true
find /var/tmp -name "libpod_tmp_*" -type d -exec rm -rf {} \; 2>/dev/null || true
find /var/tmp -name "buildah*" -type d -exec rm -rf {} \; 2>/dev/null || true

# Clean container temp files
find /var/tmp -name "*container*" -type f -mtime +0 -delete 2>/dev/null || true
find /var/tmp -name "*podman*" -type f -mtime +0 -delete 2>/dev/null || true

# Clean old containers and images
echo "Cleaning old containers and images..."
podman system prune -f --filter until=24h 2>/dev/null || true

echo ""
echo "Cleanup completed!"
echo "Final disk usage:"
df -h / | grep -E "(Filesystem|/)"
echo ""
echo "Container temp directories after cleanup:"
if ls /var/tmp/container_images_storage* >/dev/null 2>&1; then
    du -sh /var/tmp/container_images_storage* 2>/dev/null | head -5
else
    echo "✅ All container temp directories cleaned"
fi
EOF

chmod +x /usr/local/bin/cleanup-container-temps.sh

# Enable and configure systemd services
log "Enabling systemd services and timers..."

# Reload systemd configuration
systemctl daemon-reload

# Enable core services
systemctl enable mosquitto.service
systemctl enable frigate.service
systemctl enable kiln-ocr.service

# Enable backup and cleanup timers
systemctl enable kiln-backup.timer
systemctl enable kiln-cleanup.timer

# Enable auto-update timer
systemctl enable podman-auto-update-kiln.timer

# Enable container cleanup timer
systemctl enable container-cleanup-kiln.timer

# Enable certificate monitoring
systemctl enable cert-monitor.timer

# Start timers (services will be started manually or by image build)
systemctl start kiln-backup.timer
systemctl start kiln-cleanup.timer
systemctl start podman-auto-update-kiln.timer
systemctl start container-cleanup-kiln.timer
systemctl start cert-monitor.timer

# Configure service startup order test
log "Creating startup order test script..."

cat > /usr/local/bin/test-kiln-startup.sh << 'EOF'
#!/bin/bash
# Test service startup order and dependencies

echo "=== Kiln Monitoring Startup Order Test ==="
echo "Date: $(date)"

# Stop all services
echo "Stopping all services..."
systemctl stop kiln-ocr.service frigate.service mosquitto.service

# Wait for clean stop
sleep 5

# Test dependency order by starting base service
echo "Starting mosquitto (base service)..."
systemctl start mosquitto.service

# Wait and check
sleep 3
if systemctl is-active mosquitto.service >/dev/null; then
    echo "✅ Mosquitto started successfully"
else
    echo "❌ Mosquitto failed to start"
    exit 1
fi

# Start frigate (depends on mosquitto)
echo "Starting frigate..."
systemctl start frigate.service

# Wait and check
sleep 10
if systemctl is-active frigate.service >/dev/null; then
    echo "✅ Frigate started successfully"
else
    echo "❌ Frigate failed to start"
    journalctl -u frigate.service --lines 10 --no-pager
    exit 1
fi

# Start OCR service (depends on both)
echo "Starting kiln-ocr..."
systemctl start kiln-ocr.service

# Wait and check
sleep 5
if systemctl is-active kiln-ocr.service >/dev/null; then
    echo "✅ Kiln OCR started successfully"
else
    echo "❌ Kiln OCR failed to start"
    journalctl -u kiln-ocr.service --lines 10 --no-pager
    exit 1
fi

echo ""
echo "=== Final Service Status ==="
systemctl status mosquitto.service frigate.service kiln-ocr.service --no-pager --lines 0

echo ""
echo "✅ Startup order test completed successfully!"
EOF

chmod +x /usr/local/bin/test-kiln-startup.sh

# Restart journald to apply new configuration
systemctl restart systemd-journald

log "🔧 System integration completed successfully!"
log ""
log "📊 Management Commands:"
log "   Health check: /usr/local/bin/kiln-health-check.sh"
log "   Restart services: /usr/local/bin/restart-kiln-services.sh"
log "   Container cleanup: /usr/local/bin/cleanup-container-temps.sh"
log "   Test startup order: /usr/local/bin/test-kiln-startup.sh"
log ""
log "🌐 Cockpit Integration:"
log "   Kiln monitoring panel available at: https://192.168.7.200:9090"
log ""
log "📋 Enabled Services:"
log "   - mosquitto.service (MQTT broker)"
log "   - frigate.service (NVR)"
log "   - kiln-ocr.service (OCR processing)"
log ""
log "⏰ Enabled Timers:"
log "   - kiln-backup.timer (daily backups)"
log "   - kiln-cleanup.timer (daily cleanup)"
log "   - container-cleanup-kiln.timer (daily container temp cleanup)"
log "   - podman-auto-update-kiln.timer (weekly updates)"
log "   - cert-monitor.timer (weekly certificate check)"
log ""
log "📝 Log Rotation:"
log "   - All service logs configured for rotation"
log "   - 30-day retention for service logs"
log "   - 14-day retention for system logs" 