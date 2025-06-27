#!/bin/bash
# Firewall Configuration for Kiln Monitoring System
# Sets up secure network access for Frigate, MQTT, and related services

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

# Check if running as root or with sudo
if [[ $EUID -ne 0 ]]; then
    error "This script must be run as root or with sudo"
    exit 1
fi

log "🔥 Configuring firewall for Kiln Monitoring System"

# Network configuration
LOCAL_NETWORK="192.168.0.0/16"  # Adjust based on your network
HOME_ASSISTANT_IP="192.168.5.0/24"  # Home Assistant network
FITLET_IP="192.168.7.200"  # This device

# Service ports
FRIGATE_WEB_PORT="5000"
FRIGATE_RTSP_PORT="8554"
FRIGATE_WEBRTC_PORT="8555"
MQTT_PORT="1883"
MQTT_WEBSOCKET_PORT="9001"
SSH_PORT="22"
COCKPIT_PORT="9090"

# Check if firewalld is available
if command -v firewall-cmd &> /dev/null; then
    FIREWALL_TYPE="firewalld"
    log "Using firewalld for firewall configuration"
elif command -v ufw &> /dev/null; then
    FIREWALL_TYPE="ufw"
    log "Using UFW for firewall configuration"
elif command -v iptables &> /dev/null; then
    FIREWALL_TYPE="iptables"
    log "Using iptables for firewall configuration"
else
    error "No supported firewall found (firewalld, ufw, or iptables)"
    exit 1
fi

configure_firewalld() {
    log "Configuring firewalld rules..."
    
    # Enable firewalld
    systemctl enable --now firewalld
    
    # Set default zone to public (restrictive)
    firewall-cmd --set-default-zone=public
    
    # Allow SSH from local network only
    firewall-cmd --permanent --zone=public --add-rich-rule="rule family='ipv4' source address='$LOCAL_NETWORK' service name='ssh' accept"
    
    # Allow Cockpit from local network only
    firewall-cmd --permanent --zone=public --add-rich-rule="rule family='ipv4' source address='$LOCAL_NETWORK' port protocol='tcp' port='$COCKPIT_PORT' accept"
    
    # Frigate web interface - local network only
    firewall-cmd --permanent --zone=public --add-rich-rule="rule family='ipv4' source address='$LOCAL_NETWORK' port protocol='tcp' port='$FRIGATE_WEB_PORT' accept"
    
    # Frigate RTSP stream - local network only
    firewall-cmd --permanent --zone=public --add-rich-rule="rule family='ipv4' source address='$LOCAL_NETWORK' port protocol='tcp' port='$FRIGATE_RTSP_PORT' accept"
    
    # Frigate WebRTC - local network only
    firewall-cmd --permanent --zone=public --add-rich-rule="rule family='ipv4' source address='$LOCAL_NETWORK' port protocol='tcp' port='$FRIGATE_WEBRTC_PORT' accept"
    firewall-cmd --permanent --zone=public --add-rich-rule="rule family='ipv4' source address='$LOCAL_NETWORK' port protocol='udp' port='$FRIGATE_WEBRTC_PORT' accept"
    
    # MQTT broker - allow from Home Assistant network and local network
    firewall-cmd --permanent --zone=public --add-rich-rule="rule family='ipv4' source address='$HOME_ASSISTANT_IP' port protocol='tcp' port='$MQTT_PORT' accept"
    firewall-cmd --permanent --zone=public --add-rich-rule="rule family='ipv4' source address='$LOCAL_NETWORK' port protocol='tcp' port='$MQTT_PORT' accept"
    
    # MQTT WebSocket - local network only
    firewall-cmd --permanent --zone=public --add-rich-rule="rule family='ipv4' source address='$LOCAL_NETWORK' port protocol='tcp' port='$MQTT_WEBSOCKET_PORT' accept"
    
    # Allow container traffic on podman networks
    firewall-cmd --permanent --zone=public --add-interface=podman0 2>/dev/null || true
    firewall-cmd --permanent --zone=public --add-masquerade
    
    # Block all other incoming traffic by default
    firewall-cmd --permanent --zone=public --set-target=DROP
    
    # Reload firewall rules
    firewall-cmd --reload
    
    log "Firewalld configuration completed"
}

configure_ufw() {
    log "Configuring UFW rules..."
    
    # Reset UFW to defaults
    ufw --force reset
    
    # Set default policies
    ufw default deny incoming
    ufw default allow outgoing
    
    # Allow SSH from local network only
    ufw allow from $LOCAL_NETWORK to any port $SSH_PORT proto tcp
    
    # Allow Cockpit from local network only
    ufw allow from $LOCAL_NETWORK to any port $COCKPIT_PORT proto tcp
    
    # Frigate services - local network only
    ufw allow from $LOCAL_NETWORK to any port $FRIGATE_WEB_PORT proto tcp
    ufw allow from $LOCAL_NETWORK to any port $FRIGATE_RTSP_PORT proto tcp
    ufw allow from $LOCAL_NETWORK to any port $FRIGATE_WEBRTC_PORT proto tcp
    ufw allow from $LOCAL_NETWORK to any port $FRIGATE_WEBRTC_PORT proto udp
    
    # MQTT broker - Home Assistant and local network
    ufw allow from $HOME_ASSISTANT_IP to any port $MQTT_PORT proto tcp
    ufw allow from $LOCAL_NETWORK to any port $MQTT_PORT proto tcp
    ufw allow from $LOCAL_NETWORK to any port $MQTT_WEBSOCKET_PORT proto tcp
    
    # Enable UFW
    ufw --force enable
    
    log "UFW configuration completed"
}

configure_iptables() {
    log "Configuring iptables rules..."
    
    # Save current rules
    iptables-save > /etc/iptables.rules.backup
    
    # Flush existing rules
    iptables -F
    iptables -X
    iptables -t nat -F
    iptables -t nat -X
    
    # Set default policies
    iptables -P INPUT DROP
    iptables -P FORWARD DROP
    iptables -P OUTPUT ACCEPT
    
    # Allow loopback traffic
    iptables -A INPUT -i lo -j ACCEPT
    iptables -A OUTPUT -o lo -j ACCEPT
    
    # Allow established and related connections
    iptables -A INPUT -m state --state ESTABLISHED,RELATED -j ACCEPT
    
    # Allow SSH from local network
    iptables -A INPUT -s $LOCAL_NETWORK -p tcp --dport $SSH_PORT -j ACCEPT
    
    # Allow Cockpit from local network
    iptables -A INPUT -s $LOCAL_NETWORK -p tcp --dport $COCKPIT_PORT -j ACCEPT
    
    # Allow Frigate services from local network
    iptables -A INPUT -s $LOCAL_NETWORK -p tcp --dport $FRIGATE_WEB_PORT -j ACCEPT
    iptables -A INPUT -s $LOCAL_NETWORK -p tcp --dport $FRIGATE_RTSP_PORT -j ACCEPT
    iptables -A INPUT -s $LOCAL_NETWORK -p tcp --dport $FRIGATE_WEBRTC_PORT -j ACCEPT
    iptables -A INPUT -s $LOCAL_NETWORK -p udp --dport $FRIGATE_WEBRTC_PORT -j ACCEPT
    
    # Allow MQTT from Home Assistant network and local network
    iptables -A INPUT -s $HOME_ASSISTANT_IP -p tcp --dport $MQTT_PORT -j ACCEPT
    iptables -A INPUT -s $LOCAL_NETWORK -p tcp --dport $MQTT_PORT -j ACCEPT
    iptables -A INPUT -s $LOCAL_NETWORK -p tcp --dport $MQTT_WEBSOCKET_PORT -j ACCEPT
    
    # Allow container traffic
    iptables -A INPUT -i podman0 -j ACCEPT
    iptables -A FORWARD -i podman0 -j ACCEPT
    iptables -A FORWARD -o podman0 -j ACCEPT
    
    # Save rules
    iptables-save > /etc/iptables.rules
    
    # Create service to restore rules on boot
    cat > /etc/systemd/system/iptables-restore.service << 'EOF'
[Unit]
Description=Restore iptables rules
Before=network-pre.target
Wants=network-pre.target

[Service]
Type=oneshot
ExecStart=/sbin/iptables-restore /etc/iptables.rules

[Install]
WantedBy=multi-user.target
EOF
    
    systemctl enable iptables-restore.service
    
    log "iptables configuration completed"
}

# Configure based on available firewall
case $FIREWALL_TYPE in
    "firewalld")
        configure_firewalld
        ;;
    "ufw")
        configure_ufw
        ;;
    "iptables")
        configure_iptables
        ;;
esac

# Create firewall status check script
log "Creating firewall status check script..."

cat > /usr/local/bin/check-kiln-firewall.sh << 'EOF'
#!/bin/bash
# Check firewall status for kiln monitoring system

echo "=== Kiln Monitoring Firewall Status ==="
echo "Date: $(date)"
echo ""

# Check firewall service
if command -v firewall-cmd &> /dev/null; then
    echo "Firewall Type: firewalld"
    echo "Status: $(systemctl is-active firewalld)"
    echo "Default Zone: $(firewall-cmd --get-default-zone)"
    echo ""
    echo "Active Rules:"
    firewall-cmd --list-all
elif command -v ufw &> /dev/null; then
    echo "Firewall Type: UFW"
    echo "Status: $(ufw status | head -1)"
    echo ""
    echo "Active Rules:"
    ufw status numbered
elif command -v iptables &> /dev/null; then
    echo "Firewall Type: iptables"
    echo ""
    echo "Active Rules:"
    iptables -L -n --line-numbers
fi

echo ""
echo "=== Port Check ==="
# Check if services are listening on expected ports
netstat -tuln | grep -E ':(5000|8554|8555|1883|9001|22|9090)\b' || echo "No services found on expected ports"

echo ""
echo "=== Network Connectivity Test ==="
# Test connectivity to MQTT broker
if nc -z localhost 1883 2>/dev/null; then
    echo "✅ MQTT broker (1883): Accessible"
else
    echo "❌ MQTT broker (1883): Not accessible"
fi

# Test connectivity to Frigate
if nc -z localhost 5000 2>/dev/null; then
    echo "✅ Frigate web (5000): Accessible"
else
    echo "❌ Frigate web (5000): Not accessible"
fi
EOF

chmod +x /usr/local/bin/check-kiln-firewall.sh

# Test firewall configuration
log "Testing firewall configuration..."

# Check if services are accessible locally
if nc -z localhost $MQTT_PORT 2>/dev/null; then
    log "✅ MQTT broker is accessible locally"
else
    warn "⚠️  MQTT broker not accessible locally (service may not be running)"
fi

if nc -z localhost $FRIGATE_WEB_PORT 2>/dev/null; then
    log "✅ Frigate web interface is accessible locally"
else
    warn "⚠️  Frigate web interface not accessible locally (service may not be running)"
fi

# Create network security audit script
log "Creating network security audit script..."

cat > /usr/local/bin/kiln-security-audit.sh << 'EOF'
#!/bin/bash
# Security audit script for kiln monitoring system

echo "=== Kiln Monitoring Security Audit ==="
echo "Date: $(date)"
echo "Hostname: $(hostname)"
echo ""

# Check for open ports
echo "=== Open Ports ==="
ss -tuln | grep LISTEN

echo ""
echo "=== Container Security ==="
# Check container configurations
if command -v podman &> /dev/null; then
    echo "Podman containers:"
    podman ps --format "table {{.Names}}\t{{.Ports}}\t{{.Status}}"
fi

echo ""
echo "=== SSH Security ==="
# Check SSH configuration
if [ -f /etc/ssh/sshd_config ]; then
    echo "SSH Password Authentication: $(grep -E '^PasswordAuthentication' /etc/ssh/sshd_config || echo 'Not configured')"
    echo "SSH Root Login: $(grep -E '^PermitRootLogin' /etc/ssh/sshd_config || echo 'Not configured')"
fi

echo ""
echo "=== SSL/TLS Status ==="
# Check for SSL certificates
if [ -d /ssl ]; then
    echo "SSL certificates found:"
    ls -la /ssl/
else
    echo "⚠️  No SSL certificates directory found"
fi

echo ""
echo "=== File Permissions ==="
# Check critical file permissions
echo "Container configs:"
ls -la /etc/containers/systemd/ 2>/dev/null || echo "No container configs found"

echo ""
echo "Storage permissions:"
ls -la /var/lib/kiln-monitoring/ 2>/dev/null || echo "No storage directory found"

echo ""
echo "=== System Updates ==="
# Check for available updates
if command -v dnf &> /dev/null; then
    echo "Available updates: $(dnf check-update -q | wc -l)"
elif command -v apt &> /dev/null; then
    echo "Available updates: $(apt list --upgradable 2>/dev/null | wc -l)"
fi

echo ""
echo "=== Security Recommendations ==="
# Provide security recommendations
echo "1. Regularly update system packages"
echo "2. Use SSH key authentication only"
echo "3. Consider VPN for remote access"
echo "4. Monitor firewall logs"
echo "5. Review container security settings"
echo "6. Implement SSL/TLS for web interfaces"
EOF

chmod +x /usr/local/bin/kiln-security-audit.sh

log "🔒 Firewall configuration completed!"
log ""
log "📊 Management Commands:"
log "   Check status: /usr/local/bin/check-kiln-firewall.sh"
log "   Security audit: /usr/local/bin/kiln-security-audit.sh"
log ""
log "🔧 Service Access:"
log "   Frigate Web: http://$FITLET_IP:$FRIGATE_WEB_PORT"
log "   MQTT Broker: $FITLET_IP:$MQTT_PORT"
log "   Cockpit: https://$FITLET_IP:$COCKPIT_PORT"
log ""
log "⚠️  Note: Services are restricted to local network ($LOCAL_NETWORK)"
log "🏠 Home Assistant can access MQTT from: $HOME_ASSISTANT_IP" 