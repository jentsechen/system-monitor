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

# Load environment variables from .env file if it exists
if [ -f "$BASE_DIR/.env" ]; then
    source "$BASE_DIR/.env"
fi

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
PROCESS_CSV="$DATA_DIR/process-$YESTERDAY.csv"
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

analyze_usage_by_period() {
    if [ ! -f "$SYSTEM_CSV" ]; then
        echo "PERIOD_0006_CPU=0"
        echo "PERIOD_0006_GPU=0"
        echo "PERIOD_0612_CPU=0"
        echo "PERIOD_0612_GPU=0"
        echo "PERIOD_1218_CPU=0"
        echo "PERIOD_1218_GPU=0"
        echo "PERIOD_1824_CPU=0"
        echo "PERIOD_1824_GPU=0"
        return
    fi

    # Calculate CPU averages for each 6-hour period
    awk -F',' 'NR>1 {
        # Extract hour from ISO 8601 timestamp
        split($1, dt, "T");
        split(dt[2], tm, ":");
        hour = int(tm[1]);
        cpu = $3;

        if (hour >= 0 && hour < 6) {
            period_0006_cpu_sum += cpu;
            period_0006_count++;
        } else if (hour >= 6 && hour < 12) {
            period_0612_cpu_sum += cpu;
            period_0612_count++;
        } else if (hour >= 12 && hour < 18) {
            period_1218_cpu_sum += cpu;
            period_1218_count++;
        } else {
            period_1824_cpu_sum += cpu;
            period_1824_count++;
        }
    }
    END {
        printf "PERIOD_0006_CPU=%.0f\n", (period_0006_count > 0 ? period_0006_cpu_sum/period_0006_count : 0);
        printf "PERIOD_0612_CPU=%.0f\n", (period_0612_count > 0 ? period_0612_cpu_sum/period_0612_count : 0);
        printf "PERIOD_1218_CPU=%.0f\n", (period_1218_count > 0 ? period_1218_cpu_sum/period_1218_count : 0);
        printf "PERIOD_1824_CPU=%.0f\n", (period_1824_count > 0 ? period_1824_cpu_sum/period_1824_count : 0);
    }' "$SYSTEM_CSV"

    # Calculate GPU averages for each period if GPU data exists
    if [ -f "$GPU_CSV" ]; then
        awk -F',' 'NR>1 {
            # Extract hour from ISO 8601 timestamp
            split($1, dt, "T");
            split(dt[2], tm, ":");
            hour = int(tm[1]);
            gpu_util = $5;

            if (hour >= 0 && hour < 6) {
                period_0006_gpu_sum += gpu_util;
                period_0006_gpu_count++;
            } else if (hour >= 6 && hour < 12) {
                period_0612_gpu_sum += gpu_util;
                period_0612_gpu_count++;
            } else if (hour >= 12 && hour < 18) {
                period_1218_gpu_sum += gpu_util;
                period_1218_gpu_count++;
            } else {
                period_1824_gpu_sum += gpu_util;
                period_1824_gpu_count++;
            }
        }
        END {
            printf "PERIOD_0006_GPU=%.0f\n", (period_0006_gpu_count > 0 ? period_0006_gpu_sum/period_0006_gpu_count : 0);
            printf "PERIOD_0612_GPU=%.0f\n", (period_0612_gpu_count > 0 ? period_0612_gpu_sum/period_0612_gpu_count : 0);
            printf "PERIOD_1218_GPU=%.0f\n", (period_1218_gpu_count > 0 ? period_1218_gpu_sum/period_1218_gpu_count : 0);
            printf "PERIOD_1824_GPU=%.0f\n", (period_1824_gpu_count > 0 ? period_1824_gpu_sum/period_1824_gpu_count : 0);
        }' "$GPU_CSV"
    else
        echo "PERIOD_0006_GPU=0"
        echo "PERIOD_0612_GPU=0"
        echo "PERIOD_1218_GPU=0"
        echo "PERIOD_1824_GPU=0"
    fi
}

analyze_user_usage() {
    if [ ! -f "$SYSTEM_CSV" ]; then
        echo ""
        return
    fi

    # Extract user CPU time from system CSV
    awk -F',' 'NR>1 {
        cpu = $3;
        split($10, user_arr, ";");
        for (i in user_arr) {
            if (user_arr[i] != "") {
                # Each sample is 5 minutes, accumulate CPU-weighted time
                user_cpu_time[user_arr[i]] += (cpu / 100) * 5 / 60;  # hours
            }
        }
    }
    END {
        for (u in user_cpu_time) {
            printf "USER_%s_CPU_TIME=%.1f\n", u, user_cpu_time[u];
        }
    }' "$SYSTEM_CSV"

    # Extract user GPU time and peak VRAM from GPU CSV
    if [ -f "$GPU_CSV" ]; then
        awk -F',' 'NR>1 {
            gpu_util = $5;
            processes = $9;
            vram_used = $6;

            # Parse processes field (format: user:cmd;user:cmd)
            split(processes, proc_arr, ";");
            for (i in proc_arr) {
                if (proc_arr[i] != "idle" && proc_arr[i] != "") {
                    split(proc_arr[i], user_cmd, ":");
                    user = user_cmd[1];

                    # Each sample is 5 minutes, accumulate GPU-weighted time
                    user_gpu_time[user] += (gpu_util / 100) * 5 / 60;  # hours

                    # Track peak VRAM per user
                    if (vram_used > user_peak_vram[user]) {
                        user_peak_vram[user] = vram_used;
                    }
                }
            }
        }
        END {
            for (u in user_gpu_time) {
                printf "USER_%s_GPU_TIME=%.1f\n", u, user_gpu_time[u];
                printf "USER_%s_PEAK_VRAM=%d\n", u, user_peak_vram[u];
            }
        }' "$GPU_CSV"
    fi
}

analyze_process_metrics() {
    if [ ! -f "$PROCESS_CSV" ]; then
        log_message "No process data found: $PROCESS_CSV"
        echo ""
        return
    fi

    # Analyze process metrics: per-user, per-command CPU usage
    # Output format: PROC_<USER>_<COMMAND>_AVG, PROC_<USER>_<COMMAND>_PEAK, PROC_<USER>_<COMMAND>_HOURS
    awk -F',' 'NR>1 {
        user = $3;
        command = toupper($4);  # Normalize to uppercase
        cpu_percent = $5;

        key = user "_" command;

        # Accumulate CPU percentage
        proc_cpu_sum[key] += cpu_percent;
        proc_cpu_count[key]++;

        # Track peak
        if (cpu_percent > proc_cpu_peak[key]) {
            proc_cpu_peak[key] = cpu_percent;
        }

        # Track if process was active (>1%)
        if (cpu_percent > 1.0) {
            proc_active_count[key]++;
        }

        # Store user and command separately for later use
        proc_user[key] = user;
        proc_command[key] = command;
    }
    END {
        for (key in proc_cpu_sum) {
            avg_cpu = proc_cpu_sum[key] / proc_cpu_count[key];
            peak_cpu = proc_cpu_peak[key];
            active_hours = (proc_active_count[key] * 5) / 60;  # 5-min intervals to hours

            user = proc_user[key];
            command = proc_command[key];

            # Output with normalized variable names (replace special chars with _)
            gsub(/[^a-zA-Z0-9_]/, "_", key);
            printf "PROC_%s_AVG=%.0f\n", key, avg_cpu;
            printf "PROC_%s_PEAK=%.0f\n", key, peak_cpu;
            printf "PROC_%s_HOURS=%.1f\n", key, active_hours;
            printf "PROC_%s_USER=%s\n", key, user;
            printf "PROC_%s_CMD=%s\n", key, command;
        }
    }' "$PROCESS_CSV"
}

analyze_cpu_attribution() {
    if [ ! -f "$PROCESS_CSV" ]; then
        echo "ATTR_MATLAB=0"
        echo "ATTR_PYTHON=0"
        echo "ATTR_OTHER=0"
        echo "ATTR_IDLE=0"
        return
    fi

    # Get total system CPU from system CSV
    if [ ! -f "$SYSTEM_CSV" ]; then
        echo "ATTR_MATLAB=0"
        echo "ATTR_PYTHON=0"
        echo "ATTR_OTHER=0"
        echo "ATTR_IDLE=0"
        return
    fi

    # Calculate total CPU usage and attribution by process type
    awk -F',' -v system_csv="$SYSTEM_CSV" '
    BEGIN {
        # Read system CPU data to get total CPU usage
        total_cpu_sum = 0;
        total_cpu_count = 0;
        while ((getline < system_csv) > 0) {
            if (NR == 1) continue;  # Skip header
            split($0, fields, ",");
            total_cpu_sum += fields[3];
            total_cpu_count++;
        }
        close(system_csv);
        avg_total_cpu = total_cpu_sum / total_cpu_count;
    }
    NR>1 {
        command = toupper($4);
        cpu_percent = $5;

        # Categorize by command
        if (command ~ /MATLAB/) {
            matlab_cpu += cpu_percent;
            matlab_count++;
        } else if (command ~ /PYTHON/) {
            python_cpu += cpu_percent;
            python_count++;
        } else {
            other_cpu += cpu_percent;
            other_count++;
        }

        total_proc_cpu += cpu_percent;
        total_proc_count++;
    }
    END {
        # Calculate averages
        avg_matlab = (matlab_count > 0) ? matlab_cpu / matlab_count : 0;
        avg_python = (python_count > 0) ? python_cpu / python_count : 0;
        avg_other = (other_count > 0) ? other_cpu / other_count : 0;
        avg_proc_total = (total_proc_count > 0) ? total_proc_cpu / total_proc_count : 0;

        # Calculate percentage of total system CPU
        # Note: avg_total_cpu is the average system-wide CPU %
        # Process CPU percentages are per-core, so we need to normalize
        if (avg_total_cpu > 0) {
            matlab_pct = (avg_matlab / avg_total_cpu) * 100;
            python_pct = (avg_python / avg_total_cpu) * 100;
            other_pct = (avg_other / avg_total_cpu) * 100;
            idle_pct = 100 - (matlab_pct + python_pct + other_pct);

            # Ensure idle is not negative
            if (idle_pct < 0) idle_pct = 0;
        } else {
            matlab_pct = 0;
            python_pct = 0;
            other_pct = 0;
            idle_pct = 100;
        }

        printf "ATTR_MATLAB=%.0f\n", matlab_pct;
        printf "ATTR_PYTHON=%.0f\n", python_pct;
        printf "ATTR_OTHER=%.0f\n", other_pct;
        printf "ATTR_IDLE=%.0f\n", idle_pct;
    }' "$PROCESS_CSV"
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
    local period_0006_cpu=$8
    local period_0006_gpu=$9
    local period_0612_cpu=${10}
    local period_0612_gpu=${11}
    local period_1218_cpu=${12}
    local period_1218_gpu=${13}
    local period_1824_cpu=${14}
    local period_1824_gpu=${15}
    shift 15
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

    # Usage by period
    cat << EOF
[USAGE BY PERIOD]
--------------------------------------------------------------------------------
00-06:  CPU ${period_0006_cpu}% | GPU ${period_0006_gpu}%
06-12:  CPU ${period_0612_cpu}% | GPU ${period_0612_gpu}%
12-18:  CPU ${period_1218_cpu}% | GPU ${period_1218_gpu}%
18-24:  CPU ${period_1824_cpu}% | GPU ${period_1824_gpu}%

EOF

    # User usage breakdown
    echo "[USER USAGE]"
    echo "--------------------------------------------------------------------------------"
    printf "%-10s %-15s %-15s %-12s\n" "User" "CPU Time" "GPU Time" "Peak VRAM"

    # Get all users and their stats
    local user_list=()
    for var in $(set | grep '^USER_.*_CPU_TIME=' | cut -d= -f1); do
        local username=$(echo "$var" | sed 's/USER_\(.*\)_CPU_TIME/\1/')
        user_list+=("$username")
    done

    # Sort users alphabetically
    IFS=$'\n' sorted_users=($(sort <<<"${user_list[*]}"))
    unset IFS

    for username in "${sorted_users[@]}"; do
        eval "cpu_time=\${USER_${username}_CPU_TIME:-0.0}"
        eval "gpu_time=\${USER_${username}_GPU_TIME:-0.0}"
        eval "peak_vram=\${USER_${username}_PEAK_VRAM:--}"

        printf "%-10s %-15s %-15s %-12s\n" \
            "$username" \
            "${cpu_time}h" \
            "${gpu_time}h" \
            "$([ "$peak_vram" = "-" ] && echo "-" || echo "${peak_vram} MB")"
    done
    echo ""

    # CPU Consumers section (percentage normalized to server = 100%)
    echo "🔥 CPU Consumers"
    echo "--------------------------------------------------------------------------------"

    # Get all process data and organize by user
    local proc_list=()
    for var in $(set | grep '^PROC_.*_AVG=' | cut -d= -f1); do
        proc_list+=("$var")
    done

    # Build a user->processes map
    declare -A user_processes
    for proc_var in "${proc_list[@]}"; do
        local proc_key=$(echo "$proc_var" | sed 's/_AVG$//')
        eval "local proc_user=\${${proc_key}_USER}"

        if [ -n "$proc_user" ]; then
            if [ -z "${user_processes[$proc_user]}" ]; then
                user_processes[$proc_user]="$proc_key"
            else
                user_processes[$proc_user]="${user_processes[$proc_user]} $proc_key"
            fi
        fi
    done

    # Display processes grouped by user
    for username in "${sorted_users[@]}"; do
        local procs="${user_processes[$username]}"
        if [ -n "$procs" ]; then
            echo "$username"

            # Sort processes by avg CPU (descending)
            local proc_array=($procs)
            local sorted_procs=()

            # Simple bubble sort by avg CPU
            for proc in "${proc_array[@]}"; do
                eval "local avg=\${${proc}_AVG:-0}"
                sorted_procs+=("$avg:$proc")
            done

            IFS=$'\n' sorted_procs=($(sort -rn <<<"${sorted_procs[*]}"))
            unset IFS

            # Display each process
            for item in "${sorted_procs[@]}"; do
                local proc=$(echo "$item" | cut -d: -f2-)
                eval "local cmd=\${${proc}_CMD}"
                eval "local avg=\${${proc}_AVG}"
                eval "local peak=\${${proc}_PEAK}"
                eval "local hours=\${${proc}_HOURS}"

                printf "  %-10s avg %2s%% | peak %2s%% | active %sh\n" \
                    "$cmd" "$avg" "$peak" "$hours"
            done
            echo ""
        fi
    done

    # CPU Attribution section
    echo "🔥 CPU Attribution"
    echo "--------------------------------------------------------------------------------"
    printf "%-15s %3s%%\n" "MATLAB" "${ATTR_MATLAB:-0}"
    printf "%-15s %3s%%\n" "Python" "${ATTR_PYTHON:-0}"
    printf "%-15s %3s%%\n" "Other" "${ATTR_OTHER:-0}"
    printf "%-15s %3s%%\n" "Idle" "${ATTR_IDLE:-0}"
    echo ""

    # Disk and users
    cat << EOF
[STORAGE & ACTIVE USERS]
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

    # Check time-based CPU warnings (>70% in any period)
    if [ "$period_0006_cpu" -gt 70 ]; then
        echo "⚠ CPU utilization was high during 00:00–06:00 (${period_0006_cpu}%)"
        has_warnings=1
    fi
    if [ "$period_0612_cpu" -gt 70 ]; then
        echo "⚠ CPU utilization was high during 06:00–12:00 (${period_0612_cpu}%)"
        has_warnings=1
    fi
    if [ "$period_1218_cpu" -gt 70 ]; then
        echo "⚠ CPU utilization was high during 12:00–18:00 (${period_1218_cpu}%)"
        has_warnings=1
    fi
    if [ "$period_1824_cpu" -gt 70 ]; then
        echo "⚠ CPU utilization was high during 18:00–24:00 (${period_1824_cpu}%)"
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
    local tomorrow=$(date -d 'tomorrow' '+%Y-%m-%d' 2>/dev/null || date -v +1d '+%Y-%m-%d')
    cat << EOF
================================================================================
Report generated: $(date '+%Y-%m-%d %H:%M:%S')
Data source: $YESTERDAY
Next report will cover: $TODAY (scheduled for $tomorrow 01:30)
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

    # Analyze usage by period
    eval "$(analyze_usage_by_period)"

    # Analyze user usage
    eval "$(analyze_user_usage)"

    # Analyze process metrics
    eval "$(analyze_process_metrics)"

    # Analyze CPU attribution
    eval "$(analyze_cpu_attribution)"

    # Generate report
    generate_report_text \
        "${CPU_AVG:-N/A}" "${CPU_PEAK:-N/A}" \
        "${RAM_AVG:-N/A}" "${RAM_PEAK:-N/A}" \
        "${DISK_ROOT:-N/A}" "${DISK_HOME:-N/A}" \
        "${USERS:-none}" \
        "${PERIOD_0006_CPU:-0}" "${PERIOD_0006_GPU:-0}" \
        "${PERIOD_0612_CPU:-0}" "${PERIOD_0612_GPU:-0}" \
        "${PERIOD_1218_CPU:-0}" "${PERIOD_1218_GPU:-0}" \
        "${PERIOD_1824_CPU:-0}" "${PERIOD_1824_GPU:-0}" \
        "${GPU_STATS[@]}" \
        > "$REPORT_FILE"

    log_message "Summary generated: $REPORT_FILE"

    # Clean up old data files (older than retention days)
    find "$DATA_DIR" -name "system-*.csv" -mtime +$DATA_RETENTION_DAYS -delete 2>/dev/null
    find "$DATA_DIR" -name "gpu-*.csv" -mtime +$DATA_RETENTION_DAYS -delete 2>/dev/null
    find "$DATA_DIR" -name "process-*.csv" -mtime +$DATA_RETENTION_DAYS -delete 2>/dev/null
    find "$REPORT_DIR" -name "usage-summary-*.txt" -mtime +$DATA_RETENTION_DAYS -delete 2>/dev/null

    log_message "Cleaned up files older than $DATA_RETENTION_DAYS days"

    # Send to Discord
    log_message "Sending report to Discord..."
    source "$SCRIPT_DIR/send-discord-report.sh"
    if send_to_discord; then
        log_message "Successfully sent report to Discord"
    else
        log_message "Failed to send report to Discord"
    fi

    # Display report if --show flag is provided
    if [ "$1" = "--show" ]; then
        cat "$REPORT_FILE"
    fi

    echo "Summary report generated: $REPORT_FILE"
}

# Execute
main "$@"
