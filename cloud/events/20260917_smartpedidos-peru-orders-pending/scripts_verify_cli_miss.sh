#!/usr/bin/env bash
# Event: 20260917_smartpedidos-peru-orders-pending (GITIN-2068)
# Diagnosing WHY az monitor activity-log list missed the confirmed 06:08-
# 06:11 ART swap in 3 earlier attempts. Testing with a narrow window first
# (rules out simple truncation if it's still missing), then checking the
# raw, unfiltered count for a wider window to see if truncation is even
# plausible (does total entry count exceed any typical default page size).

# C26 — narrow window, exactly around the confirmed swap, no filtering at
# all (just count total entries returned)
az monitor activity-log list \
  --resource-group SmartFran.Cloud.PRO \
  --subscription 85c76dea-3304-4310-8656-bf21b28e4f4b \
  --start-time 2026-09-17T09:00:00Z \
  --end-time 2026-09-17T09:20:00Z \
  --query "length([])" \
  -o tsv \
  > data/cli_narrow_window_count.txt
cat data/cli_narrow_window_count.txt

# C27 — same narrow window, check specifically for the swap operation
az monitor activity-log list \
  --resource-group SmartFran.Cloud.PRO \
  --subscription 85c76dea-3304-4310-8656-bf21b28e4f4b \
  --start-time 2026-09-17T09:00:00Z \
  --end-time 2026-09-17T09:20:00Z \
  --query "[].{time:eventTimestamp, operation:operationName.value, resourceId:resourceId}" \
  -o json \
  > data/cli_narrow_window_swap_check.json
cat data/cli_narrow_window_swap_check.json

# C28 — total raw entry count for the full day (no resource/type filter at
# all) -- if this number is very large, it's plausible the CLI or the
# underlying API silently caps/paginates and my earlier broader queries
# just never paged deep enough
az monitor activity-log list \
  --resource-group SmartFran.Cloud.PRO \
  --subscription 85c76dea-3304-4310-8656-bf21b28e4f4b \
  --start-time 2026-09-17T00:00:00Z \
  --end-time 2026-09-17T23:59:59Z \
  --query "length([])" \
  -o tsv \
  > data/cli_full_day_count.txt
cat data/cli_full_day_count.txt
