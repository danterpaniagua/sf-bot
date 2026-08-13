#!/bin/bash
# Evento: 20260728_logging-verbosity-ef-core-cors
# Host: sfcloud-monitoreo (OpenSearch, puerto 9200 local)
# Todos los comandos son de solo lectura (consultas _search/_mapping/_cat)

# === Q1 — Confirmar campos reales de app/categoria en un doc de muestra (sales__0) ===
curl -s "http://127.0.0.1:9200/sales__0/_search?size=1&pretty" -H 'Content-Type: application/json' -d '{"query":{"match_all":{}}}' | grep -E '"category"|"name"|"resource_path"|"_source"'
# OUTPUT (2026-07-28):
# "resource_path": "SMARTFRAN.CLOUD.PRO/PROVIDERS/MICROSOFT.WEB/SITES/SMARTFRAN-CLOUD-SALES-PRO"
# "name": "SMARTFRAN-CLOUD-SALES-PRO"
# "category": "AppServiceAppLogs"

# === Q2 — Primer intento de agregacion por name.keyword/category.keyword (fallido) ===
curl -s "http://127.0.0.1:9200/business__*,sales__*/_search" -H 'Content-Type: application/json' -d '{
  "size": 0,
  "aggs": {
    "by_app": {
      "terms": { "field": "name.keyword", "size": 10 },
      "aggs": { "by_category": { "terms": { "field": "category.keyword", "size": 10 } } }
    }
  }
}'
# OUTPUT: 0 buckets pese a 10000+ hits -> campos no tienen subcampo .keyword (ver Q4)

# === Q3 — Listado real de indices actuales ===
curl -s "http://127.0.0.1:9200/_cat/indices?v&bytes=gb&h=index,docs.count,store.size" | sort -k3 -h -r
# OUTPUT (2026-07-28):
# business__2  54.146.780 docs  21GB | business__5  51.634.300  20GB | business__4  52.580.879  20GB
# business__3  46.765.263 docs  18GB | business__6  13.165.348   5GB (mas reciente, aun llenandose)
# sales__1      8.559.508 docs   5GB | sales__0      8.585.832   5GB | sales__2   4.301.166   2GB (mas reciente)
# business__1 (usado en 20260723_franchise-scaling-costs, C2) ya no existe -> rotado/purgado

# === Q4 — Mapping real de business__6: name y category son "keyword" puro (sin subcampo .keyword) ===
curl -s "http://127.0.0.1:9200/business__6/_mapping?pretty" | grep -E -A 5 '"name"|"category"'
# OUTPUT: "category": {"type": "keyword"} ; "name": {"type": "keyword"}
# -> corrige Q2: usar los campos directos (name, category), no name.keyword/category.keyword

# === Q5 — Agregacion real por app + categoria (indices mas recientes: business__6, sales__2) ===
curl -s "http://127.0.0.1:9200/business__6,sales__2/_search" -H 'Content-Type: application/json' -d '{
  "size": 0,
  "aggs": {
    "by_app": {
      "terms": { "field": "name", "size": 10 },
      "aggs": { "by_category": { "terms": { "field": "category", "size": 10 } } }
    }
  }
}'
# OUTPUT (2026-07-28):
# SMARTFRAN-CLOUD-BUSINESS-PRO (13.165.348 docs): AppServiceConsoleLogs=8.459.208, AppServiceAppLogs=4.639.994,
#   AppServiceHTTPLogs=65.866, AppServicePlatformLogs=280
# SMARTFRAN-CLOUD-SALES-PRO (4.301.166 docs): AppServiceAppLogs=3.895.072, AppServiceHTTPLogs=406.094
#   (SIN AppServiceConsoleLogs -> hallazgo nuevo, contradice el drift documentado en cloud-graylog/CLAUDE.md)

# === Q6 — Mapping de message y operationName ===
curl -s "http://127.0.0.1:9200/business__1/_mapping?pretty" | grep -A 5 '"name"\|"category"'
# (fallo inicial: pipe literal sin -E; corregido en Q4 con grep -E)

# === Q7 — Agregacion por app + top operationName + top categoria ===
curl -s "http://127.0.0.1:9200/business__6,sales__2/_search" -H 'Content-Type: application/json' -d '{
  "size": 0,
  "aggs": {
    "by_app": {
      "terms": { "field": "name", "size": 10 },
      "aggs": {
        "top_operations": { "terms": { "field": "operationName", "size": 15 } },
        "top_categories": { "terms": { "field": "category", "size": 10 } }
      }
    }
  }
}'
# OUTPUT (2026-07-28):
# Business: operationName "Microsoft.Web/sites/log"=8.459.208 (coincide exacto con ConsoleLogs), "ContainerLogs"=280
# Sales: operationName "Microsoft.Web/sites/log"=3.895.108 (coincide exacto con AppLogs, NO con ConsoleLogs)
# -> operationName es un tag generico de Azure, no distingue mensajes reales (mismo valor para categorias distintas segun la app)

# === Q8 — Mapping de message (text, no agregable) y resultDescription (keyword) ===
curl -s "http://127.0.0.1:9200/business__6/_mapping?pretty" | grep -E -A 8 '"message"'
curl -s "http://127.0.0.1:9200/business__6/_mapping?pretty" | grep -E -A 5 '"resultDescription"'
# OUTPUT: message={"type":"text","analyzer":"standard"} (no agregable como string exacto)
#         resultDescription={"type":"keyword"} (candidato correcto para top-mensajes)

# === Q9 — Agregacion final: top resultDescription por app (con marcador "missing") ===
curl -s "http://127.0.0.1:9200/business__6,sales__2/_search" -H 'Content-Type: application/json' -d '{
  "size": 0,
  "aggs": {
    "by_app": {
      "terms": { "field": "name", "size": 10 },
      "aggs": {
        "top_result_descriptions": { "terms": { "field": "resultDescription", "size": 20, "missing": "__none__" } }
      }
    }
  }
}'
# OUTPUT (2026-07-28): ver detalle completo en 20260728_logging-verbosity-ef-core-cors_ops.md, seccion Hallazgos.
# Resumen: Business top-20 = 4.374.288 docs (33,2% de su volumen actual), 19/20 son EF Core debug + 1 ASP.NET Core MVC debug.
# Sales top-20 = 1.489.355 docs (34,6% de su volumen actual): 406.094 sin resultDescription (HTTPLogs real),
#   193.002 "CORS policy execution successful" (ruido), resto = pipeline MVC (Start/Route matched/Executing/Executed x6 por request real).
