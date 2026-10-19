#!/usr/bin/env bash
# Event: 20261009_gitin2209-graylog-poco-espacio-disco
# Ingest - Solo lectura. Confirma cuantos GB por dia entran al Graylog de SmartCloud: lista los indices de OpenSearch con su fecha de creacion y su tamano
# (por SSH no interactivo a la VM de Graylog, GET _cat/indices) y calcula localmente los GB por dia (total y de los 4 index sets mas grandes).
# Salidas: data/ingest-cat-indices.json (crudo), data/ingest-per-index.tsv, data/ingest-gb-per-day.tsv.
set -euo pipefail
trap 'echo "FALLO en linea $LINENO: $BASH_COMMAND" >&2' ERR
D="/home/dpaniagua/Documentos/git/bots/cloud/events/20261009_gitin2209-graylog-poco-espacio-disco"
ssh -p 5689 -i ~/.ssh/sfcloud_monitoreo gadmin@sfcloud-monitoreo.smartfran.com "curl -s 'http://127.0.0.1:9200/_cat/indices?h=index,creation.date.string,store.size,docs.count&bytes=b&format=json'" > "$D/data/ingest-cat-indices.json"
echo "indices recibidos: $(jq 'length' "$D/data/ingest-cat-indices.json")"
python3 "$D/scripts/ingest_per_day.py"
echo listo
