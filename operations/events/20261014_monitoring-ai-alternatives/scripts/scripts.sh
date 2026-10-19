#!/usr/bin/env bash
# Event: 20261014_monitoring-ai-alternatives
# C1 - Solo lectura. Que recursos de Azure exportan logs/metricas por Diagnostic Settings y a donde (Event Hub, Log Analytics, Storage).
#      Recorre las dos suscripciones conocidas. Por cada recurso con Diagnostic Settings: tipo, nombre, categorias habilitadas y tipo de destino.
#      Tambien lista la exportacion del Activity Log de cada suscripcion. No imprime claves ni cadenas de conexion (solo ids de recurso).
#      Salida: data/c1-diag-settings.tsv y data/c1-activitylog.json (todo por archivo, nada por stdout salvo el resumen final).
set -euo pipefail
trap 'echo "FALLO en linea $LINENO: $BASH_COMMAND" >&2' ERR
OUT="/home/dpaniagua/Documentos/git/bots/operations/events/20261014_monitoring-ai-alternatives/data"
SUBS="0190fa7d-4ccf-4e3d-beb1-323b5780bfc8 85c76dea-3304-4310-8656-bf21b28e4f4b"
TSV="$OUT/c1-diag-settings.tsv"; ACT="$OUT/c1-activitylog.json"
printf 'subscription\tresource_type\tresource\tsetting\tcategories\tdestinations\n' > "$TSV"
echo '[]' > "$ACT"
for S in $SUBS; do
  echo "suscripcion $S: $(az account show --subscription "$S" --query name -o tsv 2>/dev/null || echo 'sin acceso')" >&2
  az monitor diagnostic-settings subscription list --subscription "$S" -o json 2>/dev/null \
    | jq --arg s "$S" '[.value[]? | {subscription:$s, name, logs:[.logs[]? | select(.enabled) | .category], eventHub:(.eventHubName // .eventHubAuthorizationRuleId // null | tostring | split("/") | last), workspace:(.workspaceId // null | tostring | split("/") | last), storage:(.storageAccountId // null | tostring | split("/") | last)}]' > "$OUT/.act.tmp" || echo '[]' > "$OUT/.act.tmp"
  jq -s '.[0] + .[1]' "$ACT" "$OUT/.act.tmp" > "$OUT/.act2.tmp" && mv "$OUT/.act2.tmp" "$ACT"; rm -f "$OUT/.act.tmp"
  az resource list --subscription "$S" --query '[].[id,type]' -o tsv 2>/dev/null | while IFS=$'\t' read -r ID TYPE; do
    az monitor diagnostic-settings list --resource "$ID" --subscription "$S" -o json 2>/dev/null \
      | jq -r --arg s "$S" --arg id "$ID" --arg t "$TYPE" '.value[]? |
          [$s, $t, ($id | split("/") | last), .name,
           ([.logs[]? | select(.enabled) | .category] + [.metrics[]? | select(.enabled) | "metric:" + .category] | join(",")),
           ([(if .eventHubAuthorizationRuleId then "eventhub" else empty end), (if .workspaceId then "loganalytics" else empty end), (if .storageAccountId then "storage" else empty end)] | join(","))] | @tsv' >> "$TSV" || true
  done
done
echo "filas de diagnostic settings: $(($(wc -l < "$TSV") - 1)) | recursos por tipo y destino:"
LC_ALL=C awk -F'\t' 'NR>1 {k[$2" -> "$6]++} END {for (x in k) printf "%5d  %s\n", k[x], x}' "$TSV" | sort -rn
echo "exportacion del Activity Log (suscripciones con configuracion): $(jq 'length' "$ACT")"
echo listo
