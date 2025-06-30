# 🏠 Home Assistant MQTT Integration Setup

## 📡 **MQTT Broker Information**
- **Host:** `192.168.7.200` (Fitlet2)
- **Port:** `1883`
- **Authentication:** None (basic setup)
- **WebSocket Port:** `9001` (if needed)

---

## 🔧 **Step 1: Add MQTT Integration in Home Assistant**

### **Option A: Via UI (Recommended)**
1. Go to **Settings** → **Devices & Services**
2. Click **"+ ADD INTEGRATION"**
3. Search for **"MQTT"**
4. Enter connection details:
   - **Broker:** `192.168.7.200`
   - **Port:** `1883`
   - **Username:** (leave empty)
   - **Password:** (leave empty)
5. Click **Submit**

### **Option B: Via Configuration File**
Add to your `configuration.yaml`:
```yaml
mqtt:
  broker: 192.168.7.200
  port: 1883
  discovery: true
  discovery_prefix: homeassistant
```

Then restart Home Assistant.

---

## 🧪 **Step 2: Test MQTT Connection**

### **In Home Assistant Developer Tools:**
1. Go to **Developer Tools** → **Services**
2. Use service: `mqtt.publish`
3. Service data:
```yaml
topic: test/homeassistant
payload: "Hello from Home Assistant!"
```

### **Check if message was received on Fitlet2:**
SSH to Fitlet2 and run:
```bash
podman exec mosquitto mosquitto_sub -h localhost -t 'test/homeassistant' -C 1
```

---

## 🔥 **Step 3: Set Up Kiln Monitoring Entities**

### **Create MQTT Sensors in Home Assistant**

Add to `configuration.yaml`:
```yaml
mqtt:
  broker: 192.168.7.200
  port: 1883
  discovery: true
  
  sensor:
    - name: "Kiln Temperature"
      state_topic: "kiln/temperature"
      unit_of_measurement: "°F"
      device_class: temperature
      icon: mdi:thermometer-high
      
    - name: "Kiln Status"
      state_topic: "kiln/status"
      icon: mdi:fire
      
    - name: "OCR Confidence"
      state_topic: "kiln/ocr_confidence"
      unit_of_measurement: "%"
      icon: mdi:eye
```

### **Create MQTT Binary Sensors for Alerts**
```yaml
mqtt:
  binary_sensor:
    - name: "Kiln High Temperature Alert"
      state_topic: "kiln/alerts/high_temp"
      payload_on: "ON"
      payload_off: "OFF"
      device_class: heat
      
    - name: "Kiln Motion Detected"
      state_topic: "kiln/motion"
      payload_on: "ON"
      payload_off: "OFF"
      device_class: motion
```

---

## 🚨 **Step 4: Create Automation for Alerts**

```yaml
automation:
  - alias: "Kiln High Temperature Alert"
    trigger:
      - platform: numeric_state
        entity_id: sensor.kiln_temperature
        above: 2000  # Adjust threshold as needed
    action:
      - service: notify.notify
        data:
          title: "🔥 Kiln Alert"
          message: "Kiln temperature is {{ states('sensor.kiln_temperature') }}°F"
      
  - alias: "Kiln Temperature Reading Failed"
    trigger:
      - platform: state
        entity_id: sensor.kiln_temperature
        to: "unavailable"
        for:
          minutes: 5
    action:
      - service: notify.notify
        data:
          title: "⚠️ Kiln Monitoring Alert"
          message: "Unable to read kiln temperature for 5 minutes"
```

---

## 📊 **Step 5: Create Dashboard Cards**

### **Temperature Gauge Card**
```yaml
type: gauge
entity: sensor.kiln_temperature
name: Kiln Temperature
min: 0
max: 2300
severity:
  green: 0
  yellow: 1800
  red: 2100
```

### **History Graph Card**
```yaml
type: history-graph
entities:
  - entity: sensor.kiln_temperature
hours_to_show: 24
refresh_interval: 30
```

### **Camera Card (when Frigate is ready)**
```yaml
type: picture-entity
entity: camera.kiln_camera
name: Kiln View
show_state: false
```

---

## 🔍 **Step 6: Test OCR Temperature Reading**

Once you have camera images, test the OCR system:

### **Send Test Image to OCR Service**
```bash
# From your Home Assistant system, test MQTT publishing
mosquitto_pub -h 192.168.7.200 -t 'kiln/image_request' -m 'capture'
```

### **Monitor Temperature Readings**
```bash
# Subscribe to temperature readings
mosquitto_sub -h 192.168.7.200 -t 'kiln/temperature' -v
```

---

## 🚀 **Expected MQTT Topics**

| Topic | Purpose | Example Value |
|-------|---------|---------------|
| `kiln/temperature` | Current temperature | `1850` |
| `kiln/status` | Kiln status | `heating`, `cooling`, `off` |
| `kiln/ocr_confidence` | OCR reading confidence | `95.2` |
| `kiln/alerts/high_temp` | High temp alert | `ON`/`OFF` |
| `kiln/motion` | Motion detection | `ON`/`OFF` |
| `homeassistant/sensor/kiln_temp/config` | Auto-discovery | JSON config |

---

## 🔧 **Troubleshooting**

### **Connection Issues**
- Verify networks can communicate: `ping 192.168.7.200`
- Check firewall: `sudo firewall-cmd --list-all`
- Test with mosquitto client: `mosquitto_sub -h 192.168.7.200 -t '#' -v`

### **No Data Received**
- Check OCR service logs: `podman logs kiln-ocr`
- Verify MQTT broker logs: `podman logs mosquitto`
- Test manual MQTT publish from Fitlet2

### **OCR Not Working**
- Check camera feed is working
- Verify OCR zones are configured correctly
- Test with sample images

---

## ✅ **Next Steps**
1. Set up MQTT integration ✅
2. Test basic connectivity ✅  
3. Configure sensor entities ⏳
4. Create dashboard cards ⏳
5. Set up automation alerts ⏳
6. Wait for Frigate camera integration ⏳

**Your kiln monitoring system integration is ready to configure!** 🎉 