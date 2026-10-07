#!/usr/bin/env bash
# Event: 20260917_smartpedidos-peru-orders-pending (GITIN-2068)
# Checking deployment history for TODAY (2026-09-17) across every known
# SmartFran Cloud App Service / Function App, to locate the 06:00 ART
# deploy the user mentioned, which is not present for Orders-PRO.

SUB=85c76dea-3304-4310-8656-bf21b28e4f4b
RG=SmartFran.Cloud.PRO
OUT=/home/dpaniagua/Documentos/git/bots/cloud/events/20260917_smartpedidos-peru-orders-pending/data/all_services_deploys_today.txt

> "$OUT"

WEBAPPS="SmartFran-Cloud-Admin-PRO SmartFran-Cloud-Business-PRO SmartFran-Cloud-Catalog-PRO SmartFran-Cloud-Orders-PRO SmartFran-Cloud-Person-PRO SmartFran-Cloud-Platform-PRO SmartFran-Cloud-Pos-PRO SmartFran-Cloud-Sales-PRO"
FUNCAPPS="SFC-CodeGenerator-PRO SFC-ScheduledJobs-PRO SFC-TicketProcess-PRO SFC-PosWasmRelay-PRO"

for app in $WEBAPPS; do
  echo "=== $app (production slot) ===" >> "$OUT"
  az webapp log deployment list --name "$app" --resource-group "$RG" --subscription "$SUB" \
    --query "[?starts_with(start_time, '2026-09-17')].{start:start_time,end:end_time,active:active}" \
    -o json >> "$OUT" 2>>"$OUT"
done

for app in $FUNCAPPS; do
  echo "=== $app (function app) ===" >> "$OUT"
  az functionapp log deployment list --name "$app" --resource-group "$RG" --subscription "$SUB" \
    --query "[?starts_with(start_time, '2026-09-17')].{start:start_time,end:end_time,active:active}" \
    -o json >> "$OUT" 2>>"$OUT"
done
