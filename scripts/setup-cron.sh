#!/bin/bash

################################################################################
# Cron Auto-Configuration Script
# Purpose: Automatically configure cron jobs for usage monitoring
# Usage: ./setup-cron.sh
################################################################################

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COLLECTOR_SCRIPT="$SCRIPT_DIR/collect-usage.sh"
SUMMARY_SCRIPT="$SCRIPT_DIR/daily-usage-summary.sh"

# Check if scripts exist
if [ ! -f "$COLLECTOR_SCRIPT" ]; then
    echo "Error: Collector script not found: $COLLECTOR_SCRIPT"
    exit 1
fi

if [ ! -f "$SUMMARY_SCRIPT" ]; then
    echo "Error: Summary script not found: $SUMMARY_SCRIPT"
    exit 1
fi

# Cron job entries
COLLECTOR_JOB="*/5 * * * * $COLLECTOR_SCRIPT >> $SCRIPT_DIR/../logs/collector.log 2>&1"
SUMMARY_JOB="30 1 * * * $SUMMARY_SCRIPT >> $SCRIPT_DIR/../logs/summary.log 2>&1"

# Remove old monitoring cron jobs if they exist
crontab -l 2>/dev/null | grep -v "collect-usage.sh" | grep -v "daily-usage-summary.sh" | crontab -

# Add new cron jobs
(crontab -l 2>/dev/null 2>&1; echo "$COLLECTOR_JOB"; echo "$SUMMARY_JOB") | crontab -

echo "================================================================================
Cron Jobs Configured Successfully!
================================================================================

[USAGE COLLECTOR]
Schedule: Every 5 minutes
Script:   $COLLECTOR_SCRIPT
Log:      $SCRIPT_DIR/../logs/collector.log
Purpose:  Collect system and GPU metrics to CSV files

[DAILY USAGE SUMMARY]
Schedule: Daily at 1:30 AM
Script:   $SUMMARY_SCRIPT
Log:      $SCRIPT_DIR/../logs/summary.log
Purpose:  Generate daily usage summary report

Current Crontab:
--------------------------------------------------------------------------------"
crontab -l 2>/dev/null | grep -E "(collect-usage|daily-usage-summary)" || echo "No monitoring jobs found (this shouldn't happen)"

cat << EOF

================================================================================
Notes:
- Usage data will be collected every 5 minutes in: $(dirname "$SCRIPT_DIR")/data/usage/
- CSV format: system-YYYY-MM-DD.csv and gpu-YYYY-MM-DD.csv (if GPU exists)
- Daily summaries will be generated in: $(dirname "$SCRIPT_DIR")/reports/usage/
- Data older than 90 days will be automatically cleaned up
- Manual collection: $COLLECTOR_SCRIPT
- Manual summary: $SUMMARY_SCRIPT --show
================================================================================
EOF
