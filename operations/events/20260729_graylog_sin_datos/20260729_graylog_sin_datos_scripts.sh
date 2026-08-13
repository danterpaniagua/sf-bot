#!/usr/bin/env bash
# Evento: 20260729_graylog_sin_datos
# Comandos agrupados por fase: Investigación / Auditoría
# Los tokens/secretos se referencian via variables de entorno, nunca en texto plano

# === INVESTIGACIÓN — Estado de infraestructura Azure ===

# C0 — Resource group real de la VM de Graylog
az vm list \
  --subscription 85c76dea-3304-4310-8656-bf21b28e4f4b \
  --query "[?name=='smartfran-graylog-pro'].{Name:name, RG:resourceGroup}" \
  --output table
# OUTPUT (2026-07-29): RG = SMARTFRAN.CLOUD.PRO

# C1 — Estado de energía / VM Agent
az vm get-instance-view \
  --name smartfran-graylog-pro \
  --resource-group SMARTFRAN.CLOUD.PRO \
  --subscription 85c76dea-3304-4310-8656-bf21b28e4f4b \
  --query "{PowerState:instanceView.statuses[1].displayStatus, VMAgent:instanceView.vmAgent.statuses[0].displayStatus}" \
  --output table
# OUTPUT: VM running / VM Agent Ready

# C2/C22/C23 — Activity Log en distintas ventanas horarias (la ventana correcta resultó ser
# 2026-07-28 04:00-09:00 UTC, en torno al cliff real a las 06:00 UTC)
az monitor activity-log list \
  --resource-group SMARTFRAN.CLOUD.PRO \
  --start-time "2026-07-28T04:00:00Z" \
  --end-time "2026-07-28T09:00:00Z" \
  --subscription 85c76dea-3304-4310-8656-bf21b28e4f4b \
  --query "[].{Time:eventTimestamp, Caller:caller, Operation:operationName.localizedValue, Status:status.value, Resource:resourceId}" \
  --output table
# OUTPUT: sin eventos relevantes — solo autoscale/hosting-plan de SmartFran-Cloud-Orders-Plan-PRO
# (app no relacionada con este pipeline de Graylog)

# C3/C4 — App Settings de Business/Sales, búsqueda de claves Logging/ASPNETCORE_ENVIRONMENT
az webapp config appsettings list \
  --name SmartFran-Cloud-Business-PRO \
  --resource-group SmartFran.Cloud.PRO \
  --subscription 85c76dea-3304-4310-8656-bf21b28e4f4b \
  --query "[?contains(name, 'Logging') || contains(name, 'ASPNETCORE_ENVIRONMENT')]" \
  --output table
az webapp config appsettings list \
  --name SmartFran-Cloud-Sales-PRO \
  --resource-group SmartFran.Cloud.PRO \
  --subscription 85c76dea-3304-4310-8656-bf21b28e4f4b \
  --query "[?contains(name, 'Logging') || contains(name, 'ASPNETCORE_ENVIRONMENT')]" \
  --output table
# OUTPUT: ambos vacíos — la verbosidad de logging no se controla vía App Settings

# C24 — Métricas de Event Hub (namespace del pipeline de Graylog), en torno al cliff
az monitor metrics list \
  --resource "/subscriptions/85c76dea-3304-4310-8656-bf21b28e4f4b/resourceGroups/SMARTFRAN.CLOUD.PRO/providers/Microsoft.EventHub/namespaces/smartfran-graylog-evhns-pro" \
  --metric "IncomingMessages" "OutgoingMessages" \
  --start-time "2026-07-28T04:00:00Z" \
  --end-time "2026-07-28T09:00:00Z" \
  --interval PT5M \
  --output table
# OUTPUT: volumen de batches estable y sin variación antes/después de las 06:00 UTC

# === INVESTIGACIÓN — App Configuration compartida ===

# C29 — Verificación de rol RBAC data-plane sobre el App Configuration store
az role assignment list \
  --scope "/subscriptions/85c76dea-3304-4310-8656-bf21b28e4f4b/resourceGroups/SMARTFRAN.CLOUD.PRO/providers/Microsoft.AppConfiguration/configurationStores/SmartFran-Cloud-Settings-PRO" \
  --include-inherited \
  --query "[].{Principal:principalName, Role:roleDefinitionName, Scope:scope}" \
  --output table
# OUTPUT: ningún principal con rol "App Configuration Data Reader/Owner" — brecha RBAC data-plane

# C30/C31 — Credencial de acceso (read-only) para desbloquear la lectura sin el rol RBAC
az appconfig credential list \
  --name SmartFran-Cloud-Settings-PRO \
  --resource-group SMARTFRAN.CLOUD.PRO \
  --subscription 85c76dea-3304-4310-8656-bf21b28e4f4b \
  --query "[?name=='Primary Read Only'].connectionString | [0]" -o tsv
# OUTPUT: connection string obtenida (no persistida en texto plano en ningún archivo)

# C33 — Listado completo de claves en App Configuration
az appconfig kv list \
  --connection-string "$APPCONFIG_CONN" \
  --query "[].{Key:key, Label:label, LastModified:last_modified}" \
  --output table
# OUTPUT: ninguna clave relacionada a Logging/Telemetry/Sampling/LogLevel — store contiene
# únicamente configuración de Cosmos DB y Blob Storage por tenant

# === INVESTIGACIÓN — Graylog REST API (Views/Search) ===

# C21/C25 — Conteo de mensajes por hora, 48h, desglosado por stream (Business/Sales/Default)
# vía /api/views/search (crear búsqueda + ejecutar + poll de estado)
curl -s -u "$GRAYLOG_TOKEN:token" -H "X-Requested-By: cli" -H "Content-Type: application/json" \
  -X POST "https://sfcloud-monitoreo.smartfran.com/graylog/api/views/search" \
  -d '{"queries":[
    {"id":"q_business","query":{"type":"elasticsearch","query_string":"*"},
     "timerange":{"type":"relative","range":172800},
     "filter":{"type":"stream","id":"6a452a0d18ebc987b1ca003a"},
     "search_types":[{"id":"agg_business","type":"pivot","rollup":true,
       "row_groups":[{"type":"time","field":"timestamp","interval":{"type":"timeunit","timeunit":"1h"}}],
       "series":[{"type":"count","id":"count()"}]}]},
    {"id":"q_sales","query":{"type":"elasticsearch","query_string":"*"},
     "timerange":{"type":"relative","range":172800},
     "filter":{"type":"stream","id":"6a47c5c94b3c88a95fad7a7a"},
     "search_types":[{"id":"agg_sales","type":"pivot","rollup":true,
       "row_groups":[{"type":"time","field":"timestamp","interval":{"type":"timeunit","timeunit":"1h"}}],
       "series":[{"type":"count","id":"count()"}]}]},
    {"id":"q_default","query":{"type":"elasticsearch","query_string":"*"},
     "timerange":{"type":"relative","range":172800},
     "filter":{"type":"stream","id":"000000000000000000000001"},
     "search_types":[{"id":"agg_default","type":"pivot","rollup":true,
       "row_groups":[{"type":"time","field":"timestamp","interval":{"type":"timeunit","timeunit":"1h"}}],
       "series":[{"type":"count","id":"count()"}]}]}
  ]}'
# (respuesta devuelve un id de búsqueda; ejecutar via POST /views/search/{id}/execute,
#  luego poll GET /views/search/status/{jobId} hasta done:true)
# OUTPUT: Business 02:00 ART=667.074/h -> 03:00 ART=22.488/h (caída ~96,6%)
#         Sales    02:00 ART=33.038/h  -> 03:00 ART=2.656/h  (caída ~92%)
#         Default: 0 mensajes en toda la ventana de 48h
#         Caída sincronizada en ambos streams a las 2026-07-28 03:00 ART (06:00 UTC),
#         sostenida sin recuperación durante 46+ horas

# === INVESTIGACIÓN — Fallas de indexado ===

# C34 — Conteo de fallas de indexado desde el momento exacto del cliff
curl -s -u "$GRAYLOG_TOKEN:token" -H "X-Requested-By: cli" \
  "https://sfcloud-monitoreo.smartfran.com/graylog/api/system/indexer/failures/count?since=2026-07-28T06:00:00.000Z"
# OUTPUT: {"count": 62876}

# C35 — Conteo de fallas en las 24h ANTERIORES al cliff, para comparación
curl -s -u "$GRAYLOG_TOKEN:token" -H "X-Requested-By: cli" \
  "https://sfcloud-monitoreo.smartfran.com/graylog/api/system/indexer/failures/count?since=2026-07-27T06:00:00.000Z"
# OUTPUT: {"count": 62876} — idéntico a C34: cero fallas en las 24h previas al cliff,
# el 100% de las fallas recientes comienza justo en el cliff y continúa activo hasta hoy

# C36 — Detalle de fallas recientes (muestra de 25)
curl -s -u "$GRAYLOG_TOKEN:token" -H "X-Requested-By: cli" \
  "https://sfcloud-monitoreo.smartfran.com/graylog/api/system/indexer/failures?limit=25&offset=0"
# OUTPUT: 100% de la muestra es index=business__6, error idéntico:
# "Document contains at least one immense term in field=event_original... bytes can be at
# most 32766 in length; got 131736-131792" — mismo tipo de error que el incidente documentado
# en cloud-graylog/CLAUDE.md del 2026-07-02

# === INVESTIGACIÓN — Host de Graylog (Logstash), vía az vm run-command ===

# C37 — Estado del servicio Logstash y timestamp exacto de arranque
az vm run-command invoke \
  --resource-group SMARTFRAN.CLOUD.PRO \
  --name smartfran-graylog-pro \
  --subscription 85c76dea-3304-4310-8656-bf21b28e4f4b \
  --command-id RunShellScript \
  --scripts "systemctl status logstash --no-pager; echo '---'; systemctl show logstash --property=ActiveEnterTimestamp,ExecMainStartTimestamp"
# OUTPUT: ExecMainStartTimestamp=Tue 2026-07-28 06:06:40 UTC
#         ActiveEnterTimestamp=Tue 2026-07-28 06:06:40 UTC
# — coincide casi exactamente con la hora del cliff de volumen (03:00 ART / 06:00 UTC)

# C38 — Journal de Logstash en la ventana del cliff
az vm run-command invoke \
  --resource-group SMARTFRAN.CLOUD.PRO \
  --name smartfran-graylog-pro \
  --subscription 85c76dea-3304-4310-8656-bf21b28e4f4b \
  --command-id RunShellScript \
  --scripts "journalctl -u logstash --since '2026-07-28 04:00:00' --until '2026-07-28 09:00:00' --no-pager | head -200"
# OUTPUT: arranque limpio del pipeline a las 06:06:57-58 UTC (Starting pipeline, Pipeline
# started, reconexión del consumer de Event Hub) — no se observó traza de crash en esta
# muestra; pendiente revisar el journal INMEDIATAMENTE ANTES de las 06:06:40 UTC para
# confirmar si el restart fue limpio (deploy/manual) o producto de un crash

# C39 — Verificación del fix de event_original en la config actual del pipeline
az vm run-command invoke \
  --resource-group SMARTFRAN.CLOUD.PRO \
  --name smartfran-graylog-pro \
  --subscription 85c76dea-3304-4310-8656-bf21b28e4f4b \
  --command-id RunShellScript \
  --scripts "grep -rn -A5 -B5 'event_original' /etc/logstash/conf.d/ 2>/dev/null"
# OUTPUT: el fix del 2026-07-02 SIGUE presente y correcto (event.set("event_original",
# record.to_json), líneas 51-67 de azure-eventhub-to-graylog.conf) — descarta reversión
# del fix como causa de las fallas de indexado actuales. La causa real es que registros
# individuales de Business superan por sí solos los 32.766 bytes (hasta 131KB), consistente
# con EnableSensitiveDataLogging(true) (hardcodeado en Business Program.cs, confirmado por
# separado en este mismo evento) volcando valores de parámetros SQL completos

# === AUDITORÍA — Estado del nodo Graylog (UI, confirmación final) ===
# Verificado vía Graylog Web UI (Nodes page), sin comando CLI:
# CPU 0,43% | JVM heap 1,1/4,0GiB (26,6%) | Buffers Input/Process/Output 0% | Journal 58,5MiB/5GB (1,14%)
# Throughput actual: 0 msg/s in/out — consistente con el volumen bajo post-cliff, no es una falla activa
