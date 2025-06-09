A bootc based deployment of motioneye in a container for use with an x86 device that has a webcam plugged into it.

[![Docker Repository on Quay](https://quay.io/repository/jtligon/fitlet2/status "Docker Repository on Quay")](https://quay.io/repository/jtligon/fitlet2)

## Overview

This repository contains a containerized deployment of MotionEye using bootc, designed for x86 devices with webcam support. MotionEye provides a web-based interface for video surveillance, motion detection, and recording capabilities.

## Hardware Requirements

- x86-based device (e.g., Fitlet2, PC, or compatible single-board computer)
- USB webcam or compatible camera
- Minimum 2GB RAM
- 10GB+ storage space for video recordings
- Network connectivity

## Installation

1. Ensure your device has bootc installed and configured
2. Pull the container image:
   ```bash
   podman pull quay.io/jtligon/fitlet2
   ```
3. Run the container:
   ```bash
   podman run -d \
     --name motioneye \
     -p 8765:8765 \
     -p 8766:8766 \
     -p 9090:9090 \
     -p 9100:9100 \
     -v /path/to/recordings:/var/lib/motioneye \
     -v /path/to/ssl:/etc/motioneye/ssl \
     -v /path/to/metrics:/etc/motioneye/metrics \
     --device=/dev/video0:/dev/video0 \
     quay.io/jtligon/fitlet2
   ```

## Configuration

### Environment Variables

The container can be configured using the following environment variables:

| Variable | Description | Default |
|----------|-------------|---------|
| `MOTIONEYE_PORT` | Web interface port | 8765 |
| `MOTIONEYE_USERNAME` | Admin username | admin |
| `MOTIONEYE_PASSWORD` | Admin password | admin |
| `MOTIONEYE_CONF_PATH` | Configuration directory | /etc/motioneye |
| `MOTIONEYE_RUN_PATH` | Runtime directory | /var/run/motion |
| `MOTIONEYE_MEDIA_PATH` | Media storage directory | /var/lib/motioneye |
| `MOTIONEYE_LOG_LEVEL` | Logging level (debug/info/warning/error) | info |
| `MOTIONEYE_LOG_FILE` | Log file path | /var/log/motion/motioneye.log |
| `MOTIONEYE_SSL_ENABLED` | Enable SSL/TLS | false |
| `MOTIONEYE_SSL_CERT` | SSL certificate path | /etc/motioneye/ssl/cert.pem |
| `MOTIONEYE_SSL_KEY` | SSL private key path | /etc/motioneye/ssl/key.pem |
| `MOTIONEYE_METRICS_PORT` | Prometheus metrics port | 9090 |
| `MOTIONEYE_METRICS_ENABLED` | Enable metrics collection | false |
| `MOTIONEYE_LOG_RETENTION_DAYS` | Number of days to keep logs | 30 |

### Security Features

#### SSL/TLS Support
The container supports SSL/TLS encryption for secure access to the web interface. To enable SSL:

1. Mount a volume for SSL certificates:
   ```bash
   -v /path/to/ssl:/etc/motioneye/ssl
   ```

2. Enable SSL and specify certificate paths:
   ```bash
   -e MOTIONEYE_SSL_ENABLED=true \
   -e MOTIONEYE_SSL_CERT=/etc/motioneye/ssl/cert.pem \
   -e MOTIONEYE_SSL_KEY=/etc/motioneye/ssl/key.pem
   ```

3. If no certificates are provided, the container will generate self-signed certificates.

#### Security Headers
The web interface is protected by several security headers:
- X-Frame-Options
- X-XSS-Protection
- X-Content-Type-Options
- Referrer-Policy
- Content-Security-Policy
- Strict-Transport-Security

### Monitoring and Maintenance

#### Metrics Collection
The container includes Prometheus and Node Exporter for metrics collection:

1. Enable metrics collection:
   ```bash
   -e MOTIONEYE_METRICS_ENABLED=true
   ```

2. Access metrics:
   - Prometheus: `http://your-device-ip:9090`
   - Node Exporter: `http://your-device-ip:9100`

Available metrics include:
- System metrics (CPU, memory, disk usage)
- MotionEye-specific metrics
- Network statistics
- Camera status and performance

#### Log Management
- Logs are automatically rotated daily
- Compressed logs are retained for 30 days by default
- Configure retention period with `MOTIONEYE_LOG_RETENTION_DAYS`
- Logs are stored in `/var/log/motion/`

#### Backup and Restore
1. Backup configuration and data:
   ```bash
   podman exec motioneye tar -czf backup.tar.gz /var/lib/motioneye /etc/motioneye
   podman cp motioneye:/backup.tar.gz ./backup.tar.gz
   ```

2. Restore from backup:
   ```bash
   podman cp backup.tar.gz motioneye:/backup.tar.gz
   podman exec motioneye tar -xzf backup.tar.gz -C /
   ```

### Basic Settings
- Web Interface: Access at `http://your-device-ip:8765` or `https://your-device-ip:8766` (if SSL enabled)
- Default credentials: admin/admin (change immediately after first login)

### Storage
- Recordings are stored in the mounted volume at `/var/lib/motioneye`
- Configure retention policies in the MotionEye web interface

### Camera Setup
1. Connect your webcam to the device
2. Access the MotionEye web interface
3. Add a new camera using the web interface
4. Configure motion detection settings as needed

## Troubleshooting

### Common Issues
1. **Camera not detected**
   - Verify camera is properly connected
   - Check device permissions
   - Ensure correct device path in container run command

2. **Web interface not accessible**
   - Verify container is running
   - Check port mapping
   - Ensure firewall allows ports 8765 and 8766
   - Check SSL certificate configuration if using HTTPS

3. **Recording issues**
   - Verify storage volume has sufficient space
   - Check write permissions
   - Review motion detection settings

4. **SSL/TLS issues**
   - Verify SSL certificates are properly mounted
   - Check certificate permissions
   - Ensure SSL is properly enabled in environment variables

5. **Monitoring issues**
   - Verify metrics collection is enabled
   - Check Prometheus and Node Exporter logs
   - Ensure ports 9090 and 9100 are accessible

## Support

For issues and feature requests, please open an issue in this repository.

## License

[Add License Information]
