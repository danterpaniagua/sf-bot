#!/usr/bin/env bash
# Event: 20260820_sales-default-stream-leak (GITIN-1905)
# Todos los comandos corren contra la API de Graylog (sfcloud-monitoreo), vía
# la variable de entorno $GRAYLOG_API_KEY. Los comandos ⚠️ modifican estado
# real en producción.

# === INVESTIGACIÓN ===

# C1 — consulta inicial contra el ID de stream citado en la documentación
# histórica del proyecto (20260630_graylog-vm-terraform) como Sales
curl -s -u "${GRAYLOG_API_KEY}:token" \
  -H "Accept: application/json" \
  "https://sfcloud-monitoreo.smartfran.com/graylog/api/streams/6a452a0d18ebc987b1ca003a" | python3 -m json.tool
# Resultado: ese ID corresponde hoy a "PROD-Business-AppServicePlan", no a
# Sales — referencia de documentación desactualizada/incorrecta, descartada.

# C2 — listado completo de streams reales
curl -s -u "${GRAYLOG_API_KEY}:token" \
  -H "Accept: application/json" \
  "https://sfcloud-monitoreo.smartfran.com/graylog/api/streams" | python3 -c "
import json, sys
data = json.load(sys.stdin)
for s in data['streams']:
    print(s['id'], '|', s['title'], '|', 'remove_from_default:', s['remove_matches_from_default_stream'])
"
# Resultado: ID real de Sales = 6a47c5c94b3c88a95fad7a7a. Todos los streams
# de apps (incluido Sales) muestran remove_matches_from_default_stream: True.

# C3 — configuración completa del stream real de Sales
curl -s -u "${GRAYLOG_API_KEY}:token" \
  -H "Accept: application/json" \
  "https://sfcloud-monitoreo.smartfran.com/graylog/api/streams/6a47c5c94b3c88a95fad7a7a" | python3 -m json.tool
# Resultado: creado 2026-07-03, regla field:name type:1 (exact) value:
# SMARTFRAN-CLOUD-SALES-PRO, remove_matches_from_default_stream: true —
# configuración correcta en apariencia.

# C4 — conteo de mensajes de Sales en Default Stream, últimas 24h
BASE="https://sfcloud-monitoreo.smartfran.com/graylog/api"
SEARCH_ID=$(curl -s -u "${GRAYLOG_API_KEY}:token" \
  -H "Content-Type: application/json" -H "Accept: application/json" -H "X-Requested-By: cli" \
  -d '{
    "queries": [{
      "id": "q1",
      "query": {"type": "elasticsearch", "query_string": "name:SMARTFRAN-CLOUD-SALES-PRO"},
      "timerange": {"type": "relative", "range": 86400},
      "filter": {"type": "stream", "id": "000000000000000000000001"},
      "search_types": [{"id": "agg1", "type": "pivot", "series": [{"type": "count", "id": "count()"}], "rollup": true}]
    }]
  }' "${BASE}/views/search" | python3 -c "import json,sys; print(json.load(sys.stdin)['id'])")
JOB_ID=$(curl -s -u "${GRAYLOG_API_KEY}:token" \
  -H "Content-Type: application/json" -H "Accept: application/json" -H "X-Requested-By: cli" \
  -d '{}' "${BASE}/views/search/${SEARCH_ID}/execute" | python3 -c "import json,sys; print(json.load(sys.stdin)['id'])")
curl -s -u "${GRAYLOG_API_KEY}:token" -H "Accept: application/json" "${BASE}/views/search/status/${JOB_ID}" | python3 -m json.tool
# Resultado: 1.101.464 mensajes de Sales en Default Stream, últimas 24h.

# C5 — mismo conteo, filtrado al stream de Sales en vez de Default
BASE="https://sfcloud-monitoreo.smartfran.com/graylog/api"
SEARCH_ID=$(curl -s -u "${GRAYLOG_API_KEY}:token" \
  -H "Content-Type: application/json" -H "Accept: application/json" -H "X-Requested-By: cli" \
  -d '{
    "queries": [{
      "id": "q1",
      "query": {"type": "elasticsearch", "query_string": "name:SMARTFRAN-CLOUD-SALES-PRO"},
      "timerange": {"type": "relative", "range": 86400},
      "filter": {"type": "stream", "id": "6a47c5c94b3c88a95fad7a7a"},
      "search_types": [{"id": "agg1", "type": "pivot", "series": [{"type": "count", "id": "count()"}], "rollup": true}]
    }]
  }' "${BASE}/views/search" | python3 -c "import json,sys; print(json.load(sys.stdin)['id'])")
JOB_ID=$(curl -s -u "${GRAYLOG_API_KEY}:token" \
  -H "Content-Type: application/json" -H "Accept: application/json" -H "X-Requested-By: cli" \
  -d '{}' "${BASE}/views/search/${SEARCH_ID}/execute" | python3 -c "import json,sys; print(json.load(sys.stdin)['id'])")
curl -s -u "${GRAYLOG_API_KEY}:token" -H "Accept: application/json" "${BASE}/views/search/status/${JOB_ID}" | python3 -m json.tool
# Resultado: 1.987.186 mensajes en el stream de Sales, mismas 24h — ambos
# conteos reales y grandes, confirma duplicación real, no dos poblaciones
# separadas.

# C6 — muestra real de un mensaje de Sales dentro de Default Stream
BASE="https://sfcloud-monitoreo.smartfran.com/graylog/api"
SEARCH_ID=$(curl -s -u "${GRAYLOG_API_KEY}:token" \
  -H "Content-Type: application/json" -H "Accept: application/json" -H "X-Requested-By: cli" \
  -d '{
    "queries": [{
      "id": "q1",
      "query": {"type": "elasticsearch", "query_string": "name:SMARTFRAN-CLOUD-SALES-PRO AND _exists_:MessageTemplate"},
      "timerange": {"type": "relative", "range": 3600},
      "filter": {"type": "stream", "id": "000000000000000000000001"},
      "search_types": [{"id": "msgs1", "type": "messages", "limit": 1}]
    }]
  }' "${BASE}/views/search" | python3 -c "import json,sys; print(json.load(sys.stdin)['id'])")
JOB_ID=$(curl -s -u "${GRAYLOG_API_KEY}:token" \
  -H "Content-Type: application/json" -H "Accept: application/json" -H "X-Requested-By: cli" \
  -d '{}' "${BASE}/views/search/${SEARCH_ID}/execute" | python3 -c "import json,sys; print(json.load(sys.stdin)['id'])")
curl -s -u "${GRAYLOG_API_KEY}:token" -H "Accept: application/json" "${BASE}/views/search/status/${JOB_ID}" | python3 -m json.tool
# Resultado: mensaje real con MessageTemplate presente (forma CLEF directa-
# GELF, confirmada) y "streams": ["6a47c5c94b3c88a95fad7a7a",
# "000000000000000000000001"] — ambos IDs de stream en el mismo mensaje,
# prueba directa de duplicación. total_results: 99.786 en 1h — consistente
# con el total de 24h.

# C7 — obtener el ID y source real de la Pipeline Rule de Sales
curl -s -u "${GRAYLOG_API_KEY}:token" -H "Accept: application/json" \
  "https://sfcloud-monitoreo.smartfran.com/graylog/api/system/pipelines/rule" | python3 -c "
import json, sys
data = json.load(sys.stdin)
for r in data:
    if 'Sales PRO' in r.get('title', ''):
        print(json.dumps(r, indent=2))
"
# Resultado: rule id 6a7f2cb84814bcaed30c8de3. Confirma route_to_stream()
# presente, remove_from_stream() ausente — causa raíz confirmada. También
# revela que el `when` real usa $message.Service/$message.Environment
# (no Properties_Service/Properties_Environment como tenía el archivo de
# referencia local) — drift adicional, corregido en el mismo cambio.

# === REMEDIACIÓN ===

# ⚠️ C8 — aplicar el fix a la Pipeline Rule real (agrega remove_from_stream)
cat > /tmp/gitin-1905-rule-source.txt <<'RULEEOF'
rule "GITIN-1835: CLEF Azure resource fields for Sales PRO"
when
  has_field("MessageTemplate") AND to_string($message.Service) == "Sales" AND to_string($message.Environment) == "Production"
then
  set_field("name", "SMARTFRAN-CLOUD-SALES-PRO");
  set_field("resource_group", "SMARTFRAN.CLOUD.PRO");
  set_field("resource_path", "SMARTFRAN.CLOUD.PRO/PROVIDERS/MICROSOFT.WEB/SITES/SMARTFRAN-CLOUD-SALES-PRO");
  set_field("subscription", "85C76DEA-3304-4310-8656-BF21B28E4F4B");
  set_field("type", "MICROSOFT.WEB/SITES");
  set_field("source", "SMARTFRAN.CLOUD.PRO/PROVIDERS/MICROSOFT.WEB/SITES/SMARTFRAN-CLOUD-SALES-PRO");
  route_to_stream(id: "6a47c5c94b3c88a95fad7a7a");
  remove_from_stream(id: "000000000000000000000001");
end
RULEEOF
python3 -c "
import json
with open('/tmp/gitin-1905-rule-source.txt') as f:
    source = f.read().rstrip('\n')
payload = {
    'title': 'GITIN-1835: CLEF Azure resource fields for Sales PRO',
    'description': None,
    'source': source
}
with open('/tmp/gitin-1905-rule-payload.json', 'w') as f:
    json.dump(payload, f)
"
curl -s -u "${GRAYLOG_API_KEY}:token" \
  -X PUT \
  -H "Content-Type: application/json" -H "Accept: application/json" -H "X-Requested-By: cli" \
  --data-binary @/tmp/gitin-1905-rule-payload.json \
  "https://sfcloud-monitoreo.smartfran.com/graylog/api/system/pipelines/rule/6a7f2cb84814bcaed30c8de3" | python3 -m json.tool
rm /tmp/gitin-1905-rule-source.txt /tmp/gitin-1905-rule-payload.json
# Resultado: modified_at actualizado a 2026-08-20T19:04:53.891Z, source
# confirma remove_from_stream() agregado.

# === VALIDACIÓN ===

# C9 — conteo post-fix, ventana relativa de 5 min (inconclusa: la ventana
# incluye tráfico previo al fix, no aísla el resultado)
BASE="https://sfcloud-monitoreo.smartfran.com/graylog/api"
SEARCH_ID=$(curl -s -u "${GRAYLOG_API_KEY}:token" \
  -H "Content-Type: application/json" -H "Accept: application/json" -H "X-Requested-By: cli" \
  -d '{
    "queries": [{
      "id": "q1",
      "query": {"type": "elasticsearch", "query_string": "name:SMARTFRAN-CLOUD-SALES-PRO AND _exists_:MessageTemplate"},
      "timerange": {"type": "relative", "range": 300},
      "filter": {"type": "stream", "id": "000000000000000000000001"},
      "search_types": [{"id": "agg1", "type": "pivot", "series": [{"type": "count", "id": "count()"}], "rollup": true}]
    }]
  }' "${BASE}/views/search" | python3 -c "import json,sys; print(json.load(sys.stdin)['id'])")
JOB_ID=$(curl -s -u "${GRAYLOG_API_KEY}:token" \
  -H "Content-Type: application/json" -H "Accept: application/json" -H "X-Requested-By: cli" \
  -d '{}' "${BASE}/views/search/${SEARCH_ID}/execute" | python3 -c "import json,sys; print(json.load(sys.stdin)['id'])")
curl -s -u "${GRAYLOG_API_KEY}:token" -H "Accept: application/json" "${BASE}/views/search/status/${JOB_ID}" | python3 -m json.tool
# Resultado: 8.403 — inconcluso, la ventana (19:00:57-19:05:57) cubre en su
# mayoría tráfico previo al fix (aplicado a las 19:04:53).

# C10 — conteo post-fix, ventana absoluta desde 1s después del fix
BASE="https://sfcloud-monitoreo.smartfran.com/graylog/api"
SEARCH_ID=$(curl -s -u "${GRAYLOG_API_KEY}:token" \
  -H "Content-Type: application/json" -H "Accept: application/json" -H "X-Requested-By: cli" \
  -d '{
    "queries": [{
      "id": "q1",
      "query": {"type": "elasticsearch", "query_string": "name:SMARTFRAN-CLOUD-SALES-PRO AND _exists_:MessageTemplate"},
      "timerange": {"type": "absolute", "from": "2026-08-20T19:04:54.000Z", "to": "2026-08-21T00:00:00.000Z"},
      "filter": {"type": "stream", "id": "000000000000000000000001"},
      "search_types": [{"id": "agg1", "type": "pivot", "series": [{"type": "count", "id": "count()"}], "rollup": true}]
    }]
  }' "${BASE}/views/search" | python3 -c "import json,sys; print(json.load(sys.stdin)['id'])")
JOB_ID=$(curl -s -u "${GRAYLOG_API_KEY}:token" \
  -H "Content-Type: application/json" -H "Accept: application/json" -H "X-Requested-By: cli" \
  -d '{}' "${BASE}/views/search/${SEARCH_ID}/execute" | python3 -c "import json,sys; print(json.load(sys.stdin)['id'])")
curl -s -u "${GRAYLOG_API_KEY}:token" -H "Accept: application/json" "${BASE}/views/search/status/${JOB_ID}" | python3 -m json.tool
# Resultado: 0 mensajes desde el fix en adelante — fix confirmado contra
# tráfico real, no solo contra el source de la regla.
