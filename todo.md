# Kiln Monitoring System: MotionEye → Frigate Migration

## 🎯 Project Goal
Replace MotionEye with Frigate for advanced kiln monitoring with OCR capabilities, Home Assistant integration, and comprehensive temperature tracking with automated alerts.

---

## 📋 Todo List

### 1. Container Infrastructure Changes
- [x] Replace `motioneye.container` with `frigate.container` systemd service
- [x] Update `fitlet.Containerfile` to remove MotionEye references and add Frigate requirements
- [x] Create Frigate configuration directory structure (`/frigate/config`, `/frigate/media`)
- [x] Add required dependencies for Frigate (Intel GPU drivers for hardware acceleration)
- [x] Remove obsolete MotionEye directories and references
- [x] Create `mosquitto.container` systemd service for MQTT broker
- [x] Remove Home Assistant container (using existing HA on network)

### 2. Frigate Configuration
- [ ] Create `frigate.yml` configuration file with camera stream configuration
- [ ] Configure OCR zones for temperature displays
- [ ] Set up object detection settings optimized for text recognition  
- [ ] Configure recording and snapshot settings
- [ ] Set up MQTT configuration for Home Assistant integration
- [ ] Configure hardware acceleration (if Intel GPU available)

### 3. OCR Zone Setup
- [ ] Configure OCR zones to detect current temperature display area
- [ ] Configure OCR zones to detect target temperature display area (if applicable)
- [ ] Configure OCR zones to detect status indicators/error codes area
- [ ] Set up text recognition patterns for temperature values
- [ ] Configure confidence thresholds for OCR accuracy
- [ ] Test OCR accuracy with actual kiln display

### 4. MQTT & Communication Setup
- [x] Install and configure MQTT broker (Mosquitto) container
- [x] Configure MQTT for same-network communication (192.168.x.x)
- [ ] Set up MQTT topics for temperature data
- [ ] Configure MQTT topics for status and error codes
- [ ] Test MQTT message flow between Fitlet2 and Home Assistant

### 5. Home Assistant Integration
- [ ] Configure Frigate integration in existing Home Assistant (192.168.5.x)
- [ ] Set up MQTT integration in Home Assistant pointing to Fitlet2 (192.168.7.200)
- [ ] Create Home Assistant sensors for current kiln temperature
- [ ] Create Home Assistant sensors for target temperature
- [ ] Create Home Assistant sensors for kiln status/error codes
- [ ] Create Home Assistant sensors for firing start time
- [ ] Create Home Assistant sensors for firing duration

### 6. Home Assistant Automations
#### Temperature Threshold Alerts
- [ ] Create high temperature warning automation
- [ ] Create low temperature alert (unexpected cooling) automation
- [ ] Create temperature rate change alerts automation
- [ ] Configure notification channels (email, mobile, etc.)

#### Firing Completion Notifications  
- [ ] Create automation to detect firing completion based on temperature patterns
- [ ] Set up multi-channel notifications for firing completion
- [ ] Create cooling phase detection automation

#### Error Code Detection
- [ ] Create automation to detect and alert on error codes
- [ ] Map common error codes to human-readable messages
- [ ] Set up immediate alert system for critical errors

#### Time-based Monitoring
- [ ] Create automation to track firing duration
- [ ] Set up schedule-based alerts (e.g., firing taking too long)
- [ ] Create automatic firing phase detection (heating, soaking, cooling)

### 7. Dashboard Development
- [ ] Create Home Assistant dashboard layout
- [ ] Add current kiln temperature display (large, prominent)
- [ ] Add time since firing started (countdown/timer)
- [ ] Add temperature trend graphs (historical data visualization)
- [ ] Add live webcam feed from Frigate
- [ ] Add status indicators and error code display
- [ ] Add quick action buttons (if applicable)
- [ ] Optimize dashboard for mobile viewing

### 8. Data Storage & Persistence
- [ ] Configure persistent storage for Frigate recordings and snapshots
- [ ] Configure persistent storage for Home Assistant database
- [ ] Set up persistent storage for historical temperature data
- [ ] Configure data retention policies for recordings
- [ ] Configure data retention policies for temperature history
- [ ] Set up automated backup strategies
- [ ] Test data persistence across container restarts

### 9. Network & Security
- [ ] Update firewall rules for Frigate ports
- [ ] Update firewall rules for Home Assistant ports  
- [ ] Update firewall rules for MQTT broker ports
- [ ] Configure SSL certificates for secure web access
- [ ] Set up Home Assistant authentication
- [ ] Configure MQTT authentication
- [ ] Review and implement network segmentation

### 10. System Integration
- [ ] Update systemd services configuration for new containers
- [ ] Modify container auto-update policies
- [ ] Configure log rotation for Frigate
- [ ] Configure log rotation for Home Assistant
- [ ] Configure log rotation for MQTT broker
- [ ] Update Cockpit integration for new containers
- [ ] Test systemd service startup order

### 11. Testing & Validation
- [ ] Test OCR accuracy with actual kiln display
- [ ] Validate temperature reading precision and accuracy
- [ ] Test all automation triggers with simulated scenarios
- [ ] Verify notification delivery across all channels
- [ ] Performance testing under continuous monitoring
- [ ] Test system recovery after power loss
- [ ] Validate data integrity across restarts

### 12. Documentation & Maintenance
- [ ] Update README with new Frigate-based setup instructions
- [ ] Document OCR zone configuration process
- [ ] Create troubleshooting guide for common issues
- [ ] Document Home Assistant automation logic
- [ ] Create user manual for dashboard usage
- [ ] Document backup and recovery procedures

---

## 🚀 Completed Tasks
<!-- Completed tasks will be moved here as they are finished -->

---

## 📝 Notes
- Each task should be completed in a separate branch and PR for review
- Test thoroughly before marking tasks as complete
- Update this file as new requirements are discovered
- Consider hardware limitations of the Fitlet device when configuring

---

## 🔧 Technical Considerations
- Intel GPU acceleration availability on Fitlet2
- Network bandwidth requirements for continuous video processing
- Storage requirements for recordings and historical data
- Power consumption impact of additional containers
- Temperature monitoring accuracy requirements
- **Network Setup**: Fitlet2 at 192.168.7.200, Home Assistant at 192.168.5.x (same network)
- MQTT broker on Fitlet2 will serve Home Assistant over network 