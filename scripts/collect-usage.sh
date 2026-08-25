#!/bin/bash

################################################################################
# Usage Data Collector
# Purpose: Collect system and GPU metrics every 5 minutes
# Author: System Monitor
# Date: 2026-08-25
################################################################################

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BASE_DIR="$(dirname "$SCRIPT_DIR")"
DATA_DIR="$BASE_DIR/data/usage"
LOG_DIR="$BASE_DIR/logs"

# Ensure directories exist
mkdir -p "$DATA_DIR" "$LOG_DIR"

# Timestamps
DATE_STAMP=$(date '+%Y-%m-%d')
TIMESTAMP=$(date -Iseconds)  # ISO 8601 format with timezone

# File paths
SYSTEM_CSV="$DATA_DIR/system-$DATE_STAMP.csv"
GPU_CSV="$DATA_DIR/gpu-$DATE_STAMP.csv"
LOG_FILE="$LOG_DIR/collector.log"

# Log function
log_message() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> "$LOG_FILE"
}

################################################################################
# System Metrics Collection
################################################################################

collect_system_metrics() {
    # Hostname
    HOSTNAME=$(hostname)

    # CPU usage percentage (100 - idle%)
    CPU_PERCENT=$(top -bn1 | grep "Cpu(s)" | sed "s/.*, *\([0-9.]*\)%* id.*/\1/" | awk '{printf "%.1f", 100 - $1}')

    # RAM usage percentage
    RAM_PERCENT=$(free | grep Mem | awk '{printf "%.1f", ($3/$2) * 100}')

    # Load averages
    LOAD_1M=$(uptime | awk -F'load average:' '{print $2}' | awk '{print $1}' | tr -d ',')
    LOAD_5M=$(uptime | awk -F'load average:' '{print $2}' | awk '{print $2}' | tr -d ',')
    LOAD_15M=$(uptime | awk -F'load average:' '{print $2}' | awk '{print $3}' | tr -d ',')

    # Disk usage for / and /home
    DISK_ROOT=$(df -h / | tail -1 | awk '{print $5}' | tr -d '%')
    DISK_HOME=$(df -h /home 2>/dev/null | tail -1 | awk '{print $5}' | tr -d '%' || echo "N/A")

    # Logged-in users (semicolon separated, unique)
    LOGGED_USERS=$(who | awk '{print $1}' | sort -u | tr '\n' ';' | sed 's/;$//')

    # Create CSV header if file doesn't exist
    if [ ! -f "$SYSTEM_CSV" ]; then
        echo "timestamp,hostname,cpu_percent,ram_percent,load_1m,load_5m,load_15m,disk_root_percent,disk_home_percent,logged_users" > "$SYSTEM_CSV"
    fi

    # Prepare data line
    DATA_LINE="$TIMESTAMP,$HOSTNAME,$CPU_PERCENT,$RAM_PERCENT,$LOAD_1M,$LOAD_5M,$LOAD_15M,$DISK_ROOT,$DISK_HOME,$LOGGED_USERS"

    # Atomic write (write to temp file, then move)
    TEMP_FILE="$SYSTEM_CSV.tmp.$$"
    echo "$DATA_LINE" >> "$TEMP_FILE"
    cat "$TEMP_FILE" >> "$SYSTEM_CSV"
    rm -f "$TEMP_FILE"

    log_message "System metrics collected: CPU=$CPU_PERCENT% RAM=$RAM_PERCENT%"
}

################################################################################
# GPU Metrics Collection
################################################################################

collect_gpu_metrics() {
    # Check if nvidia-smi exists
    if ! command -v nvidia-smi &> /dev/null; then
        log_message "nvidia-smi not found, skipping GPU metrics"
        return
    fi

    # Check if GPUs are available
    GPU_COUNT=$(nvidia-smi --query-gpu=count --format=csv,noheader 2>/dev/null | head -1)
    if [ -z "$GPU_COUNT" ] || [ "$GPU_COUNT" -eq 0 ]; then
        log_message "No GPUs detected, skipping GPU metrics"
        return
    fi

    # Create CSV header if file doesn't exist
    if [ ! -f "$GPU_CSV" ]; then
        echo "timestamp,hostname,gpu_id,gpu_name,gpu_util_percent,vram_used_mb,vram_total_mb,temp_c,processes" > "$GPU_CSV"
    fi

    HOSTNAME=$(hostname)

    # Query GPU count to iterate
    for GPU_ID in $(nvidia-smi --query-gpu=index --format=csv,noheader 2>/dev/null); do
        # Query each metric separately to avoid parsing issues with spaces in GPU name
        GPU_NAME=$(nvidia-smi --query-gpu=name --format=csv,noheader --id=$GPU_ID 2>/dev/null | tr -d ',')
        GPU_UTIL=$(nvidia-smi --query-gpu=utilization.gpu --format=csv,noheader,nounits --id=$GPU_ID 2>/dev/null | tr -d ' ')
        VRAM_USED=$(nvidia-smi --query-gpu=memory.used --format=csv,noheader,nounits --id=$GPU_ID 2>/dev/null | tr -d ' ')
        VRAM_TOTAL=$(nvidia-smi --query-gpu=memory.total --format=csv,noheader,nounits --id=$GPU_ID 2>/dev/null | tr -d ' ')
        TEMP=$(nvidia-smi --query-gpu=temperature.gpu --format=csv,noheader,nounits --id=$GPU_ID 2>/dev/null | tr -d ' ')

        # Get processes running on this GPU
        GPU_PROCESSES=$(nvidia-smi --query-compute-apps=pid --format=csv,noheader --id=$GPU_ID 2>/dev/null | while read PID; do
            if [ -n "$PID" ]; then
                # Get username and command
                USER=$(ps -o user= -p $PID 2>/dev/null || echo "unknown")
                CMD=$(ps -o comm= -p $PID 2>/dev/null || echo "unknown")
                echo "$USER:$CMD"
            fi
        done | tr '\n' ';' | sed 's/;$//')

        # If no processes, set to idle
        [ -z "$GPU_PROCESSES" ] && GPU_PROCESSES="idle"

        # Prepare data line (GPU_NAME may contain spaces, so quote it)
        DATA_LINE="$TIMESTAMP,$HOSTNAME,$GPU_ID,\"$GPU_NAME\",$GPU_UTIL,$VRAM_USED,$VRAM_TOTAL,$TEMP,$GPU_PROCESSES"

        # Atomic write
        TEMP_FILE="$GPU_CSV.tmp.$$"
        echo "$DATA_LINE" >> "$TEMP_FILE"
        cat "$TEMP_FILE" >> "$GPU_CSV"
        rm -f "$TEMP_FILE"

        log_message "GPU $GPU_ID metrics collected: Util=$GPU_UTIL% VRAM=$VRAM_USED/$VRAM_TOTAL MB Temp=$TEMP°C"
    done
}

################################################################################
# Main Execution
################################################################################

main() {
    log_message "Starting usage data collection"

    # Collect system metrics
    collect_system_metrics

    # Collect GPU metrics (if available)
    collect_gpu_metrics

    log_message "Collection completed successfully"
}

# Execute
main
