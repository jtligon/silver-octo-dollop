# Kiln Monitoring System with Frigate NVR

A comprehensive kiln monitoring solution using **Frigate NVR**, **OCR processing**, and **Home Assistant integration** for real-time temperature tracking, automated alerts, and firing management.

## 🎯 Overview

This system replaces traditional MotionEye-based monitoring with advanced **Frigate NVR** technology, featuring:

- **🔥 Real-time kiln monitoring** with OCR temperature reading
- **📱 Home Assistant integration** with automated alerts
- **🎥 Live video feed** with intelligent zones for text recognition
- **📊 Historical data logging** with SQLite database
- **🔒 Secure network access** with SSL/TLS and authentication
- **⚡ Intel GPU acceleration** for efficient video processing
- **📈 Performance monitoring** and automated testing

## 🏗️ Architecture

```
┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐
│   Kiln Camera   │    │  Frigate NVR    │    │ Home Assistant  │
│                 │───▶│  OCR Processing │───▶│   Dashboard     │
│  /dev/video0    │    │  MQTT Publish   │    │   Automations   │
└─────────────────┘    └─────────────────┘    └─────────────────┘
                              │
                              ▼
                       ┌─────────────────┐
                       │ MQTT Broker     │
                       │ (Mosquitto)     │
                       │ Authentication  │
                       └─────────────────┘
                              │
                              ▼
                       ┌─────────────────┐
                       │ Data Storage    │
                       │ • Temperature   │
                       │ • Recordings    │
                       │ • Backups       │
                       └─────────────────┘
```

## 🚀 Quick Start

### Prerequisites

- **Fitlet2** or compatible x86_64 device
- **USB camera** connected as `/dev/video0`
- **Home Assistant** running on your network
- **Fedora bootc** compatible system

### Installation

1. **Clone the repository:**
   ```bash
   git clone https://github.com/jtligon/silver-octo-dollop.git
   cd silver-octo-dollop
   ```

2. **Build the bootc image:**
   ```bash
   sudo podman build -t kiln-monitoring .
   ```

3. **Deploy to Fitlet2:**
   ```bash
   # Follow Fedora bootc deployment procedures
   sudo bootc switch kiln-monitoring
   sudo systemctl reboot
   ```

4. **Run initial setup:**
   ```bash
   # Set up storage
   sudo /usr/local/bin/storage-setup.sh
   
   # Configure SSL certificates
   sudo /usr/local/bin/ssl-setup.sh
   
   # Set up MQTT authentication
   sudo /usr/local/bin/mqtt-auth-setup.sh
   
   # Configure firewall
   sudo /usr/local/bin/firewall-setup.sh
   
   # Configure system integration
   sudo /usr/local/bin/systemd-integration.sh
   ```

5. **Validate installation:**
   ```bash
   sudo /usr/local/bin/testing-validation.sh
   ```

## 📡 Network Configuration

### IP Configuration
- **Fitlet2**: `192.168.7.200`
- **Home Assistant**: `192.168.5.x` (same network)

### Service Ports
| Service | Port | Protocol | Access |
|---------|------|----------|--------|
| Frigate Web | 5000 | HTTP | Local network |
| Frigate RTSP | 8554 | TCP | Local network |
| MQTT | 1883 | TCP | HA + Local |
| MQTT SSL | 8883 | TCP | HA + Local |
| MQTT WebSocket | 9001 | TCP | Local network |
| MQTT WS SSL | 9002 | TCP | Local network |
| Cockpit | 9090 | HTTPS | Local network |
| SSH | 22 | TCP | Local network |

## 🔧 Configuration

### OCR Zone Setup

The system monitors three zones on your kiln display:

1. **Temperature Display Zone** (`100,100,300,200`)
2. **Status Display Zone** (`100,220,300,280`)
3. **Error Display Zone** (`100,300,300,360`)

To calibrate OCR zones:

```bash
# Run calibration mode
python3 /kiln-ocr/frigate-ocr-integration.py --calibrate

# View calibration images
ls /frigate/media/zone_*.jpg

# Edit coordinates in frigate.yml if needed
sudo nano /frigate/config/config.yml
```

### Home Assistant Integration

#### 1. Configure MQTT Integration

Add to your Home Assistant `configuration.yaml`:

```yaml
mqtt:
  broker: 192.168.7.200
  port: 1883
  username: homeassistant
  password: [from /mosquitto/config/credentials.txt]
  discovery: true
```

#### 2. Import Sensor Configuration

Copy the contents of `home-assistant-config.yaml` to your `configuration.yaml`.

#### 3. Import Automations

Copy the contents of `home-assistant-automations.yaml` to your `automations.yaml`.

#### 4. Import Dashboard

In Home Assistant:
1. Go to **Settings** → **Dashboards**
2. Create new dashboard: **"Kiln Monitoring"**
3. Copy YAML from `kiln-dashboard.yaml`

## 📊 Monitoring & Alerts

### Automated Alerts

The system provides intelligent alerts for:

- **🌡️ High Temperature**: Alerts when exceeding threshold (default: 2000°F)
- **❄️ Rapid Cooling**: Detects unexpected temperature drops
- **✅ Firing Complete**: Automatic detection when cooling below 200°F
- **🚨 Error Codes**: Immediate alerts for kiln error displays
- **⏰ Long Firing**: Alerts for firings exceeding time limit
- **📊 Daily Summary**: End-of-day firing statistics

### Dashboard Features

Access the dashboard at: `https://192.168.7.200:9090` (Cockpit) or through Home Assistant

**Real-time Monitoring:**
- Live temperature gauge (0-2500°F)
- Firing duration timer
- Current kiln status
- Error code display

**Historical Data:**
- 24-hour temperature trends
- Temperature rate of change
- Firing statistics
- Alert history

**Live Video:**
- Real-time kiln camera feed
- OCR zone overlays
- Snapshot capabilities

## 🔒 Security Features

### Network Security
- **Firewall**: Restricts access to local network only
- **SSL/TLS**: Encrypted communication for all web interfaces
- **Authentication**: MQTT broker with user-based access control

### Access Control
- **MQTT Users**: Role-based permissions (admin, frigate, homeassistant, readonly)
- **SSH**: Key-based authentication only
- **Certificates**: Self-signed CA with 1-year validity

### File Permissions
- **SSL keys**: Secured with 600 permissions
- **MQTT passwords**: Hashed and secured
- **Configuration files**: Protected access

## 💾 Data Management

### Storage Structure
```
/var/lib/kiln-monitoring/
├── frigate/           # Frigate recordings and snapshots
├── mosquitto/         # MQTT broker data and logs
├── kiln-data/         # Temperature history and firing logs
└── logs/              # System and service logs
```

### Backup Strategy

**Automated Backups:**
- **Daily**: Configuration files and recent data
- **Weekly**: Complete system backup
- **Monthly**: Long-term archive

**Manual Backup:**
```bash
sudo /var/lib/kiln-monitoring/backup-kiln-data.sh weekly
```

### Data Retention

| Data Type | Retention Period |
|-----------|------------------|
| Raw temperature readings | 90 days |
| Frigate recordings | 7 days (30 days for events) |
| Firing logs | Permanent |
| System logs | 14 days |
| MQTT logs | 30 days |

## 🧪 Testing & Validation

### System Health Check
```bash
sudo /usr/local/bin/kiln-health-check.sh
```

### Performance Testing
```bash
sudo /usr/local/bin/performance-test.sh [duration_seconds]
```

### Comprehensive Testing
```bash
sudo /usr/local/bin/testing-validation.sh
```

## 🔧 Maintenance

### Service Management

**Check service status:**
```bash
systemctl status mosquitto.service frigate.service kiln-ocr.service
```

**Restart services:**
```bash
sudo /usr/local/bin/restart-kiln-services.sh
```

**View logs:**
```bash
journalctl -u frigate.service -f
journalctl -u mosquitto.service -f
journalctl -u kiln-ocr.service -f
```

### Updates

**Container auto-updates** run weekly (Sundays at 3 AM):
```bash
systemctl status podman-auto-update-kiln.timer
```

**Manual update:**
```bash
sudo podman auto-update
sudo systemctl restart mosquitto.service frigate.service kiln-ocr.service
```

### Certificate Management

**Check certificate expiration:**
```bash
sudo /usr/local/bin/renew-kiln-certificates.sh
```

**View certificate info:**
```bash
cat /ssl/cert-info.txt
```

## 🚨 Troubleshooting

### Common Issues

#### Services Not Starting
```bash
# Check dependencies
sudo systemctl list-dependencies mosquitto.service

# Check logs
journalctl -u mosquitto.service --since "10 minutes ago"

# Test startup order
sudo /usr/local/bin/test-kiln-startup.sh
```

#### MQTT Connection Issues
```bash
# Test MQTT authentication
sudo /usr/local/bin/test-mqtt-auth.sh

# Check MQTT credentials
sudo cat /mosquitto/config/credentials.txt

# Test MQTT manually
mosquitto_pub -h localhost -p 1883 -u admin -P [password] -t test -m "hello"
```

#### OCR Not Reading Temperature
```bash
# Check camera connection
ls -la /dev/video*

# Run OCR calibration
python3 /kiln-ocr/frigate-ocr-integration.py --calibrate

# Check debug images
ls /frigate/media/debug/

# Test OCR manually
python3 /kiln-ocr/ocr_processor.py
```

#### Frigate Not Recording
```bash
# Check Frigate logs
journalctl -u frigate.service -f

# Test Frigate API
curl http://localhost:5000/api/stats

# Check storage space
df -h /var/lib/kiln-monitoring
```

#### Network Access Issues
```bash
# Check firewall status
sudo /usr/local/bin/check-kiln-firewall.sh

# Test connectivity
nc -z 192.168.7.200 1883  # MQTT
nc -z 192.168.7.200 5000  # Frigate
nc -z 192.168.7.200 9090  # Cockpit
```

### Performance Issues

#### High CPU Usage
```bash
# Check container resources
podman stats

# Run performance test
sudo /usr/local/bin/performance-test.sh

# Check for intensive processes
top -p $(pgrep -d',' frigate)
```

#### Storage Full
```bash
# Run cleanup
sudo /var/lib/kiln-monitoring/cleanup-kiln-data.sh

# Check storage usage
du -sh /var/lib/kiln-monitoring/*

# Adjust retention policies
sudo nano /var/lib/kiln-monitoring/retention-config.yml
```

## 📞 Support

### Log Locations
- **System logs**: `journalctl -u [service-name]`
- **Frigate logs**: `/var/lib/kiln-monitoring/logs/frigate/`
- **MQTT logs**: `/var/lib/kiln-monitoring/mosquitto/log/`
- **OCR logs**: `/var/lib/kiln-monitoring/logs/ocr-processor/`

### Configuration Files
- **Frigate**: `/frigate/config/config.yml`
- **MQTT**: `/mosquitto/config/mosquitto.conf`
- **Firewall**: `/usr/local/bin/check-kiln-firewall.sh`
- **SSL**: `/ssl/cert-info.txt`

### Health Monitoring
The system includes comprehensive monitoring scripts that automatically check:
- Service status and dependencies
- Network connectivity
- Storage health
- Certificate validity
- Performance metrics
- Security configuration

## 🏆 Features Summary

- ✅ **Frigate NVR** with Intel GPU acceleration
- ✅ **OCR temperature reading** with configurable zones
- ✅ **MQTT broker** with authentication and SSL
- ✅ **Home Assistant integration** with sensors and automations
- ✅ **Real-time dashboard** with live video feed
- ✅ **Automated alerts** for all firing phases
- ✅ **Secure network access** with firewall and SSL
- ✅ **Data persistence** with automated backups
- ✅ **Performance monitoring** and health checks
- ✅ **Comprehensive testing** framework
- ✅ **Complete documentation** and troubleshooting guides

---

## 📝 License

This project is licensed under the MIT License - see the LICENSE file for details.

## 🤝 Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

## 🙏 Acknowledgments

- **Frigate NVR** project for excellent video processing
- **Home Assistant** community for automation platform
- **Mosquitto** for reliable MQTT messaging
- **Fedora bootc** for immutable OS foundation

# Testing

## Pre-Deployment Testing

Before deploying to your Fitlet2 device, thoroughly test the system using the provided testing scripts:

### 🧪 Comprehensive Test Suite

Run the full test suite to validate all components:

```bash
# Run complete test suite
./scripts/test-ocr-container.sh

# Quick build-only test
./scripts/test-ocr-container.sh --build-only

# Essential tests only
./scripts/test-ocr-container.sh --quick
```

The test suite includes:
- **Container Build Test**: Validates OCR container builds successfully
- **Dependency Test**: Verifies all Python packages and Tesseract are available
- **OCR Functionality Test**: Tests text recognition with sample images
- **Health Check Test**: Validates container health monitoring
- **Systemd Config Test**: Verifies service configuration syntax
- **Frigate Integration Test**: Tests API connectivity with mock Frigate
- **Performance Test**: Measures startup time and memory usage

### 🔧 Development Testing

For iterative development and debugging:

```bash
# Setup development environment (first time)
./scripts/test-local-development.sh setup

# Quick build test during development
./scripts/test-local-development.sh build

# Interactive shell for debugging
./scripts/test-local-development.sh shell

# Test OCR on sample images
./scripts/test-local-development.sh test-ocr

# Live development with auto-rebuild
./scripts/test-local-development.sh live

# Performance profiling
./scripts/test-local-development.sh profile
```

### 🐛 Debugging OCR Issues

If OCR is not working correctly:

1. **Test with sample images**:
   ```bash
   ./scripts/test-local-development.sh test-ocr
   ```

2. **Interactive debugging**:
   ```bash
   ./scripts/test-local-development.sh shell
   # In container:
   python3 -c "import cv2, pytesseract; print('Dependencies OK')"
   tesseract --version
   ```

3. **Check OCR configuration**:
   ```bash
   # Test different OCR modes
   tesseract image.png stdout --oem 3 --psm 8
   tesseract image.png stdout --oem 3 --psm 7
   ```

### 🔄 Local Integration Testing

Test the complete system locally before deployment:

```bash
# 1. Build all containers
podman build -f containerfiles/kiln-ocr.Containerfile -t kiln-ocr:test .

# 2. Start mock services
docker run -d --name frigate-mock -p 5000:5000 minimal-frigate-mock
docker run -d --name mqtt-mock -p 1883:1883 eclipse-mosquitto

# 3. Test OCR integration
podman run --rm --network host kiln-ocr:test python3 frigate-ocr-integration.py --test

# 4. Cleanup
docker rm -f frigate-mock mqtt-mock
```

### ✅ Pre-Deployment Checklist

Before deploying to production:

- [ ] **All tests pass**: `./scripts/test-ocr-container.sh`
- [ ] **OCR accuracy verified**: Test with your specific kiln display images
- [ ] **Container builds successfully**: No build errors or warnings
- [ ] **Dependencies available**: All Python packages and Tesseract working
- [ ] **Health checks pass**: Container monitoring functional
- [ ] **Performance acceptable**: Startup time < 10s, memory usage reasonable
- [ ] **Network connectivity**: Can reach Frigate and MQTT services
- [ ] **File permissions correct**: Scripts executable, configs readable

### 🚀 Production Deployment

Once all tests pass:

1. **Build and push container image**:
   ```bash
   podman build -f containerfiles/kiln-ocr.Containerfile -t quay.io/jtligon/kiln-ocr:latest .
   podman push quay.io/jtligon/kiln-ocr:latest
   ```

2. **Build bootc image**:
   ```bash
   podman build -f containerfiles/fitlet.Containerfile -t fitlet2-kiln:latest .
   ```

3. **Deploy to Fitlet2** using your preferred method (bootc, Anaconda, etc.)
