# 🚨 DISK SPACE EMERGENCY - Kiln Monitoring System

**CRITICAL**: Your Fitlet2 filesystem has filled up with log messages. Follow these steps immediately to restore normal operation.

## ⚡ IMMEDIATE ACTION (Run These First)

### 1. Quick Cleanup on Your Mac
```bash
# From your local machine (silver-octo-dollop directory)
cd /Users/jligon/Documents/code/silver-octo-dollop
./scripts/immediate-disk-cleanup.sh
```

### 2. SSH to Fitlet2 and Run Emergency Cleanup
```bash
# SSH to the Fitlet2
ssh jtligon@192.168.7.200

# Copy the emergency script
scp scripts/emergency-log-cleanup.sh jtligon@192.168.7.200:/tmp/

# Run emergency cleanup as root
sudo /tmp/emergency-log-cleanup.sh
```

### 3. Check Results
```bash
# Check disk usage after cleanup
df -h

# Check if services are running
sudo systemctl status mosquitto.service frigate.service kiln-ocr.service
```

## 🔍 What Caused This

Based on your kiln monitoring system configuration, the disk filled up due to:

1. **Container Logs**: Frigate, MQTT, and OCR containers generating excessive logs
2. **SystemD Journal**: Service logs accumulating without rotation
3. **OCR Debug Images**: Temperature reading screenshots piling up
4. **Frigate Recordings**: Video files not being cleaned up properly
5. **Error Loop**: OCR container showing repetitive error messages

## 🛠️ Detailed Cleanup Steps

### SystemD Logs (Usually the biggest culprit)
```bash
# Clean journal logs aggressively
sudo journalctl --vacuum-time=1d
sudo journalctl --vacuum-size=100M

# Check what services are logging the most
sudo journalctl --disk-usage
sudo journalctl -u kiln-ocr.service --since "1 hour ago" | wc -l
sudo journalctl -u frigate.service --since "1 hour ago" | wc -l
```

### Container Cleanup
```bash
# Clean all unused containers, images, and volumes
sudo podman system prune -a -f --volumes

# Check container logs individually
sudo podman logs mosquitto --tail 50
sudo podman logs frigate --tail 50
sudo podman logs kiln-ocr --tail 50
```

### Application Data Cleanup
```bash
# Clean OCR processor logs
sudo find /var/lib/kiln-monitoring/logs/ocr-processor -name "*.log" -exec truncate -s 0 {} \;

# Clean old Frigate recordings (keep last 24 hours only)
sudo find /var/lib/kiln-monitoring/frigate/recordings -name "*.mp4" -mtime +1 -delete

# Clean debug images
sudo find /var/lib/kiln-monitoring/kiln-data/ocr-debug -name "*.jpg" -mtime +1 -delete
sudo find /var/lib/kiln-monitoring/kiln-data/ocr-debug -name "*.png" -mtime +1 -delete

# Clean Frigate cache
sudo find /var/lib/kiln-monitoring/frigate/cache -type f -delete
```

## 🚨 Root Cause Fix

The OCR container is showing this error repeatedly:
```
Traceback (most recent call last): File "/app/frigate-ocr-integration.py", line 13, in <module> from ocr_processor import KilnOCRProcessor
```

### Fix the OCR Container Error
```bash
# Stop the problematic service
sudo systemctl stop kiln-ocr.service

# Check the container issue
sudo podman logs kiln-ocr

# Restart with fixed configuration
sudo systemctl restart kiln-ocr.service

# Monitor to ensure it's not error looping
sudo journalctl -u kiln-ocr.service -f
```

## 🔧 Permanent Solutions

### 1. Configure Log Rotation
```bash
# Run the emergency script which sets up proper log rotation
sudo /tmp/emergency-log-cleanup.sh
```

### 2. Set Container Log Limits
The emergency script configures:
- Container logs limited to 10MB each
- SystemD journal limited to 200MB total
- Automatic cleanup every 15 minutes
- MQTT alerts when disk usage > 85%

### 3. Monitor Disk Usage
```bash
# Check disk usage regularly
df -h

# Monitor specific directories
sudo du -sh /var/lib/kiln-monitoring/*
sudo du -sh /var/log/journal/*
```

## 📊 Prevention Monitoring

After running the emergency cleanup, you'll have:

1. **Automatic Monitoring**: Script runs every 15 minutes
2. **MQTT Alerts**: Home Assistant will show disk usage warnings  
3. **Log Rotation**: Daily cleanup of old logs
4. **Container Limits**: Prevents containers from generating excessive logs

## 🔍 Diagnostic Commands

### Find What's Using Space
```bash
# Find largest files
sudo find /var -size +100M -ls 2>/dev/null | head -10

# Check journal size
sudo journalctl --disk-usage

# Check container data
sudo podman system df

# Check kiln monitoring data
sudo du -sh /var/lib/kiln-monitoring/* | sort -h
```

### Monitor Services
```bash
# Watch disk usage in real-time
watch -n 5 'df -h'

# Monitor services
sudo systemctl status mosquitto.service frigate.service kiln-ocr.service

# Watch logs without filling disk
sudo journalctl -u kiln-ocr.service -f --lines=20
```

## 🎯 Expected Results

After cleanup, you should see:
- **Disk usage** reduced from 95%+ to under 50%
- **Services running** normally without error loops
- **Automatic monitoring** preventing future issues
- **Home Assistant** receiving disk space alerts via MQTT

## 🆘 If Still Having Issues

### Emergency Contact
1. **Stop all services**: `sudo systemctl stop mosquitto.service frigate.service kiln-ocr.service`
2. **Clean everything**: `sudo rm -rf /var/lib/kiln-monitoring/logs/*`
3. **Restart services**: `sudo systemctl start mosquitto.service frigate.service`
4. **Skip OCR temporarily**: Leave kiln-ocr.service stopped until container is fixed

### Alternative: Reset Storage
```bash
# Nuclear option - clears all historical data but preserves configs
sudo systemctl stop mosquitto.service frigate.service kiln-ocr.service
sudo rm -rf /var/lib/kiln-monitoring/frigate/recordings/*
sudo rm -rf /var/lib/kiln-monitoring/frigate/snapshots/*
sudo rm -rf /var/lib/kiln-monitoring/logs/*
sudo systemctl start mosquitto.service frigate.service
```

## ✅ Success Verification

Your system is healthy when:
- `df -h` shows < 80% disk usage
- All services show "active (running)" status
- No repetitive errors in `journalctl -f`
- Home Assistant kiln dashboard shows current temperature
- Frigate web interface at http://192.168.7.200:5000 works

---

**Remember**: This is a production kiln monitoring system. Keeping it running is critical for ceramic firing safety and success! 