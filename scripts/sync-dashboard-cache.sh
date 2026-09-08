#!/bin/bash
# Auto-sync CIPP Dashboard cache for all tenants
# Runs via cron every 4 hours
set -euo pipefail

LOG="/var/log/cipp-dashboard-sync.log"
SYNC_SCRIPT="/opt/M365-MTM/CIPP-API/scripts/Sync-DashboardData.ps1"

echo "=== $(date -u '+%Y-%m-%d %H:%M:%S UTC') Dashboard Sync ===" >> "$LOG"
/usr/bin/pwsh -NoProfile -File "$SYNC_SCRIPT" >> "$LOG" 2>&1
echo "=== Done ===" >> "$LOG"
