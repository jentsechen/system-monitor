# Server Usage Monitoring System

Automated system and GPU usage monitoring with historical data collection and daily summary reports.

## Features

- ✅ **5-Minute Data Collection**: Automatic collection of system and GPU metrics every 5 minutes
- ✅ **CSV Storage**: Historical data stored in ISO 8601 formatted CSV files
- ✅ **GPU Support**: Automatic NVIDIA GPU monitoring with graceful fallback if no GPU exists
- ✅ **Daily Summaries**: Concise daily usage reports with averages, peaks, and warnings
- ✅ **Time-Based Analytics**: Usage breakdown across 6-hour periods (00-06, 06-12, 12-18, 18-24)
- ✅ **Per-User Tracking**: Individual CPU/GPU usage hours and peak VRAM consumption per user
- ✅ **Intelligent Warnings**: Automatic detection of disk usage, idle GPUs, time-specific high CPU, and resource issues
- ✅ **Automatic Cleanup**: Data older than 90 days is automatically removed
- ✅ **Discord-Ready**: Report generation separated from collection for easy webhook integration

## Directory Structure

```
system-monitor/
├── README.md                  # This file
├── scripts/
│   ├── collect-usage.sh       # 5-min usage collector
│   ├── daily-usage-summary.sh # Daily summary generator
│   └── setup-cron.sh          # Cron configuration script
├── data/
│   └── usage/                 # Historical CSV data
│       ├── system-YYYY-MM-DD.csv  # System metrics
│       └── gpu-YYYY-MM-DD.csv     # GPU metrics (if GPU exists)
├── reports/
│   └── usage/                 # Daily summary reports
│       └── usage-summary-YYYY-MM-DD.txt
└── logs/
    ├── collector.log          # Collection log
    └── summary.log            # Summary generation log
```

## Quick Start

### 1. Configure Automatic Monitoring

```bash
cd system-monitor
./scripts/setup-cron.sh
```

This sets up two cron jobs:
- **Usage collector**: Runs every 5 minutes
- **Daily summary**: Runs daily at 1:30 AM

### 2. Manual Operations

```bash
# Collect current usage data
./scripts/collect-usage.sh

# Generate summary for yesterday
./scripts/daily-usage-summary.sh --show

# View latest summary report
cat reports/usage/usage-summary-$(date -d 'yesterday' '+%Y-%m-%d').txt
```

## Collected Metrics

### System Metrics (Every 5 Minutes)

- **Timestamp**: ISO 8601 format with timezone
- **Hostname**: Server identifier
- **CPU Usage**: Percentage utilization
- **RAM Usage**: Percentage utilization
- **Load Average**: 1m, 5m, 15m
- **Disk Usage**: `/` and `/home` partitions
- **Logged Users**: All currently logged-in users

### GPU Metrics (Every 5 Minutes, if GPU exists)

- **GPU ID**: Device index
- **GPU Name**: Model name (e.g., NVIDIA RTX A6000)
- **GPU Utilization**: Percentage
- **VRAM**: Used and total memory (MB)
- **Temperature**: Degrees Celsius
- **Processes**: Running processes with users and commands

## Daily Summary Report

Each morning at 1:30 AM, a summary report is generated for the previous day:

```
================================================================================
                    SERVER DAILY USAGE — 2026-08-24
================================================================================

[SYSTEM METRICS]
--------------------------------------------------------------------------------
CPU:    avg 43% | peak 94%
RAM:    avg 28% | peak 58%

[GPU METRICS]
--------------------------------------------------------------------------------
GPU 0:  avg  61% | peak 100% | active 18.2h | VRAM 48950/49140 MB
GPU 1:  avg   3% | peak  42% | active  1.1h | VRAM 12400/49140 MB

[USAGE BY PERIOD]
--------------------------------------------------------------------------------
00-06:  CPU 12% | GPU  8%
06-12:  CPU 45% | GPU 42%
12-18:  CPU 78% | GPU 85%
18-24:  CPU 52% | GPU 61%

[USER USAGE]
--------------------------------------------------------------------------------
User       CPU Time     GPU Time     Peak VRAM
alice      4.2h         12.5h        45280 MB
bob        8.1h         3.2h         12400 MB
charlie    2.5h         0.0h         -

[STORAGE & ACTIVE USERS]
--------------------------------------------------------------------------------
Disk:   / 25% | /home 37%
Users:  alice, bob, charlie

[WARNINGS]
--------------------------------------------------------------------------------
⚠ GPU 1 was mostly idle (avg 3%)
⚠ CPU utilization was high during 12:00–18:00 (78%)

================================================================================
```

## Warning System

The daily summary automatically detects and reports:

- **Disk Usage**: Alerts when disk usage exceeds 80%
- **High CPU/RAM**: Alerts when average usage exceeds 80%
- **Time-Based CPU Usage**: Alerts when CPU utilization exceeds 70% in any 6-hour period
- **Idle GPU**: Alerts when GPU average utilization is below 10%
- **Heavy GPU Usage**: Alerts when GPU is active for more than 20 hours

## Configuration

Edit thresholds at the top of `scripts/daily-usage-summary.sh`:

```bash
# Thresholds (configurable)
DISK_WARNING_THRESHOLD=80        # Disk usage warning (%)
IDLE_GPU_THRESHOLD=10            # GPU idle threshold (%)
HIGH_GPU_ACTIVE_HOURS=20         # Heavy usage threshold (hours)
DATA_RETENTION_DAYS=90           # Data retention period
```

## CSV File Format

### system-YYYY-MM-DD.csv

```csv
timestamp,hostname,cpu_percent,ram_percent,load_1m,load_5m,load_15m,disk_root_percent,disk_home_percent,logged_users
2026-08-25T12:00:00+08:00,Server,23.5,11.2,0.34,0.25,0.14,25,37,user1;user2
```

### gpu-YYYY-MM-DD.csv

```csv
timestamp,hostname,gpu_id,gpu_name,gpu_util_percent,vram_used_mb,vram_total_mb,temp_c,processes
2026-08-25T12:00:00+08:00,Server,0,"NVIDIA RTX A6000",71,28500,49140,68,user1:python;user2:matlab
```

## Cron Schedule

```cron
# Collect usage data every 5 minutes
*/5 * * * * /path/to/scripts/collect-usage.sh >> /path/to/logs/collector.log 2>&1

# Generate daily summary at 1:30 AM
30 1 * * * /path/to/scripts/daily-usage-summary.sh >> /path/to/logs/summary.log 2>&1
```

## Data Retention

- CSV files and reports older than **90 days** are automatically deleted
- Modify `DATA_RETENTION_DAYS` in `daily-usage-summary.sh` to change retention period
- Manual cleanup: `find data/usage -name "*.csv" -mtime +90 -delete`

## Troubleshooting

### Scripts Don't Have Execute Permission

```bash
chmod +x scripts/collect-usage.sh
chmod +x scripts/daily-usage-summary.sh
chmod +x scripts/setup-cron.sh
```

### Cron Jobs Not Running

1. Check cron service:
   ```bash
   systemctl status crond
   ```

2. View cron logs:
   ```bash
   tail -f logs/collector.log
   tail -f logs/summary.log
   ```

3. Verify cron jobs:
   ```bash
   crontab -l
   ```

### No GPU Data Collected

This is normal if:
- `nvidia-smi` is not installed
- No NVIDIA GPUs are present
- GPU drivers are not loaded

The system will work normally and only collect system metrics.

### CSV Files Have Corrupt Data

The collector uses atomic writes (temp file + mv) to prevent corruption. If corruption occurs:

1. Check disk space: `df -h`
2. Check filesystem errors: `dmesg | grep -i error`
3. Verify file permissions: `ls -la data/usage/`

## Integration with Discord/Slack (Future)

The `generate_report_text()` function in `daily-usage-summary.sh` is separated from output handling, making it easy to add webhook notifications:

```bash
# Example Discord webhook integration (add to daily-usage-summary.sh)
send_to_discord() {
    local report_file=$1
    local webhook_url="YOUR_WEBHOOK_URL"

    curl -H "Content-Type: application/json" \
         -d "{\"content\": \"$(cat $report_file)\"}" \
         "$webhook_url"
}
```

## System Requirements

- Linux system (tested on CentOS/RHEL 9)
- Bash 4.0+
- Basic utilities: top, free, df, ps, awk, bc
- Optional: nvidia-smi (for GPU monitoring)

## License

MIT License

## Author

System Monitor - 2026
