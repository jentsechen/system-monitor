#!/bin/bash

################################################################################
# Discord Report Sender
# Purpose: Send daily usage reports to Discord via webhook
# Author: System Monitor
# Date: 2026-08-26
################################################################################

# Configuration
# IMPORTANT: Set DISCORD_WEBHOOK_URL as an environment variable
# Example: export DISCORD_WEBHOOK_URL="your-webhook-url"
# Or create a .env file in the project root (see README)
DISCORD_WEBHOOK_URL="${DISCORD_WEBHOOK_URL:-}"

# Validate webhook URL is set
if [ -z "$DISCORD_WEBHOOK_URL" ]; then
    echo "ERROR: DISCORD_WEBHOOK_URL environment variable is not set"
    echo "Please set it in your environment or create a .env file"
    exit 1
fi

# Colors (Discord uses decimal color codes)
COLOR_SUCCESS=5763719    # Green
COLOR_WARNING=16776960   # Yellow
COLOR_ERROR=15158332     # Red
COLOR_INFO=3447003       # Blue
COLOR_PURPLE=10181046    # Purple

# Date for report
YESTERDAY=${1:-$(date -d 'yesterday' '+%Y-%m-%d' 2>/dev/null || date -v -1d '+%Y-%m-%d')}

################################################################################
# Helper Functions
################################################################################

# Escape JSON special characters
json_escape() {
    echo "$1" | sed 's/\\/\\\\/g; s/"/\\"/g; s/\n/\\n/g'
}

# Determine embed color based on warnings
get_embed_color() {
    local has_warnings=$1
    if [ "$has_warnings" -eq 1 ]; then
        echo "$COLOR_WARNING"
    else
        echo "$COLOR_SUCCESS"
    fi
}

# Build Discord embed JSON
build_discord_payload() {
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

    # Check for warnings
    local has_warnings=0
    if [ "$disk_root" != "N/A" ] && [ "$disk_root" -gt 80 ]; then has_warnings=1; fi
    if [ "$disk_home" != "N/A" ] && [ "$disk_home" -gt 80 ]; then has_warnings=1; fi
    if [ "$cpu_avg" -gt 80 ]; then has_warnings=1; fi
    if [ "$ram_avg" -gt 80 ]; then has_warnings=1; fi

    local embed_color=$(get_embed_color $has_warnings)

    # Build System Metrics field
    local system_metrics="**CPU:** avg ${cpu_avg}% | peak ${cpu_peak}%\n**RAM:** avg ${ram_avg}% | peak ${ram_peak}%"

    # Build GPU Metrics field (if GPU data exists)
    local gpu_metrics=""
    local gpu_count=0
    for var in $(set | grep '^GPU_[0-9]*_AVG=' | cut -d= -f1); do
        gpu_count=$((gpu_count + 1))
        gpu_id=$(echo "$var" | sed 's/GPU_\([0-9]*\)_AVG/\1/')
        eval "gpu_avg=\$GPU_${gpu_id}_AVG"
        eval "gpu_peak=\$GPU_${gpu_id}_PEAK"
        eval "gpu_hours=\$GPU_${gpu_id}_ACTIVE_HOURS"
        eval "gpu_vram_peak=\$GPU_${gpu_id}_VRAM_PEAK"
        eval "gpu_vram_total=\$GPU_${gpu_id}_VRAM_TOTAL"

        if [ -n "$gpu_metrics" ]; then
            gpu_metrics="${gpu_metrics}\n"
        fi
        gpu_metrics="${gpu_metrics}**GPU ${gpu_id}:** avg ${gpu_avg}% | peak ${gpu_peak}% | active ${gpu_hours}h\n**VRAM:** ${gpu_vram_peak}/${gpu_vram_total} MB"

        # Check for GPU warnings
        if [ "$gpu_avg" -lt 10 ]; then has_warnings=1; fi
        if (( $(echo "$gpu_hours > 20" | bc -l 2>/dev/null || echo 0) )); then has_warnings=1; fi
    done

    # Build Usage by Period field
    local period_usage="**00-06:** CPU ${period_0006_cpu}% | GPU ${period_0006_gpu}%\n"
    period_usage="${period_usage}**06-12:** CPU ${period_0612_cpu}% | GPU ${period_0612_gpu}%\n"
    period_usage="${period_usage}**12-18:** CPU ${period_1218_cpu}% | GPU ${period_1218_gpu}%\n"
    period_usage="${period_usage}**18-24:** CPU ${period_1824_cpu}% | GPU ${period_1824_gpu}%"

    # Check time-based warnings
    if [ "$period_0006_cpu" -gt 70 ] || [ "$period_0612_cpu" -gt 70 ] || [ "$period_1218_cpu" -gt 70 ] || [ "$period_1824_cpu" -gt 70 ]; then
        has_warnings=1
    fi

    # Recalculate color after all warning checks
    embed_color=$(get_embed_color $has_warnings)

    # Build User Usage field
    local user_usage=""
    local user_list=()
    for var in $(set | grep '^USER_.*_CPU_TIME=' | cut -d= -f1); do
        local username=$(echo "$var" | sed 's/USER_\(.*\)_CPU_TIME/\1/')
        user_list+=("$username")
    done

    # Sort users alphabetically
    IFS=$'\n' sorted_users=($(sort <<<"${user_list[*]}" 2>/dev/null))
    unset IFS

    for username in "${sorted_users[@]}"; do
        eval "cpu_time=\${USER_${username}_CPU_TIME:-0.0}"
        eval "gpu_time=\${USER_${username}_GPU_TIME:-0.0}"
        eval "peak_vram=\${USER_${username}_PEAK_VRAM:--}"

        if [ -n "$user_usage" ]; then
            user_usage="${user_usage}\n"
        fi

        if [ "$peak_vram" = "-" ]; then
            user_usage="${user_usage}**${username}:** CPU Time ${cpu_time}h | GPU ${gpu_time}h"
        else
            user_usage="${user_usage}**${username}:** CPU Time ${cpu_time}h | GPU ${gpu_time}h | VRAM ${peak_vram}MB"
        fi
    done

    if [ -z "$user_usage" ]; then
        user_usage="No user activity recorded"
    fi

    # Build CPU Consumers field
    local cpu_consumers=""
    local proc_list=()
    for var in $(set | grep '^PROC_.*_AVG=' | cut -d= -f1); do
        proc_list+=("$var")
    done

    # Build a user->processes map
    declare -A user_processes_map
    for proc_var in "${proc_list[@]}"; do
        local proc_key=$(echo "$proc_var" | sed 's/_AVG$//')
        eval "local proc_user=\${${proc_key}_USER}"

        if [ -n "$proc_user" ]; then
            if [ -z "${user_processes_map[$proc_user]}" ]; then
                user_processes_map[$proc_user]="$proc_key"
            else
                user_processes_map[$proc_user]="${user_processes_map[$proc_user]} $proc_key"
            fi
        fi
    done

    # Build CPU consumers text
    for username in "${sorted_users[@]}"; do
        local procs="${user_processes_map[$username]}"
        if [ -n "$procs" ]; then
            if [ -n "$cpu_consumers" ]; then
                cpu_consumers="${cpu_consumers}\n"
            fi
            cpu_consumers="${cpu_consumers}**${username}**\n"

            # Sort processes by avg CPU
            local proc_array=($procs)
            local sorted_procs=()
            for proc in "${proc_array[@]}"; do
                eval "local avg=\${${proc}_AVG:-0}"
                sorted_procs+=("$avg:$proc")
            done
            IFS=$'\n' sorted_procs=($(sort -rn <<<"${sorted_procs[*]}" 2>/dev/null))
            unset IFS

            # Display each process
            for item in "${sorted_procs[@]}"; do
                local proc=$(echo "$item" | cut -d: -f2-)
                eval "local cmd=\${${proc}_CMD}"
                eval "local avg=\${${proc}_AVG}"
                eval "local peak=\${${proc}_PEAK}"
                eval "local hours=\${${proc}_HOURS}"

                cpu_consumers="${cpu_consumers}  ${cmd}: avg ${avg}% | peak ${peak}% | active ${hours}h\n"
            done
        fi
    done

    if [ -z "$cpu_consumers" ]; then
        cpu_consumers="No process data available"
    fi

    # Build CPU Attribution field
    local cpu_attribution="**MATLAB:** ${ATTR_MATLAB:-0}%\n**Python:** ${ATTR_PYTHON:-0}%\n**Other:** ${ATTR_OTHER:-0}%\n**Idle:** ${ATTR_IDLE:-0}%"

    # Build Storage field
    local storage_info="**Root (/):** ${disk_root}%\n**Home (/home):** ${disk_home}%\n**Active Users:** ${users}"

    # Build Warnings field
    local warnings=""

    # Disk warnings
    if [ "$disk_root" != "N/A" ] && [ "$disk_root" -gt 80 ]; then
        warnings="${warnings}:warning: Root disk usage high: ${disk_root}%\n"
    fi
    if [ "$disk_home" != "N/A" ] && [ "$disk_home" -gt 80 ]; then
        warnings="${warnings}:warning: Home disk usage high: ${disk_home}%\n"
    fi

    # CPU/RAM warnings
    if [ "$cpu_avg" -gt 80 ]; then
        warnings="${warnings}:warning: High average CPU usage: ${cpu_avg}%\n"
    fi
    if [ "$ram_avg" -gt 80 ]; then
        warnings="${warnings}:warning: High average RAM usage: ${ram_avg}%\n"
    fi

    # Time-based CPU warnings
    if [ "$period_0006_cpu" -gt 70 ]; then
        warnings="${warnings}:warning: CPU high during 00:00-06:00 (${period_0006_cpu}%)\n"
    fi
    if [ "$period_0612_cpu" -gt 70 ]; then
        warnings="${warnings}:warning: CPU high during 06:00-12:00 (${period_0612_cpu}%)\n"
    fi
    if [ "$period_1218_cpu" -gt 70 ]; then
        warnings="${warnings}:warning: CPU high during 12:00-18:00 (${period_1218_cpu}%)\n"
    fi
    if [ "$period_1824_cpu" -gt 70 ]; then
        warnings="${warnings}:warning: CPU high during 18:00-24:00 (${period_1824_cpu}%)\n"
    fi

    # GPU warnings
    for var in $(set | grep '^GPU_[0-9]*_AVG=' | cut -d= -f1); do
        gpu_id=$(echo "$var" | sed 's/GPU_\([0-9]*\)_AVG/\1/')
        eval "gpu_avg=\$GPU_${gpu_id}_AVG"
        eval "gpu_hours=\$GPU_${gpu_id}_ACTIVE_HOURS"

        if [ "$gpu_avg" -lt 10 ]; then
            warnings="${warnings}:warning: GPU ${gpu_id} mostly idle (avg ${gpu_avg}%)\n"
        fi
        if (( $(echo "$gpu_hours > 20" | bc -l 2>/dev/null || echo 0) )); then
            warnings="${warnings}:warning: GPU ${gpu_id} heavily utilized (${gpu_hours}h)\n"
        fi
    done

    if [ -z "$warnings" ]; then
        warnings=":white_check_mark: No warnings detected"
    fi

    # Build the JSON payload
    cat <<EOF
{
  "embeds": [
    {
      "title": ":chart_with_upwards_trend: Server Daily Usage Report",
      "description": "**Date:** ${YESTERDAY}",
      "color": ${embed_color},
      "fields": [
        {
          "name": ":desktop: System Metrics",
          "value": "${system_metrics}",
          "inline": false
        }$(if [ $gpu_count -gt 0 ]; then echo ",
        {
          \"name\": \":video_game: GPU Metrics\",
          \"value\": \"${gpu_metrics}\",
          \"inline\": false
        }"; fi),
        {
          "name": ":clock3: Usage by Period",
          "value": "${period_usage}",
          "inline": false
        },
        {
          "name": ":busts_in_silhouette: User Usage",
          "value": "${user_usage}",
          "inline": false
        },
        {
          "name": ":fire: CPU Consumers",
          "value": "${cpu_consumers}",
          "inline": false
        },
        {
          "name": ":fire: CPU Attribution",
          "value": "${cpu_attribution}",
          "inline": false
        },
        {
          "name": ":floppy_disk: Storage & Users",
          "value": "${storage_info}",
          "inline": false
        },
        {
          "name": ":warning: Warnings",
          "value": "${warnings}",
          "inline": false
        }
      ],
      "footer": {
        "text": "System Monitor | Next report: $(date '+%Y-%m-%d')"
      },
      "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%S.000Z)"
    }
  ]
}
EOF
}

################################################################################
# Main Execution
################################################################################

send_to_discord() {
    # Build the payload
    local payload=$(build_discord_payload \
        "${CPU_AVG:-N/A}" "${CPU_PEAK:-N/A}" \
        "${RAM_AVG:-N/A}" "${RAM_PEAK:-N/A}" \
        "${DISK_ROOT:-N/A}" "${DISK_HOME:-N/A}" \
        "${USERS:-none}" \
        "${PERIOD_0006_CPU:-0}" "${PERIOD_0006_GPU:-0}" \
        "${PERIOD_0612_CPU:-0}" "${PERIOD_0612_GPU:-0}" \
        "${PERIOD_1218_CPU:-0}" "${PERIOD_1218_GPU:-0}" \
        "${PERIOD_1824_CPU:-0}" "${PERIOD_1824_GPU:-0}")

    # Send to Discord
    response=$(curl -s -w "\n%{http_code}" -H "Content-Type: application/json" \
         -d "$payload" \
         "$DISCORD_WEBHOOK_URL")

    http_code=$(echo "$response" | tail -n1)
    response_body=$(echo "$response" | head -n-1)

    if [ "$http_code" -eq 204 ] || [ "$http_code" -eq 200 ]; then
        echo "Successfully sent report to Discord (HTTP $http_code)"
        return 0
    else
        echo "Failed to send report to Discord (HTTP $http_code)"
        echo "Response: $response_body"
        return 1
    fi
}

# Export function for use by daily-usage-summary.sh
if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
    # Script is being run directly
    echo "This script should be sourced by daily-usage-summary.sh"
    echo "Or run with environment variables set for CPU_AVG, RAM_AVG, etc."

    if [ -n "$CPU_AVG" ]; then
        send_to_discord
    else
        echo "No data provided. Set environment variables and try again."
        exit 1
    fi
fi
