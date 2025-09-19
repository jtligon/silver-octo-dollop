# OCR Configuration Guide - Kiln Monitoring System

This guide provides detailed instructions for configuring and optimizing OCR (Optical Character Recognition) for accurate kiln temperature and status monitoring.

## 🎯 Overview

The OCR system monitors three zones on your kiln display:
1. **Temperature Display Zone** - Current kiln temperature
2. **Status Display Zone** - Firing status (FIRING, COOLING, etc.)
3. **Error Display Zone** - Error codes and alerts

## 📐 Zone Configuration

### Initial Setup

The default zone coordinates are defined in `/var/lib/kiln-monitoring/frigate-config/config.yml`:

```yaml
zones:
  temperature_display:
    coordinates: 100,100,300,200  # x1,y1,x2,y2
    filters:
      - person
    
  status_display:
    coordinates: 100,220,300,280
    filters:
      - person
      
  error_display:
    coordinates: 100,300,300,360
    filters:
      - person
```

### Zone Calibration Process

#### 1. Capture Calibration Image

```bash
# Run calibration mode
python3 /kiln-ocr/frigate-ocr-integration.py --calibrate
```

This creates:
- `/var/lib/kiln-monitoring/frigate-media/calibration_image.jpg` - Full camera view
- `/var/lib/kiln-monitoring/frigate-media/zone_*.jpg` - Individual zone extracts

#### 2. Analyze Zone Images

```bash
# View the full image
display /var/lib/kiln-monitoring/frigate-media/calibration_image.jpg

# Check individual zones
ls -la /var/lib/kiln-monitoring/frigate-media/zone_*.jpg
```

#### 3. Determine Optimal Coordinates

**Zone Coordinate Format**: `x1,y1,x2,y2`
- `x1,y1` = Top-left corner
- `x2,y2` = Bottom-right corner
- Origin (0,0) is top-left of image

**Guidelines for Zone Sizing:**
- **Temperature Zone**: Should tightly frame the numeric display
- **Status Zone**: Should capture status text area
- **Error Zone**: Should cover error code display area
- **Padding**: Add 10-20 pixels around text for best results

#### 4. Update Zone Coordinates

Edit `/var/lib/kiln-monitoring/frigate-config/config.yml`:

```yaml
zones:
  temperature_display:
    coordinates: 150,120,350,180  # Adjusted coordinates
    filters:
      - person
```

#### 5. Test New Coordinates

```bash
# Restart Frigate to apply changes
sudo systemctl restart frigate.service

# Wait for startup
sleep 10

# Run calibration again to verify
python3 /kiln-ocr/frigate-ocr-integration.py --calibrate
```

## 🔤 Text Recognition Patterns

### Temperature Patterns

The OCR system uses regex patterns to extract temperature values:

```python
temp_patterns = [
    r'(\d{1,4})°?[FC]?',      # Basic: 1200F or 1200°F
    r'(\d{1,4})\s*[°]?[FC]',  # With space: 1200 F
    r'TEMP[:\s]*(\d{1,4})',   # Label format: TEMP: 1200
    r'(\d{1,4})\s*DEG',       # Degree format: 1200 DEG
]
```

### Status Patterns

Status detection patterns:

```python
status_patterns = [
    r'(FIRING|READY|COOLING|COMPLETE|IDLE)',
    r'(ON|OFF|HEAT|COOL)',
    r'(START|STOP|PAUSE|RESUME)',
]
```

### Error Patterns

Error code detection:

```python
error_patterns = [
    r'ERR[OR]*[:\s]*(\w+)',   # ERROR: CODE
    r'FAULT[:\s]*(\w+)',      # FAULT: CODE
    r'FAIL[:\s]*(\w+)',       # FAIL: CODE
    r'E\d{1,3}',              # E01, E123
]
```

### Customizing Patterns

To modify patterns for your specific kiln display:

```bash
# Edit the OCR processor
sudo nano /kiln-ocr/ocr_processor.py

# Find the pattern arrays and modify as needed
# Example: Add pattern for your kiln's format
r'CURRENT[:\s]*(\d{1,4})',  # CURRENT: 1200
```

## 🖼️ Image Preprocessing

### Current Preprocessing Steps

The OCR system preprocesses images for better recognition:

1. **Grayscale Conversion** - Removes color information
2. **Threshold Application** - Creates high contrast black/white
3. **Noise Removal** - Morphological operations
4. **Image Scaling** - 2x upscale for better OCR

### OCR Configuration

Tesseract OCR settings:

```python
ocr_config = '--oem 3 --psm 8 -c tessedit_char_whitelist=0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ°FC:'
```

**Parameters:**
- `--oem 3` - Use default OCR engine
- `--psm 8` - Single word mode
- `tessedit_char_whitelist` - Allowed characters

### Advanced Preprocessing

For difficult-to-read displays, you can enhance preprocessing:

```python
# Add to preprocess_image() function in ocr_processor.py

# Gaussian blur to reduce noise
blurred = cv2.GaussianBlur(gray, (3, 3), 0)

# Adaptive threshold for varying lighting
adaptive_thresh = cv2.adaptiveThreshold(
    blurred, 255, cv2.ADAPTIVE_THRESH_GAUSSIAN_C, 
    cv2.THRESH_BINARY, 11, 2
)

# Dilate text to make it thicker
kernel = np.ones((2, 2), np.uint8)
dilated = cv2.dilate(adaptive_thresh, kernel, iterations=1)
```

## 🎯 Optimization Techniques

### Lighting Considerations

**Optimal Lighting:**
- Avoid glare and reflections on display
- Ensure even illumination
- Consider infrared camera for high-temperature environments

**Camera Positioning:**
- Mount camera perpendicular to display
- Minimize distance for larger text
- Avoid vibration that could blur text

### Zone Optimization

#### Temperature Zone Best Practices

```yaml
temperature_display:
  coordinates: 120,100,280,150  # Tight fit around numbers
  filters:
    - person
```

**Tips:**
- Include entire numeric display
- Exclude degree symbols if they cause confusion
- Add small padding (5-10 pixels) around numbers

#### Status Zone Best Practices

```yaml
status_display:
  coordinates: 100,200,300,240  # Wider for text
  filters:
    - person
```

**Tips:**
- Include full status text area
- Account for varying text lengths
- Ensure consistent vertical alignment

### Confidence Tuning

Adjust confidence thresholds in `ocr_processor.py`:

```python
# Temperature confidence
if temp:
    result['confidence'] = 90 if len(temp) >= 3 else 70

# Status confidence  
if status:
    result['confidence'] = 85 if status in KNOWN_STATUSES else 60
```

## 🧪 Testing and Validation

### Manual OCR Testing

```bash
# Test OCR on a specific image
cd /kiln-ocr
python3 -c "
import cv2
from ocr_processor import KilnOCRProcessor

processor = KilnOCRProcessor()
image = cv2.imread('/var/lib/kiln-monitoring/frigate-media/zone_temperature_display.jpg')
result = processor.process_zone_image(image, 'temperature_display')
print('Raw text:', result.get('raw_text'))
print('Extracted temp:', result.get('temperature'))
print('Confidence:', result.get('confidence'))
"
```

### Live OCR Testing

```bash
# Monitor OCR results in real-time
mosquitto_sub -h localhost -p 1883 -u admin -P [password] -t "frigate/kiln/+/+" -v
```

### Debug Image Analysis

```bash
# View debug images with overlays
ls /var/lib/kiln-monitoring/frigate-media/debug/full_with_zones_*.jpg

# Check individual zone extracts
ls /var/lib/kiln-monitoring/frigate-media/debug/temperature_display_*.jpg
ls /var/lib/kiln-monitoring/frigate-media/debug/status_display_*.jpg
ls /var/lib/kiln-monitoring/frigate-media/debug/error_display_*.jpg
```

## 🔧 Common Issues and Solutions

### Issue: No Temperature Reading

**Symptoms:**
- MQTT shows no temperature data
- OCR confidence is 0
- Raw text is empty

**Solutions:**
1. **Check zone coordinates**:
   ```bash
   python3 /kiln-ocr/frigate-ocr-integration.py --calibrate
   # Verify zone captures the numeric display
   ```

2. **Verify camera feed**:
   ```bash
   curl http://localhost:5000/api/kiln_camera/latest.jpg -o test.jpg
   # Check if display is visible and clear
   ```

3. **Test OCR manually**:
   ```bash
   tesseract /var/lib/kiln-monitoring/frigate-media/zone_temperature_display.jpg stdout
   ```

### Issue: Inaccurate Temperature Reading

**Symptoms:**
- Temperature reading is consistently wrong
- Values are off by consistent amount
- OCR confidence is high but value is incorrect

**Solutions:**
1. **Check text patterns**:
   ```python
   # Add specific pattern for your display
   r'(\d{4})\s*F',  # If display shows "1200 F"
   ```

2. **Improve preprocessing**:
   ```python
   # Increase image scaling
   scaled = cv2.resize(cleaned, None, fx=3, fy=3, interpolation=cv2.INTER_CUBIC)
   ```

3. **Adjust zone coordinates**:
   - Ensure zone includes complete numbers
   - Exclude distracting elements

### Issue: Intermittent Readings

**Symptoms:**
- Temperature reading works sometimes
- Confidence varies significantly
- Readings drop out periodically

**Solutions:**
1. **Check lighting conditions**:
   - Verify consistent illumination
   - Avoid reflections and glare

2. **Improve image quality**:
   ```yaml
   # In frigate.yml
   snapshots:
     quality: 95  # Increase from 90
   ```

3. **Add noise filtering**:
   ```python
   # Add to preprocessing
   filtered = cv2.bilateralFilter(gray, 9, 75, 75)
   ```

## 📊 Performance Monitoring

### OCR Performance Metrics

Monitor OCR performance:

```bash
# Check OCR processing logs
tail -f /var/lib/kiln-monitoring/logs/ocr-processor/ocr.log

# Monitor MQTT message frequency
mosquitto_sub -h localhost -p 1883 -u admin -P [password] -t "frigate/kiln/temperature/current" | while read line; do echo "$(date): $line"; done
```

### Confidence Tracking

Track OCR confidence over time:

```bash
# Extract confidence values from MQTT
mosquitto_sub -h localhost -p 1883 -u admin -P [password] -t "frigate/kiln/temperature/current" | jq .confidence
```

### Processing Speed

Monitor OCR processing speed:

```bash
# Check processing interval
grep -E "Processing.*seconds" /var/lib/kiln-monitoring/logs/ocr-processor/*.log
```

## 🚀 Advanced Configuration

### Multiple Display Zones

For kilns with multiple temperature displays:

```yaml
zones:
  chamber_1_temp:
    coordinates: 100,100,200,150
    filters: [person]
  
  chamber_2_temp:
    coordinates: 220,100,320,150
    filters: [person]
    
  setpoint_temp:
    coordinates: 100,200,200,250
    filters: [person]
```

### Custom OCR Models

For specialized displays, consider training custom models:

```bash
# Generate training data
python3 generate_training_data.py

# Train custom model (requires additional setup)
tesseract image.png output -l custom_kiln
```

### Hardware Acceleration

For systems with Intel GPU:

```yaml
# In frigate.yml
ffmpeg:
  hwaccel_args: preset-intel-qsv-h264
```

## 📝 Configuration Templates

### High-Temperature Kiln

```yaml
zones:
  temperature_display:
    coordinates: 150,80,350,140
    filters: [person]
  
  setpoint_display:
    coordinates: 150,160,350,200
    filters: [person]
    
  ramp_rate:
    coordinates: 400,80,500,120
    filters: [person]
```

### Multi-Zone Kiln

```yaml
zones:
  zone_1_temp:
    coordinates: 100,100,250,150
    filters: [person]
    
  zone_2_temp:
    coordinates: 100,170,250,220
    filters: [person]
    
  zone_3_temp:
    coordinates: 100,240,250,290
    filters: [person]
```

### Kiln with Alphanumeric Display

```python
# Custom patterns for alphanumeric displays
temp_patterns = [
    r'T1[:\s]*(\d{3,4})',     # T1: 1200
    r'TEMP1[:\s]*(\d{3,4})',  # TEMP1: 1200
    r'CH1[:\s]*(\d{3,4})',    # CH1: 1200
]
```

---

## 📞 Support

For OCR-specific issues:

1. **Generate debug package**:
   ```bash
   mkdir /tmp/ocr-debug
   cp /var/lib/kiln-monitoring/frigate-media/debug/* /tmp/ocr-debug/
cp /var/lib/kiln-monitoring/frigate-config/config.yml /tmp/ocr-debug/
   cp /var/lib/kiln-monitoring/logs/ocr-processor/*.log /tmp/ocr-debug/
   tar -czf /tmp/ocr-debug-$(date +%Y%m%d).tar.gz -C /tmp ocr-debug/
   ```

2. **Include in issue report**:
   - OCR debug images
   - Configuration file
   - Error logs
   - Display photos (for reference)

3. **Test commands used**:
   - Calibration commands
   - Manual OCR tests
   - Zone coordinate changes 