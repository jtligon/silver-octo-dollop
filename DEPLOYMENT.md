# 🚀 Fitlet2 Kiln Monitoring System Deployment Guide

## 📋 **Pre-Deployment Checklist**

- [ ] Fitlet2 device at IP `192.168.7.200` accessible
- [ ] Network access to quay.io registry
- [ ] SSH access to Fitlet2 (if upgrading existing system)
- [ ] Backup of existing data (if applicable)

## 🎯 **Container Images Built**

| Container | Registry URL | Purpose |
|-----------|--------------|---------|
| **Main OS** | `quay.io/jtligon/fitlet2-kiln:latest` | Bootc OS with all services |
| **OCR Service** | `quay.io/jtligon/kiln-ocr:latest` | OCR processing container |
| **Backup Tags** | `:20250627` | Dated versions for rollback |

---

## 🔧 **Deployment Methods**

### **Method 1: Bootc Image Deployment (Recommended)**

#### **Step 1: Create Bootable Image**
```bash
# Create qcow2 image for VM deployment or dd to USB
podman run --rm -it --privileged --pull=newer \
  -v $(pwd)/output:/output \
  -v /var/lib/containers/storage:/var/lib/containers/storage \
  quay.io/centos-bootc/bootc-image-builder:latest \
  --type qcow2 \
  quay.io/jtligon/fitlet2-kiln:latest
```

#### **Step 2: Deploy to Fitlet2**
```bash
# Option A: Flash to USB and boot Fitlet2
sudo dd if=output/disk.qcow2 of=/dev/sdX bs=4M status=progress

# Option B: Direct network deployment (if supported)
scp output/disk.qcow2 root@192.168.7.200:/tmp/
ssh root@192.168.7.200 "dd if=/tmp/disk.qcow2 of=/dev/sda bs=4M"
```

### **Method 2: Upgrade Existing System**

#### **Step 1: Pull New Image**
```bash
ssh root@192.168.7.200
podman pull quay.io/jtligon/fitlet2-kiln:latest
```

#### **Step 2: Bootc Upgrade**
```bash
# Upgrade to new image
bootc switch quay.io/jtligon/fitlet2-kiln:latest
systemctl reboot
```

---

## 🛠️ **Post-Deployment Configuration**

### **Step 1: Initial System Setup**
```bash
# SSH into Fitlet2
ssh jtligon@192.168.7.200

# Run initial setup scripts
sudo /usr/local/bin/storage-setup.sh
sudo /usr/local/bin/firewall-setup.sh
sudo /usr/local/bin/ssl-setup.sh
```

### **Step 2: Configure MQTT Authentication**
```bash
# Setup MQTT users and ACLs
sudo /usr/local/bin/mqtt-auth-setup.sh
```

### **Step 3: Configure Systemd Services**
```bash
# Setup service dependencies and log rotation
sudo /usr/local/bin/systemd-integration.sh
```

### **Step 4: Start All Services**
```bash
# Enable and start all containers
sudo systemctl daemon-reload
sudo systemctl enable --now frigate.container
sudo systemctl enable --now mosquitto.container
sudo systemctl enable --now kiln-ocr.container
```

---

## 🔍 **Verification & Testing**

### **Step 1: Service Status Check**
```bash
# Check all services are running
sudo systemctl status frigate.container
sudo systemctl status mosquitto.container
sudo systemctl status kiln-ocr.container

# Check container logs
sudo podman logs frigate
sudo podman logs mosquitto
sudo podman logs kiln-ocr
```

### **Step 2: Network Connectivity Test**
```bash
# Test MQTT connectivity
mosquitto_pub -h localhost -p 1883 -t test/topic -m "hello world"
mosquitto_sub -h localhost -p 1883 -t test/topic -C 1

# Test Frigate web interface
curl -I http://localhost:5000
```

### **Step 3: OCR Processing Test**
```bash
# Test OCR container functionality
sudo podman exec kiln-ocr python3 -c "import cv2, pytesseract; print('OCR Working!')"
```

### **Step 4: Comprehensive Testing**
```bash
# Run full test suite
sudo /usr/local/bin/testing-validation.sh
```

---

## 🔐 **Security Configuration**

### **SSL Certificate Setup**
```bash
# Generate SSL certificates for MQTT and web services
sudo /usr/local/bin/ssl-setup.sh

# Configure MQTT to use SSL
sudo systemctl restart mosquitto.container
```

### **Firewall Configuration**
```bash
# Verify firewall rules
sudo firewall-cmd --list-all
sudo ufw status  # if using UFW
```

### **User Access Control**
```bash
# Add users to necessary groups
sudo usermod -aG wheel jtligon
sudo usermod -aG podman jtligon
```

---

## 📊 **Monitoring & Maintenance**

### **Container Auto-Updates**
```bash
# Verify auto-update timer is active
sudo systemctl status podman-auto-update.timer

# Manual update check
sudo podman auto-update
```

### **Log Management**
```bash
# Check log rotation
sudo logrotate -d /etc/logrotate.d/containers

# View recent logs
sudo journalctl -u frigate.container -f
sudo journalctl -u mosquitto.container -f
sudo journalctl -u kiln-ocr.container -f
```

### **Performance Monitoring**
```bash
# Run performance tests
sudo /usr/local/bin/performance-test.sh

# Check resource usage
sudo podman stats
```

---

## 🏠 **Home Assistant Integration**

### **Step 1: MQTT Discovery**
```bash
# Verify MQTT discovery messages
mosquitto_sub -h 192.168.7.200 -p 1883 -t homeassistant/# -v
```

### **Step 2: Frigate Integration**
```bash
# Test Frigate API from Home Assistant
curl http://192.168.7.200:5000/api/stats
```

### **Step 3: Configure Dashboards**
Home Assistant configuration files are pre-installed:
- `/var/lib/kiln-monitoring/frigate-config/config.yml` - Frigate configuration
- Dashboards configured for kiln monitoring

---

## 🔧 **Troubleshooting**

### **Common Issues**

#### **Container Won't Start**
```bash
# Check container status
sudo podman ps -a
sudo podman logs <container_name>

# Restart container
sudo systemctl restart <service>.container
```

#### **Network Issues**
```bash
# Check network connectivity
ping 8.8.8.8
ss -tulpn | grep -E "(1883|5000|8080)"

# Restart networking
sudo systemctl restart NetworkManager
```

#### **OCR Not Working**
```bash
# Check OCR container logs
sudo podman logs kiln-ocr

# Test OCR functionality
sudo podman exec kiln-ocr python3 -c "import cv2, pytesseract; print(pytesseract.get_tesseract_version())"
```

### **Emergency Recovery**
```bash
# Rollback to previous version
bootc switch quay.io/jtligon/fitlet2-kiln:20250627
systemctl reboot

# Reset to factory defaults
sudo /usr/local/bin/storage-setup.sh --reset
```

---

## 📝 **Configuration Files**

### **Key Configuration Locations**
- **Frigate Config**: `/var/lib/kiln-monitoring/frigate-config/config.yml`
- **MQTT Config**: `/var/lib/kiln-monitoring/mosquitto-config/mosquitto.conf`
- **SSL Certificates**: `/etc/ssl/kiln-monitoring/`
- **Systemd Services**: `/etc/containers/systemd/*.container`

### **Data Directories**
- **Frigate Media**: `/var/lib/kiln-monitoring/frigate-media/`
- **MQTT Data**: `/var/lib/kiln-monitoring/mosquitto/data/`
- **OCR Logs**: `/kiln-ocr/logs/`
- **Backup Data**: `/data/backups/`

---

## 🎯 **Performance Optimization**

### **Container Resource Limits**
Each container is configured with appropriate resource limits:
- **Frigate**: 2GB RAM, 2 CPU cores
- **MQTT**: 512MB RAM, 1 CPU core  
- **OCR**: 1GB RAM, 1 CPU core

### **Storage Optimization**
```bash
# Clean up old container images
sudo podman system prune -a

# Optimize storage usage
sudo /usr/local/bin/storage-setup.sh --optimize
```

---

## 📞 **Support & Documentation**

### **Additional Resources**
- **Frigate Documentation**: https://docs.frigate.video/
- **Mosquitto Documentation**: https://mosquitto.org/documentation/
- **Bootc Documentation**: https://containers.github.io/bootc/

### **Log Files for Support**
```bash
# Collect system information
sudo /usr/local/bin/testing-validation.sh > system-report.txt

# Collect container logs
sudo podman logs frigate > frigate.log 2>&1
sudo podman logs mosquitto > mosquitto.log 2>&1
sudo podman logs kiln-ocr > kiln-ocr.log 2>&1
```

---

## ✅ **Deployment Complete!**

After successful deployment, your Fitlet2 will be running:
- **🎥 Frigate NVR** - Camera monitoring and object detection
- **📡 MQTT Broker** - Message communication hub
- **🔍 OCR Service** - Temperature reading from kiln display
- **🏠 Home Assistant Integration** - Automated monitoring and alerts
- **🔐 SSL Security** - Encrypted communications
- **🔄 Auto-Updates** - Automated container updates

**Web Interfaces:**
- **Frigate**: http://192.168.7.200:5000
- **Cockpit**: https://192.168.7.200:9090

**Your kiln monitoring system is now fully operational!** 🎉 