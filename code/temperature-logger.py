#!/usr/bin/env python3
"""
Temperature Data Logger for Kiln Monitoring
Logs temperature readings to structured files for historical analysis and backup
"""

import json
import os
import time
import logging
from datetime import datetime, timedelta
from typing import Dict, List, Optional
import paho.mqtt.client as mqtt
from pathlib import Path
import sqlite3
import threading
from collections import deque

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)

class TemperatureLogger:
    def __init__(self, data_path: str = '/data', mqtt_host: str = 'localhost'):
        """Initialize temperature logger"""
        self.data_path = Path(data_path)
        self.temp_history_path = self.data_path / 'temperature-history'
        self.firing_logs_path = self.data_path / 'firing-logs'
        self.statistics_path = self.data_path / 'statistics'
        
        # Create directories
        for path in [self.temp_history_path, self.firing_logs_path, self.statistics_path]:
            path.mkdir(parents=True, exist_ok=True)
        
        # Initialize database
        self.db_path = self.data_path / 'kiln_monitoring.db'
        self.init_database()
        
        # MQTT setup
        self.mqtt_client = mqtt.Client()
        self.mqtt_client.on_connect = self.on_mqtt_connect
        self.mqtt_client.on_message = self.on_mqtt_message
        
        try:
            self.mqtt_client.connect(mqtt_host, 1883, 60)
            self.mqtt_client.loop_start()
        except Exception as e:
            logger.error(f"Failed to connect to MQTT: {e}")
        
        # In-memory data for aggregation
        self.recent_temperatures = deque(maxlen=1440)  # 24 hours at 1-minute intervals
        self.current_firing = None
        self.firing_start_temp = None
        
        # Background tasks
        self.aggregation_thread = threading.Thread(target=self.run_aggregation_tasks, daemon=True)
        self.aggregation_thread.start()

    def init_database(self):
        """Initialize SQLite database for temperature data"""
        try:
            with sqlite3.connect(self.db_path) as conn:
                cursor = conn.cursor()
                
                # Temperature readings table
                cursor.execute('''
                    CREATE TABLE IF NOT EXISTS temperature_readings (
                        id INTEGER PRIMARY KEY AUTOINCREMENT,
                        timestamp DATETIME NOT NULL,
                        temperature REAL NOT NULL,
                        confidence INTEGER,
                        firing_id INTEGER,
                        raw_ocr_text TEXT,
                        INDEX(timestamp),
                        INDEX(firing_id)
                    )
                ''')
                
                # Firing sessions table
                cursor.execute('''
                    CREATE TABLE IF NOT EXISTS firing_sessions (
                        id INTEGER PRIMARY KEY AUTOINCREMENT,
                        start_time DATETIME NOT NULL,
                        end_time DATETIME,
                        start_temperature REAL,
                        max_temperature REAL,
                        end_temperature REAL,
                        duration_minutes INTEGER,
                        status TEXT,
                        notes TEXT
                    )
                ''')
                
                # Hourly temperature aggregates
                cursor.execute('''
                    CREATE TABLE IF NOT EXISTS temperature_hourly (
                        hour_timestamp DATETIME PRIMARY KEY,
                        min_temp REAL,
                        max_temp REAL,
                        avg_temp REAL,
                        reading_count INTEGER,
                        firing_id INTEGER
                    )
                ''')
                
                # Daily temperature aggregates
                cursor.execute('''
                    CREATE TABLE IF NOT EXISTS temperature_daily (
                        date DATE PRIMARY KEY,
                        min_temp REAL,
                        max_temp REAL,
                        avg_temp REAL,
                        max_firing_temp REAL,
                        total_firing_minutes INTEGER,
                        firing_count INTEGER
                    )
                ''')
                
                conn.commit()
                logger.info("Database initialized successfully")
                
        except Exception as e:
            logger.error(f"Database initialization failed: {e}")

    def on_mqtt_connect(self, client, userdata, flags, rc):
        """Callback for MQTT connection"""
        if rc == 0:
            logger.info("Connected to MQTT broker")
            client.subscribe("frigate/kiln/temperature/current")
            client.subscribe("frigate/kiln/status/firing")
        else:
            logger.error(f"Failed to connect to MQTT: {rc}")

    def on_mqtt_message(self, client, userdata, msg):
        """Process incoming MQTT temperature messages"""
        try:
            topic = msg.topic
            payload = json.loads(msg.payload.decode())
            
            if topic == "frigate/kiln/temperature/current":
                self.log_temperature_reading(payload)
            elif topic == "frigate/kiln/status/firing":
                self.handle_firing_status(payload)
                
        except Exception as e:
            logger.error(f"Error processing MQTT message: {e}")

    def log_temperature_reading(self, data: Dict):
        """Log a single temperature reading"""
        try:
            timestamp = datetime.now()
            temperature = data.get('temperature')
            confidence = data.get('confidence', 0)
            
            if temperature is None:
                return
            
            # Add to recent temperatures for aggregation
            temp_record = {
                'timestamp': timestamp,
                'temperature': temperature,
                'confidence': confidence
            }
            self.recent_temperatures.append(temp_record)
            
            # Store in database
            with sqlite3.connect(self.db_path) as conn:
                cursor = conn.cursor()
                cursor.execute('''
                    INSERT INTO temperature_readings 
                    (timestamp, temperature, confidence, firing_id, raw_ocr_text) 
                    VALUES (?, ?, ?, ?, ?)
                ''', (
                    timestamp,
                    temperature,
                    confidence,
                    self.current_firing,
                    data.get('raw_text', '')
                ))
                conn.commit()
            
            # Store daily JSON file for easy backup/analysis
            self.store_daily_json(timestamp, temp_record)
            
            logger.debug(f"Logged temperature: {temperature}°F (confidence: {confidence}%)")
            
        except Exception as e:
            logger.error(f"Failed to log temperature reading: {e}")

    def store_daily_json(self, timestamp: datetime, record: Dict):
        """Store temperature reading in daily JSON file"""
        try:
            date_str = timestamp.strftime('%Y-%m-%d')
            json_file = self.temp_history_path / f"temperatures_{date_str}.json"
            
            # Load existing data or create new
            if json_file.exists():
                with open(json_file, 'r') as f:
                    daily_data = json.load(f)
            else:
                daily_data = {
                    'date': date_str,
                    'readings': []
                }
            
            # Add new reading
            daily_data['readings'].append({
                'timestamp': timestamp.isoformat(),
                'temperature': record['temperature'],
                'confidence': record['confidence']
            })
            
            # Write back to file
            with open(json_file, 'w') as f:
                json.dump(daily_data, f, indent=2)
                
        except Exception as e:
            logger.error(f"Failed to store daily JSON: {e}")

    def handle_firing_status(self, data: Dict):
        """Handle firing start/stop events"""
        try:
            firing = data.get('firing', False)
            
            if firing and self.current_firing is None:
                # Start new firing session
                self.start_firing_session(data)
            elif not firing and self.current_firing is not None:
                # End current firing session
                self.end_firing_session(data)
                
        except Exception as e:
            logger.error(f"Failed to handle firing status: {e}")

    def start_firing_session(self, data: Dict):
        """Start a new firing session"""
        try:
            start_time = datetime.now()
            
            # Get current temperature as start temperature
            if self.recent_temperatures:
                self.firing_start_temp = self.recent_temperatures[-1]['temperature']
            else:
                self.firing_start_temp = None
            
            with sqlite3.connect(self.db_path) as conn:
                cursor = conn.cursor()
                cursor.execute('''
                    INSERT INTO firing_sessions 
                    (start_time, start_temperature, status) 
                    VALUES (?, ?, ?)
                ''', (start_time, self.firing_start_temp, 'active'))
                
                self.current_firing = cursor.lastrowid
                conn.commit()
            
            logger.info(f"Started firing session {self.current_firing} at {start_time}")
            
        except Exception as e:
            logger.error(f"Failed to start firing session: {e}")

    def end_firing_session(self, data: Dict):
        """End the current firing session"""
        try:
            if self.current_firing is None:
                return
            
            end_time = datetime.now()
            
            # Calculate session statistics
            with sqlite3.connect(self.db_path) as conn:
                cursor = conn.cursor()
                
                # Get session start time
                cursor.execute('''
                    SELECT start_time, start_temperature FROM firing_sessions 
                    WHERE id = ?
                ''', (self.current_firing,))
                
                result = cursor.fetchone()
                if result:
                    start_time_str, start_temp = result
                    start_time = datetime.fromisoformat(start_time_str)
                    duration_minutes = int((end_time - start_time).total_seconds() / 60)
                    
                    # Get max temperature during this session
                    cursor.execute('''
                        SELECT MAX(temperature), MIN(temperature) FROM temperature_readings 
                        WHERE firing_id = ?
                    ''', (self.current_firing,))
                    
                    temp_stats = cursor.fetchone()
                    max_temp = temp_stats[0] if temp_stats[0] else None
                    
                    # Get end temperature
                    end_temp = None
                    if self.recent_temperatures:
                        end_temp = self.recent_temperatures[-1]['temperature']
                    
                    # Update firing session
                    cursor.execute('''
                        UPDATE firing_sessions 
                        SET end_time = ?, max_temperature = ?, end_temperature = ?, 
                            duration_minutes = ?, status = ?
                        WHERE id = ?
                    ''', (end_time, max_temp, end_temp, duration_minutes, 'completed', self.current_firing))
                    
                    conn.commit()
                    
                    # Create firing log file
                    self.create_firing_log(self.current_firing, start_time, end_time, 
                                         start_temp, max_temp, end_temp, duration_minutes)
                    
                    logger.info(f"Completed firing session {self.current_firing}: "
                              f"{duration_minutes} minutes, max temp: {max_temp}°F")
                    
                    self.current_firing = None
            
        except Exception as e:
            logger.error(f"Failed to end firing session: {e}")

    def create_firing_log(self, firing_id: int, start_time: datetime, end_time: datetime,
                         start_temp: float, max_temp: float, end_temp: float, duration: int):
        """Create detailed firing log file"""
        try:
            log_filename = f"firing_{firing_id}_{start_time.strftime('%Y%m%d_%H%M')}.json"
            log_file = self.firing_logs_path / log_filename
            
            # Get all temperature readings for this firing
            with sqlite3.connect(self.db_path) as conn:
                cursor = conn.cursor()
                cursor.execute('''
                    SELECT timestamp, temperature, confidence 
                    FROM temperature_readings 
                    WHERE firing_id = ? 
                    ORDER BY timestamp
                ''', (firing_id,))
                
                readings = []
                for row in cursor.fetchall():
                    readings.append({
                        'timestamp': row[0],
                        'temperature': row[1],
                        'confidence': row[2]
                    })
            
            # Create comprehensive firing log
            firing_log = {
                'firing_id': firing_id,
                'start_time': start_time.isoformat(),
                'end_time': end_time.isoformat(),
                'duration_minutes': duration,
                'temperatures': {
                    'start': start_temp,
                    'max': max_temp,
                    'end': end_temp
                },
                'statistics': {
                    'total_readings': len(readings),
                    'avg_confidence': sum(r['confidence'] for r in readings) / len(readings) if readings else 0
                },
                'readings': readings
            }
            
            with open(log_file, 'w') as f:
                json.dump(firing_log, f, indent=2)
            
            logger.info(f"Created firing log: {log_file}")
            
        except Exception as e:
            logger.error(f"Failed to create firing log: {e}")

    def run_aggregation_tasks(self):
        """Background thread for data aggregation"""
        while True:
            try:
                # Run hourly aggregation
                self.aggregate_hourly_data()
                
                # Run daily aggregation (once per day)
                current_time = datetime.now()
                if current_time.hour == 1 and current_time.minute < 5:  # Run at 1 AM
                    self.aggregate_daily_data()
                
                # Sleep for 5 minutes
                time.sleep(300)
                
            except Exception as e:
                logger.error(f"Error in aggregation tasks: {e}")
                time.sleep(60)  # Wait a minute before retrying

    def aggregate_hourly_data(self):
        """Aggregate temperature data by hour"""
        try:
            current_hour = datetime.now().replace(minute=0, second=0, microsecond=0)
            last_hour = current_hour - timedelta(hours=1)
            
            with sqlite3.connect(self.db_path) as conn:
                cursor = conn.cursor()
                
                # Check if we already have data for this hour
                cursor.execute('''
                    SELECT COUNT(*) FROM temperature_hourly WHERE hour_timestamp = ?
                ''', (last_hour,))
                
                if cursor.fetchone()[0] > 0:
                    return  # Already aggregated
                
                # Aggregate temperature data for the last hour
                cursor.execute('''
                    SELECT MIN(temperature), MAX(temperature), AVG(temperature), 
                           COUNT(*), firing_id
                    FROM temperature_readings 
                    WHERE timestamp >= ? AND timestamp < ?
                    GROUP BY CASE WHEN firing_id IS NOT NULL THEN firing_id ELSE 0 END
                ''', (last_hour, current_hour))
                
                for row in cursor.fetchall():
                    min_temp, max_temp, avg_temp, count, firing_id = row
                    
                    cursor.execute('''
                        INSERT OR REPLACE INTO temperature_hourly 
                        (hour_timestamp, min_temp, max_temp, avg_temp, reading_count, firing_id)
                        VALUES (?, ?, ?, ?, ?, ?)
                    ''', (last_hour, min_temp, max_temp, avg_temp, count, firing_id))
                
                conn.commit()
                logger.debug(f"Aggregated hourly data for {last_hour}")
                
        except Exception as e:
            logger.error(f"Failed to aggregate hourly data: {e}")

    def aggregate_daily_data(self):
        """Aggregate temperature data by day"""
        try:
            yesterday = (datetime.now() - timedelta(days=1)).date()
            
            with sqlite3.connect(self.db_path) as conn:
                cursor = conn.cursor()
                
                # Check if we already have data for this day
                cursor.execute('''
                    SELECT COUNT(*) FROM temperature_daily WHERE date = ?
                ''', (yesterday,))
                
                if cursor.fetchone()[0] > 0:
                    return  # Already aggregated
                
                # Aggregate temperature data for yesterday
                cursor.execute('''
                    SELECT MIN(temperature), MAX(temperature), AVG(temperature)
                    FROM temperature_readings 
                    WHERE DATE(timestamp) = ?
                ''', (yesterday,))
                
                temp_stats = cursor.fetchone()
                
                # Get firing statistics for the day
                cursor.execute('''
                    SELECT MAX(max_temperature), SUM(duration_minutes), COUNT(*)
                    FROM firing_sessions 
                    WHERE DATE(start_time) = ? AND status = 'completed'
                ''', (yesterday,))
                
                firing_stats = cursor.fetchone()
                
                if temp_stats and temp_stats[0] is not None:
                    cursor.execute('''
                        INSERT INTO temperature_daily 
                        (date, min_temp, max_temp, avg_temp, max_firing_temp, 
                         total_firing_minutes, firing_count)
                        VALUES (?, ?, ?, ?, ?, ?, ?)
                    ''', (
                        yesterday,
                        temp_stats[0], temp_stats[1], temp_stats[2],
                        firing_stats[0] if firing_stats else None,
                        firing_stats[1] if firing_stats else 0,
                        firing_stats[2] if firing_stats else 0
                    ))
                    
                    conn.commit()
                    logger.info(f"Aggregated daily data for {yesterday}")
                
        except Exception as e:
            logger.error(f"Failed to aggregate daily data: {e}")

# Main execution
if __name__ == "__main__":
    data_path = os.environ.get('KILN_DATA_PATH', '/data')
    logger.info(f"Starting temperature logger with data path: {data_path}")
    
    try:
        temp_logger = TemperatureLogger(data_path)
        logger.info("Temperature logger started successfully")
        
        # Keep running
        while True:
            time.sleep(60)
            
    except KeyboardInterrupt:
        logger.info("Shutting down temperature logger")
    except Exception as e:
        logger.error(f"Fatal error in temperature logger: {e}")
        exit(1) 