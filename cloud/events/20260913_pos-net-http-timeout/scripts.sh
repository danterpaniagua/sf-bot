#!/usr/bin/env bash
# Event: 20260913_pos-net-http-timeout
# Commands are grouped by phase: Investigation / Audit / Remediation
# All commands below are read-only. No state-changing action was executed during this investigation.

# === INVESTIGATION ===

# C1 — App Insights sanity check (Pos-PRO, unfiltered requests)
az monitor app-insights query \
  --app SmartFran-Cloud-Pos-PRO_new -g SmartFran.Cloud.PRO \
  --subscription 85c76dea-3304-4310-8656-bf21b28e4f4b \
  --analytics-query "requests | where timestamp > ago(6h) | take 5" \
  --output table \
  > data/pos_requests_sanity.txt 2>&1

# C2 — Azure CLI auth/subscription sanity check
az account show --output table \
  > data/account_check.txt 2>&1

# C3 — Load Balancer inventory check (subscription-wide)
az network lb list --subscription 85c76dea-3304-4310-8656-bf21b28e4f4b \
  --query "[].{Name:name, RG:resourceGroup}" --output table \
  > data/lb_check.txt

# C4 — Application Gateway inventory check (subscription-wide)
az network application-gateway list --subscription 85c76dea-3304-4310-8656-bf21b28e4f4b \
  --query "[].{Name:name, RG:resourceGroup}" --output table \
  > data/appgw_check.txt

# C5 — App Insights instrumentation key config on Pos-PRO App Service
az webapp config appsettings list \
  --name SmartFran-Cloud-Pos-PRO --resource-group SmartFran.Cloud.PRO \
  --subscription 85c76dea-3304-4310-8656-bf21b28e4f4b \
  --query "[?contains(name, 'APPINSIGHTS') || contains(name, 'APPLICATIONINSIGHTS')]" \
  --output table \
  > data/pos_appinsights_config.txt

# C6 — List all App Insights components in the shared services RG
az monitor app-insights component show \
  --resource-group SmartFran.Cloud.PRO \
  --subscription 85c76dea-3304-4310-8656-bf21b28e4f4b \
  --query "[].{Name:name, InstrumentationKey:instrumentationKey}" \
  --output table \
  > data/appinsights_components_list.txt

# C7 — Sales-PRO platform metrics, 6h (corrected metric names, explicit end-time)
az monitor metrics list \
  --resource "/subscriptions/85c76dea-3304-4310-8656-bf21b28e4f4b/resourceGroups/SmartFran.Cloud.PRO/providers/Microsoft.Web/sites/SmartFran-Cloud-Sales-PRO" \
  --metric "Http5xx" "AverageResponseTime" "InstanceCount" "Threads" "MemoryWorkingSet" \
  --interval PT15M --start-time <6h-ago> --end-time <now> \
  --output json \
  > data/sales_platform_metrics_6h_v2.json

# C8 — Business-PRO platform metrics, 6h (corrected metric names, explicit end-time)
az monitor metrics list \
  --resource "/subscriptions/85c76dea-3304-4310-8656-bf21b28e4f4b/resourceGroups/SmartFran.Cloud.PRO/providers/Microsoft.Web/sites/SmartFran-Cloud-Business-PRO" \
  --metric "Http5xx" "AverageResponseTime" "InstanceCount" "Threads" "MemoryWorkingSet" \
  --interval PT15M --start-time <6h-ago> --end-time <now> \
  --output json \
  > data/business_platform_metrics_6h_v2.json

# C9 — App Insights exceptions table, Sales-PRO, 48h (returned 0 results)
az monitor app-insights query \
  --app SmartFran-Cloud-Sales-PRO_new -g SmartFran.Cloud.PRO \
  --subscription 85c76dea-3304-4310-8656-bf21b28e4f4b \
  --analytics-query "exceptions | where timestamp > ago(48h) | project timestamp, type, outerMessage, method, cloud_RoleInstance | order by timestamp desc | take 100" \
  --output table \
  > data/sales_exceptions_48h.txt

# C10 — Sales-PRO Windows Event Log via Kudu VFS (ANCM/IIS worker-process lifecycle, dbghost crash-dump pointers)
TOKEN=$(az account get-access-token --resource https://management.azure.com/ --query accessToken -o tsv)
curl -s -H "Authorization: Bearer $TOKEN" \
  "https://smartfran-cloud-sales-pro.scm.azurewebsites.net/api/vfs/LogFiles/eventlog.xml" \
  > data/sales_eventlog.xml

# C11 — Sales-PRO deployment history
az webapp log deployment list \
  --name SmartFran-Cloud-Sales-PRO --resource-group SmartFran.Cloud.PRO \
  --subscription 85c76dea-3304-4310-8656-bf21b28e4f4b \
  --query "[].{Time:end_time, Status:status_text, Message:message, Author:author}" \
  --output table \
  > data/sales_deployments.txt

# C12 — App Insights dependencies, Sales-PRO, fiscal webservice targets around crash onset (returned 0 results)
az monitor app-insights query \
  --app SmartFran-Cloud-Sales-PRO_new -g SmartFran.Cloud.PRO \
  --subscription 85c76dea-3304-4310-8656-bf21b28e4f4b \
  --analytics-query "dependencies | where timestamp between (datetime(2026-09-12T20:00:00Z) .. datetime(2026-09-13T06:00:00Z)) and target contains 'WsFe' | summarize count(), avg(duration), max(duration), failed=countif(success==false) by bin(timestamp, 15m), target | order by timestamp asc" \
  --output table \
  > data/sales_fiscal_dependencies_onset.txt

# C13 — Azure App Service Diagnostics detectors list (Sales-PRO) — used to find the correct crash detector id
TOKEN=$(az account get-access-token --resource https://management.azure.com/ --query accessToken -o tsv)
curl -s -H "Authorization: Bearer $TOKEN" \
  "https://management.azure.com/subscriptions/85c76dea-3304-4310-8656-bf21b28e4f4b/resourceGroups/SmartFran.Cloud.PRO/providers/Microsoft.Web/sites/SmartFran-Cloud-Sales-PRO/detectors?api-version=2022-03-01" \
  > data/sales_detectors_list.json

# C14 — ★ ROOT CAUSE CONFIRMATION: Proactive Crash Monitoring detector (appcrashes), Sales-PRO
TOKEN=$(az account get-access-token --resource https://management.azure.com/ --query accessToken -o tsv)
END=<now-minus-20min>
curl -s -H "Authorization: Bearer $TOKEN" \
  "https://management.azure.com/subscriptions/85c76dea-3304-4310-8656-bf21b28e4f4b/resourceGroups/SmartFran.Cloud.PRO/providers/Microsoft.Web/sites/SmartFran-Cloud-Sales-PRO/detectors/appcrashes?api-version=2022-03-01&startTime=2026-09-13T00:00:00Z&endTime=${END}" \
  > data/sales_appcrashes.json

# C15 — Graylog: smartfran-pos-wasm sanity check + sample messages (SFC-PosWasmRelay-PRO stream)
curl -s -u "$GRAYLOG_API_KEY:token" \
  "https://sfcloud-monitoreo.smartfran.com/graylog/api/search/universal/relative?query=Service%3A%22smartfran-pos-wasm%22&range=21600&limit=5" \
  -H 'Accept: application/json' \
  > data/graylog_poswasm_sanity_v2.json

# C16 — ★ Graylog: client-side HTTP failures from Pos.Wasm's HttpLoggingHandler, 24h (3,005 total matches)
curl -s -u "$GRAYLOG_API_KEY:token" \
  --data-urlencode 'query=Service:"smartfran-pos-wasm" AND SourceContext:"SmartFran.Cloud.Pos.Wasm.Handlers.HttpLoggingHandler" AND AppLevel:(Warning OR Error)' \
  --data-urlencode 'range=86400' --data-urlencode 'limit=200' \
  --data-urlencode 'fields=timestamp,TenantId,message,AppLevel' \
  -G "https://sfcloud-monitoreo.smartfran.com/graylog/api/search/universal/relative" \
  -H 'Accept: application/json' \
  > data/graylog_poswasm_httpfailures_24h.json

# C17 — Graylog: StatusCode 5xx check on smartfran-pos-wasm, 24h (0 results — confirms timeouts never reach a response status)
curl -s -u "$GRAYLOG_API_KEY:token" \
  --data-urlencode 'query=Service:"smartfran-pos-wasm" AND StatusCode:[500 TO 599]' \
  --data-urlencode 'range=86400' --data-urlencode 'limit=500' \
  --data-urlencode 'fields=timestamp,TenantId,StatusCode,Path,Method,ElapsedMilliseconds' \
  -G "https://sfcloud-monitoreo.smartfran.com/graylog/api/search/universal/relative" \
  -H 'Accept: application/json' \
  > data/graylog_poswasm_5xx_24h.json

# C18 — ARM: list live instances for Sales-PRO App Service
TOKEN=$(az account get-access-token --resource https://management.azure.com/ --query accessToken -o tsv)
curl -s -H "Authorization: Bearer $TOKEN" \
  "https://management.azure.com/subscriptions/85c76dea-3304-4310-8656-bf21b28e4f4b/resourceGroups/SmartFran.Cloud.PRO/providers/Microsoft.Web/sites/SmartFran-Cloud-Sales-PRO/instances?api-version=2022-03-01" \
  > data/sales_instances_list.json

# C19 — ★ Azure Monitor: autoscale settings for the Sales App Service Plan resource group
az monitor autoscale list \
  --resource-group SmartFran.Cloud.PRO \
  --subscription 85c76dea-3304-4310-8656-bf21b28e4f4b \
  --output json \
  > data/sales_autoscale_settings.json

# C20 — Graylog: Sales-PRO server-side direct-GELF logs, narrow window bracketing the confirmed crash
curl -s -u "$GRAYLOG_API_KEY:token" \
  --data-urlencode 'query=Service:"Sales" AND Environment:"Production"' \
  --data-urlencode 'from=2026-09-13T23:54:00.000Z' --data-urlencode 'to=2026-09-13T23:56:30.000Z' \
  --data-urlencode 'limit=500' \
  -G "https://sfcloud-monitoreo.smartfran.com/graylog/api/search/universal/absolute" \
  -H 'Accept: application/json' \
  > data/graylog_sales_serverside_crash_gap.json

# C21 — Graylog: Sales-PRO server-side logs, continuation window (23:56:25-23:57:40)
curl -s -u "$GRAYLOG_API_KEY:token" \
  --data-urlencode 'query=Service:"Sales" AND Environment:"Production"' \
  --data-urlencode 'from=2026-09-13T23:56:25.000Z' --data-urlencode 'to=2026-09-13T23:57:40.000Z' \
  --data-urlencode 'limit=500' \
  -G "https://sfcloud-monitoreo.smartfran.com/graylog/api/search/universal/absolute" \
  -H 'Accept: application/json' \
  > data/graylog_sales_serverside_actual_gap.json

# C22 — ★ Graylog: direct TraceKey correlation proof (client-side failure vs. total absence server-side)
curl -s -u "$GRAYLOG_API_KEY:token" \
  --data-urlencode 'query=TraceKey:"SFCPOS.POS:356.2026-09-13T23:55:45.7570000+00:00"' \
  --data-urlencode 'range=86400' --data-urlencode 'limit=50' \
  -G "https://sfcloud-monitoreo.smartfran.com/graylog/api/search/universal/relative" \
  -H 'Accept: application/json' \
  > data/graylog_specific_tracekey_check.json

# C23 — Graylog Views Search: pivot ElapsedMilliseconds by Path, 10m buckets, 3d
# (first attempt, wrong stream — PROD-Sales-AppServicePlan, 6a47c5c94b3c88a95fad7a7a)
# Resultado: solo 32 matches en 3d — investigado, ver C24-C26.
# (full 3-call views/search create+execute+poll sequence, see chat/data files)
> data/sales_timetaken_by_path_3d_10m_createsearch_raw.json
> data/sales_timetaken_by_path_3d_10m_execute_raw.json
> data/sales_timetaken_by_path_3d_10m.json   # (superseded by C26, same filename re-run)

# C24 — Diagnostic counts on wrong stream: total / _exists_:ElapsedMilliseconds / _exists_:Path, 3d
> data/diag_sales_total_3d.json          # 1.300.402 mensajes totales
> data/diag_sales_elapsedms_only_3d.json # 32 con ElapsedMilliseconds
> data/diag_sales_path_only_3d.json      # 615.557 con Path

# C25 — Sanity count on correct stream (PROD-Sales-AppServiceHTTPLogs, 6a8edd694814bcaed323f9d6)
> data/diag_sales_httplogs_stream_count_3d.json  # 21.943 matches, confirma stream correcto

# C26 — ★ Pivot re-ejecutado contra el stream correcto: ElapsedMilliseconds por Path, 10m, 3d
> data/sales_timetaken_by_path_3d_10m.json
> data/sales_timetaken_by_path_3d_10m.csv  # 823 filas — todas 2026-09-14T10:10 a 15:10 (-03:00), ver investigation.md

# C27 — Diagnóstico: campos anidados properties.CsUriStem/properties.TimeTaken, ventana del crash — 0 resultados
> data/diag_raw_nested_fields_crashwindow.json

# C28 — Diagnóstico: total de mensajes sin filtro + muestra cruda, mismo stream/ventana
> data/diag_stream_total_crashwindow.json   # 314.915 mensajes totales
> data/diag_stream_samplemsg_crashwindow.json  # confirma properties como string JSON sin parsear

# C29 — Test del endpoint de export CSV de Graylog (1 minuto, formato validado)
> data/diag_export_test_1min.csv

# C30 — ★ Export completo 3d (raw properties) + parseo/agregación local en Python (bypassea la promoción rota)
> data/sales_httplogs_raw_export_3d.csv        # 595.472 filas crudas
> data/sales_timetaken_by_path_3d_10m_RAW.csv  # 9.066 filas agregadas — cubre la ventana real del incidente, ver investigation.md

# C31 — ★ Live recheck (2026-09-14): CPU/RAM for Sales-PRO, site + plan level, last 6h
# Resultado: confirma recurrencia activa del crash-loop OOM — 3 ciclos completos en
# la ventana, pico de MemoryWorkingSet ~2.27GB a las 20:35Z (mayor al pico previo de
# 1.62GB confirmado el 13/09). Ver investigation.md "Live recurrence confirmed".
> data/sales_site_metrics_live_recheck.json
> data/sales_plan_metrics_live_recheck.json

# C32 — Live recheck (2026-09-14): eventlog.xml (vacío, probablemente rotado) + detector appcrashes
# Resultado: ★ 9 crashes confirmados hoy (0xE0434352, mismo código que el OOM original),
# 8 nuevos en ~6h (16:05-22:20Z) vs 7 en todo el día del 13/09 — confirma recurrencia peor.
# Cada crash coincide exactamente con un pico de memoria/CPU/response-time/Http5xx ya
# identificado en el recheck de métricas. Ver investigation.md.
> data/sales_eventlog_live_recheck.xml
> data/sales_appcrashes_live_recheck.json

# C33 — az appservice plan show: SKU de Sales-Plan-PRO
# Resultado: P2v3 (PremiumV3, MediumV3) — 4 vCPU/16GiB nominal por instancia (no verificado
# contra docs esta sesión). currentNumberOfWorkers=2, contradice los 4 confirmados el 13/09.
> data/sales_plan_sku.json

# C34 — az monitor autoscale list: recheck de configuración de autoscaling, todos los planes PRO
# Resultado: ★ SmartFran-Cloud-Sales-Plan-PRO reducido de 4/4/4 a 3/3/3 en los perfiles fijos
# ("Profile 1"/"Profile 2") desde el 13/09 — cambio de configuración real, agrava el incidente.
> data/sales_autoscale_settings_live_recheck.json

# C35 — GET sites/instances: recheck de instancias vivas de Sales-PRO
# Resultado: 2 instancias READY (wn1mdwk000UZZ, wn0mdwk000SK3) — por debajo incluso del
# nuevo techo fijo de 3.
> data/sales_instances_live_recheck.json

# C36 — Re-export raw 3d+ (ventana extendida hasta ahora) y regeneración del reporte Altair
# con barra de zoom horizontal + los 8 crashes nuevos del 14/09 como marcadores verticales.
# Resultado: 660.403 filas crudas; 11.897 filas agregadas (split por referer/status);
# 110 filas bucket/path dentro de 5s del techo de 230.000ms del LB de Azure.
> data/sales_httplogs_raw_export_3d.csv
> data/report_build_log.txt
# Genera: data/timetaken_by_path_aggregated.csv, data/timetaken_report.html
python3 /home/dpaniagua/Documentos/git/bots/cloud/events/20260913_pos-net-http-timeout/graylog_timetaken_report.py \
  --raw-csv /home/dpaniagua/Documentos/git/bots/cloud/events/20260913_pos-net-http-timeout/data/sales_httplogs_raw_export_3d.csv \
  --stream-id 6a8edd694814bcaed323f9d6 --from x --to x \
  --output-dir /home/dpaniagua/Documentos/git/bots/cloud/events/20260913_pos-net-http-timeout/data \
  > /home/dpaniagua/Documentos/git/bots/cloud/events/20260913_pos-net-http-timeout/data/report_build_log.txt 2>&1

# C37 — Fix real bug in graylog_timetaken_report.py: zoom bar drag had zero effect on
# the other 4 charts. Root cause (confirmed via headless-Chrome/Playwright inspection of
# the compiled low-level Vega spec, not guesswork): a per-child scale(domain=brush)
# binding gets silently discarded when that chart is layered (`+`) with siblings sharing
# the same x field — Vega-Lite recomputes a plain union-of-data-extents domain instead.
# Fix: apply the domain-bound X once at the combined-layer level (`.encode(x=zoomed_x)`
# on the whole `a + b + c` object), keeping any x-less sibling (the "ceiling" rule,
# which must stay full-width) OUTSIDE that group. Verified via a real simulated mouse
# drag in headless Chrome (axis labels before/after differ) — not just a compile check.
# Also: moved the zoom bar below the 3 upper charts, and set the heatmap to a fixed
# threshold color scale (<600 green, 600-2000 yellow, >=2000 red) instead of proportional.
python3 /home/dpaniagua/Documentos/git/bots/cloud/events/20260913_pos-net-http-timeout/graylog_timetaken_report.py \
  --raw-csv /home/dpaniagua/Documentos/git/bots/cloud/events/20260913_pos-net-http-timeout/data/sales_httplogs_raw_export_3d.csv \
  --stream-id 6a8edd694814bcaed323f9d6 --from x --to x \
  --output-dir /home/dpaniagua/Documentos/git/bots/cloud/events/20260913_pos-net-http-timeout/data \
  > /home/dpaniagua/Documentos/git/bots/cloud/events/20260913_pos-net-http-timeout/data/report_build_log.txt 2>&1

# C38 — Response-code chart: replace category10 palette with explicit per-family shade
# scale (200-399 green gradient, 400-499 amber gradient, 500-599 red gradient), each
# observed code graded lightest->darkest within its family. Verified against the
# compiled spec's actual domain/range (11 real codes: 200,201,204,210,400,401,403,
# 408,424,500,503).
python3 /home/dpaniagua/Documentos/git/bots/cloud/events/20260913_pos-net-http-timeout/graylog_timetaken_report.py \
  --raw-csv /home/dpaniagua/Documentos/git/bots/cloud/events/20260913_pos-net-http-timeout/data/sales_httplogs_raw_export_3d.csv \
  --stream-id 6a8edd694814bcaed323f9d6 --from x --to x \
  --output-dir /home/dpaniagua/Documentos/git/bots/cloud/events/20260913_pos-net-http-timeout/data \
  > /home/dpaniagua/Documentos/git/bots/cloud/events/20260913_pos-net-http-timeout/data/report_build_log.txt 2>&1

# C39 — Heatmap avg_ms color: replace flat threshold (1 color per band) with a
# piecewise-linear gradient scale — light->dark within each band (0-600 green,
# 600-2000 amber, 2000+ red), hard edges at 600/2000 via near-duplicate domain
# stops. Verified against compiled spec: domain [0,600,600.001,2000,2000.001,
# 188415.2] (real observed max), clamp:true.
python3 /home/dpaniagua/Documentos/git/bots/cloud/events/20260913_pos-net-http-timeout/graylog_timetaken_report.py \
  --raw-csv /home/dpaniagua/Documentos/git/bots/cloud/events/20260913_pos-net-http-timeout/data/sales_httplogs_raw_export_3d.csv \
  --stream-id 6a8edd694814bcaed323f9d6 --from x --to x \
  --output-dir /home/dpaniagua/Documentos/git/bots/cloud/events/20260913_pos-net-http-timeout/data \
  > /home/dpaniagua/Documentos/git/bots/cloud/events/20260913_pos-net-http-timeout/data/report_build_log.txt 2>&1

# C40 — Add CPU/RAM panels to the Altair report. Pulled plan-level CpuPercentage/
# MemoryPercentage (Microsoft.Web/serverfarms/SmartFran-Cloud-Sales-Plan-PRO, PT5M,
# same 2026-09-11T18:20Z-now window as the Graylog export) so it's a % scale, not raw
# seconds/bytes. Both new panels share the same zoomed_x/brush/incident markers as
# every other panel (verified via a real simulated drag + domainRaw check).
# NOTE: first attempt regenerated the report from a stale/pre-CPU-RAM run — caught
# and fixed by actually re-running the script with --metrics-json after the pull.
> data/sales_cpu_ram_full_window.json
python3 /home/dpaniagua/Documentos/git/bots/cloud/events/20260913_pos-net-http-timeout/graylog_timetaken_report.py \
  --raw-csv /home/dpaniagua/Documentos/git/bots/cloud/events/20260913_pos-net-http-timeout/data/sales_httplogs_raw_export_3d.csv \
  --stream-id 6a8edd694814bcaed323f9d6 --from x --to x \
  --metrics-json /home/dpaniagua/Documentos/git/bots/cloud/events/20260913_pos-net-http-timeout/data/sales_cpu_ram_full_window.json \
  --output-dir /home/dpaniagua/Documentos/git/bots/cloud/events/20260913_pos-net-http-timeout/data \
  > /home/dpaniagua/Documentos/git/bots/cloud/events/20260913_pos-net-http-timeout/data/report_build_log.txt 2>&1

# C41 — Add min/max to CPU and RAM panels: shaded band between min/max (mark_area,
# opacity 0.15) + thin dashed min/max edge lines + the existing avg solid line, all
# per 10-min bucket. Re-verified zoom-link end-to-end with a real drag test (had to
# disambiguate the zoom bar's own area mark from the two new CPU/RAM band area marks
# in the test selector — 3 area-class elements now instead of 1 — same underlying
# domainRaw binding, unaffected).
python3 /home/dpaniagua/Documentos/git/bots/cloud/events/20260913_pos-net-http-timeout/graylog_timetaken_report.py \
  --raw-csv /home/dpaniagua/Documentos/git/bots/cloud/events/20260913_pos-net-http-timeout/data/sales_httplogs_raw_export_3d.csv \
  --stream-id 6a8edd694814bcaed323f9d6 --from x --to x \
  --metrics-json /home/dpaniagua/Documentos/git/bots/cloud/events/20260913_pos-net-http-timeout/data/sales_cpu_ram_full_window.json \
  --output-dir /home/dpaniagua/Documentos/git/bots/cloud/events/20260913_pos-net-http-timeout/data \
  > /home/dpaniagua/Documentos/git/bots/cloud/events/20260913_pos-net-http-timeout/data/report_build_log.txt 2>&1

# C42 — Correction: previous min/max for CPU/RAM panels was derived by re-aggregating
# only 2 already-averaged PT5M sub-samples per 10-min bucket in Python, not real Azure
# telemetry. Re-pulled with --aggregation Average Minimum Maximum so Azure reports true
# per-5-min min/max directly (e.g. real sample: CPU avg 15% but max 53% within one
# 5-min window — a burst the average-only pull completely hid). Rolled up into 10-min
# buckets as min-of-minimums / max-of-maximums (both genuine), mean-of-averages.
> data/sales_cpu_ram_full_window.json
python3 /home/dpaniagua/Documentos/git/bots/cloud/events/20260913_pos-net-http-timeout/graylog_timetaken_report.py \
  --raw-csv /home/dpaniagua/Documentos/git/bots/cloud/events/20260913_pos-net-http-timeout/data/sales_httplogs_raw_export_3d.csv \
  --stream-id 6a8edd694814bcaed323f9d6 --from x --to x \
  --metrics-json /home/dpaniagua/Documentos/git/bots/cloud/events/20260913_pos-net-http-timeout/data/sales_cpu_ram_full_window.json \
  --output-dir /home/dpaniagua/Documentos/git/bots/cloud/events/20260913_pos-net-http-timeout/data \
  > /home/dpaniagua/Documentos/git/bots/cloud/events/20260913_pos-net-http-timeout/data/report_build_log.txt 2>&1

# C43 — Generalized the report tooling for reuse across all 8 production App Services:
#   - graylog_timetaken_report.py moved to cloud/scripts/appservice_perf_report.py
#     (was living inside this one event's folder).
#   - DEFAULT_INCIDENTS (hardcoded Sales-PRO crash list) externalized to incidents.txt
#     alongside this file — script now takes --incidents-file (or --incident, repeatable).
#   - Added --app-label so chart titles aren't hardcoded to "Sales-PRO".
#   - New skill: cloud-appservice-perf-report (.claude/commands/), with the per-app
#     stream-id/App-Service/Plan reference table and the 3-step workflow.
# Regenerated this event's report from the new location — output unchanged (7 panels,
# same data), confirmed via panel-title/structure check.
python3 /home/dpaniagua/Documentos/git/bots/cloud/scripts/appservice_perf_report.py \
  --raw-csv /home/dpaniagua/Documentos/git/bots/cloud/events/20260913_pos-net-http-timeout/data/sales_httplogs_raw_export_3d.csv \
  --stream-id 6a8edd694814bcaed323f9d6 --from x --to x \
  --app-label Sales-PRO \
  --metrics-json /home/dpaniagua/Documentos/git/bots/cloud/events/20260913_pos-net-http-timeout/data/sales_cpu_ram_full_window.json \
  --incidents-file /home/dpaniagua/Documentos/git/bots/cloud/events/20260913_pos-net-http-timeout/incidents.txt \
  --output-dir /home/dpaniagua/Documentos/git/bots/cloud/events/20260913_pos-net-http-timeout/data \
  > /home/dpaniagua/Documentos/git/bots/cloud/events/20260913_pos-net-http-timeout/data/report_build_log.txt 2>&1

# C44 — Live refresh: fresh Graylog fetch (raw_export.csv, 478MB) + fresh Azure CPU/RAM
# pull (Average/Minimum/Maximum), report rebuilt from both. 13,236 aggregated rows
# (up from 11,897), 111 bucket/path rows within 5s of the 230s Azure ceiling (up from
# 110) — recurrence still active as of this refresh.
python3 /home/dpaniagua/Documentos/git/bots/cloud/scripts/appservice_perf_report.py \
  --raw-csv /home/dpaniagua/Documentos/git/bots/cloud/events/20260913_pos-net-http-timeout/data/raw_export.csv \
  --stream-id 6a8edd694814bcaed323f9d6 --from x --to x \
  --app-label Sales-PRO \
  --metrics-json /home/dpaniagua/Documentos/git/bots/cloud/events/20260913_pos-net-http-timeout/data/sales_cpu_ram_full_window.json \
  --incidents-file /home/dpaniagua/Documentos/git/bots/cloud/events/20260913_pos-net-http-timeout/incidents.txt \
  --output-dir /home/dpaniagua/Documentos/git/bots/cloud/events/20260913_pos-net-http-timeout/data \
  > /home/dpaniagua/Documentos/git/bots/cloud/events/20260913_pos-net-http-timeout/data/report_build_log.txt 2>&1
