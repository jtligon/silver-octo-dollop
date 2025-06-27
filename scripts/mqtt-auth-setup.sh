#!/bin/bash
# MQTT Authentication Setup for Kiln Monitoring System
# Configures secure authentication for Mosquitto MQTT broker

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

log "🔐 Setting up MQTT authentication for Kiln Monitoring System"

# Configuration
MQTT_CONFIG_DIR="/mosquitto/config"
MQTT_AUTH_DIR="$MQTT_CONFIG_DIR/auth"
MQTT_SSL_DIR="$MQTT_CONFIG_DIR/ssl"

# Create directories
mkdir -p "$MQTT_AUTH_DIR"
mkdir -p "$MQTT_SSL_DIR"

# Generate random passwords
generate_password() {
    openssl rand -base64 32 | tr -d "=+/" | cut -c1-25
}

FRIGATE_PASSWORD=$(generate_password)
HOMEASSISTANT_PASSWORD=$(generate_password)
ADMIN_PASSWORD=$(generate_password)
READONLY_PASSWORD=$(generate_password)

log "Creating MQTT user accounts..."

# Create password file
PASSWD_FILE="$MQTT_AUTH_DIR/passwd"
touch "$PASSWD_FILE"

# Add users with mosquitto_passwd
mosquitto_passwd -c -b "$PASSWD_FILE" "frigate" "$FRIGATE_PASSWORD"
mosquitto_passwd -b "$PASSWD_FILE" "homeassistant" "$HOMEASSISTANT_PASSWORD"
mosquitto_passwd -b "$PASSWD_FILE" "admin" "$ADMIN_PASSWORD"
mosquitto_passwd -b "$PASSWD_FILE" "readonly" "$READONLY_PASSWORD"

# Create ACL (Access Control List) file
log "Creating MQTT access control lists..."

cat > "$MQTT_AUTH_DIR/acl" << 'EOF'
# MQTT Access Control List for Kiln Monitoring System
# Format: user <username>
#         topic [read|write|readwrite] <topic>

# Admin user - full access
user admin
topic readwrite #

# Frigate user - can publish kiln data and read config
user frigate
topic write frigate/+/+/+
topic write frigate/+/+/+/+
topic read frigate/config/+
topic read homeassistant/+

# Home Assistant user - can read all frigate data and publish config
user homeassistant
topic read frigate/+/+/+
topic read frigate/+/+/+/+
topic write homeassistant/+
topic write frigate/config/+

# Read-only user - can only read kiln data
user readonly
topic read frigate/kiln/+/+
topic read frigate/kiln/+/+/+

# Anonymous users are denied (this is enforced by allow_anonymous false)
EOF

# Update main Mosquitto configuration with authentication
log "Updating Mosquitto configuration..."

# Backup original config
cp "$MQTT_CONFIG_DIR/mosquitto.conf" "$MQTT_CONFIG_DIR/mosquitto.conf.backup"

# Create new configuration with authentication
cat > "$MQTT_CONFIG_DIR/mosquitto.conf" << 'EOF'
# Mosquitto MQTT Broker Configuration for Kiln Monitoring
# This broker runs on Fitlet2 and serves Home Assistant on same network

# Persistence settings
persistence true
persistence_location /mosquitto/data/

# Logging
log_dest file /mosquitto/log/mosquitto.log
log_type error
log_type warning
log_type notice
log_type information
log_timestamp true

# Network settings
listener 1883 0.0.0.0
protocol mqtt

# WebSocket listener for web clients
listener 9001 0.0.0.0
protocol websockets

# SSL/TLS listener (secure MQTT)
listener 8883 0.0.0.0
protocol mqtt
cafile /mosquitto/config/ssl/ca-cert.pem
certfile /mosquitto/config/ssl/server-cert.pem
keyfile /mosquitto/config/ssl/server-key.pem
require_certificate false
use_identity_as_username false

# WebSocket SSL listener
listener 9002 0.0.0.0
protocol websockets
cafile /mosquitto/config/ssl/ca-cert.pem
certfile /mosquitto/config/ssl/server-cert.pem
keyfile /mosquitto/config/ssl/server-key.pem

# Authentication settings
allow_anonymous false
password_file /mosquitto/config/auth/passwd
acl_file /mosquitto/config/auth/acl

# Connection settings
max_connections -1
max_queued_messages 1000
message_size_limit 0

# Retain settings for persistent data
max_inflight_messages 20
persistent_client_expiration 2m

# Security settings
max_keepalive 65535
max_packet_size 0

# Topics for kiln monitoring (documented for reference)
# frigate/kiln/temperature/current
# frigate/kiln/temperature/target  
# frigate/kiln/status/firing
# frigate/kiln/status/errors
# frigate/kiln/ocr/raw
# frigate/kiln/system/storage
EOF

# Copy SSL certificates for MQTT SSL
log "Setting up SSL certificates for MQTT..."

if [ -d "/ssl/certs" ] && [ -d "/ssl/private" ]; then
    cp /ssl/certs/ca-cert.pem "$MQTT_SSL_DIR/"
    cp /ssl/certs/server-cert.pem "$MQTT_SSL_DIR/"
    cp /ssl/private/server-key.pem "$MQTT_SSL_DIR/"
    
    # Set proper permissions
    chmod 644 "$MQTT_SSL_DIR"/*.pem
    chown -R 1883:1883 "$MQTT_SSL_DIR" 2>/dev/null || true
    
    log "✅ SSL certificates configured for MQTT"
else
    warn "⚠️  SSL certificates not found. Run ssl-setup.sh first for secure MQTT."
fi

# Set proper permissions for MQTT files
chown -R 1883:1883 "$MQTT_AUTH_DIR" 2>/dev/null || true
chmod 600 "$PASSWD_FILE"
chmod 644 "$MQTT_AUTH_DIR/acl"

# Create MQTT client configuration files
log "Creating MQTT client configuration files..."

# Frigate client config
cat > "$MQTT_CONFIG_DIR/frigate-client.conf" << EOF
# MQTT Configuration for Frigate
username frigate
password $FRIGATE_PASSWORD
host localhost
port 1883
keepalive 60
client_id frigate_kiln
EOF

# Home Assistant client config
cat > "$MQTT_CONFIG_DIR/homeassistant-client.conf" << EOF
# MQTT Configuration for Home Assistant
username homeassistant
password $HOMEASSISTANT_PASSWORD
host 192.168.7.200
port 1883
keepalive 60
client_id homeassistant_kiln
EOF

# Admin client config (for troubleshooting)
cat > "$MQTT_CONFIG_DIR/admin-client.conf" << EOF
# MQTT Configuration for Admin Access
username admin
password $ADMIN_PASSWORD
host localhost
port 1883
keepalive 60
client_id admin_kiln
EOF

# Set permissions on client configs
chmod 600 "$MQTT_CONFIG_DIR"/*-client.conf

# Create MQTT testing script
log "Creating MQTT testing script..."

cat > /usr/local/bin/test-mqtt-auth.sh << 'EOF'
#!/bin/bash
# Test MQTT authentication and authorization

MQTT_CONFIG_DIR="/mosquitto/config"

echo "=== MQTT Authentication Test ==="
echo "Date: $(date)"
echo ""

# Test function
test_mqtt_access() {
    local username="$1"
    local password="$2"
    local topic="$3"
    local action="$4"
    local test_message="test_$(date +%s)"
    
    echo -n "Testing $username $action access to $topic: "
    
    if [ "$action" = "publish" ]; then
        if mosquitto_pub -h localhost -p 1883 -u "$username" -P "$password" \
           -t "$topic" -m "$test_message" -q 1 2>/dev/null; then
            echo "✅ SUCCESS"
        else
            echo "❌ FAILED"
        fi
    elif [ "$action" = "subscribe" ]; then
        timeout 3 mosquitto_sub -h localhost -p 1883 -u "$username" -P "$password" \
           -t "$topic" -C 1 >/dev/null 2>&1 && echo "✅ SUCCESS" || echo "❌ FAILED"
    fi
}

# Load passwords from config files
if [ -f "$MQTT_CONFIG_DIR/frigate-client.conf" ]; then
    FRIGATE_PASS=$(grep password "$MQTT_CONFIG_DIR/frigate-client.conf" | cut -d' ' -f2)
    HOMEASSISTANT_PASS=$(grep password "$MQTT_CONFIG_DIR/homeassistant-client.conf" | cut -d' ' -f2)
    ADMIN_PASS=$(grep password "$MQTT_CONFIG_DIR/admin-client.conf" | cut -d' ' -f2)
    
    echo "Testing authentication and authorization..."
    echo ""
    
    # Test admin access
    echo "Admin User Tests:"
    test_mqtt_access "admin" "$ADMIN_PASS" "frigate/kiln/temperature/current" "publish"
    test_mqtt_access "admin" "$ADMIN_PASS" "frigate/kiln/temperature/current" "subscribe"
    
    echo ""
    echo "Frigate User Tests:"
    test_mqtt_access "frigate" "$FRIGATE_PASS" "frigate/kiln/temperature/current" "publish"
    test_mqtt_access "frigate" "$FRIGATE_PASS" "homeassistant/sensor/test" "subscribe"
    
    echo ""
    echo "Home Assistant User Tests:"
    test_mqtt_access "homeassistant" "$HOMEASSISTANT_PASS" "frigate/kiln/temperature/current" "subscribe"
    test_mqtt_access "homeassistant" "$HOMEASSISTANT_PASS" "homeassistant/sensor/test" "publish"
    
    echo ""
    echo "Unauthorized Access Tests (should fail):"
    test_mqtt_access "frigate" "$FRIGATE_PASS" "homeassistant/sensor/test" "publish"
    test_mqtt_access "homeassistant" "$HOMEASSISTANT_PASS" "frigate/kiln/temperature/current" "publish"
    
else
    echo "❌ MQTT client configuration files not found"
fi

echo ""
echo "Testing SSL connections..."
if nc -z localhost 8883 2>/dev/null; then
    echo "✅ MQTT SSL port (8883) is accessible"
else
    echo "❌ MQTT SSL port (8883) is not accessible"
fi

if nc -z localhost 9002 2>/dev/null; then
    echo "✅ MQTT WebSocket SSL port (9002) is accessible"
else
    echo "❌ MQTT WebSocket SSL port (9002) is not accessible"
fi
EOF

chmod +x /usr/local/bin/test-mqtt-auth.sh

# Create credential information file
log "Creating credential information file..."

cat > "$MQTT_CONFIG_DIR/credentials.txt" << EOF
MQTT Authentication Credentials for Kiln Monitoring System
=========================================================
Generated: $(date)

User Accounts:
==============

Admin User (full access):
Username: admin
Password: $ADMIN_PASSWORD
Access: Read/Write all topics

Frigate User (kiln data publisher):
Username: frigate
Password: $FRIGATE_PASSWORD
Access: Write frigate/*, Read frigate/config/*, homeassistant/*

Home Assistant User (kiln data consumer):
Username: homeassistant
Password: $HOMEASSISTANT_PASSWORD
Access: Read frigate/*, Write homeassistant/*, frigate/config/*

Read-Only User (monitoring only):
Username: readonly
Password: $READONLY_PASSWORD
Access: Read frigate/kiln/* only

Connection Information:
======================
MQTT (unencrypted): port 1883
MQTT SSL: port 8883
WebSocket: port 9001
WebSocket SSL: port 9002

Home Assistant MQTT Configuration:
==================================
broker: 192.168.7.200
port: 1883
username: homeassistant
password: $HOMEASSISTANT_PASSWORD
discovery: true

For SSL (recommended):
port: 8883
certificate: /path/to/ca-cert.pem
client_cert: /path/to/client-cert.pem
client_key: /path/to/client-key.pem

Security Notes:
===============
- All passwords are randomly generated
- ACL restricts access to appropriate topics per user
- SSL/TLS available on ports 8883 and 9002
- Anonymous access is disabled
- Client certificates available for additional security

Testing:
========
Run: /usr/local/bin/test-mqtt-auth.sh
EOF

# Secure the credentials file
chmod 600 "$MQTT_CONFIG_DIR/credentials.txt"

# Update container configuration to use authentication
log "Updating container configuration..."

# The mosquitto.container file will automatically use the new config
# since we updated the main mosquitto.conf file

log "🔐 MQTT authentication setup completed!"
log ""
log "📁 Configuration Files:"
log "   Main config: $MQTT_CONFIG_DIR/mosquitto.conf"
log "   User accounts: $MQTT_AUTH_DIR/passwd"
log "   Access control: $MQTT_AUTH_DIR/acl"
log "   Credentials: $MQTT_CONFIG_DIR/credentials.txt"
log ""
log "🔧 Management Commands:"
log "   Test authentication: /usr/local/bin/test-mqtt-auth.sh"
log "   View credentials: cat $MQTT_CONFIG_DIR/credentials.txt"
log ""
log "🏠 Home Assistant Configuration:"
log "   Username: homeassistant"
log "   Password: $HOMEASSISTANT_PASSWORD"
log "   Broker: 192.168.7.200:1883"
log ""
log "⚠️  Important:"
log "   1. Update Frigate configuration with new MQTT credentials"
log "   2. Update Home Assistant MQTT integration"
log "   3. Restart MQTT container to apply authentication"
log "   4. Use SSL ports (8883/9002) for secure connections" 