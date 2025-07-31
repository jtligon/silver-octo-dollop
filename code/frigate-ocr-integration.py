#!/usr/bin/env python3
"""
Frigate OCR Integration Script
Monitors Frigate API for zone snapshots and processes them for kiln monitoring
"""

import requests
import cv2
import numpy as np
import time
import logging
from datetime import datetime
from ocr_processor import KilnOCRProcessor
import os
import threading

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)

class FrigateOCRIntegration:
    def __init__(self, frigate_host='localhost', frigate_port=5000):
        """Initialize Frigate integration"""
        self.frigate_base_url = f"http://{frigate_host}:{frigate_port}"
        self.camera_name = "kiln_camera"
        self.ocr_processor = KilnOCRProcessor()
        
        # Zone coordinates (from frigate.yml)
        self.zones = {
            'temperature_display': (100, 100, 300, 200),
            'status_display': (100, 220, 300, 280),
            'error_display': (100, 300, 300, 360)
        }
        
        # Processing intervals
        self.process_interval = 5  # seconds
        self.snapshot_cache = {}
        
        logger.info(f"Initialized Frigate integration at {self.frigate_base_url}")

    def get_camera_snapshot(self) -> np.ndarray:
        """Get latest camera snapshot from Frigate"""
        try:
            url = f"{self.frigate_base_url}/api/{self.camera_name}/latest.jpg"
            response = requests.get(url, timeout=10)
            
            if response.status_code == 200:
                # Convert bytes to numpy array
                nparr = np.frombuffer(response.content, np.uint8)
                image = cv2.imdecode(nparr, cv2.IMREAD_COLOR)
                return image
            else:
                logger.error(f"Failed to get snapshot: HTTP {response.status_code}")
                return None
                
        except Exception as e:
            logger.error(f"Error getting camera snapshot: {e}")
            return None

    def extract_zone_from_image(self, image: np.ndarray, zone_coords: tuple) -> np.ndarray:
        """Extract a specific zone from the full camera image"""
        x1, y1, x2, y2 = zone_coords
        
        # Ensure coordinates are within image bounds
        height, width = image.shape[:2]
        x1 = max(0, min(x1, width))
        x2 = max(0, min(x2, width))
        y1 = max(0, min(y1, height))
        y2 = max(0, min(y2, height))
        
        # Extract zone
        zone_image = image[y1:y2, x1:x2]
        return zone_image

    def save_debug_images(self, full_image: np.ndarray, zone_images: dict):
        """Save debug images for troubleshooting OCR zones"""
        debug_dir = "/var/lib/kiln-monitoring/frigate-media/debug"
        os.makedirs(debug_dir, exist_ok=True)
        
        timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
        
        # Save full image with zone overlays
        debug_full = full_image.copy()
        for zone_name, coords in self.zones.items():
            x1, y1, x2, y2 = coords
            cv2.rectangle(debug_full, (x1, y1), (x2, y2), (0, 255, 0), 2)
            cv2.putText(debug_full, zone_name, (x1, y1-10), 
                       cv2.FONT_HERSHEY_SIMPLEX, 0.7, (0, 255, 0), 2)
        
        cv2.imwrite(f"{debug_dir}/full_with_zones_{timestamp}.jpg", debug_full)
        
        # Save individual zone images
        for zone_name, zone_img in zone_images.items():
            if zone_img is not None:
                cv2.imwrite(f"{debug_dir}/{zone_name}_{timestamp}.jpg", zone_img)

    def process_snapshot(self):
        """Process a single snapshot for OCR"""
        try:
            # Get latest snapshot
            full_image = self.get_camera_snapshot()
            if full_image is None:
                return
            
            # Extract zones
            zone_images = {}
            for zone_name, coords in self.zones.items():
                zone_img = self.extract_zone_from_image(full_image, coords)
                zone_images[zone_name] = zone_img
            
            # Save debug images periodically
            if int(time.time()) % 60 == 0:  # Every minute
                self.save_debug_images(full_image, zone_images)
            
            # Process with OCR
            self.ocr_processor.process_and_publish(
                temperature_img=zone_images.get('temperature_display'),
                status_img=zone_images.get('status_display'),
                error_img=zone_images.get('error_display')
            )
            
            logger.debug("Processed snapshot for OCR")
            
        except Exception as e:
            logger.error(f"Error processing snapshot: {e}")

    def check_frigate_health(self) -> bool:
        """Check if Frigate is running and accessible"""
        try:
            url = f"{self.frigate_base_url}/api/stats"
            response = requests.get(url, timeout=5)
            return response.status_code == 200
        except:
            return False

    def run_continuous_monitoring(self):
        """Run continuous OCR monitoring"""
        logger.info("Starting continuous OCR monitoring")
        
        while True:
            try:
                # Check Frigate health
                if not self.check_frigate_health():
                    logger.warning("Frigate not accessible, waiting...")
                    time.sleep(30)
                    continue
                
                # Process snapshot
                self.process_snapshot()
                
                # Wait for next cycle
                time.sleep(self.process_interval)
                
            except KeyboardInterrupt:
                logger.info("Stopping OCR monitoring")
                break
            except Exception as e:
                logger.error(f"Error in monitoring loop: {e}")
                time.sleep(10)  # Wait before retrying

    def calibrate_zones(self):
        """Interactive zone calibration helper"""
        logger.info("Starting zone calibration mode")
        
        # Get a snapshot for calibration
        image = self.get_camera_snapshot()
        if image is None:
            logger.error("Could not get snapshot for calibration")
            return
        
        # Save calibration image
        cv2.imwrite("/var/lib/kiln-monitoring/frigate-media/calibration_image.jpg", image)
        
        print("\nZone Calibration Mode")
        print("="*50)
        print(f"Calibration image saved to: /var/lib/kiln-monitoring/frigate-media/calibration_image.jpg")
        print(f"Current zones:")
        
        for zone_name, coords in self.zones.items():
            print(f"  {zone_name}: {coords}")
            
            # Extract and save zone
            zone_img = self.extract_zone_from_image(image, coords)
            zone_path = f"/var/lib/kiln-monitoring/frigate-media/zone_{zone_name}.jpg"
            cv2.imwrite(zone_path, zone_img)
            print(f"    Zone image: {zone_path}")
        
        print("\nInstructions:")
        print("1. View the calibration images")
        print("2. Adjust zone coordinates in frigate.yml if needed")
        print("3. Restart this script to use new coordinates")

# Main execution
if __name__ == "__main__":
    import argparse
    
    parser = argparse.ArgumentParser(description='Frigate OCR Integration')
    parser.add_argument('--calibrate', action='store_true', 
                       help='Run zone calibration mode')
    parser.add_argument('--frigate-host', default='localhost',
                       help='Frigate host (default: localhost)')
    parser.add_argument('--frigate-port', type=int, default=5000,
                       help='Frigate port (default: 5000)')
    
    args = parser.parse_args()
    
    # Initialize integration
    integration = FrigateOCRIntegration(
        frigate_host=args.frigate_host,
        frigate_port=args.frigate_port
    )
    
    if args.calibrate:
        # Run calibration mode
        integration.calibrate_zones()
    else:
        # Run continuous monitoring
        try:
            integration.run_continuous_monitoring()
        except KeyboardInterrupt:
            logger.info("Shutting down Frigate OCR integration")
        except Exception as e:
            logger.error(f"Fatal error: {e}")
            exit(1) 