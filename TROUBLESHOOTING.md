# Troubleshooting Guide - Kiln Monitoring System

This guide provides solutions for common issues encountered with the Frigate-based kiln monitoring system.

## 🚨 Emergency Procedures

### System Not Responding
1. **Check power and network connectivity**
2. **SSH into system**: `ssh jtligon@192.168.7.200`
3. **Check system status**: `sudo systemctl status`
4. **Restart if needed**: `sudo systemctl reboot`

### Complete Service Failure
```bash
# Emergency restart all services
sudo systemctl stop kiln-ocr.service frigate.service mosquitto.service
sleep 10
sudo systemctl start mosquitto.service
sleep 5
sudo systemctl start frigate.service
sleep 5
sudo systemctl start kiln-ocr.service

# Check status
sudo /usr/local/bin/kiln-health-check.sh
```

## 🔧 Service Issues

### Mosquitto MQTT Broker

#### Service Won't Start
```bash
# Check service status
systemctl status mosquitto.service

# Check configuration syntax
mosquitto -c /var/lib/kiln-monitoring/mosquitto-config/mosquitto.conf -t

# Check permissions
ls -la /var/lib/kiln-monitoring/mosquitto-config/
ls -la /var/lib/kiln-monitoring/mosquitto/

# Reset permissions
sudo chown -R 1883:1883 /var/lib/kiln-monitoring/mosquitto/
sudo chown -R 1883:1883 /var/lib/kiln-monitoring/mosquitto-config/auth/
```

#### Authentication Failures
```bash
# Test authentication
sudo /usr/local/bin/test-mqtt-auth.sh

# Check password file
sudo cat /var/lib/kiln-monitoring/mosquitto-config/auth/passwd

# Regenerate passwords
sudo /usr/local/bin/mqtt-auth-setup.sh

# View current credentials
sudo cat /var/lib/kiln-monitoring/mosquitto-config/credentials.txt
```

#### Connection Refused
```bash
# Check if service is listening
netstat -tuln | grep 1883

# Check firewall
sudo /usr/local/bin/check-kiln-firewall.sh

# Test local connection
mosquitto_pub -h localhost -p 1883 -t test -m "hello" -u admin -P [password]

# Check logs
journalctl -u mosquitto.service -f
```

### Frigate NVR

#### Service Fails to Start
```bash
# Check Frigate logs
journalctl -u frigate.service -f

# Check camera device
ls -la /dev/video*

# Test camera directly
ffmpeg -f v4l2 -i /dev/video0 -frames:v 1 test.jpg

# Check GPU acceleration
ls -la /dev/dri/

# Verify configuration
python3 -c "import yaml; yaml.safe_load(open('/var/lib/kiln-monitoring/frigate-config/config.yml'))"
```

#### Camera Not Detected
```bash
# List video devices
ls /dev/video*

# Check camera permissions
ls -la /dev/video0

# Test camera capture
sudo v4l2-ctl --device=/dev/video0 --info

# Add user to video group
sudo usermod -a -G video jtligon

# Check USB connections
lsusb | grep -i camera
```

#### High CPU Usage
```bash
# Check container resources
podman stats frigate

# Monitor CPU usage
htop -p $(pgrep frigate)

# Check hardware acceleration
grep -i "hwaccel" /var/lib/kiln-monitoring/frigate-config/config.yml

# Reduce recording quality
sudo nano /var/lib/kiln-monitoring/frigate-config/config.yml
# Modify: quality: 8 → quality: 6
```

#### No Recordings
```bash
# Check storage space
df -h /var/lib/kiln-monitoring/frigate/

# Check recording configuration
grep -A 10 "record:" /var/lib/kiln-monitoring/frigate-config/config.yml

# Check motion detection
curl http://localhost:5000/api/stats

# Check detection zones
curl http://localhost:5000/api/config | jq '.cameras.kiln_camera.zones'

# Manual recording test
curl -X POST "http://localhost:5000/api/kiln_camera/recordings/start"
```

### Kiln OCR Service

#### OCR Service Won't Start
```bash
# Check OCR service logs
journalctl -u kiln-ocr.service -f

# Test Python dependencies
python3 -c "import cv2, pytesseract, paho.mqtt.client"

# Check requirements
pip3 list | grep -E "(opencv|pytesseract|paho-mqtt)"

# Reinstall dependencies
sudo pip3 install -r /kiln-ocr/requirements.txt --force-reinstall

# Test script manually
cd /kiln-ocr
python3 temperature-logger.py
```

#### OCR Not Reading Temperature
```bash
# Run calibration mode
python3 /kiln-ocr/frigate-ocr-integration.py --calibrate

# Check debug images
ls /var/lib/kiln-monitoring/frigate-media/debug/
ls /var/lib/kiln-monitoring/kiln-data/ocr-debug/

# Test OCR zones
python3 /kiln-ocr/frigate-ocr-integration.py --test-ocr

# Check zone coordinates
grep -A 20 "zones:" /var/lib/kiln-monitoring/frigate-config/config.yml

# Test Tesseract directly
tesseract /var/lib/kiln-monitoring/frigate-media/debug/temperature_display_*.jpg stdout
```

#### Inaccurate Temperature Readings
```bash
# Check OCR confidence levels
grep "confidence" /var/lib/kiln-monitoring/logs/ocr-processor/*.log

# Adjust OCR zone coordinates
sudo nano /var/lib/kiln-monitoring/frigate-config/config.yml
# Modify zone coordinates based on calibration images

# Update OCR patterns
sudo nano /kiln-ocr/ocr_processor.py
# Modify temp_patterns array for your display format

# Test with sample images
python3 -c "
from ocr_processor import KilnOCRProcessor
import cv2
processor = KilnOCRProcessor()
image = cv2.imread('/var/lib/kiln-monitoring/frigate-media/debug/latest.jpg')
result = processor.process_zone_image(image, 'temperature_display')
print(result)
"
```

## 🌐 Network Issues

### Cannot Access Web Interfaces

#### Frigate Web Interface (Port 5000)
```bash
# Test local access
curl http://localhost:5000/api/stats

# Check container port mapping
podman ps | grep frigate

# Test from another device
curl http://192.168.7.200:5000/api/stats

# Check firewall rules
sudo firewall-cmd --list-all | grep 5000
```

#### Cockpit (Port 9090)
```bash
# Check Cockpit service
systemctl status cockpit.service

# Test SSL certificate
openssl s_client -connect localhost:9090 -servername localhost

# Check firewall
sudo firewall-cmd --list-services | grep cockpit

# Reset Cockpit
sudo systemctl restart cockpit
```

### Home Assistant Cannot Connect

#### MQTT Connection Issues
```bash
# Test from Home Assistant host
mosquitto_pub -h 192.168.7.200 -p 1883 -u homeassistant -P [password] -t test -m "hello"

# Check network connectivity
ping 192.168.7.200

# Check MQTT logs on Fitlet2
journalctl -u mosquitto.service | grep homeassistant

# Verify credentials
sudo cat /var/lib/kiln-monitoring/mosquitto-config/credentials.txt | grep homeassistant
```

#### SSL/TLS Connection Issues
```bash
# Test SSL connection
mosquitto_pub -h 192.168.7.200 -p 8883 --cafile /ssl/certs/ca-cert.pem -u homeassistant -P [password] -t test -m "hello"

# Check certificate validity
openssl x509 -in /ssl/certs/server-cert.pem -text -noout

# Generate new certificates
sudo /usr/local/bin/ssl-setup.sh

# Copy certificates to Home Assistant
sudo cat /tmp/kiln-ssl-certificates.tar.gz | base64
```

## 💾 Storage Issues

### Disk Space Full
```bash
# Check disk usage
df -h
du -sh /var/lib/kiln-monitoring/*

# Run cleanup
sudo /var/lib/kiln-monitoring/cleanup-kiln-data.sh

# Clean old recordings
find /var/lib/kiln-monitoring/frigate/recordings -name "*.mp4" -mtime +7 -delete

# Clean old logs
journalctl --vacuum-time=7d

# Check large files
find /var/lib/kiln-monitoring -size +100M -ls
```

### Database Issues
```bash
# Check SQLite database
sqlite3 /var/lib/kiln-monitoring/kiln-data/kiln_monitoring.db ".schema"

# Vacuum database
sqlite3 /var/lib/kiln-monitoring/kiln-data/kiln_monitoring.db "VACUUM;"

# Check database integrity
sqlite3 /var/lib/kiln-monitoring/kiln-data/kiln_monitoring.db "PRAGMA integrity_check;"

# Backup database
cp /var/lib/kiln-monitoring/kiln-data/kiln_monitoring.db /tmp/backup.db
```

### Backup Failures
```bash
# Check backup service
systemctl status kiln-backup.timer

# Run manual backup
sudo /var/lib/kiln-monitoring/backup-kiln-data.sh daily

# Check backup directory
ls -la /var/backups/kiln-monitoring/

# Check disk space for backups
df -h /var/backups/

# Test backup restore
sudo tar -tzf /var/backups/kiln-monitoring/daily/kiln-backup-*/kiln-data.tar.gz
```

## 🔒 Security Issues

### SSL Certificate Problems

#### Certificate Expired
```bash
# Check certificate expiration
openssl x509 -in /ssl/certs/server-cert.pem -noout -enddate

# Generate new certificates
sudo /usr/local/bin/ssl-setup.sh

# Restart services
sudo systemctl restart cockpit mosquitto.service

# Update Home Assistant certificates
sudo tar -czf /tmp/new-certs.tar.gz -C /ssl certs/ private/
```

#### Certificate Trust Issues
```bash
# Check certificate chain
openssl verify -CAfile /ssl/certs/ca-cert.pem /ssl/certs/server-cert.pem

# View certificate details
openssl x509 -in /ssl/certs/server-cert.pem -text -noout

# Export certificate for browsers
openssl x509 -in /ssl/certs/ca-cert.pem -out /tmp/kiln-ca.crt

# Check certificate fingerprint
openssl x509 -in /ssl/certs/server-cert.pem -noout -fingerprint -sha256
```

### Firewall Issues

#### Services Blocked
```bash
# Check firewall status
sudo /usr/local/bin/check-kiln-firewall.sh

# List all rules
sudo firewall-cmd --list-all

# Temporarily disable firewall (for testing)
sudo systemctl stop firewalld

# Reconfigure firewall
sudo /usr/local/bin/firewall-setup.sh

# Add specific rule
sudo firewall-cmd --permanent --add-port=5000/tcp
sudo firewall-cmd --reload
```

#### SSH Access Issues
```bash
# Check SSH service
systemctl status ssh.service

# Check SSH configuration
sudo sshd -T | grep -E "(PasswordAuthentication|PubkeyAuthentication)"

# Check authorized keys
ls -la ~/.ssh/authorized_keys

# Reset SSH keys
curl https://github.com/jtligon.keys > ~/.ssh/authorized_keys
chmod 600 ~/.ssh/authorized_keys
```

## 📊 Performance Issues

### High Resource Usage

#### Memory Issues
```bash
# Check memory usage
free -h
ps aux --sort=-%mem | head -10

# Check container memory
podman stats --no-stream

# Clean up containers
podman system prune -f

# Check for memory leaks
journalctl | grep -i "out of memory"

# Adjust container limits
sudo nano /etc/containers/systemd/*.container
# Add: Memory=2G
```

#### CPU Issues
```bash
# Check CPU usage
htop
iostat 5 3

# Check container CPU
podman stats --no-stream

# Disable hardware acceleration (if causing issues)
sudo nano /frigate/config/config.yml
# Comment out: hwaccel_args: preset-intel-qsv-h264

# Check for intensive processes
ps aux --sort=-%cpu | head -10
```

### Network Performance

#### Slow Video Streaming
```bash
# Check network bandwidth
iperf3 -s &  # On Fitlet2
iperf3 -c 192.168.7.200  # From client

# Check video quality settings
grep -A 5 "quality:" /var/lib/kiln-monitoring/frigate-config/config.yml

# Reduce video quality
sudo nano /var/lib/kiln-monitoring/frigate-config/config.yml
# Modify: quality: 8 → quality: 5

# Check container network
podman network ls
podman network inspect podman
```

#### MQTT Message Delays
```bash
# Test MQTT performance
sudo /usr/local/bin/performance-test.sh 60

# Check message queue
mosquitto_sub -h localhost -p 1883 -u admin -P [password] -t '$SYS/broker/messages/stored'

# Reduce message frequency
sudo nano /kiln-ocr/frigate-ocr-integration.py
# Modify: sleep(5)  # Increase from 5 to 10 seconds
```

## 🧪 Testing and Validation

### System Health Check
```bash
# Run comprehensive health check
sudo /usr/local/bin/kiln-health-check.sh

# Check service dependencies
systemctl list-dependencies mosquitto.service

# Test startup sequence
sudo /usr/local/bin/test-kiln-startup.sh

# Run full system test
sudo /usr/local/bin/testing-validation.sh
```

### Performance Testing
```bash
# Run performance test
sudo /usr/local/bin/performance-test.sh 300

# Monitor during test
watch -n 5 'podman stats --no-stream'

# Check test results
ls /tmp/kiln-performance-test-*/
```

## 📞 Getting Help

### Log Collection
```bash
# Collect all relevant logs
mkdir /tmp/kiln-logs
journalctl -u mosquitto.service > /tmp/kiln-logs/mosquitto.log
journalctl -u frigate.service > /tmp/kiln-logs/frigate.log
journalctl -u kiln-ocr.service > /tmp/kiln-logs/kiln-ocr.log
cp /var/lib/kiln-monitoring/logs/ocr-processor/*.log /tmp/kiln-logs/
tar -czf /tmp/kiln-debugging-$(date +%Y%m%d_%H%M%S).tar.gz -C /tmp kiln-logs/
```

### System Information
```bash
# Generate system report
{
    echo "=== System Information ==="
    uname -a
    cat /etc/os-release
    
    echo -e "\n=== Hardware ==="
    lscpu | grep -E "(Model|Core|Thread|MHz)"
    free -h
    df -h
    
    echo -e "\n=== Network ==="
    ip addr show
    ss -tuln | grep -E "(1883|5000|9090)"
    
    echo -e "\n=== Services ==="
    systemctl status mosquitto.service frigate.service kiln-ocr.service
    
    echo -e "\n=== Containers ==="
    podman ps
    
    echo -e "\n=== Storage ==="
    du -sh /var/lib/kiln-monitoring/*
    
} > /tmp/system-report-$(date +%Y%m%d_%H%M%S).txt
```

### Contact Information
- **GitHub Issues**: [Create an issue](https://github.com/jtligon/silver-octo-dollop/issues)
- **Documentation**: [README.md](README.md)
- **System Health**: `/usr/local/bin/kiln-health-check.sh`

---

## 📝 Quick Reference

### Essential Commands
```bash
# Health check
sudo /usr/local/bin/kiln-health-check.sh

# Restart services
sudo /usr/local/bin/restart-kiln-services.sh

# Test system
sudo /usr/local/bin/testing-validation.sh

# View logs
journalctl -u [service-name] -f

# Check configuration
sudo /usr/local/bin/check-kiln-firewall.sh
sudo /usr/local/bin/test-mqtt-auth.sh
```

### Important Files
- **Configs**: `/var/lib/kiln-monitoring/frigate-config/`, `/var/lib/kiln-monitoring/mosquitto-config/`
- **Logs**: `/var/lib/kiln-monitoring/logs/`
- **Data**: `/var/lib/kiln-monitoring/kiln-data/`
- **Backups**: `/var/backups/kiln-monitoring/`
- **SSL**: `/ssl/` 