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
     -v /path/to/recordings:/var/lib/motioneye \
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

Example with custom configuration:
```bash
podman run -d \
  --name motioneye \
  -p 8080:8080 \
  -v /path/to/recordings:/var/lib/motioneye \
  --device=/dev/video0:/dev/video0 \
  -e MOTIONEYE_PORT=8080 \
  -e MOTIONEYE_USERNAME=myuser \
  -e MOTIONEYE_PASSWORD=mypassword \
  -e MOTIONEYE_LOG_LEVEL=debug \
  quay.io/jtligon/fitlet2
```

### Basic Settings
- Web Interface: Access at `http://your-device-ip:8765`
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
   - Ensure firewall allows port 8765

3. **Recording issues**
   - Verify storage volume has sufficient space
   - Check write permissions
   - Review motion detection settings

## Support

For issues and feature requests, please open an issue in this repository.

## License

[Add License Information]
