#!/bin/bash
# Local Development Testing Script
# For iterative development and debugging of the OCR container

set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log() { echo -e "${BLUE}[$(date +'%H:%M:%S')]${NC} $1"; }
success() { echo -e "${GREEN}✅ $1${NC}"; }
error() { echo -e "${RED}❌ $1${NC}"; }
warning() { echo -e "${YELLOW}⚠️  $1${NC}"; }

# Configuration
DEV_IMAGE="kiln-ocr:dev"
DEV_CONTAINER="kiln-ocr-dev"
DEV_DIR="$HOME/.kiln-ocr-dev"

# Cleanup function
cleanup_dev() {
    log "Cleaning up development environment..."
    podman rm -f "$DEV_CONTAINER" 2>/dev/null || true
    podman rmi -f "$DEV_IMAGE" 2>/dev/null || true
}

# Setup development environment
setup_dev_environment() {
    log "Setting up development environment..."
    
    mkdir -p "$DEV_DIR"/{logs,data,images,debug}
    
    # Create sample test images if ImageMagick is available
    if command -v convert &> /dev/null; then
        log "Creating sample test images..."
        
        # Temperature displays
        convert -size 400x150 xc:black -fill white -pointsize 64 \
            -annotate +100+90 "1250°F" "$DEV_DIR/images/temp_1250.png"
        
        convert -size 400x150 xc:black -fill white -pointsize 64 \
            -annotate +100+90 "875°F" "$DEV_DIR/images/temp_875.png"
        
        # Status displays
        convert -size 400x100 xc:black -fill white -pointsize 48 \
            -annotate +100+65 "FIRING" "$DEV_DIR/images/status_firing.png"
        
        convert -size 400x100 xc:black -fill white -pointsize 48 \
            -annotate +100+65 "COOLING" "$DEV_DIR/images/status_cooling.png"
            
        success "Test images created in $DEV_DIR/images/"
    else
        warning "ImageMagick not available - using text placeholders"
        echo "1250°F" > "$DEV_DIR/images/temp_1250.txt"
        echo "FIRING" > "$DEV_DIR/images/status_firing.txt"
    fi
}

# Quick build test
quick_build() {
    log "Quick build test..."
    
    if podman build -f containerfiles/kiln-ocr.Containerfile -t "$DEV_IMAGE" . --quiet; then
        success "Container builds successfully"
        return 0
    else
        error "Container build failed"
        return 1
    fi
}

# Interactive development shell
dev_shell() {
    log "Starting interactive development shell..."
    
    if ! podman image exists "$DEV_IMAGE"; then
        log "Building development image first..."
        quick_build || return 1
    fi
    
    log "Starting development container with shell access..."
    echo "Available commands in container:"
    echo "  - python3 ocr-processor.py"
    echo "  - python3 frigate-ocr-integration.py"
    echo "  - tesseract --help"
    echo "  - ls /app/ (to see scripts)"
    echo "  - exit (to leave container)"
    
    podman run -it --rm \
        --name "$DEV_CONTAINER" \
        -v "$DEV_DIR/images:/test_images:ro" \
        -v "$DEV_DIR/logs:/logs" \
        -v "$DEV_DIR/data:/data" \
        -v "$DEV_DIR/debug:/debug" \
        "$DEV_IMAGE" \
        /bin/bash
}

# Test OCR on sample images
test_ocr_samples() {
    log "Testing OCR on sample images..."
    
    if ! podman image exists "$DEV_IMAGE"; then
        quick_build || return 1
    fi
    
    local test_images=("$DEV_DIR/images"/*.png)
    if [[ ! -f "${test_images[0]}" ]]; then
        warning "No test images found. Run with --setup first."
        return 1
    fi
    
    for img in "${test_images[@]}"; do
        local basename=$(basename "$img")
        log "Testing OCR on $basename..."
        
        podman run --rm \
            -v "$DEV_DIR/images:/test_images:ro" \
            "$DEV_IMAGE" \
            python3 -c "
import cv2
import pytesseract
import os

img_path = '/test_images/$basename'
if os.path.exists(img_path):
    img = cv2.imread(img_path)
    if img is not None:
        # Test with different OCR configs
        configs = [
            '--oem 3 --psm 8',
            '--oem 3 --psm 7',
            '--oem 3 --psm 6'
        ]
        
        print(f'=== Testing {img_path} ===')
        for i, config in enumerate(configs):
            try:
                text = pytesseract.image_to_string(img, config=config)
                print(f'Config {i+1} ({config}): \"{text.strip()}\"')
            except Exception as e:
                print(f'Config {i+1} failed: {e}')
        print()
    else:
        print(f'Could not load image: {img_path}')
else:
    print(f'Image not found: {img_path}')
"
    done
}

# Live development with file watching (requires inotify-tools)
live_development() {
    log "Starting live development mode..."
    warning "This will rebuild and test the container when files change"
    warning "Press Ctrl+C to stop"
    
    if ! command -v inotifywait &> /dev/null; then
        error "inotifywait not found. Install inotify-tools for live development."
        echo "On Ubuntu/Debian: sudo apt install inotify-tools"
        echo "On RHEL/CentOS: sudo dnf install inotify-tools"
        return 1
    fi
    
    # Initial build
    quick_build || return 1
    
    # Watch for changes
    while true; do
        log "Watching for file changes..."
        
        # Watch relevant directories
        inotifywait -r -e modify,create,delete \
            --include='.*\.(py|txt|Containerfile)$' \
            containerfiles/ code/ config/ 2>/dev/null || true
        
        log "Files changed, rebuilding..."
        if quick_build; then
            success "Rebuild successful"
            
            # Optionally run quick test
            warning "Running quick OCR test..."
            podman run --rm "$DEV_IMAGE" python3 -c "
import cv2, pytesseract, numpy as np
print('Dependencies OK')
# Test basic OCR
img = np.zeros((100, 300, 3), dtype=np.uint8)
cv2.putText(img, '1234°F', (50, 60), cv2.FONT_HERSHEY_SIMPLEX, 2, (255,255,255), 3)
text = pytesseract.image_to_string(img, config='--oem 3 --psm 8')
print(f'OCR Test: \"{text.strip()}\"')
"
        else
            error "Rebuild failed"
        fi
        
        echo "---"
        sleep 1
    done
}

# Test with mock MQTT broker
test_with_mock_mqtt() {
    log "Testing with mock MQTT broker..."
    
    # Start Mosquitto in Docker if available
    if command -v docker &> /dev/null; then
        log "Starting Mosquitto container..."
        docker run -d --name mqtt-test \
            -p 1883:1883 \
            eclipse-mosquitto:latest || true
        
        sleep 3
        
        # Test MQTT connection
        podman run --rm --network host \
            "$DEV_IMAGE" \
            python3 -c "
import paho.mqtt.client as mqtt
import time

def on_connect(client, userdata, flags, rc):
    print(f'MQTT connected with result code {rc}')
    client.publish('test/topic', 'Hello from OCR container')

client = mqtt.Client()
client.on_connect = on_connect

try:
    client.connect('localhost', 1883, 60)
    client.loop_start()
    time.sleep(2)
    client.loop_stop()
    client.disconnect()
    print('✅ MQTT test successful')
except Exception as e:
    print(f'❌ MQTT test failed: {e}')
"
        
        # Cleanup
        docker rm -f mqtt-test
    else
        warning "Docker not available, skipping MQTT test"
    fi
}

# Performance profiling
profile_performance() {
    log "Profiling container performance..."
    
    if ! podman image exists "$DEV_IMAGE"; then
        quick_build || return 1
    fi
    
    # Test startup time
    log "Testing startup time..."
    local start_time=$(date +%s.%N)
    podman run --rm "$DEV_IMAGE" python3 -c "print('Started')" >/dev/null
    local end_time=$(date +%s.%N)
    local startup_time=$(echo "$end_time - $start_time" | bc)
    echo "Container startup time: ${startup_time}s"
    
    # Test memory usage
    log "Testing memory usage..."
    podman run --rm "$DEV_IMAGE" python3 -c "
import psutil
import cv2
import pytesseract
import numpy as np

# Get initial memory
initial_mem = psutil.Process().memory_info().rss / 1024 / 1024

# Load libraries and do some work
img = np.random.randint(0, 255, (480, 640, 3), dtype=np.uint8)
gray = cv2.cvtColor(img, cv2.COLOR_BGR2GRAY)

# Get memory after operations
final_mem = psutil.Process().memory_info().rss / 1024 / 1024

print(f'Initial memory: {initial_mem:.1f} MB')
print(f'Final memory: {final_mem:.1f} MB')
print(f'Memory increase: {final_mem - initial_mem:.1f} MB')
"
}

# Show usage help
show_help() {
    echo "Local Development Testing Script"
    echo ""
    echo "Usage: $0 [COMMAND]"
    echo ""
    echo "Commands:"
    echo "  setup          Setup development environment"
    echo "  build          Quick build test"
    echo "  shell          Interactive development shell"
    echo "  test-ocr       Test OCR on sample images"
    echo "  live           Live development with file watching"
    echo "  test-mqtt      Test with mock MQTT broker"
    echo "  profile        Performance profiling"
    echo "  clean          Clean development environment"
    echo ""
    echo "Examples:"
    echo "  $0 setup       # First time setup"
    echo "  $0 build       # Quick build check"
    echo "  $0 shell       # Interactive debugging"
    echo "  $0 live        # Auto-rebuild on changes"
}

# Main command handler
main() {
    case "${1:-help}" in
        setup)
            setup_dev_environment
            ;;
        build)
            quick_build
            ;;
        shell)
            dev_shell
            ;;
        test-ocr)
            test_ocr_samples
            ;;
        live)
            live_development
            ;;
        test-mqtt)
            test_with_mock_mqtt
            ;;
        profile)
            profile_performance
            ;;
        clean)
            cleanup_dev
            success "Development environment cleaned"
            ;;
        help|--help|-h)
            show_help
            ;;
        *)
            error "Unknown command: $1"
            show_help
            exit 1
            ;;
    esac
}

# Check dependencies
if ! command -v podman &> /dev/null; then
    error "Podman not found. Please install podman for development testing."
    exit 1
fi

# Run main function
main "$@" 