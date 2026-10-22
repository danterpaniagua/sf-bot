#!/usr/bin/env bash
# C16 (SOLO LECTURA, dry-run) - cuantos documentos AppLevel=Information con mas de 7 dias hay en los indices de las 8 apps de negocio.
# No borra nada: solo usa _cat/indices y _count. Los nombres de indice (`<servicio>__<n>`) se tomaron de C1 (business__13..19, sales__*) y
# se verifican en tiempo de ejecucion; si el patron no encuentra indices, aborta.
# Se ejecuta en la VM sfcloud-monitoreo: ssh sfcloud-monitoreo "bash -s" < scripts-c16.sh > data/c16-...txt
# Carga: lee los indices (disco lento); correr fuera de las horas pico. Un _count por indice y por consulta.
set -u
[ "$(hostname)" = "sfcloud-monitoreo" ] || { echo "ABORTA: host distinto de sfcloud-monitoreo"; exit 1; }
OS=localhost:9200
DAYS=7
SERVICES='admin|business|catalog|orders|person|platform|pos|sales'
echo "== host: $(hostname) | $(date -u +%FT%TZ) | umbral: mas de ${DAYS} dias | solo lectura"
INDICES=$(curl -s -m 20 "$OS/_cat/indices?h=index&s=index" | grep -E "^(${SERVICES})__[0-9]+\$")
[ -n "$INDICES" ] || { echo "ABORTA: ningun indice coincide con ^(${SERVICES})__[0-9]+\$ (revisar prefijos con C14)"; exit 1; }
cnt() {  # $1 indice, $2 cuerpo JSON -> numero o ERR
  local r; r=$(curl -s -m 120 -H 'Content-Type: application/json' "$OS/$1/_count" -d "$2") || { echo ERR; return; }
  echo "$r" | grep -o '"count":[0-9]*' | head -1 | cut -d: -f2 | grep . || echo ERR
}
OLD="\"range\":{\"timestamp\":{\"lt\":\"now-${DAYS}d\"}}"
INFO='"query_string":{"query":"AppLevel:\"Information\""}'
printf 'indice\ttotal\tinformation\tinfo_mas_de_%sd\ttotal_mas_de_%sd\n' "$DAYS" "$DAYS"
for I in $INDICES; do
  T=$(cnt "$I" '{}')
  F=$(cnt "$I" "{\"query\":{${INFO}}}")
  FO=$(cnt "$I" "{\"query\":{\"bool\":{\"filter\":[{${INFO}},{${OLD}}]}}}")
  TO=$(cnt "$I" "{\"query\":{${OLD}}}")
  printf '%s\t%s\t%s\t%s\t%s\n' "$I" "$T" "$F" "$FO" "$TO"
done
