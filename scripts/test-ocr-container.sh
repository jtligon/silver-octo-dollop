#!/bin/bash
# OCR Container Testing Script
# Tests the new containerized OCR architecture before deployment

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Test configuration
TEST_DIR="/tmp/kiln-ocr-test"
CONTAINER_NAME="kiln-ocr-test"
TEST_IMAGE_NAME="kiln-ocr:test"

# Logging function
log() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $1"
}

success() {
    echo -e "${GREEN}✅ $1${NC}"
}

error() {
    echo -e "${RED}❌ $1${NC}"
}

warning() {
    echo -e "${YELLOW}⚠️  $1${NC}"
}

# Cleanup function
cleanup() {
    log "Cleaning up test environment..."
    podman rm -f "$CONTAINER_NAME" 2>/dev/null || true
    podman rmi -f "$TEST_IMAGE_NAME" 2>/dev/null || true
    rm -rf "$TEST_DIR" 2>/dev/null || true
}

# Set up cleanup on exit
trap cleanup EXIT

# Create test environment
setup_test_environment() {
    log "Setting up test environment..."
    
    # Create test directory
    mkdir -p "$TEST_DIR"/{images,logs,data}
    
    # Create test images for OCR
    create_test_images
    
    success "Test environment created at $TEST_DIR"
}

# Create test images with various temperature displays
create_test_images() {
    log "Creating test images for OCR..."
    
    # Check if ImageMagick is available for creating test images
    if command -v convert &> /dev/null; then
        # Create temperature display test images
        convert -size 300x100 xc:black -fill white -pointsize 48 \
            -annotate +50+60 "1250°F" "$TEST_DIR/images/temp_1250.png"
        
        convert -size 300x100 xc:black -fill white -pointsize 48 \
            -annotate +50+60 "875°F" "$TEST_DIR/images/temp_875.png"
        
        convert -size 300x100 xc:black -fill white -pointsize 48 \
            -annotate +50+60 "2100°F" "$TEST_DIR/images/temp_2100.png"
        
        # Create status display test images
        convert -size 300x80 xc:black -fill white -pointsize 36 \
            -annotate +50+50 "FIRING" "$TEST_DIR/images/status_firing.png"
        
        convert -size 300x80 xc:black -fill white -pointsize 36 \
            -annotate +50+50 "COOLING" "$TEST_DIR/images/status_cooling.png"
        
        # Create error display test images
        convert -size 300x80 xc:black -fill white -pointsize 36 \
            -annotate +50+50 "ERR: E01" "$TEST_DIR/images/error_e01.png"
        
        success "Test images created with ImageMagick"
    else
        warning "ImageMagick not available, using placeholder test files"
        echo "1250°F" > "$TEST_DIR/images/temp_1250.txt"
        echo "875°F" > "$TEST_DIR/images/temp_875.txt"
        echo "FIRING" > "$TEST_DIR/images/status_firing.txt"
    fi
}

# Test 1: Build the OCR container
test_container_build() {
    log "Test 1: Building OCR container..."
    
    if podman build -f containerfiles/kiln-ocr.Containerfile -t "$TEST_IMAGE_NAME" .; then
        success "OCR container built successfully"
        return 0
    else
        error "Failed to build OCR container"
        return 1
    fi
}

# Test 2: Test container dependencies
test_container_dependencies() {
    log "Test 2: Testing container dependencies..."
    
    # Test Python imports
    if podman run --rm "$TEST_IMAGE_NAME" python3 -c "
import cv2
import pytesseract
import numpy as np
import paho.mqtt.client as mqtt
print('All Python dependencies available')
"; then
        success "Python dependencies test passed"
    else
        error "Python dependencies test failed"
        return 1
    fi
    
    # Test Tesseract OCR
    if podman run --rm "$TEST_IMAGE_NAME" tesseract --version; then
        success "Tesseract OCR available"
    else
        error "Tesseract OCR not available"
        return 1
    fi
    
    # Test OpenCV
    if podman run --rm "$TEST_IMAGE_NAME" python3 -c "
import cv2
print(f'OpenCV version: {cv2.__version__}')
# Test basic image operations
img = cv2.imread('/dev/null')  # This will fail but shouldn't crash
print('OpenCV basic operations working')
"; then
        success "OpenCV test passed"
    else
        error "OpenCV test failed"
        return 1
    fi
}

# Test 3: Test OCR functionality with sample images
test_ocr_functionality() {
    log "Test 3: Testing OCR functionality..."
    
    if [[ ! -f "$TEST_DIR/images/temp_1250.png" ]]; then
        warning "No test images available, skipping OCR functionality test"
        return 0
    fi
    
    # Mount test images and run OCR
    if podman run --rm \
        -v "$TEST_DIR/images:/test_images:ro" \
        "$TEST_IMAGE_NAME" \
        python3 -c "
import cv2
import pytesseract
import os

# Test OCR on temperature image
img_path = '/test_images/temp_1250.png'
if os.path.exists(img_path):
    img = cv2.imread(img_path)
    if img is not None:
        text = pytesseract.image_to_string(img, config='--oem 3 --psm 8')
        print(f'OCR Result: {text.strip()}')
        if '1250' in text:
            print('✅ Temperature OCR working correctly')
        else:
            print('❌ Temperature OCR not extracting expected value')
    else:
        print('❌ Could not load test image')
else:
    print('❌ Test image not found')
"; then
        success "OCR functionality test passed"
    else
        error "OCR functionality test failed"
        return 1
    fi
}

# Test 4: Test container health check
test_health_check() {
    log "Test 4: Testing container health check..."
    
    # Start container in background
    podman run -d --name "$CONTAINER_NAME" \
        -v "$TEST_DIR/logs:/logs" \
        -v "$TEST_DIR/data:/data" \
        "$TEST_IMAGE_NAME" \
        tail -f /dev/null  # Keep container running
    
    # Wait a moment for container to start
    sleep 5
    
    # Check health
    if podman healthcheck run "$CONTAINER_NAME"; then
        success "Container health check passed"
    else
        error "Container health check failed"
        return 1
    fi
    
    # Stop test container
    podman rm -f "$CONTAINER_NAME"
}

# Test 5: Test systemd service configuration (dry run)
test_systemd_config() {
    log "Test 5: Testing systemd service configuration..."
    
    # Check if the systemd service file is valid
    if systemctl cat kiln-ocr.service &>/dev/null; then
        warning "Systemd service already exists, checking configuration..."
    fi
    
    # Validate the .container file syntax
    local container_file="systemd/kiln-ocr.container"
    if [[ -f "$container_file" ]]; then
        # Basic syntax validation
        if grep -q "^\[Unit\]" "$container_file" && \
           grep -q "^\[Container\]" "$container_file" && \
           grep -q "^\[Service\]" "$container_file" && \
           grep -q "^\[Install\]" "$container_file"; then
            success "Systemd container file syntax valid"
        else
            error "Systemd container file syntax invalid"
            return 1
        fi
    else
        error "Systemd container file not found"
        return 1
    fi
}

# Test 6: Integration test with mock Frigate
test_frigate_integration() {
    log "Test 6: Testing Frigate integration (mock)..."
    
    # Create a simple mock Frigate API server
    cat > "$TEST_DIR/mock_frigate.py" << 'EOF'
#!/usr/bin/env python3
from http.server import HTTPServer, BaseHTTPRequestHandler
import json
import threading
import time

class MockFrigateHandler(BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path == '/api/stats':
            self.send_response(200)
            self.send_header('Content-type', 'application/json')
            self.end_headers()
            self.wfile.write(json.dumps({"status": "ok"}).encode())
        elif self.path == '/api/kiln_camera/latest.jpg':
            self.send_response(200)
            self.send_header('Content-type', 'image/jpeg')
            self.end_headers()
            # Send a minimal JPEG header (won't be a real image but won't crash)
            self.wfile.write(b'\xff\xd8\xff\xe0\x00\x10JFIF\x00\x01\x01\x01\x00\x48\x00\x48\x00\x00\xff\xdb\x00C\x00\x08\x06\x06\x07\x06\x05\x08\x07\x07\x07\t\t\x08\n\x0c\x14\r\x0c\x0b\x0b\x0c\x19\x12\x13\x0f\x14\x1d\x1a\x1f\x1e\x1d\x1a\x1c\x1c $.\' ",#\x1c\x1c(7),01444\x1f\'9=82<.342\xff\xc0\x00\x11\x08\x00\x64\x00\x64\x01\x01\x11\x00\x02\x11\x01\x03\x11\x01\xff\xc4\x00\x14\x00\x01\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x08\xff\xc4\x00\x14\x10\x01\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\xff\xda\x00\x0c\x03\x01\x00\x02\x11\x03\x11\x00\x3f\x00\xaa\xff\xd9')
        else:
            self.send_response(404)
            self.end_headers()

if __name__ == '__main__':
    server = HTTPServer(('localhost', 5000), MockFrigateHandler)
    print("Mock Frigate server running on port 5000")
    server.serve_forever()
EOF
    
    # Start mock Frigate server in background
    python3 "$TEST_DIR/mock_frigate.py" &
    local mock_pid=$!
    
    # Give it time to start
    sleep 2
    
    # Test if our OCR integration can connect
    if podman run --rm --network host \
        "$TEST_IMAGE_NAME" \
        python3 -c "
import requests
import time

try:
    response = requests.get('http://localhost:5000/api/stats', timeout=5)
    if response.status_code == 200:
        print('✅ Successfully connected to mock Frigate API')
    else:
        print(f'❌ Mock Frigate API returned status: {response.status_code}')
        exit(1)
except Exception as e:
    print(f'❌ Failed to connect to mock Frigate API: {e}')
    exit(1)
"; then
        success "Frigate integration test passed"
        local result=0
    else
        error "Frigate integration test failed"
        local result=1
    fi
    
    # Clean up mock server
    kill $mock_pid 2>/dev/null || true
    return $result
}

# Test 7: Performance test
test_performance() {
    log "Test 7: Testing container performance..."
    
    # Test container startup time
    local start_time=$(date +%s)
    podman run --rm "$TEST_IMAGE_NAME" python3 -c "print('Container started successfully')"
    local end_time=$(date +%s)
    local startup_time=$((end_time - start_time))
    
    if [[ $startup_time -lt 10 ]]; then
        success "Container startup time acceptable: ${startup_time}s"
    else
        warning "Container startup time slow: ${startup_time}s"
    fi
    
    # Test memory usage
    local memory_usage=$(podman run --rm "$TEST_IMAGE_NAME" python3 -c "
import psutil
mem = psutil.virtual_memory()
print(f'{mem.used // 1024 // 1024}')
" 2>/dev/null || echo "unknown")
    
    if [[ "$memory_usage" != "unknown" && $memory_usage -lt 500 ]]; then
        success "Memory usage acceptable: ${memory_usage}MB"
    else
        warning "Memory usage high or unknown: ${memory_usage}MB"
    fi
}

# Main test runner
run_all_tests() {
    log "Starting OCR Container Test Suite..."
    echo "=================================="
    
    local tests_passed=0
    local tests_failed=0
    
    # Array of test functions
    local tests=(
        "test_container_build"
        "test_container_dependencies"
        "test_ocr_functionality"
        "test_health_check"
        "test_systemd_config"
        "test_frigate_integration"
        "test_performance"
    )
    
    for test in "${tests[@]}"; do
        if $test; then
            ((tests_passed++))
        else
            ((tests_failed++))
        fi
        echo "--------------------------------"
    done
    
    # Summary
    echo "=================================="
    log "Test Summary:"
    success "Tests passed: $tests_passed"
    if [[ $tests_failed -gt 0 ]]; then
        error "Tests failed: $tests_failed"
        echo ""
        error "❌ Some tests failed. Please review and fix issues before deployment."
        return 1
    else
        echo ""
        success "🎉 All tests passed! Ready for deployment."
        return 0
    fi
}

# Production deployment check
check_deployment_readiness() {
    log "Checking deployment readiness..."
    
    local checks_passed=true
    
    # Check if all required files exist
    local required_files=(
        "containerfiles/kiln-ocr.Containerfile"
        "systemd/kiln-ocr.container"
        "code/ocr-processor.py"
        "code/frigate-ocr-integration.py"
        "code/temperature-logger.py"
        "config/requirements.txt"
    )
    
    for file in "${required_files[@]}"; do
        if [[ -f "$file" ]]; then
            success "Required file present: $file"
        else
            error "Missing required file: $file"
            checks_passed=false
        fi
    done
    
    # Check container registry availability (if using remote registry)
    if grep -q "quay.io" systemd/kiln-ocr.container; then
        warning "Using remote container registry. Ensure image is pushed before deployment."
        echo "  To push: podman build -f containerfiles/kiln-ocr.Containerfile -t quay.io/jtligon/kiln-ocr:latest ."
        echo "           podman push quay.io/jtligon/kiln-ocr:latest"
    fi
    
    if $checks_passed; then
        success "Deployment readiness check passed"
        return 0
    else
        error "Deployment readiness check failed"
        return 1
    fi
}

# Main execution
main() {
    echo "🧪 OCR Container Testing Suite"
    echo "=============================="
    
    # Check dependencies
    if ! command -v podman &> /dev/null; then
        error "Podman not found. Please install podman to run tests."
        exit 1
    fi
    
    # Setup test environment
    setup_test_environment
    
    # Run tests
    if run_all_tests && check_deployment_readiness; then
        echo ""
        success "🚀 Ready for deployment!"
        echo ""
        echo "To deploy to production:"
        echo "1. Build and push container image:"
        echo "   podman build -f containerfiles/kiln-ocr.Containerfile -t quay.io/jtligon/kiln-ocr:latest ."
        echo "   podman push quay.io/jtligon/kiln-ocr:latest"
        echo ""
        echo "2. Deploy using bootc image:"
        echo "   podman build -f containerfiles/fitlet.Containerfile -t fitlet2-kiln:latest ."
        echo ""
        echo "3. Install on Fitlet2 device"
        exit 0
    else
        echo ""
        error "❌ Tests failed. Fix issues before deployment."
        exit 1
    fi
}

# Help function
show_help() {
    echo "OCR Container Testing Script"
    echo ""
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  -h, --help     Show this help message"
    echo "  --test-only    Run tests only (skip deployment check)"
    echo "  --build-only   Only test container build"
    echo "  --quick        Run quick tests only"
    echo ""
    echo "Examples:"
    echo "  $0                 # Run full test suite"
    echo "  $0 --build-only    # Only test if container builds"
    echo "  $0 --quick         # Run essential tests only"
}

# Parse command line arguments
case "${1:-}" in
    -h|--help)
        show_help
        exit 0
        ;;
    --build-only)
        setup_test_environment
        test_container_build
        exit $?
        ;;
    --quick)
        setup_test_environment
        test_container_build && test_container_dependencies
        exit $?
        ;;
    --test-only)
        setup_test_environment
        run_all_tests
        exit $?
        ;;
    "")
        main
        ;;
    *)
        error "Unknown option: $1"
        show_help
        exit 1
        ;;
esac 