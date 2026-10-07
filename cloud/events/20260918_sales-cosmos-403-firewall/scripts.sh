# C1 — graylog-fulltext-cosmos-403-firewall (INTENTO 1, DESCARTADO)
# El OR de dos frases entre comillas no filtro nada real: total_results
# 891990 en 7 dias (volumen ~full-corpus) y los 100 hits devueltos son
# todos placeholders genericos de la categoria AppServiceHTTPLogs
# (message:"AppServiceHTTPLogs" literal, sin relacion con la frase/IP
# buscada). No confiar en este resultado como "no hay errores de Cosmos".
#
# C1b — graylog-fulltext-cosmos-403-firewall-retry
# Reintento con AND de dos terminos simples sin comillas (evita depender
# del manejo de phrase-query del endpoint) y excluyendo explicitamente el
# placeholder ruidoso de AppServiceHTTPLogs.
curl -s -G "https://sfcloud-monitoreo.smartfran.com/graylog/api/search/universal/relative" \
  -u "$GRAYLOG_API_KEY:token" -H "Accept: application/json" -H "X-Requested-By: cli" \
  --data-urlencode "query=firewall AND Cosmos AND NOT message:AppServiceHTTPLogs" \
  --data-urlencode "range=604800" --data-urlencode "limit=50" \
  --data-urlencode "fields=timestamp,Service,Environment,TenantId,message" \
  > /home/dpaniagua/Documentos/git/bots/cloud/events/20260918_sales-cosmos-403-firewall/data/graylog_cosmos_403_firewall_7d_retry.json

# C1c — graylog-fulltext-ip-only
# Busqueda aislada solo por la IP (sin combinar con frases), para
# descartar que el problema en C1 haya sido el operador OR/quoting en vez
# del tokenizado de la IP.
curl -s -G "https://sfcloud-monitoreo.smartfran.com/graylog/api/search/universal/relative" \
  -u "$GRAYLOG_API_KEY:token" -H "Accept: application/json" -H "X-Requested-By: cli" \
  --data-urlencode 'query="20.253.36.226"' \
  --data-urlencode "range=604800" --data-urlencode "limit=50" \
  --data-urlencode "fields=timestamp,Service,Environment,TenantId,message" \
  > /home/dpaniagua/Documentos/git/bots/cloud/events/20260918_sales-cosmos-403-firewall/data/graylog_ip_only_7d.json
