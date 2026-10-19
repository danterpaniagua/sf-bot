#!/usr/bin/env bash
# Event: 20261015_gitin2239-mobile-healthcheck-alerta-zabbix (GITIN-2239)
# C11 - Azure CLI, SOLO LECTURA. Pedido del usuario (2026-10-16): "check configuration in az lb".
#       Suscripcion Smart IT - Grido (0190fa7d-...). Lista TODOS los balanceadores de la suscripcion (no se asume cual es el de WebService) y por cada uno:
#       reglas (puerto, timeout, sonda asociada), sondas (protocolo, puerto, intervalo, numberOfProbes, ruta) y pool de backend (nombres de las NIC, sin IPs).
#       Sirve para ver que sonda usa cada LB (por ejemplo, si alguna usa /healthcheck.ashx) y a que servidores apunta. No cambia nada.
set -euo pipefail
trap 'echo "FALLO en linea $LINENO: $BASH_COMMAND" >&2' ERR
SUB=0190fa7d-4ccf-4e3d-beb1-323b5780bfc8
OUT="/home/dpaniagua/Documentos/git/bots/loyalty/events/20261015_gitin2239-mobile-healthcheck-alerta-zabbix/data"
TS=$(date -u +%Y%m%dT%H%M%SZ); RUN="$OUT/c11-run-$TS"; mkdir -p "$RUN"
echo "run $TS | balanceadores de la suscripcion $SUB"
az network lb list --subscription "$SUB" -o json > "$RUN/lb-list.json"
jq -r '.[]|[.name,("rg="+.resourceGroup),("sku="+.sku.name),("frontends="+(.frontendIPConfigurations|length|tostring)),("reglas="+(.loadBalancingRules|length|tostring)),("sondas="+(.probes|length|tostring))]|@tsv' "$RUN/lb-list.json"
echo "== por balanceador"
jq -c '.[]' "$RUN/lb-list.json" | while read -r lb; do
  N=$(jq -r .name <<<"$lb")
  echo "---- $N"
  echo "  reglas (nombre | protocolo | puerto frontend->backend | timeout min | sonda)"
  jq -r '.loadBalancingRules[]|["   "+.name,.protocol,("\(.frontendPort)->\(.backendPort)"),("idle="+(.idleTimeoutInMinutes|tostring)),("sonda="+((.probe.id // "ninguna")|split("/")|last))]|join(" | ")' <<<"$lb"
  echo "  sondas (nombre | protocolo | puerto | intervalo s | numberOfProbes | ruta)"
  jq -r '.probes[]|["   "+.name,.protocol,(.port|tostring),(.intervalInSeconds|tostring),(.numberOfProbes|tostring),(.requestPath // "-")]|join(" | ")' <<<"$lb"
  echo "  pools de backend (nombre | NIC miembros)"
  jq -r '.backendAddressPools[]|["   "+.name,([(.backendIPConfigurations // [])[]|.id|split("/networkInterfaces/")|.[1]|split("/")|.[0]]|join(","))]|join(" | ")' <<<"$lb"
done
echo "guardado en $RUN"
