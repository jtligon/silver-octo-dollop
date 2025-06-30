#!/bin/bash

# 🚀 Fitlet2 Kiln Monitoring System Deployment Script
# Usage: ./deploy-fitlet2.sh [--upgrade|--fresh-install]

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
FITLET_IP="${FITLET_IP:-192.168.7.200}"
FITLET_USER="${FITLET_USER:-jtligon}"
MAIN_IMAGE="quay.io/jtligon/fitlet2-kiln:latest"
OCR_IMAGE="quay.io/jtligon/kiln-ocr:latest"

# Functions
log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
log_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check if podman is available
    if ! command -v podman &> /dev/null; then
        log_error "Podman is required but not installed"
        exit 1
    fi
    
    # Check if ssh is available
    if ! command -v ssh &> /dev/null; then
        log_error "SSH is required but not installed"
        exit 1
    fi
    
    # Test connectivity to Fitlet2
    if ! ping -c 1 "$FITLET_IP" &> /dev/null; then
        log_warning "Cannot ping Fitlet2 at $FITLET_IP"
        read -p "Continue anyway? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            exit 1
        fi
    fi
    
    log_success "Prerequisites check completed"
}

create_bootable_image() {
    log_info "Creating bootable image..."
    
    mkdir -p output
    
    log_info "Building bootc image (this may take several minutes)..."
    podman run --rm -it --privileged --pull=newer \
        -v "$(pwd)/output:/output" \
        -v /var/lib/containers/storage:/var/lib/containers/storage \
        quay.io/centos-bootc/bootc-image-builder:latest \
        --type qcow2 \
        "$MAIN_IMAGE"
    
    if [ -f "output/disk.qcow2" ]; then
        log_success "Bootable image created: output/disk.qcow2"
    else
        log_error "Failed to create bootable image"
        exit 1
    fi
}

upgrade_existing_system() {
    log_info "Upgrading existing Fitlet2 system..."
    
    # Pull latest images
    log_info "Pulling latest container images on Fitlet2..."
    ssh "$FITLET_USER@$FITLET_IP" "sudo podman pull $MAIN_IMAGE"
    ssh "$FITLET_USER@$FITLET_IP" "sudo podman pull $OCR_IMAGE"
    
    # Upgrade bootc image
    log_info "Switching to new bootc image..."
    ssh "$FITLET_USER@$FITLET_IP" "sudo bootc switch $MAIN_IMAGE"
    
    # Reboot system
    log_info "Rebooting Fitlet2..."
    ssh "$FITLET_USER@$FITLET_IP" "sudo systemctl reboot" || true
    
    # Wait for system to come back online
    log_info "Waiting for system to reboot..."
    sleep 30
    
    # Wait for SSH to be available
    local retries=0
    while ! ssh -o ConnectTimeout=5 "$FITLET_USER@$FITLET_IP" "echo 'System is up'" &> /dev/null; do
        retries=$((retries + 1))
        if [ $retries -gt 12 ]; then
            log_error "System did not come back online after upgrade"
            exit 1
        fi
        log_info "Waiting for system to be available... (attempt $retries/12)"
        sleep 10
    done
    
    log_success "System upgrade completed"
}

post_deployment_setup() {
    log_info "Running post-deployment setup..."
    
    # Run setup scripts
    log_info "Running storage setup..."
    ssh "$FITLET_USER@$FITLET_IP" "sudo /usr/local/bin/storage-setup.sh"
    
    log_info "Configuring firewall..."
    ssh "$FITLET_USER@$FITLET_IP" "sudo /usr/local/bin/firewall-setup.sh"
    
    log_info "Setting up SSL certificates..."
    ssh "$FITLET_USER@$FITLET_IP" "sudo /usr/local/bin/ssl-setup.sh"
    
    log_info "Configuring MQTT authentication..."
    ssh "$FITLET_USER@$FITLET_IP" "sudo /usr/local/bin/mqtt-auth-setup.sh"
    
    log_info "Setting up systemd integration..."
    ssh "$FITLET_USER@$FITLET_IP" "sudo /usr/local/bin/systemd-integration.sh"
    
    # Start services
    log_info "Starting all services..."
    ssh "$FITLET_USER@$FITLET_IP" "sudo systemctl daemon-reload"
    ssh "$FITLET_USER@$FITLET_IP" "sudo systemctl enable --now frigate.container"
    ssh "$FITLET_USER@$FITLET_IP" "sudo systemctl enable --now mosquitto.container"
    ssh "$FITLET_USER@$FITLET_IP" "sudo systemctl enable --now kiln-ocr.container"
    
    log_success "Post-deployment setup completed"
}

verify_deployment() {
    log_info "Verifying deployment..."
    
    # Check service status
    log_info "Checking service status..."
    ssh "$FITLET_USER@$FITLET_IP" "sudo systemctl status frigate.container --no-pager -l" || true
    ssh "$FITLET_USER@$FITLET_IP" "sudo systemctl status mosquitto.container --no-pager -l" || true
    ssh "$FITLET_USER@$FITLET_IP" "sudo systemctl status kiln-ocr.container --no-pager -l" || true
    
    # Test network connectivity
    log_info "Testing network connectivity..."
    if ssh "$FITLET_USER@$FITLET_IP" "curl -s -I http://localhost:5000" &> /dev/null; then
        log_success "Frigate web interface is accessible"
    else
        log_warning "Frigate web interface not yet accessible"
    fi
    
    # Test OCR container
    log_info "Testing OCR container..."
    if ssh "$FITLET_USER@$FITLET_IP" "sudo podman exec kiln-ocr python3 -c 'import cv2, pytesseract; print(\"OCR OK\")'" &> /dev/null; then
        log_success "OCR container is working"
    else
        log_warning "OCR container may need more time to start"
    fi
    
    # Run comprehensive tests
    log_info "Running comprehensive tests..."
    ssh "$FITLET_USER@$FITLET_IP" "sudo /usr/local/bin/testing-validation.sh" || log_warning "Some tests failed - check logs"
    
    log_success "Deployment verification completed"
}

show_completion_info() {
    log_success "🎉 Fitlet2 Kiln Monitoring System Deployment Complete!"
    echo
    echo "System Information:"
    echo "  📍 Fitlet2 IP: $FITLET_IP"
    echo "  🌐 Frigate UI: http://$FITLET_IP:5000"
    echo "  🖥️  Cockpit: https://$FITLET_IP:9090"
    echo "  📡 MQTT Broker: $FITLET_IP:1883"
    echo
    echo "Services Running:"
    echo "  🎥 Frigate NVR - Camera monitoring and object detection"
    echo "  📡 MQTT Broker - Message communication hub" 
    echo "  🔍 OCR Service - Temperature reading from kiln display"
    echo "  🔐 SSL Security - Encrypted communications"
    echo "  🔄 Auto-Updates - Automated container updates"
    echo
    echo "Next Steps:"
    echo "  1. Configure camera in Frigate UI"
    echo "  2. Set up Home Assistant integration"
    echo "  3. Calibrate OCR zones for temperature reading"
    echo "  4. Test alerts and monitoring"
    echo
    log_info "For troubleshooting, see DEPLOYMENT.md and TROUBLESHOOTING.md"
}

# Main execution
main() {
    echo "🚀 Fitlet2 Kiln Monitoring System Deployment"
    echo "=============================================="
    echo
    
    # Parse arguments
    DEPLOYMENT_TYPE="upgrade"
    if [[ "${1:-}" == "--fresh-install" ]]; then
        DEPLOYMENT_TYPE="fresh"
    elif [[ "${1:-}" == "--upgrade" ]]; then
        DEPLOYMENT_TYPE="upgrade"
    fi
    
    log_info "Deployment type: $DEPLOYMENT_TYPE"
    echo
    
    check_prerequisites
    
    if [[ "$DEPLOYMENT_TYPE" == "fresh" ]]; then
        create_bootable_image
        log_info "Flash output/disk.qcow2 to USB and boot Fitlet2"
        log_info "Then run: $0 --upgrade"
        exit 0
    else
        upgrade_existing_system
    fi
    
    post_deployment_setup
    verify_deployment
    show_completion_info
}

# Handle script interruption
trap 'log_error "Deployment interrupted"; exit 1' INT TERM

# Run main function
main "$@" 