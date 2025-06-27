#!/bin/bash
# Performance Testing Script for Kiln Monitoring System
# Tests system performance under continuous monitoring load

set -e

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] $1${NC}"
}

warn() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] WARNING: $1${NC}"
}

error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ERROR: $1${NC}"
}

# Configuration
TEST_DURATION=${1:-300}  # Default 5 minutes
MQTT_HOST="localhost"
MQTT_PORT="1883"
FRIGATE_HOST="localhost"
FRIGATE_PORT="5000"

log "🚀 Starting performance testing for Kiln Monitoring System"
log "Test duration: ${TEST_DURATION} seconds"

# Create performance test directory
TEST_DIR="/tmp/kiln-performance-test-$(date +%s)"
mkdir -p "$TEST_DIR"

# Function to get system metrics
get_system_metrics() {
    local timestamp=$(date +%s)
    local cpu_usage=$(top -bn1 | grep "Cpu(s)" | awk '{print $2}' | sed 's/%us,//')
    local memory_usage=$(free | awk 'NR==2{printf "%.1f", $3*100/$2}')
    local disk_io=$(iostat -d 1 1 | tail -n +4 | awk '{sum += $4} END {print sum}')
    local load_avg=$(uptime | awk -F'load average:' '{print $2}' | awk '{print $1}' | sed 's/,//')
    
    echo "$timestamp,$cpu_usage,$memory_usage,$disk_io,$load_avg" >> "$TEST_DIR/system_metrics.csv"
}

# Function to test MQTT performance
test_mqtt_performance() {
    local duration=$1
    local start_time=$(date +%s)
    local messages_sent=0
    local messages_received=0
    
    log "Testing MQTT performance for $duration seconds..."
    
    # Start MQTT subscriber in background
    mosquitto_sub -h $MQTT_HOST -p $MQTT_PORT -t "performance/test/+" -v > "$TEST_DIR/mqtt_received.log" &
    local sub_pid=$!
    
    # Start MQTT publisher
    while [ $(($(date +%s) - start_time)) -lt $duration ]; do
        local timestamp=$(date +%s.%N)
        mosquitto_pub -h $MQTT_HOST -p $MQTT_PORT -t "performance/test/temperature" -m "{\"temperature\": 1000, \"timestamp\": \"$timestamp\"}" -q 1
        mosquitto_pub -h $MQTT_HOST -p $MQTT_PORT -t "performance/test/status" -m "{\"status\": \"firing\", \"timestamp\": \"$timestamp\"}" -q 1
        ((messages_sent += 2))
        sleep 0.1  # 10 messages per second
    done
    
    # Stop subscriber
    kill $sub_pid 2>/dev/null || true
    sleep 2
    
    # Count received messages
    messages_received=$(wc -l < "$TEST_DIR/mqtt_received.log")
    
    local message_loss_rate=$(echo "scale=2; (($messages_sent - $messages_received) * 100) / $messages_sent" | bc)
    
    echo "MQTT Performance Results:" >> "$TEST_DIR/performance_summary.txt"
    echo "  Messages sent: $messages_sent" >> "$TEST_DIR/performance_summary.txt"
    echo "  Messages received: $messages_received" >> "$TEST_DIR/performance_summary.txt"
    echo "  Message loss rate: ${message_loss_rate}%" >> "$TEST_DIR/performance_summary.txt"
    echo "  Throughput: $(echo "scale=2; $messages_sent / $duration" | bc) msg/s" >> "$TEST_DIR/performance_summary.txt"
    echo "" >> "$TEST_DIR/performance_summary.txt"
}

# Function to test Frigate API performance
test_frigate_performance() {
    local duration=$1
    local start_time=$(date +%s)
    local requests_sent=0
    local successful_requests=0
    local response_times=()
    
    log "Testing Frigate API performance for $duration seconds..."
    
    while [ $(($(date +%s) - start_time)) -lt $duration ]; do
        local request_start=$(date +%s.%N)
        
        if curl -s -f "http://$FRIGATE_HOST:$FRIGATE_PORT/api/stats" >/dev/null; then
            ((successful_requests++))
        fi
        
        local request_end=$(date +%s.%N)
        local response_time=$(echo "$request_end - $request_start" | bc)
        response_times+=($response_time)
        
        ((requests_sent++))
        sleep 1  # 1 request per second
    done
    
    # Calculate average response time
    local total_time=0
    for time in "${response_times[@]}"; do
        total_time=$(echo "$total_time + $time" | bc)
    done
    local avg_response_time=$(echo "scale=3; $total_time / ${#response_times[@]}" | bc)
    
    local success_rate=$(echo "scale=2; ($successful_requests * 100) / $requests_sent" | bc)
    
    echo "Frigate API Performance Results:" >> "$TEST_DIR/performance_summary.txt"
    echo "  Requests sent: $requests_sent" >> "$TEST_DIR/performance_summary.txt"
    echo "  Successful requests: $successful_requests" >> "$TEST_DIR/performance_summary.txt"
    echo "  Success rate: ${success_rate}%" >> "$TEST_DIR/performance_summary.txt"
    echo "  Average response time: ${avg_response_time}s" >> "$TEST_DIR/performance_summary.txt"
    echo "" >> "$TEST_DIR/performance_summary.txt"
}

# Function to monitor container resources
monitor_container_resources() {
    local duration=$1
    local start_time=$(date +%s)
    
    log "Monitoring container resources for $duration seconds..."
    
    # Create header for container metrics
    echo "timestamp,container,cpu_percent,memory_usage,memory_limit,memory_percent" > "$TEST_DIR/container_metrics.csv"
    
    while [ $(($(date +%s) - start_time)) -lt $duration ]; do
        local timestamp=$(date +%s)
        
        # Get container stats if podman is available
        if command -v podman &> /dev/null; then
            podman stats --no-stream --format "{{.Name}},{{.CPUPerc}},{{.MemUsage}},{{.MemPerc}}" 2>/dev/null | while read line; do
                if [[ $line =~ (mosquitto|frigate|kiln-ocr) ]]; then
                    echo "$timestamp,$line" >> "$TEST_DIR/container_metrics.csv"
                fi
            done
        fi
        
        sleep 5
    done
}

# Function to simulate OCR load
simulate_ocr_load() {
    local duration=$1
    local start_time=$(date +%s)
    
    log "Simulating OCR processing load for $duration seconds..."
    
    # Create test images directory
    mkdir -p "$TEST_DIR/test_images"
    
    # Generate test images with text
    local image_count=0
    while [ $(($(date +%s) - start_time)) -lt $duration ]; do
        local temp_value=$((RANDOM % 2000 + 100))
        local image_file="$TEST_DIR/test_images/temp_${image_count}.png"
        
        # Create simple test image with temperature text (requires ImageMagick)
        if command -v convert &> /dev/null; then
            convert -size 300x100 xc:black -fill white -pointsize 48 -annotate +50+60 "${temp_value}°F" "$image_file"
        else
            # Create placeholder file if ImageMagick not available
            echo "Test image ${temp_value}°F" > "$image_file"
        fi
        
        ((image_count++))
        sleep 2
    done
    
    echo "OCR Load Simulation Results:" >> "$TEST_DIR/performance_summary.txt"
    echo "  Test images created: $image_count" >> "$TEST_DIR/performance_summary.txt"
    echo "  Images per minute: $(echo "scale=2; $image_count * 60 / $duration" | bc)" >> "$TEST_DIR/performance_summary.txt"
    echo "" >> "$TEST_DIR/performance_summary.txt"
}

# Function to test disk I/O performance
test_disk_performance() {
    log "Testing disk I/O performance..."
    
    local test_file="$TEST_DIR/disk_test.tmp"
    local write_speed=$(dd if=/dev/zero of="$test_file" bs=1M count=100 2>&1 | grep -o '[0-9.]* MB/s' | tail -1)
    local read_speed=$(dd if="$test_file" of=/dev/null bs=1M 2>&1 | grep -o '[0-9.]* MB/s' | tail -1)
    
    rm -f "$test_file"
    
    echo "Disk I/O Performance Results:" >> "$TEST_DIR/performance_summary.txt"
    echo "  Write speed: $write_speed" >> "$TEST_DIR/performance_summary.txt"
    echo "  Read speed: $read_speed" >> "$TEST_DIR/performance_summary.txt"
    echo "" >> "$TEST_DIR/performance_summary.txt"
}

# Initialize performance summary
echo "Kiln Monitoring System Performance Test" > "$TEST_DIR/performance_summary.txt"
echo "========================================" >> "$TEST_DIR/performance_summary.txt"
echo "Test started: $(date)" >> "$TEST_DIR/performance_summary.txt"
echo "Test duration: $TEST_DURATION seconds" >> "$TEST_DIR/performance_summary.txt"
echo "" >> "$TEST_DIR/performance_summary.txt"

# Initialize system metrics CSV
echo "timestamp,cpu_usage,memory_usage,disk_io,load_avg" > "$TEST_DIR/system_metrics.csv"

# Start system monitoring in background
log "Starting system monitoring..."
(
    local start_time=$(date +%s)
    while [ $(($(date +%s) - start_time)) -lt $TEST_DURATION ]; do
        get_system_metrics
        sleep 5
    done
) &
local monitor_pid=$!

# Start container monitoring in background
monitor_container_resources $TEST_DURATION &
local container_monitor_pid=$!

# Run individual tests
test_disk_performance

# Run tests in parallel
test_mqtt_performance $((TEST_DURATION / 3)) &
test_frigate_performance $((TEST_DURATION / 3)) &
simulate_ocr_load $((TEST_DURATION / 3)) &

# Wait for parallel tests to complete
wait

# Stop monitoring
kill $monitor_pid 2>/dev/null || true
kill $container_monitor_pid 2>/dev/null || true

# Generate final performance report
log "Generating performance report..."

# Calculate system performance statistics
if [ -f "$TEST_DIR/system_metrics.csv" ]; then
    local avg_cpu=$(awk -F',' 'NR>1 {sum+=$2; count++} END {if(count>0) printf "%.1f", sum/count}' "$TEST_DIR/system_metrics.csv")
    local avg_memory=$(awk -F',' 'NR>1 {sum+=$3; count++} END {if(count>0) printf "%.1f", sum/count}' "$TEST_DIR/system_metrics.csv")
    local avg_load=$(awk -F',' 'NR>1 {sum+=$5; count++} END {if(count>0) printf "%.2f", sum/count}' "$TEST_DIR/system_metrics.csv")
    
    echo "System Performance Summary:" >> "$TEST_DIR/performance_summary.txt"
    echo "  Average CPU usage: ${avg_cpu}%" >> "$TEST_DIR/performance_summary.txt"
    echo "  Average memory usage: ${avg_memory}%" >> "$TEST_DIR/performance_summary.txt"
    echo "  Average load: $avg_load" >> "$TEST_DIR/performance_summary.txt"
    echo "" >> "$TEST_DIR/performance_summary.txt"
fi

echo "Test completed: $(date)" >> "$TEST_DIR/performance_summary.txt"

# Display results
log "Performance test completed!"
echo ""
cat "$TEST_DIR/performance_summary.txt"
echo ""
log "Detailed results saved to: $TEST_DIR"
log "System metrics: $TEST_DIR/system_metrics.csv"
log "Container metrics: $TEST_DIR/container_metrics.csv"

# Performance analysis
echo ""
log "Performance Analysis:"

# Check if performance is acceptable
if [ -n "$avg_cpu" ] && [ "$avg_cpu" -lt 80 ]; then
    echo "✅ CPU usage is acceptable (${avg_cpu}%)"
else
    echo "⚠️  CPU usage may be high (${avg_cpu}%)"
fi

if [ -n "$avg_memory" ] && [ "$avg_memory" -lt 85 ]; then
    echo "✅ Memory usage is acceptable (${avg_memory}%)"
else
    echo "⚠️  Memory usage may be high (${avg_memory}%)"
fi

# Cleanup option
echo ""
read -p "Remove test data? (y/N): " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    rm -rf "$TEST_DIR"
    log "Test data cleaned up"
else
    log "Test data preserved at: $TEST_DIR"
fi 