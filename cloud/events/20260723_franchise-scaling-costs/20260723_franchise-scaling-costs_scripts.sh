#!/bin/bash
# Evento: 20260723_franchise-scaling-costs
# Proyecto: cloud-graylog (validación de costos, no Terraform)
# Suscripción: SmartIT Cloud (85c76dea-3304-4310-8656-bf21b28e4f4b)

# === C1 — Tamaño real por evento (Log Analytics, _BilledSize) ===
az monitor log-analytics query \
  --workspace 76536d4a-5616-44ae-bee4-0aa6963b5d28 \
  --analytics-query "
    union AppServiceConsoleLogs, AppServiceHTTPLogs, AppServiceAppLogs, AppServicePlatformLogs
    | where TimeGenerated > ago(7d)
    | summarize AvgBytes=avg(_BilledSize), TotalBytes=sum(_BilledSize), Count=count() by Type
    | order by TotalBytes desc
  " \
  --output table
# OUTPUT (2026-07-23):
# AppServiceConsoleLogs   avg=167.78 bytes   count=190.770.704   total=32.006.861.628 bytes
# AppServiceAppLogs       avg=229.14 bytes   count=92.707.647    total=21.242.982.404 bytes
# AppServiceHTTPLogs      avg=494.71 bytes   count=5.738.015     total=2.838.660.610 bytes
# AppServicePlatformLogs  avg=146.16 bytes   count=1.136         total=166.037 bytes
# Ratio ponderado: ~194 bytes/evento (crudo, pre-pipeline — no usado como final, ver C2)

# === C2 — Tamaño real indexado en OpenSearch (ejecutado en sfcloud-monitoreo) ===
curl -s "http://127.0.0.1:9200/_cat/indices?v&bytes=gb&h=index,docs.count,store.size" | sort -k3 -h -r
# OUTPUT (2026-07-23):
# business__2   54.146.780 docs   21 GB
# business__1   53.060.355 docs   21 GB
# business__4   52.580.879 docs   20 GB
# business__3   46.765.263 docs   18 GB
# business__5   11.153.847 docs    4 GB
# sales__1       8.559.508 docs    5 GB
# sales__0       8.585.832 docs    5 GB
# sales__2          99.145 docs    0 GB
# (graylog_0/graylog_1, top_queries-*, gl-*, .plugins-ml-config excluidos — índices internos, no logs de apps)
#
# Business total: 217.707.124 docs / 84 GB -> ~414 bytes/doc
# Sales total:     17.244.485 docs / 10 GB -> ~623 bytes/doc
# Combinado:      234.951.609 docs / 94 GB -> ~429,5 bytes/evento (real, usado en la proyección)

# === C3 — Utilización real de RAM/heap (ejecutado en sfcloud-monitoreo) ===
free -h
curl -s "http://127.0.0.1:9200/_nodes/stats/jvm,os,process?pretty" | grep -E "heap_used_percent|\"percent\"|load_average"
# OUTPUT (2026-07-23):
# Mem: total=31Gi used=20Gi free=609Mi buff/cache=11Gi available=11Gi
# Swap: 0B (sin swap en uso)
# heap_used_percent: 53
# -> VM D8s (32GB RAM), sirviendo Sales+Business (~74% del volumen de flota por proxy), sin señales de estrés

# === C4 — Precios reales Premium SSD Managed Disks (East US) ===
curl -s "https://prices.azure.com/api/retail/prices?\$filter=serviceName%20eq%20%27Storage%27%20and%20armRegionName%20eq%20%27eastus%27" \
  | jq -r '.Items[] | select(.productName == "Premium SSD Managed Disks" and .type == "Consumption" and (.meterName | test("^P(20|30|40|50|60) LRS Disk$"))) | "\(.meterName) | \(.retailPrice)"'
# OUTPUT (2026-07-23):
# P20 LRS Disk | 73.22
# P30 LRS Disk | 135.17   (coincide exacto con la estimación ya aprobada)
# P40 LRS Disk | 259.0457
# P50 LRS Disk | 495.5657
# P60 LRS Disk | 946.08

# === C5 — Precio real Event Hubs Standard/Basic/Premium/Dedicated (East US) ===
curl -s "https://prices.azure.com/api/retail/prices?\$filter=serviceName%20eq%20%27Event%20Hubs%27%20and%20armRegionName%20eq%20%27eastus%27" \
  | jq -r '.Items[] | "\(.skuName) | \(.meterName) | \(.retailPrice) | \(.unitOfMeasure)"' | sort -u
# OUTPUT (2026-07-23):
# Basic     | Basic Throughput Unit    | 0.015 | 1 Hour
# Standard  | Standard Throughput Unit | 0.03  | 1 Hour   <- $21,90/mes real (730h), NO ~$11/mes usado en CG-003
# Premium   | Premium Processing Unit  | 1.027 | 1 Hour
# Dedicated | Dedicated Capacity Unit  | 6.849 | 1 Hour
# Standard  | Standard Ingress Events  | 0.028 | (sin cambio, ya era correcto)

# === C6 — Precio real E16s_v5 / E16s_v6 (Linux, Consumption, no Spot/Low Priority) ===
curl -s "https://prices.azure.com/api/retail/prices?\$filter=serviceName%20eq%20%27Virtual%20Machines%27%20and%20armRegionName%20eq%20%27eastus%27%20and%20(armSkuName%20eq%20%27Standard_E16s_v5%27%20or%20armSkuName%20eq%20%27Standard_E16s_v6%27)" \
  | jq -r '.Items[] | select(.type=="Consumption") | "\(.armSkuName) | \(.skuName) | \(.productName) | \(.retailPrice)"' | sort -u
# OUTPUT (2026-07-23):
# Standard_E16s_v5 | E16s v5              | Virtual Machines Esv5 Series | 1.008     -> $736,00/mes (CONFIRMADO correcto)
# Standard_E16s_v5 | E16s v5 Low Priority | Virtual Machines Esv5 Series | 0.202     (no apto para producción)
# Standard_E16s_v5 | E16s v5 Spot         | Virtual Machines Esv5 Series | 0.212285  (no apto para producción)
# Standard_E16s_v6 | E16s v6              | Virtual Machines Esv6 Series | 1.058     -> $772,34/mes si fuera v6

# === C7 — Precio real Log Analytics (Analytics Logs) ===
curl -s "https://prices.azure.com/api/retail/prices?\$filter=serviceName%20eq%20%27Log%20Analytics%27%20and%20armRegionName%20eq%20%27eastus%27" \
  | jq -r '.Items[] | "\(.skuName) | \(.meterName) | \(.retailPrice) | \(.unitOfMeasure)"' | sort -u
# OUTPUT (2026-07-23):
# Analytics Logs | Analytics Logs Data Analyzed  | 2.3 | 1 GB   (coincide con tarifa ya usada)
# Analytics Logs | Analytics Logs Data Retention | 0.1 | 1 GB/Month (solo aplica más allá de retención incluida)
# Sin meters de "commitment tier" (100/200/300GB por día) encontrados en esta consulta

# === C8 — Intento de desglose por meter vía CLI (falló) ===
az extension add --name costmanagement --upgrade
az costmanagement query \
  --scope /subscriptions/85c76dea-3304-4310-8656-bf21b28e4f4b \
  --type ActualCost \
  --timeframe TheLastMonth \
  --dataset-filter "{\"and\":[{\"dimensions\":{\"name\":\"ResourceId\",\"operator\":\"Contains\",\"values\":[\"SmartFranCloudPro\"]}}]}" \
  --dataset-granularity None \
  --dataset-aggregation "{\"totalCost\":{\"name\":\"Cost\",\"function\":\"Sum\"}}" \
  --dataset-grouping name=Meter type=Dimension \
  --output table
# OUTPUT (2026-07-23):
# "'query' is misspelled or not recognized by the system."
# az costmanagement -h muestra solo: export, show-operation-result (extensión v1.0.0, sin soporte para query)
# Alternativa usada: Portal Azure, Cost Analysis, agrupado por Meter (ver C9)

# === C9 — Desglose real de facturación completa (Portal UI, agrupado por Meter) ===
# (no es un comando CLI — captura manual del Portal, ver _ops-events.md)
# OUTPUT (2026-07-23) — líneas relevantes:
# Log Analytics | Analytics Logs Data Ingestion | 525.5754291565   <- ÚNICO meter, sin "Data Analyzed" ni "Data Retention"
# Virtual Machines | D8s v6 | 216.357326848                        <- VM Graylog real, aún tamaño pilot
# Storage | P6 LRS Disk | 13.4203609344
# Storage | P10 LRS Disk | 12.95745024
# Event Hubs | Standard Throughput Unit | 15.6                     <- consistente con tarifa corregida ($0,03/h)

# === C10 — Retención real configurada del workspace ===
az monitor log-analytics workspace show \
  --resource-group SmartFran.Cloud.PRO \
  --workspace-name SmartFranCloudPro \
  --subscription 85c76dea-3304-4310-8656-bf21b28e4f4b \
  --query "{retentionInDays:retentionInDays, sku:sku.name}" \
  --output table
# OUTPUT (2026-07-23):
# RetentionInDays: 30   Sku: pergb2018

# === C11 — Utilización real semanal (Zabbix, host sfcloud-monitoreo) ===
# (no es un comando CLI — captura manual del dashboard Zabbix, ver _ops-events.md)
# OUTPUT (2026-07-23) — semana en curso:
# CPU utilization: avg 3%   max 31%
# Memory:          avg 63%  max 64%

# === C12 — Precios reales Azure Monitor (alertas, notificaciones, search jobs/queries) ===
curl -s "https://prices.azure.com/api/retail/prices?\$filter=serviceName%20eq%20%27Azure%20Monitor%27%20and%20armRegionName%20eq%20%27eastus%27" \
  | jq -r '.Items[] | "\(.productName) | \(.meterName) | \(.retailPrice) | \(.unitOfMeasure)"' | sort -u
# OUTPUT (2026-07-23) — líneas relevantes:
# Azure Monitor | Alerts Resource Monitored at 1/5/10/15 Minute Frequency | 0.10 a 0.30 | 1/Month
# Azure Monitor | Alerts System Log Monitored at 1/5/10/15 Minute Frequency | 0.50 a 3.00 | 1/Month
# Azure Monitor | Basic Logs Data Ingestion | 0.5 | 1 GB          <- tier distinto al usado hoy (pergb2018/Analytics Logs)
# Azure Monitor | Search Jobs Scanned | 0.005 | 1 GB              <- cobra por GB escaneado, pero solo en Search Jobs (Basic/Archive tier)
# Azure Monitor | Search Queries Scanned | 0.005 | 1 GB           <- idem, no aplica a consultas KQL interactivas sobre Analytics Logs
# Sin ningún meter de "dashboard" en toda la lista

# === C13 — Precio real de transformación/procesamiento de datos (Azure Monitor) ===
curl -s "https://prices.azure.com/api/retail/prices?\$filter=serviceName%20eq%20%27Azure%20Monitor%27%20and%20armRegionName%20eq%20%27eastus%27" \
  | jq -r '.Items[] | "\(.productName) | \(.meterName) | \(.retailPrice) | \(.unitOfMeasure)"' | sort -u \
  | grep -i -E "process|transform|collect|ingest|pipeline"
# OUTPUT (2026-07-23) — líneas relevantes:
# Azure Monitor | Logs Processed GB | 0.1 | 1                              <- meter real de transformaciones en ingesta (Data Collection Rule)
# Azure Monitor | Platform Logs Data Processed | 0.25 | 1 GB               <- procesamiento de Diagnostic Settings, no aplica a este caso
# Azure Monitor | Logs Emitted From Cloud Pipeline Data Emitted | 0.15 | 1 GB  <- pipeline custom -> Data Collection Endpoint, no aplica a este caso

# === C15 — Diagnostic Settings reales de Orders (verificación de cobertura de logs) ===
az monitor diagnostic-settings list \
  --resource "/subscriptions/85c76dea-3304-4310-8656-bf21b28e4f4b/resourceGroups/SmartFran.Cloud.PRO/providers/Microsoft.Web/sites/SmartFran-Cloud-Orders-PRO" \
  --subscription 85c76dea-3304-4310-8656-bf21b28e4f4b \
  --output table
# OUTPUT (2026-07-23): vacío — sin ningún Diagnostic Setting configurado.
# Orders no envía logs ni a Log Analytics ni a Graylog. Confirma que la excepción ya señalada
# en el email de 2026-06-25 ("Orders todavía no tiene logging configurado") sigue vigente hoy.

# === C14 — Precios reales de reserva de 1/3 años (VM, Storage, Event Hubs) ===
curl -s "https://prices.azure.com/api/retail/prices?\$filter=serviceName%20eq%20%27Virtual%20Machines%27%20and%20armRegionName%20eq%20%27eastus%27%20and%20(armSkuName%20eq%20%27Standard_E16s_v5%27%20or%20armSkuName%20eq%20%27Standard_E16s_v6%27)%20and%20type%20eq%20%27Reservation%27" \
  | jq -r '.Items[] | "\(.armSkuName) | \(.skuName) | \(.meterName) | \(.retailPrice) | \(.unitOfMeasure)"' | sort -u
curl -s "https://prices.azure.com/api/retail/prices?\$filter=serviceName%20eq%20%27Storage%27%20and%20armRegionName%20eq%20%27eastus%27%20and%20type%20eq%20%27Reservation%27" \
  | jq -r '.Items[] | select(.productName == "Premium SSD Managed Disks") | "\(.meterName) | \(.retailPrice) | \(.unitOfMeasure)"' | sort -u
curl -s "https://prices.azure.com/api/retail/prices?\$filter=serviceName%20eq%20%27Event%20Hubs%27%20and%20armRegionName%20eq%20%27eastus%27%20and%20type%20eq%20%27Reservation%27" \
  | jq -r '.Items[] | "\(.skuName) | \(.meterName) | \(.retailPrice) | \(.unitOfMeasure)"' | sort -u
# OUTPUT (2026-07-23):
# VM E16s_v5: 5210.0 (~1yr término) y 10464.0 (~3yr término) — equivalente mensual ~$434 (1yr), ~41% más barato que PAYG ($736)
# VM E16s_v6: 5748.0 y 10848.0 — mismo patrón
# Storage: reserva encontrada solo para P30 en adelante (P30 1541, P40 2953, P50 5650, P60 10785, P70 20544, P80 41087) — NINGUNA para P20, el tier real necesario (H2)
# Event Hubs: SIN RESULTADOS — no existe ningún SKU de reserva/compromiso para Event Hubs Standard

# === C16 — SKU/tamaño real de SFCG-WSV2-01 (SmartLoyalty, sub. Smart IT - Grido) — pendiente ===
az vm show \
  --resource-group DefaultGroup01 \
  --name SFCG-WSV2-01 \
  --subscription 0190fa7d-4ccf-4e3d-beb1-323b5780bfc8 \
  --query "{name:name, size:hardwareProfile.vmSize, location:location, osDisk:storageProfile.osDisk.managedDisk.storageAccountType}" \
  --output table

# OUTPUT (2026-07-27):
# SFCG-WSV2-01 | Standard_D8as_v5 | eastus | StandardSSD_LRS
# SFCG-WSV2-02 | Standard_D2ds_v4 | eastus
# Reveló que SFCG-WSV2-02 ya existía, no documentada en loyalty/docs/infrastructure.md (H17).
# Aclaración del usuario: SFCG-WSV2-02 nunca fue encendida — no es una secundaria on-demand,
# es un recurso provisto y nunca puesto en servicio real.

# === C17 — Precio PAYG real de SFCG-WSV2-01 (Standard_D8as_v5, eastus) ===
curl -s "https://prices.azure.com/api/retail/prices?\$filter=serviceName%20eq%20%27Virtual%20Machines%27%20and%20armRegionName%20eq%20%27eastus%27%20and%20armSkuName%20eq%20%27Standard_D8as_v5%27%20and%20priceType%20eq%20%27Consumption%27" \
  | jq -r '.Items[] | "\(.armSkuName) | \(.productName) | \(.meterName) | \(.retailPrice) | \(.unitOfMeasure)"' | sort -u
# OUTPUT (2026-07-27):
# Standard_D8as_v5 | Dasv5 Series Cloud Services | D8as v5 | 0.712 | 1 Hour
# Standard_D8as_v5 | Dasv5 Series Cloud Services | D8as v5 Low Priority | 0.285 | 1 Hour
# Standard_D8as_v5 | Virtual Machines Dasv5 Series | D8as v5 | 0.344 | 1 Hour                       <- Linux Regular
# Standard_D8as_v5 | Virtual Machines Dasv5 Series | D8as v5 Low Priority | 0.0688 | 1 Hour
# Standard_D8as_v5 | Virtual Machines Dasv5 Series | D8as v5 Spot | 0.072618 | 1 Hour
# Standard_D8as_v5 | Virtual Machines Dasv5 Series Windows | D8as v5 | 0.712 | 1 Hour                <- Windows Regular, usado (H17)
# Standard_D8as_v5 | Virtual Machines Dasv5 Series Windows | D8as v5 Low Priority | 0.285 | 1 Hour
# Standard_D8as_v5 | Virtual Machines Dasv5 Series Windows | D8as v5 Spot | 0.150303 | 1 Hour
# Usado: Windows Regular $0.712/hs x 730 hs/mes = $519.76/mes. SO Windows inferido por patrón de la
# flota SmartLoyalty (D:\/C:\, cuenta SMARTIT\itservices, DB en Windows Server 2022) — no confirmado
# por query directa (storageProfile.osDisk.osType), pendiente de confirmar.

# === C18 — Confirmar que SFCG-WSV2-02 nunca fue encendida + estado de power actual ===
az vm get-instance-view \
  --resource-group DefaultGroup01 \
  --name SFCG-WSV2-02 \
  --subscription 0190fa7d-4ccf-4e3d-beb1-323b5780bfc8 \
  --query "instanceView.statuses[?starts_with(code, 'PowerState/')].displayStatus" \
  --output tsv

az monitor activity-log list \
  --resource-group DefaultGroup01 \
  --subscription 0190fa7d-4ccf-4e3d-beb1-323b5780bfc8 \
  --offset 90d \
  --query "[?contains(resourceId, 'SFCG-WSV2-02') && (operationName.value=='Microsoft.Compute/virtualMachines/start/action' || operationName.value=='Microsoft.Compute/virtualMachines/deallocate/action')].{operation:operationName.value, status:status.value, time:eventTimestamp}" \
  --output table
# OUTPUT (2026-07-27): power state = "VM deallocated".
# La consulta con --offset 365d falló: (BadRequest) "The start time cannot be more than 90 days in
# the past" — límite duro de Azure Activity Log, no ajustable por flag.
#
# Reintento con --offset 90d (máximo permitido), OUTPUT real (2026-07-27):
#   Operation                                            Status     Time
#   deallocate/action                                    Succeeded  2026-07-27T16:57:01Z
#   deallocate/action                                    Accepted   2026-07-27T16:56:41Z
#   deallocate/action                                    Started    2026-07-27T16:56:41Z
# Sin ningún "start" en los 90 días — es decir, ya estaba corriendo desde antes de esa ventana.
# El usuario confirmó que él mismo deallocó la VM ~1 hora antes de reportar este resultado, como
# acción directa de esta investigación. CONTRADICE la hipótesis inicial de "nunca encendida":
# la VM corrió (facturando cómputo) de forma continua hasta hoy, sin aportar redundancia real.

# === C19 — Intento de obtener fecha de creación real de SFCG-WSV2-02 ===
az resource show \
  --resource-group DefaultGroup01 \
  --name SFCG-WSV2-02 \
  --resource-type "Microsoft.Compute/virtualMachines" \
  --subscription 0190fa7d-4ccf-4e3d-beb1-323b5780bfc8 \
  --api-version 2026-03-01 \
  --query "{created:systemData.createdAt, lastModified:systemData.lastModifiedAt}" \
  --output table
# OUTPUT (2026-07-27): vacío — systemData.createdAt no está poblado para este recurso.
# Resuelto igual: el usuario confirmó directamente que estuvo encendida ~3 días antes del
# deallocate de hoy.

# === C20 — SO real de SFCG-WSV2-02 (para aplicar la tarifa correcta) ===
az vm show \
  --resource-group DefaultGroup01 \
  --name SFCG-WSV2-02 \
  --subscription 0190fa7d-4ccf-4e3d-beb1-323b5780bfc8 \
  --query "storageProfile.osDisk.osType" \
  --output tsv
# OUTPUT (2026-07-27): Windows

# === C21 — Precio real PAYG de D2ds_v4 (eastus) ===
curl -s "https://prices.azure.com/api/retail/prices?\$filter=serviceName%20eq%20%27Virtual%20Machines%27%20and%20armRegionName%20eq%20%27eastus%27%20and%20armSkuName%20eq%20%27Standard_D2ds_v4%27%20and%20priceType%20eq%20%27Consumption%27" \
  | jq -r '.Items[] | "\(.armSkuName) | \(.productName) | \(.meterName) | \(.retailPrice) | \(.unitOfMeasure)"' | sort -u
# OUTPUT (2026-07-27):
# Standard_D2ds_v4 | Virtual Machines Ddsv4 Series | D2ds v4 | 0.113 | 1 Hour                        <- Linux Regular
# Standard_D2ds_v4 | Virtual Machines Ddsv4 Series | D2ds v4 Low Priority | 0.0226 | 1 Hour
# Standard_D2ds_v4 | Virtual Machines Ddsv4 Series | D2ds v4 Spot | 0.023809 | 1 Hour
# Standard_D2ds_v4 | Virtual Machines Ddsv4 Series Windows | D2ds v4 | 0.205 | 1 Hour                <- Windows Regular, usado (H17)
# Standard_D2ds_v4 | Virtual Machines Ddsv4 Series Windows | D2ds v4 Low Priority | 0.082 | 1 Hour
# Standard_D2ds_v4 | Virtual Machines Ddsv4 Series Windows | D2ds v4 Spot | 0.043194 | 1 Hour
# SO confirmado Windows (C20): $0.205/hs x 72 hs (~3 días) = $14.76 — costo real de SFCG-WSV2-02
# encendida sin uso, confirmado y final.
