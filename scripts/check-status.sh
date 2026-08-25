#!/bin/bash

################################################################################
# Status Checker
# Purpose: Verify cron jobs are running and collecting data
################################################################################

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BASE_DIR="$(dirname "$SCRIPT_DIR")"

echo "================================================================================"
echo "                    MONITORING SYSTEM STATUS CHECK"
echo "================================================================================"
echo ""

# Check 1: Cron service
echo "🔧 CRON SERVICE:"
echo "--------------------------------------------------------------------------------"
if systemctl is-active --quiet crond; then
    echo "✅ crond service is RUNNING"
else
    echo "❌ crond service is NOT running"
    echo "   Fix: sudo systemctl start crond"
fi
echo ""

# Check 2: Installed cron jobs
echo "📅 INSTALLED CRON JOBS:"
echo "--------------------------------------------------------------------------------"
COLLECTOR_CRON=$(crontab -l 2>/dev/null | grep "collect-usage.sh" | wc -l)
SUMMARY_CRON=$(crontab -l 2>/dev/null | grep "daily-usage-summary.sh" | wc -l)

if [ "$COLLECTOR_CRON" -eq 1 ]; then
    echo "✅ Usage collector job installed (every 5 minutes)"
else
    echo "❌ Usage collector job NOT found"
fi

if [ "$SUMMARY_CRON" -eq 1 ]; then
    echo "✅ Daily summary job installed (1:30 AM daily)"
else
    echo "❌ Daily summary job NOT found"
fi

if [ "$COLLECTOR_CRON" -eq 0 ] || [ "$SUMMARY_CRON" -eq 0 ]; then
    echo ""
    echo "   Fix: Run ./scripts/setup-cron.sh"
fi
echo ""

# Check 3: Last collection
echo "📊 LAST COLLECTION:"
echo "--------------------------------------------------------------------------------"
if [ -f "$BASE_DIR/logs/collector.log" ]; then
    LAST_RUN=$(tail -1 "$BASE_DIR/logs/collector.log" | grep -oP '\[\K[^\]]+')
    LAST_MSG=$(tail -1 "$BASE_DIR/logs/collector.log" | cut -d']' -f2-)
    echo "Last run: $LAST_RUN"
    echo "Status:  $LAST_MSG"

    # Check if collection happened in last 10 minutes
    if [ -n "$LAST_RUN" ]; then
        LAST_TIME=$(date -d "$LAST_RUN" +%s 2>/dev/null)
        NOW_TIME=$(date +%s)
        DIFF=$((NOW_TIME - LAST_TIME))

        if [ $DIFF -lt 600 ]; then
            echo "✅ Collection is active (last run $((DIFF/60)) minutes ago)"
        else
            echo "⚠️  No recent collection ($((DIFF/60)) minutes since last run)"
        fi
    fi
else
    echo "❌ No collector log found"
fi
echo ""

# Check 4: Data files
echo "📁 DATA FILES:"
echo "--------------------------------------------------------------------------------"
TODAY=$(date +%Y-%m-%d)
SYSTEM_CSV="$BASE_DIR/data/usage/system-$TODAY.csv"
GPU_CSV="$BASE_DIR/data/usage/gpu-$TODAY.csv"

if [ -f "$SYSTEM_CSV" ]; then
    SAMPLE_COUNT=$(tail -n +2 "$SYSTEM_CSV" | wc -l)
    echo "✅ System data: $SAMPLE_COUNT samples today"
    echo "   Latest: $(tail -1 "$SYSTEM_CSV" | cut -d',' -f1)"
else
    echo "❌ No system data file for today"
fi

if [ -f "$GPU_CSV" ]; then
    GPU_SAMPLE_COUNT=$(tail -n +2 "$GPU_CSV" | wc -l)
    echo "✅ GPU data: $GPU_SAMPLE_COUNT samples today"
else
    echo "⚠️  No GPU data (this is normal if no GPU detected)"
fi
echo ""

# Check 5: Next scheduled run
echo "⏰ NEXT SCHEDULED RUNS:"
echo "--------------------------------------------------------------------------------"
NOW_MIN=$(date +%M)
NEXT_5MIN=$(( (NOW_MIN / 5 + 1) * 5 ))
if [ $NEXT_5MIN -ge 60 ]; then
    NEXT_5MIN=0
    NEXT_HOUR=$(date -d "+1 hour" +%H)
else
    NEXT_HOUR=$(date +%H)
fi

echo "Next collection: Today at $NEXT_HOUR:$(printf "%02d" $NEXT_5MIN)"
echo "Next summary:    Tomorrow at 01:30"
echo ""

# Check 6: Disk space
echo "💾 DISK SPACE:"
echo "--------------------------------------------------------------------------------"
DATA_SIZE=$(du -sh "$BASE_DIR/data/usage" 2>/dev/null | cut -f1)
REPORT_SIZE=$(du -sh "$BASE_DIR/reports/usage" 2>/dev/null | cut -f1)
echo "Data directory:   $DATA_SIZE"
echo "Report directory: $REPORT_SIZE"
echo ""

echo "================================================================================"
echo ""
echo "💡 USEFUL COMMANDS:"
echo ""
echo "  # Watch live collection"
echo "  tail -f $BASE_DIR/logs/collector.log"
echo ""
echo "  # Force collection now"
echo "  $BASE_DIR/scripts/collect-usage.sh"
echo ""
echo "  # Generate summary manually"
echo "  $BASE_DIR/scripts/daily-usage-summary.sh --show"
echo ""
echo "  # View cron jobs"
echo "  crontab -l"
echo ""
echo "================================================================================"
