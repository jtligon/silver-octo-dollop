#!/bin/bash
# SSL Certificate Setup for Kiln Monitoring System
# Creates self-signed certificates for secure web access

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

log "🔐 Setting up SSL certificates for Kiln Monitoring System"

# Configuration
SSL_DIR="/ssl"
CERT_DIR="$SSL_DIR/certs"
KEY_DIR="$SSL_DIR/private"
FITLET_IP="192.168.7.200"
HOSTNAME=$(hostname)
DOMAIN="kiln.local"  # You can customize this

# Create SSL directories
mkdir -p "$CERT_DIR"
mkdir -p "$KEY_DIR"
chmod 755 "$SSL_DIR"
chmod 755 "$CERT_DIR"
chmod 700 "$KEY_DIR"

# Generate Certificate Authority (CA)
log "Creating Certificate Authority..."

# CA private key
openssl genrsa -out "$KEY_DIR/ca-key.pem" 4096

# CA certificate
cat > /tmp/ca.conf << EOF
[req]
distinguished_name = req_distinguished_name
x509_extensions = v3_ca
prompt = no

[req_distinguished_name]
C = US
ST = State
L = City
O = Kiln Monitoring
OU = IT Department
CN = Kiln Monitoring CA

[v3_ca]
basicConstraints = critical, CA:TRUE
keyUsage = critical, digitalSignature, keyEncipherment, keyCertSign
subjectKeyIdentifier = hash
authorityKeyIdentifier = keyid:always, issuer:always
EOF

openssl req -new -x509 -days 3650 -key "$KEY_DIR/ca-key.pem" \
    -out "$CERT_DIR/ca-cert.pem" -config /tmp/ca.conf

# Generate server certificates
log "Creating server certificates..."

# Server private key
openssl genrsa -out "$KEY_DIR/server-key.pem" 4096

# Server certificate signing request
cat > /tmp/server.conf << EOF
[req]
distinguished_name = req_distinguished_name
req_extensions = v3_req
prompt = no

[req_distinguished_name]
C = US
ST = State
L = City
O = Kiln Monitoring
OU = IT Department
CN = $HOSTNAME

[v3_req]
basicConstraints = CA:FALSE
keyUsage = nonRepudiation, digitalSignature, keyEncipherment
subjectAltName = @alt_names

[alt_names]
DNS.1 = $HOSTNAME
DNS.2 = $DOMAIN
DNS.3 = localhost
IP.1 = $FITLET_IP
IP.2 = 127.0.0.1
EOF

openssl req -new -key "$KEY_DIR/server-key.pem" \
    -out /tmp/server.csr -config /tmp/server.conf

# Sign server certificate with CA
openssl x509 -req -in /tmp/server.csr -CA "$CERT_DIR/ca-cert.pem" \
    -CAkey "$KEY_DIR/ca-key.pem" -CAcreateserial \
    -out "$CERT_DIR/server-cert.pem" -days 365 \
    -extensions v3_req -extfile /tmp/server.conf

# Generate client certificates for authentication
log "Creating client certificates..."

# Client private key
openssl genrsa -out "$KEY_DIR/client-key.pem" 4096

# Client certificate signing request
cat > /tmp/client.conf << EOF
[req]
distinguished_name = req_distinguished_name
prompt = no

[req_distinguished_name]
C = US
ST = State
L = City
O = Kiln Monitoring
OU = IT Department
CN = Kiln Monitoring Client
EOF

openssl req -new -key "$KEY_DIR/client-key.pem" \
    -out /tmp/client.csr -config /tmp/client.conf

# Sign client certificate
openssl x509 -req -in /tmp/client.csr -CA "$CERT_DIR/ca-cert.pem" \
    -CAkey "$KEY_DIR/ca-key.pem" -CAcreateserial \
    -out "$CERT_DIR/client-cert.pem" -days 365

# Create certificate bundles
log "Creating certificate bundles..."

# Full chain certificate
cat "$CERT_DIR/server-cert.pem" "$CERT_DIR/ca-cert.pem" > "$CERT_DIR/fullchain.pem"

# Combined certificate and key for some applications
cat "$CERT_DIR/server-cert.pem" "$KEY_DIR/server-key.pem" > "$CERT_DIR/server-combined.pem"

# Set proper permissions
chmod 644 "$CERT_DIR"/*.pem
chmod 600 "$KEY_DIR"/*.pem
chown -R root:root "$SSL_DIR"

# Create certificate info file
log "Creating certificate information file..."

cat > "$SSL_DIR/cert-info.txt" << EOF
Kiln Monitoring SSL Certificates
================================
Generated: $(date)
Hostname: $HOSTNAME
IP Address: $FITLET_IP
Domain: $DOMAIN

Certificate Files:
- CA Certificate: $CERT_DIR/ca-cert.pem
- Server Certificate: $CERT_DIR/server-cert.pem
- Server Private Key: $KEY_DIR/server-key.pem
- Full Chain: $CERT_DIR/fullchain.pem
- Combined: $CERT_DIR/server-combined.pem

Certificate Validity:
- CA Certificate: 10 years
- Server Certificate: 1 year
- Client Certificate: 1 year

Usage:
- Import ca-cert.pem into browser/client trust store
- Use server-cert.pem and server-key.pem for web servers
- Use fullchain.pem for applications requiring full certificate chain

Certificate Fingerprints:
CA Certificate:
$(openssl x509 -noout -fingerprint -sha256 -in "$CERT_DIR/ca-cert.pem")

Server Certificate:
$(openssl x509 -noout -fingerprint -sha256 -in "$CERT_DIR/server-cert.pem")
EOF

# Configure Cockpit to use SSL
log "Configuring Cockpit SSL..."

if [ -d /etc/cockpit ]; then
    # Create Cockpit SSL configuration
    mkdir -p /etc/cockpit/ws-certs.d
    
    # Copy certificates for Cockpit
    cp "$CERT_DIR/server-cert.pem" /etc/cockpit/ws-certs.d/
    cp "$KEY_DIR/server-key.pem" /etc/cockpit/ws-certs.d/
    
    # Set permissions
    chmod 644 /etc/cockpit/ws-certs.d/server-cert.pem
    chmod 600 /etc/cockpit/ws-certs.d/server-key.pem
    
    # Restart Cockpit to apply SSL
    systemctl restart cockpit || warn "Could not restart Cockpit service"
    
    log "✅ Cockpit SSL configured"
fi

# Create certificate renewal script
log "Creating certificate renewal script..."

cat > /usr/local/bin/renew-kiln-certificates.sh << 'EOF'
#!/bin/bash
# Certificate renewal script for kiln monitoring

SSL_DIR="/ssl"
CERT_DIR="$SSL_DIR/certs"
KEY_DIR="$SSL_DIR/private"

# Check certificate expiration
check_expiration() {
    local cert_file="$1"
    local days_until_expiry
    
    if [ -f "$cert_file" ]; then
        days_until_expiry=$(openssl x509 -noout -checkend 2592000 -in "$cert_file" && echo "OK" || echo "EXPIRING")
        if [ "$days_until_expiry" = "EXPIRING" ]; then
            echo "Certificate $cert_file expires within 30 days"
            return 1
        fi
    fi
    return 0
}

echo "Checking certificate expiration..."

# Check server certificate
if ! check_expiration "$CERT_DIR/server-cert.pem"; then
    echo "Server certificate needs renewal"
    # Add renewal logic here if needed
fi

# Check client certificate
if ! check_expiration "$CERT_DIR/client-cert.pem"; then
    echo "Client certificate needs renewal"
    # Add renewal logic here if needed
fi

echo "Certificate check completed"
EOF

chmod +x /usr/local/bin/renew-kiln-certificates.sh

# Create certificate monitoring systemd service
cat > /etc/systemd/system/cert-monitor.service << 'EOF'
[Unit]
Description=Certificate Expiration Monitor
After=network.target

[Service]
Type=oneshot
ExecStart=/usr/local/bin/renew-kiln-certificates.sh
StandardOutput=journal
StandardError=journal
EOF

cat > /etc/systemd/system/cert-monitor.timer << 'EOF'
[Unit]
Description=Weekly Certificate Check
Requires=cert-monitor.service

[Timer]
OnCalendar=weekly
Persistent=true

[Install]
WantedBy=timers.target
EOF

# Enable certificate monitoring
systemctl daemon-reload
systemctl enable cert-monitor.timer
systemctl start cert-monitor.timer

# Create client certificate package for Home Assistant
log "Creating client certificate package..."

CLIENT_PACKAGE_DIR="/tmp/kiln-certs-for-homeassistant"
mkdir -p "$CLIENT_PACKAGE_DIR"

cp "$CERT_DIR/ca-cert.pem" "$CLIENT_PACKAGE_DIR/"
cp "$CERT_DIR/client-cert.pem" "$CLIENT_PACKAGE_DIR/"
cp "$KEY_DIR/client-key.pem" "$CLIENT_PACKAGE_DIR/"

cat > "$CLIENT_PACKAGE_DIR/README.txt" << EOF
Kiln Monitoring SSL Certificates for Home Assistant
===================================================

Files included:
- ca-cert.pem: Certificate Authority certificate (trust this in Home Assistant)
- client-cert.pem: Client certificate for authentication
- client-key.pem: Client private key

Usage in Home Assistant:
1. Copy these files to your Home Assistant SSL directory
2. Configure MQTT integration to use SSL with these certificates
3. Import ca-cert.pem as a trusted certificate

MQTT SSL Configuration:
- Certificate: client-cert.pem
- Private Key: client-key.pem
- CA Certificate: ca-cert.pem
EOF

tar -czf "/tmp/kiln-ssl-certificates.tar.gz" -C /tmp kiln-certs-for-homeassistant
rm -rf "$CLIENT_PACKAGE_DIR"

# Cleanup temporary files
rm -f /tmp/ca.conf /tmp/server.conf /tmp/client.conf
rm -f /tmp/server.csr /tmp/client.csr

log "🔐 SSL setup completed successfully!"
log ""
log "📁 Certificate Locations:"
log "   SSL Directory: $SSL_DIR"
log "   CA Certificate: $CERT_DIR/ca-cert.pem"
log "   Server Certificate: $CERT_DIR/server-cert.pem"
log "   Full Chain: $CERT_DIR/fullchain.pem"
log ""
log "🏠 Home Assistant Package:"
log "   Client certificates: /tmp/kiln-ssl-certificates.tar.gz"
log ""
log "🔧 Management Commands:"
log "   Check expiration: /usr/local/bin/renew-kiln-certificates.sh"
log "   Certificate info: cat $SSL_DIR/cert-info.txt"
log ""
log "⚠️  Important:"
log "   1. Import ca-cert.pem into browser trust store to avoid warnings"
log "   2. Use https:// URLs for secure access"
log "   3. Certificates are valid for 1 year and monitored weekly" 