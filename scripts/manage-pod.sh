#!/bin/bash

# Configuration
POD_NAME="motioneye-pod"
MOTIONEYE_IMAGE="motioneye:latest"
PROMETHEUS_IMAGE="prometheus:latest"
MOTIONEYE_PORT=8765
PROMETHEUS_PORT=9090

# Function to create and start the pod
create_pod() {
    echo "Creating pod $POD_NAME..."
    podman pod create --name $POD_NAME -p $MOTIONEYE_PORT:8765 -p $PROMETHEUS_PORT:9090

    echo "Starting MotionEye container..."
    podman run -d --pod $POD_NAME \
        --name motioneye \
        -v ./config:/etc/motioneye \
        -v ./data:/var/lib/motioneye \
        $MOTIONEYE_IMAGE

    echo "Starting Prometheus container..."
    podman run -d --pod $POD_NAME \
        --name prometheus \
        -v ./config/prometheus.yml:/etc/prometheus/prometheus.yml \
        -v ./data/prometheus:/var/lib/prometheus \
        $PROMETHEUS_IMAGE
}

# Function to stop and remove the pod
remove_pod() {
    echo "Stopping pod $POD_NAME..."
    podman pod stop $POD_NAME
    podman pod rm $POD_NAME
}

# Function to show pod status
status_pod() {
    echo "Pod status:"
    podman pod ps --filter name=$POD_NAME
    echo -e "\nContainer status:"
    podman ps --filter pod=$POD_NAME
}

# Main script
case "$1" in
    "start")
        create_pod
        ;;
    "stop")
        remove_pod
        ;;
    "status")
        status_pod
        ;;
    *)
        echo "Usage: $0 {start|stop|status}"
        exit 1
        ;;
esac 