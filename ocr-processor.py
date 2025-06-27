#!/usr/bin/env python3
"""
OCR Processor for Kiln Monitoring
Processes text detection from Frigate zones and extracts temperature/status data
Publishes structured data to MQTT for Home Assistant integration
"""

import cv2
import numpy as np
import pytesseract
import paho.mqtt.client as mqtt
import json
import re
import time
import logging
from datetime import datetime
from typing import Dict, Optional, Tuple

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)

class KilnOCRProcessor:
    def __init__(self, mqtt_host='localhost', mqtt_port=1883):
        """Initialize OCR processor with MQTT connection"""
        self.mqtt_client = mqtt.Client()
        self.mqtt_client.on_connect = self.on_mqtt_connect
        self.mqtt_client.on_disconnect = self.on_mqtt_disconnect
        
        try:
            self.mqtt_client.connect(mqtt_host, mqtt_port, 60)
            self.mqtt_client.loop_start()
        except Exception as e:
            logger.error(f"Failed to connect to MQTT broker: {e}")
        
        # Temperature extraction patterns
        self.temp_patterns = [
            r'(\d{1,4})°?[FC]?',  # Basic temperature pattern
            r'(\d{1,4})\s*[°]?[FC]',  # Temperature with degree symbol
            r'TEMP[:\s]*(\d{1,4})',  # TEMP: 1234 format
            r'(\d{1,4})\s*DEG',  # 1234 DEG format
        ]
        
        # Error code patterns
        self.error_patterns = [
            r'ERR[OR]*[:\s]*(\w+)',  # ERROR: CODE format
            r'FAULT[:\s]*(\w+)',     # FAULT: CODE format
            r'FAIL[:\s]*(\w+)',      # FAIL: CODE format
            r'E\d{1,3}',             # E01, E123 format
        ]
        
        # Status patterns
        self.status_patterns = [
            r'(FIRING|READY|COOLING|COMPLETE|IDLE)',
            r'(ON|OFF|HEAT|COOL)',
            r'(START|STOP|PAUSE|RESUME)',
        ]
        
        # OCR preprocessing settings
        self.ocr_config = '--oem 3 --psm 8 -c tessedit_char_whitelist=0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ°FC:'
        
        # Last known values for change detection
        self.last_temperature = None
        self.last_status = None
        self.last_error = None
        self.firing_start_time = None

    def on_mqtt_connect(self, client, userdata, flags, rc):
        """Callback for MQTT connection"""
        if rc == 0:
            logger.info("Connected to MQTT broker")
        else:
            logger.error(f"Failed to connect to MQTT broker: {rc}")

    def on_mqtt_disconnect(self, client, userdata, rc):
        """Callback for MQTT disconnection"""
        logger.warning("Disconnected from MQTT broker")

    def preprocess_image(self, image: np.ndarray) -> np.ndarray:
        """Preprocess image for better OCR results"""
        # Convert to grayscale
        if len(image.shape) == 3:
            gray = cv2.cvtColor(image, cv2.COLOR_BGR2GRAY)
        else:
            gray = image
        
        # Apply threshold to get high contrast
        _, thresh = cv2.threshold(gray, 0, 255, cv2.THRESH_BINARY + cv2.THRESH_OTSU)
        
        # Remove noise with morphological operations
        kernel = np.ones((2,2), np.uint8)
        cleaned = cv2.morphologyEx(thresh, cv2.MORPH_CLOSE, kernel)
        
        # Scale up for better OCR
        scaled = cv2.resize(cleaned, None, fx=2, fy=2, interpolation=cv2.INTER_CUBIC)
        
        return scaled

    def extract_temperature(self, text: str) -> Optional[int]:
        """Extract temperature value from OCR text"""
        text = text.upper().strip()
        
        for pattern in self.temp_patterns:
            matches = re.findall(pattern, text)
            if matches:
                try:
                    temp = int(matches[0])
                    # Validate temperature range (reasonable for kilns)
                    if 32 <= temp <= 2500:  # 32°F to 2500°F range
                        return temp
                except ValueError:
                    continue
        
        return None

    def extract_status(self, text: str) -> Optional[str]:
        """Extract status information from OCR text"""
        text = text.upper().strip()
        
        for pattern in self.status_patterns:
            matches = re.findall(pattern, text)
            if matches:
                return matches[0]
        
        return None

    def extract_error_code(self, text: str) -> Optional[str]:
        """Extract error codes from OCR text"""
        text = text.upper().strip()
        
        for pattern in self.error_patterns:
            matches = re.findall(pattern, text)
            if matches:
                return matches[0]
        
        return None

    def process_zone_image(self, image: np.ndarray, zone_name: str) -> Dict:
        """Process a single OCR zone image"""
        try:
            # Preprocess image
            processed_img = self.preprocess_image(image)
            
            # Perform OCR
            raw_text = pytesseract.image_to_string(processed_img, config=self.ocr_config)
            
            # Extract structured data based on zone type
            result = {
                'zone': zone_name,
                'raw_text': raw_text.strip(),
                'timestamp': datetime.now().isoformat(),
                'confidence': 0
            }
            
            if 'temperature' in zone_name.lower():
                temp = self.extract_temperature(raw_text)
                if temp:
                    result['temperature'] = temp
                    result['confidence'] = 85 if temp else 0
                    
            elif 'status' in zone_name.lower():
                status = self.extract_status(raw_text)
                if status:
                    result['status'] = status
                    result['confidence'] = 75
                    
            elif 'error' in zone_name.lower():
                error = self.extract_error_code(raw_text)
                if error:
                    result['error_code'] = error
                    result['confidence'] = 90
            
            return result
            
        except Exception as e:
            logger.error(f"Error processing zone {zone_name}: {e}")
            return {
                'zone': zone_name,
                'error': str(e),
                'timestamp': datetime.now().isoformat()
            }

    def publish_to_mqtt(self, topic: str, payload: Dict):
        """Publish data to MQTT broker"""
        try:
            json_payload = json.dumps(payload)
            self.mqtt_client.publish(topic, json_payload, qos=1, retain=True)
            logger.debug(f"Published to {topic}: {json_payload}")
        except Exception as e:
            logger.error(f"Failed to publish to MQTT: {e}")

    def process_and_publish(self, temperature_img: np.ndarray = None, 
                          status_img: np.ndarray = None, 
                          error_img: np.ndarray = None):
        """Process all zone images and publish results"""
        
        # Process temperature zone
        if temperature_img is not None:
            temp_result = self.process_zone_image(temperature_img, 'temperature_display')
            
            if 'temperature' in temp_result:
                current_temp = temp_result['temperature']
                
                # Publish current temperature
                self.publish_to_mqtt('frigate/kiln/temperature/current', {
                    'temperature': current_temp,
                    'unit': 'F',
                    'timestamp': temp_result['timestamp'],
                    'confidence': temp_result['confidence']
                })
                
                # Detect firing start/stop
                if self.last_temperature is None and current_temp > 200:
                    self.firing_start_time = datetime.now()
                    self.publish_to_mqtt('frigate/kiln/status/firing', {
                        'firing': True,
                        'start_time': self.firing_start_time.isoformat(),
                        'trigger': 'temperature_rise'
                    })
                
                # Update last known temperature
                self.last_temperature = current_temp
        
        # Process status zone
        if status_img is not None:
            status_result = self.process_zone_image(status_img, 'status_display')
            
            if 'status' in status_result:
                current_status = status_result['status']
                
                self.publish_to_mqtt('frigate/kiln/status/current', {
                    'status': current_status,
                    'timestamp': status_result['timestamp'],
                    'confidence': status_result['confidence']
                })
                
                self.last_status = current_status
        
        # Process error zone
        if error_img is not None:
            error_result = self.process_zone_image(error_img, 'error_display')
            
            if 'error_code' in error_result:
                current_error = error_result['error_code']
                
                self.publish_to_mqtt('frigate/kiln/errors/current', {
                    'error_code': current_error,
                    'timestamp': error_result['timestamp'],
                    'confidence': error_result['confidence'],
                    'severity': 'high'
                })
                
                self.last_error = current_error

    def calculate_firing_duration(self) -> Optional[int]:
        """Calculate firing duration in minutes"""
        if self.firing_start_time:
            duration = datetime.now() - self.firing_start_time
            return int(duration.total_seconds() / 60)
        return None

# Example usage for testing
if __name__ == "__main__":
    processor = KilnOCRProcessor()
    
    # Test with sample images (would be provided by Frigate)
    logger.info("OCR Processor initialized and ready")
    
    # Keep running
    try:
        while True:
            time.sleep(10)  # Process every 10 seconds
            
            # In real implementation, this would receive images from Frigate
            # via HTTP API or file system monitoring
            
    except KeyboardInterrupt:
        logger.info("Shutting down OCR processor")
        processor.mqtt_client.loop_stop()
        processor.mqtt_client.disconnect() 