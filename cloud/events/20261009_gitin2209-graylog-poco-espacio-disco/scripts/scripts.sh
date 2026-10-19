#!/usr/bin/env bash
# Event: 20261009_gitin2209-graylog-poco-espacio-disco
# C1 — Solo lectura. Estado de disco y de OpenSearch de la VM de Graylog de SmartCloud (sfcloud-monitoreo), por SSH
#      no interactivo (mismo patron que otros eventos de cloud/), mas la configuracion de los index sets por la API.
#      Salidas en data/. El token de Graylog se lee de $GRAYLOG_API_KEY (nunca literal).
# Uso:  bash <ruta>/scripts.sh > <ruta>/data/pull-log.txt 2>&1
set -euo pipefail
trap 'echo "FALLO en linea $LINENO: $BASH_COMMAND" >&2' ERR

OUT="/home/dpaniagua/Documentos/git/bots/cloud/events/20261009_gitin2209-graylog-poco-espacio-disco/data"
VM() { ssh -p 5689 -i ~/.ssh/sfcloud_monitoreo gadmin@sfcloud-monitoreo.smartfran.com "$1"; }
OS="http://127.0.0.1:9200"
mkdir -p "$OUT"

echo "== disco (VM)"
VM "date -u +'%F %T UTC'; df -h /var/lib/opensearch /var/lib/mongodb /; echo; df -B1G --output=source,size,used,avail,pcent /var/lib/opensearch" > "$OUT/df.txt"
echo "== salud y asignacion"
VM "curl -s $OS/_cluster/health?pretty" > "$OUT/cluster-health.json"
VM "curl -s '$OS/_cat/allocation?v&bytes=gb'" > "$OUT/cat-allocation.txt"
echo "== umbrales de disco (incluye valores por defecto) y bloqueos de solo lectura"
VM "curl -s '$OS/_cluster/settings?include_defaults=true&flat_settings=true&filter_path=*.cluster.routing.allocation.disk*'" > "$OUT/cluster-settings-disk.json"
VM "curl -s '$OS/_all/_settings/index.blocks*?flat_settings=true'" > "$OUT/index-blocks.json"
echo "== indices (nombre, fecha de creacion, docs, tamano en GB)"
VM "curl -s '$OS/_cat/indices?h=index,health,status,pri,rep,docs.count,store.size,creation.date.string&bytes=gb&s=creation.date.string'" > "$OUT/cat-indices.txt"
echo "== index sets de Graylog (rotacion, retencion, estadisticas)"
curl -sS -f -u "$GRAYLOG_API_KEY:token" -H 'Accept: application/json' "https://sfcloud-monitoreo.smartfran.com/graylog/api/system/indices/index_sets?stats=true&skip=0&limit=0" > "$OUT/index-sets.json"
echo "indices: $(wc -l < "$OUT/cat-indices.txt") lineas | index sets: $(jq '.index_sets | length' "$OUT/index-sets.json")"
echo "listo"
