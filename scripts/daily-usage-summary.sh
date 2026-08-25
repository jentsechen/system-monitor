#!/bin/bash

################################################################################
# Daily Usage Summary Generator
# Purpose: Generate daily usage summary from collected metrics
# Author: System Monitor
# Date: 2026-08-25
################################################################################

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BASE_DIR="$(dirname "$SCRIPT_DIR")"
DATA_DIR="$BASE_DIR/data/usage"
REPORT_DIR="$BASE_DIR/reports/usage"
LOG_DIR="$BASE_DIR/logs"

# Thresholds (configurable)
DISK_WARNING_THRESHOLD=80
IDLE_GPU_THRESHOLD=10
HIGH_GPU_ACTIVE_HOURS=20
DATA_RETENTION_DAYS=90

# Ensure directories exist
mkdir -p "$REPORT_DIR" "$LOG_DIR"

# Date for yesterday's data
YESTERDAY=$(date -d 'yesterday' '+%Y-%m-%d' 2>/dev/null || date -v -1d '+%Y-%m-%d')
TODAY=$(date '+%Y-%m-%d')

# File paths
SYSTEM_CSV="$DATA_DIR/system-$YESTERDAY.csv"
GPU_CSV="$DATA_DIR/gpu-$YESTERDAY.csv"
REPORT_FILE="$REPORT_DIR/usage-summary-$YESTERDAY.txt"
LOG_FILE="$LOG_DIR/summary.log"

# Log function
log_message() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> "$LOG_FILE"
}

################################################################################
# Data Analysis Functions
################################################################################

analyze_system_metrics() {
    if [ ! -f "$SYSTEM_CSV" ]; then
        log_message "Warning: System CSV not found: $SYSTEM_CSV"
        echo "No system data available"
        return
    fi

    # Skip header and calculate averages and peaks
    awk -F',' 'NR>1 {
        cpu_sum += $3; cpu_count++; if($3 > cpu_max) cpu_max = $3;
        ram_sum += $4; ram_count++; if($4 > ram_max) ram_max = $4;
        disk_root = $8; disk_home = $9;
        users[$10] = 1;
    }
    END {
        printf "CPU_AVG=%.0f\n", cpu_sum/cpu_count;
        printf "CPU_PEAK=%.0f\n", cpu_max;
        printf "RAM_AVG=%.0f\n", ram_sum/ram_count;
        printf "RAM_PEAK=%.0f\n", ram_max;
        printf "DISK_ROOT=%s\n", disk_root;
        printf "DISK_HOME=%s\n", disk_home;

        # Extract unique users
        user_list = "";
        for (u in users) {
            split(u, user_arr, ";");
            for (i in user_arr) {
                if (user_arr[i] != "" && !seen[user_arr[i]]++) {
                    if (user_list == "") user_list = user_arr[i];
                    else user_list = user_list ", " user_arr[i];
                }
            }
        }
        printf "USERS=\"%s\"\n", user_list;
    }' "$SYSTEM_CSV"
}

analyze_gpu_metrics() {
    if [ ! -f "$GPU_CSV" ]; then
        log_message "No GPU data found: $GPU_CSV"
        echo ""
        return
    fi

    # Analyze each GPU
    awk -F',' 'NR>1 {
        gpu_id = $3;
        gpu_name = $4;
        gpu_util = $5;
        vram_used = $6;
        vram_total = $7;

        gpu_names[gpu_id] = gpu_name;
        gpu_util_sum[gpu_id] += gpu_util;
        gpu_util_count[gpu_id]++;
        if (gpu_util > gpu_util_max[gpu_id]) gpu_util_max[gpu_id] = gpu_util;
        if (vram_used > vram_max[gpu_id]) vram_max[gpu_id] = vram_used;

        vram_totals[gpu_id] = vram_total;

        # Count active hours (util > 5%)
        if (gpu_util > 5) gpu_active_count[gpu_id]++;
    }
    END {
        for (id in gpu_names) {
            avg_util = gpu_util_sum[id] / gpu_util_count[id];
            peak_util = gpu_util_max[id];
            active_hours = (gpu_active_count[id] * 5) / 60;  # 5-min intervals to hours
            peak_vram = vram_max[id];
            total_vram = vram_totals[id];

            printf "GPU_%d_NAME=%s\n", id, gpu_names[id];
            printf "GPU_%d_AVG=%.0f\n", id, avg_util;
            printf "GPU_%d_PEAK=%.0f\n", id, peak_util;
            printf "GPU_%d_ACTIVE_HOURS=%.1f\n", id, active_hours;
            printf "GPU_%d_VRAM_PEAK=%d\n", id, peak_vram;
            printf "GPU_%d_VRAM_TOTAL=%d\n", id, total_vram;
        }
    }' "$GPU_CSV"
}

################################################################################
# Report Generation Functions (separate for Discord integration later)
################################################################################

generate_report_text() {
    local cpu_avg=$1
    local cpu_peak=$2
    local ram_avg=$3
    local ram_peak=$4
    local disk_root=$5
    local disk_home=$6
    local users=$7
    shift 7
    local gpu_data=("$@")

    # Header
    cat << EOF
================================================================================
                    SERVER DAILY USAGE — $YESTERDAY
================================================================================

[SYSTEM METRICS]
--------------------------------------------------------------------------------
CPU:    avg ${cpu_avg}% | peak ${cpu_peak}%
RAM:    avg ${ram_avg}% | peak ${ram_peak}%

EOF

    # GPU metrics (if available)
    if [ ${#gpu_data[@]} -gt 0 ]; then
        echo "[GPU METRICS]"
        echo "--------------------------------------------------------------------------------"

        local i=0
        while [ $i -lt ${#gpu_data[@]} ]; do
            local gpu_id=${gpu_data[$i]}
            local gpu_avg=${gpu_data[$i+1]}
            local gpu_peak=${gpu_data[$i+2]}
            local gpu_hours=${gpu_data[$i+3]}
            local gpu_vram_peak=${gpu_data[$i+4]}
            local gpu_vram_total=${gpu_data[$i+5]}

            printf "GPU %d:  avg %3s%% | peak %3s%% | active %sh | VRAM %s/%s MB\n" \
                "$gpu_id" "$gpu_avg" "$gpu_peak" "$gpu_hours" "$gpu_vram_peak" "$gpu_vram_total"

            i=$((i + 6))
        done
        echo ""
    fi

    # Disk and users
    cat << EOF
[STORAGE & USERS]
--------------------------------------------------------------------------------
Disk:   / ${disk_root}% | /home ${disk_home}%
Users:  ${users}

EOF

    # Warnings
    echo "[WARNINGS]"
    echo "--------------------------------------------------------------------------------"

    local has_warnings=0

    # Check disk usage
    if [ "$disk_root" != "N/A" ] && [ "$disk_root" -gt "$DISK_WARNING_THRESHOLD" ]; then
        echo "⚠ Root disk usage high: ${disk_root}%"
        has_warnings=1
    fi
    if [ "$disk_home" != "N/A" ] && [ "$disk_home" -gt "$DISK_WARNING_THRESHOLD" ]; then
        echo "⚠ Home disk usage high: ${disk_home}%"
        has_warnings=1
    fi

    # Check CPU usage
    if [ "$cpu_avg" -gt 80 ]; then
        echo "⚠ High average CPU usage: ${cpu_avg}%"
        has_warnings=1
    fi

    # Check RAM usage
    if [ "$ram_avg" -gt 80 ]; then
        echo "⚠ High average RAM usage: ${ram_avg}%"
        has_warnings=1
    fi

    # Check GPU warnings
    if [ ${#gpu_data[@]} -gt 0 ]; then
        local i=0
        while [ $i -lt ${#gpu_data[@]} ]; do
            local gpu_id=${gpu_data[$i]}
            local gpu_avg=${gpu_data[$i+1]}
            local gpu_hours=${gpu_data[$i+3]}

            # Idle GPU warning
            if [ "$gpu_avg" -lt "$IDLE_GPU_THRESHOLD" ]; then
                echo "⚠ GPU $gpu_id was mostly idle (avg ${gpu_avg}%)"
                has_warnings=1
            fi

            # Heavy usage warning
            if (( $(echo "$gpu_hours > $HIGH_GPU_ACTIVE_HOURS" | bc -l 2>/dev/null || echo 0) )); then
                echo "⚠ GPU $gpu_id was heavily utilized for ${gpu_hours}h"
                has_warnings=1
            fi

            i=$((i + 6))
        done
    fi

    if [ $has_warnings -eq 0 ]; then
        echo "✓ No warnings detected"
    fi

    echo ""

    # Footer
    cat << EOF
================================================================================
Report generated: $(date '+%Y-%m-%d %H:%M:%S')
Data source: $YESTERDAY
Next report: $TODAY
================================================================================
EOF
}

################################################################################
# Main Execution
################################################################################

main() {
    log_message "Starting daily usage summary generation for $YESTERDAY"

    # Analyze system metrics
    eval "$(analyze_system_metrics)"

    # Analyze GPU metrics
    GPU_STATS=()
    if [ -f "$GPU_CSV" ]; then
        eval "$(analyze_gpu_metrics)"

        # Build GPU data array
        for gpu_var in $(set | grep '^GPU_[0-9]*_AVG=' | cut -d= -f1); do
            gpu_id=$(echo "$gpu_var" | sed 's/GPU_\([0-9]*\)_AVG/\1/')

            eval "gpu_avg=\$GPU_${gpu_id}_AVG"
            eval "gpu_peak=\$GPU_${gpu_id}_PEAK"
            eval "gpu_hours=\$GPU_${gpu_id}_ACTIVE_HOURS"
            eval "gpu_vram_peak=\$GPU_${gpu_id}_VRAM_PEAK"
            eval "gpu_vram_total=\$GPU_${gpu_id}_VRAM_TOTAL"

            GPU_STATS+=("$gpu_id" "$gpu_avg" "$gpu_peak" "$gpu_hours" "$gpu_vram_peak" "$gpu_vram_total")
        done
    fi

    # Generate report
    generate_report_text \
        "${CPU_AVG:-N/A}" "${CPU_PEAK:-N/A}" \
        "${RAM_AVG:-N/A}" "${RAM_PEAK:-N/A}" \
        "${DISK_ROOT:-N/A}" "${DISK_HOME:-N/A}" \
        "${USERS:-none}" \
        "${GPU_STATS[@]}" \
        > "$REPORT_FILE"

    log_message "Summary generated: $REPORT_FILE"

    # Clean up old data files (older than retention days)
    find "$DATA_DIR" -name "system-*.csv" -mtime +$DATA_RETENTION_DAYS -delete 2>/dev/null
    find "$DATA_DIR" -name "gpu-*.csv" -mtime +$DATA_RETENTION_DAYS -delete 2>/dev/null
    find "$REPORT_DIR" -name "usage-summary-*.txt" -mtime +$DATA_RETENTION_DAYS -delete 2>/dev/null

    log_message "Cleaned up files older than $DATA_RETENTION_DAYS days"

    # Display report if --show flag is provided
    if [ "$1" = "--show" ]; then
        cat "$REPORT_FILE"
    fi

    echo "Summary report generated: $REPORT_FILE"
}

# Execute
main "$@"
