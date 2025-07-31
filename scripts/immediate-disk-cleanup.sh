#!/bin/bash
# Immediate Disk Cleanup Script - Quick Fix for Full Filesystem
# Run this immediately to free up space on the Fitlet2

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${RED}🚨 IMMEDIATE DISK CLEANUP FOR KILN MONITORING SYSTEM${NC}"
echo "Date: $(date)"
echo ""

# Show current disk usage
echo -e "${BLUE}Current disk usage:${NC}"
df -h

echo ""
echo -e "${YELLOW}Starting immediate cleanup...${NC}"

# 1. Clean systemd logs immediately
echo "1. Cleaning systemd logs..."
sudo journalctl --vacuum-time=1d
sudo journalctl --vacuum-size=50M

# 2. Clean container logs if podman exists
echo "2. Cleaning container system..."
if command -v podman &> /dev/null; then
    sudo podman system prune -a -f --volumes
fi

# 3. Clean OCR logs
echo "3. Cleaning OCR logs..."
if [ -d "/var/lib/kiln-monitoring/logs/ocr-processor" ]; then
    sudo find /var/lib/kiln-monitoring/logs/ocr-processor -name "*.log" -type f -exec truncate -s 0 {} \;
fi

# 4. Clean Frigate cache and old recordings
echo "4. Cleaning Frigate data..."
if [ -d "/var/lib/kiln-monitoring/frigate" ]; then
    # Clean cache
    sudo find /var/lib/kiln-monitoring/frigate/cache -type f -delete 2>/dev/null || true
    # Keep only last 12 hours of recordings
    sudo find /var/lib/kiln-monitoring/frigate/recordings -name "*.mp4" -type f -mmin +720 -delete 2>/dev/null || true
fi

# Clean Frigate media debug files
if [ -d "/var/lib/kiln-monitoring/frigate-media" ]; then
    sudo find /var/lib/kiln-monitoring/frigate-media/debug -type f -mtime +1 -delete 2>/dev/null || true
fi

# 5. Clean tmp files
echo "5. Cleaning temporary files..."
sudo find /tmp -name "*kiln*" -type f -delete 2>/dev/null || true
sudo find /tmp -name "*frigate*" -type f -delete 2>/dev/null || true
sudo find /tmp -name "*ocr*" -type f -delete 2>/dev/null || true

# 6. Clean debug images
echo "6. Cleaning debug images..."
if [ -d "/var/lib/kiln-monitoring/kiln-data/ocr-debug" ]; then
    sudo find /var/lib/kiln-monitoring/kiln-data/ocr-debug -name "*.jpg" -type f -delete 2>/dev/null || true
    sudo find /var/lib/kiln-monitoring/kiln-data/ocr-debug -name "*.png" -type f -delete 2>/dev/null || true
fi

# 7. Clean package cache
echo "7. Cleaning package cache..."
if command -v dnf &> /dev/null; then
    sudo dnf clean all
elif command -v apt &> /dev/null; then
    sudo apt clean
fi

echo ""
echo -e "${GREEN}✅ Immediate cleanup completed!${NC}"
echo -e "${BLUE}Final disk usage:${NC}"
df -h

echo ""
echo -e "${YELLOW}Next steps:${NC}"
echo "1. SSH to your Fitlet2: ssh jtligon@192.168.7.200"
echo "2. Run this script on the Fitlet2 for maximum effect"
echo "3. Consider running the full emergency-log-cleanup.sh script"
echo "4. Monitor with: journalctl -f" 