#!/bin/bash
# Comprehensive Testing and Validation for Kiln Monitoring System
# Tests all components, integration, and validates system functionality

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

success() {
    echo -e "${GREEN}✅ $1${NC}"
}

fail() {
    echo -e "${RED}❌ $1${NC}"
}

# Test tracking
TESTS_TOTAL=0
TESTS_PASSED=0
TESTS_FAILED=0

run_test() {
    local test_name="$1"
    local test_command="$2"
    
    ((TESTS_TOTAL++))
    echo -n "Testing $test_name... "
    
    if eval "$test_command" &>/dev/null; then
        success "$test_name"
        ((TESTS_PASSED++))
        return 0
    else
        fail "$test_name"
        ((TESTS_FAILED++))
        return 1
    fi
}

log "🧪 Starting comprehensive testing and validation for Kiln Monitoring System"

# Prerequisites check
log "Checking prerequisites..."
if [[ $EUID -ne 0 ]]; then
    warn "Some tests require root privileges. Consider running with sudo for complete testing."
fi

# Test 1: Service Status Tests
log "=== Service Status Tests ==="

run_test "Mosquitto service is active" "systemctl is-active mosquitto.service"
run_test "Frigate service is active" "systemctl is-active frigate.service"
run_test "Kiln OCR service is active" "systemctl is-active kiln-ocr.service"
run_test "Cockpit service is active" "systemctl is-active cockpit.service"
run_test "SSH service is active" "systemctl is-active ssh.service"

# Test 2: Network Connectivity Tests  
log "=== Network Connectivity Tests ==="

run_test "MQTT broker port 1883" "nc -z localhost 1883"
run_test "MQTT WebSocket port 9001" "nc -z localhost 9001"
run_test "Frigate web port 5000" "nc -z localhost 5000"
run_test "Frigate RTSP port 8554" "nc -z localhost 8554"
run_test "Cockpit port 9090" "nc -z localhost 9090"
run_test "SSH port 22" "nc -z localhost 22"

# Test SSL/TLS ports if available
if [ -f /ssl/certs/server-cert.pem ]; then
    run_test "MQTT SSL port 8883" "nc -z localhost 8883"
    run_test "MQTT WebSocket SSL port 9002" "nc -z localhost 9002"
fi

# Test 3: Container Tests
log "=== Container Tests ==="

if command -v podman &> /dev/null; then
    run_test "Mosquitto container running" "podman ps --filter name=mosquitto --filter status=running --quiet | grep -q ."
    run_test "Frigate container running" "podman ps --filter name=frigate --filter status=running --quiet | grep -q ."
    run_test "Kiln OCR container running" "podman ps --filter name=kiln-ocr --filter status=running --quiet | grep -q ."
else
    warn "Podman not available - skipping container tests"
fi

# Test 4: MQTT Authentication Tests
log "=== MQTT Authentication Tests ==="

if [ -f /var/lib/kiln-monitoring/mosquitto-config/credentials.txt ]; then
    # Extract credentials for testing
    ADMIN_USER="admin"
    ADMIN_PASS=$(grep -A1 "Admin User" /var/lib/kiln-monitoring/mosquitto-config/credentials.txt | grep "Password:" | cut -d' ' -f2)
    
    if [ -n "$ADMIN_PASS" ]; then
        run_test "MQTT admin authentication" "mosquitto_pub -h localhost -p 1883 -u $ADMIN_USER -P $ADMIN_PASS -t test/auth -m 'test' -q 1"
        run_test "MQTT admin subscription" "timeout 3 mosquitto_sub -h localhost -p 1883 -u $ADMIN_USER -P $ADMIN_PASS -t test/auth -C 1"
    else
        warn "Could not extract MQTT credentials for testing"
    fi
else
    warn "MQTT credentials file not found - skipping authentication tests"
fi

# Test 5: Storage and File System Tests
log "=== Storage and File System Tests ==="

run_test "Frigate config directory exists" "[ -d /var/lib/kiln-monitoring/frigate-config ]"
run_test "Frigate media directory exists" "[ -d /var/lib/kiln-monitoring/frigate-media ]"
run_test "MQTT config directory exists" "[ -d /var/lib/kiln-monitoring/mosquitto-config ]"
run_test "Kiln data directory exists" "[ -d /var/lib/kiln-monitoring ]"
run_test "Backup directory exists" "[ -d /var/backups/kiln-monitoring ]"

run_test "Frigate config writable" "[ -w /var/lib/kiln-monitoring/frigate-config ]"
run_test "Kiln data directory writable" "[ -w /var/lib/kiln-monitoring ]"

# Test 6: SSL Certificate Tests
log "=== SSL Certificate Tests ==="

if [ -f /ssl/certs/server-cert.pem ]; then
    run_test "Server certificate exists" "[ -f /ssl/certs/server-cert.pem ]"
    run_test "CA certificate exists" "[ -f /ssl/certs/ca-cert.pem ]"
    run_test "Server private key exists" "[ -f /ssl/private/server-key.pem ]"
    run_test "Certificate is valid" "openssl x509 -noout -checkend 0 -in /ssl/certs/server-cert.pem"
    run_test "Certificate not expiring soon" "openssl x509 -noout -checkend 2592000 -in /ssl/certs/server-cert.pem"
else
    warn "SSL certificates not found - skipping certificate tests"
fi

# Test 7: Configuration File Tests
log "=== Configuration File Tests ==="

run_test "Frigate config exists" "[ -f /var/lib/kiln-monitoring/frigate-config/config.yml ]"
run_test "Mosquitto config exists" "[ -f /var/lib/kiln-monitoring/mosquitto-config/mosquitto.conf ]"
run_test "OCR requirements file exists" "[ -f /kiln-ocr/requirements.txt ]"

# Validate YAML syntax
if command -v python3 &> /dev/null; then
    run_test "Frigate config valid YAML" "python3 -c 'import yaml; yaml.safe_load(open(\"/var/lib/kiln-monitoring/frigate-config/config.yml\"))'"
fi

# Test 8: API Endpoint Tests
log "=== API Endpoint Tests ==="

run_test "Frigate API accessible" "curl -s -f http://localhost:5000/api/stats >/dev/null"
run_test "Frigate camera config" "curl -s -f http://localhost:5000/api/config >/dev/null"

# Test 9: OCR Processing Tests (Simulated)
log "=== OCR Processing Tests ==="

if [ -f /kiln-ocr/ocr_processor.py ]; then
    run_test "OCR processor script executable" "[ -x /kiln-ocr/ocr_processor.py ] || python3 -m py_compile /kiln-ocr/ocr_processor.py"
    run_test "Temperature logger script executable" "[ -x /kiln-ocr/temperature-logger.py ] || python3 -m py_compile /kiln-ocr/temperature-logger.py"
    
    # Test OCR dependencies
    run_test "OpenCV available" "python3 -c 'import cv2'"
    run_test "Tesseract available" "python3 -c 'import pytesseract'"
    run_test "MQTT client available" "python3 -c 'import paho.mqtt.client'"
fi

# Test 10: Backup and Maintenance Tests
log "=== Backup and Maintenance Tests ==="

run_test "Backup script exists" "[ -f /var/lib/kiln-monitoring/backup-kiln-data.sh ]"
run_test "Cleanup script exists" "[ -f /var/lib/kiln-monitoring/cleanup-kiln-data.sh ]"
run_test "Backup timer enabled" "systemctl is-enabled kiln-backup.timer"
run_test "Cleanup timer enabled" "systemctl is-enabled kiln-cleanup.timer"

# Test 11: Security Tests
log "=== Security Tests ==="

# Check firewall status
if command -v firewall-cmd &> /dev/null; then
    run_test "Firewall is active" "systemctl is-active firewalld"
elif command -v ufw &> /dev/null; then
    run_test "UFW firewall is active" "ufw status | grep -q active"
fi

# Check file permissions
run_test "SSL private keys secured" "[ \$(stat -c %a /ssl/private 2>/dev/null) = '700' ] || [ ! -d /ssl/private ]"
run_test "MQTT password file secured" "[ \$(stat -c %a /var/lib/kiln-monitoring/mosquitto-config/auth/passwd 2>/dev/null) = '600' ] || [ ! -f /var/lib/kiln-monitoring/mosquitto-config/auth/passwd ]"

# Test 12: Performance and Resource Tests
log "=== Performance and Resource Tests ==="

# Check disk space
DISK_USAGE=$(df /var/lib/kiln-monitoring 2>/dev/null | awk 'NR==2 {print $5}' | sed 's/%//' || echo "0")
run_test "Sufficient disk space (<80% used)" "[ $DISK_USAGE -lt 80 ]"

# Check memory usage
MEMORY_USAGE=$(free | awk 'NR==2{printf "%.0f", $3*100/$2}')
run_test "Reasonable memory usage (<90%)" "[ $MEMORY_USAGE -lt 90 ]"

# Test 13: Integration Tests
log "=== Integration Tests ==="

# Test service restart sequence
if [[ $EUID -eq 0 ]]; then
    log "Testing service restart sequence..."
    
    # Stop services in reverse order
    systemctl stop kiln-ocr.service || true
    sleep 2
    systemctl stop frigate.service || true
    sleep 2
    systemctl stop mosquitto.service || true
    sleep 3
    
    # Start services in proper order
    systemctl start mosquitto.service
    sleep 3
    run_test "Mosquitto restart successful" "systemctl is-active mosquitto.service"
    
    systemctl start frigate.service
    sleep 10
    run_test "Frigate restart successful" "systemctl is-active frigate.service"
    
    systemctl start kiln-ocr.service
    sleep 5
    run_test "Kiln OCR restart successful" "systemctl is-active kiln-ocr.service"
else
    warn "Skipping service restart test (requires root)"
fi

# Test 14: Data Persistence Test
log "=== Data Persistence Tests ==="

# Create test data
TEST_DIR="/var/lib/kiln-monitoring/test-data"
mkdir -p "$TEST_DIR"
echo "test-$(date +%s)" > "$TEST_DIR/persistence-test.txt"

run_test "Test data created" "[ -f $TEST_DIR/persistence-test.txt ]"

# Test MQTT data persistence
if [ -d /var/lib/kiln-monitoring/mosquitto/data ]; then
    run_test "MQTT data directory accessible" "[ -d /var/lib/kiln-monitoring/mosquitto/data ]"
fi

# Test 15: Web Interface Tests
log "=== Web Interface Tests ==="

run_test "Frigate web interface responds" "curl -s -f http://localhost:5000 >/dev/null"
run_test "Cockpit web interface responds" "curl -s -k -f https://localhost:9090 >/dev/null"

# Test 16: Log File Tests
log "=== Log File Tests ==="

run_test "Systemd journal accessible" "journalctl --no-pager -n 1 >/dev/null"
run_test "Service logs readable" "journalctl -u mosquitto.service --no-pager -n 1 >/dev/null"

# Test 17: Cleanup test data
if [ -d "$TEST_DIR" ]; then
    rm -rf "$TEST_DIR"
fi

# Final Results
log "=== Test Summary ==="
echo ""
echo "📊 Testing Results:"
echo "   Total Tests: $TESTS_TOTAL"
echo "   Passed: $TESTS_PASSED"
echo "   Failed: $TESTS_FAILED"
echo "   Success Rate: $(( TESTS_PASSED * 100 / TESTS_TOTAL ))%"
echo ""

if [ $TESTS_FAILED -eq 0 ]; then
    success "All tests passed! Kiln monitoring system is fully functional."
    exit 0
else
    error "$TESTS_FAILED tests failed. Please review the issues above."
    exit 1
fi 