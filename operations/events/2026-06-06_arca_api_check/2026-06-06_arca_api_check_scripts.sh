#!/usr/bin/env bash
#
# CX-01 — get-arca-status.sh
# Healthcheck de disponibilidad de los webservices de ARCA (ex-AFIP).
# Ubicacion final en el server: /opt/scripts/get-arca-status.sh
# Symlink: /usr/bin/get-arca-status
#
# WSAA: solo reachability (no tiene metodo dummy).
# WSFEv1: usa FEDummy, el healthcheck oficial de ARCA (sin cert/token),
#         que devuelve el estado de AppServer / DbServer / AuthServer.
#
# Exit codes:
#   0 = OK (todo responde y en OK)
#   1 = DOWN (algun componente no responde o devuelve distinto de OK)
#   2 = DEGRADADO (responde OK pero fuera del umbral de latencia)
#
# Uso:
#   ./get-arca-status.sh            -> texto legible
#   ./get-arca-status.sh --json     -> salida JSON (para Graylog / webhook / Zabbix dependent items)
#   ./get-arca-status.sh --zabbix   -> imprime el overall_status (0/1/2), para UserParameter

set -uo pipefail

TIMEOUT="${ARCA_HC_TIMEOUT:-8}"
LATENCY_WARN_MS="${ARCA_HC_LATENCY_WARN:-3000}"

WSAA_URL="https://wsaa.afip.gov.ar/ws/services/LoginCms"

WSFEV1_URL="https://servicios1.afip.gov.ar/wsfev1/service.asmx"
WSFEV1_SOAPACTION="http://ar.gov.afip.dif.FEV1/FEDummy"
WSFEV1_SOAP_BODY='<?xml version="1.0" encoding="utf-8"?>
<soap:Envelope xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xmlns:xsd="http://www.w3.org/2001/XMLSchema" xmlns:soap="http://schemas.xmlsoap.org/soap/envelope/">
  <soap:Body>
    <FEDummy xmlns="http://ar.gov.afip.dif.FEV1/" />
  </soap:Body>
</soap:Envelope>'

MODE="text"
[[ "${1:-}" == "--json" ]] && MODE="json"
[[ "${1:-}" == "--zabbix" ]] && MODE="zabbix"

overall_status=0   # 0 ok, 1 down, 2 degraded
results=()          # name|detail|status|latency_ms

check_wsaa() {
  local start end elapsed_ms http_code curl_exit
  start=$(date +%s%3N)
  http_code=$(curl -s -o /dev/null -w '%{http_code}' \
                --ciphers 'DEFAULT@SECLEVEL=1' \
                --max-time "$TIMEOUT" --connect-timeout "$TIMEOUT" \
                "$WSAA_URL")
  curl_exit=$?
  end=$(date +%s%3N)
  elapsed_ms=$((end - start))

  local status="UP" code=0
  if [[ $curl_exit -ne 0 || "$http_code" == "000" ]]; then
    status="DOWN"; code=1
  elif (( elapsed_ms > LATENCY_WARN_MS )); then
    status="DEGRADED"; code=2
  fi
  (( code > overall_status )) && overall_status=$code
  results+=("WSAA|http=${http_code}|${status}|${elapsed_ms}")
}

check_wsfev1_dummy() {
  local start end elapsed_ms response curl_exit
  local app_status db_status auth_status

  start=$(date +%s%3N)
  response=$(curl -s --ciphers 'DEFAULT@SECLEVEL=1' \
                --max-time "$TIMEOUT" --connect-timeout "$TIMEOUT" \
                -X POST "$WSFEV1_URL" \
                -H "Content-Type: text/xml; charset=utf-8" \
                -H "SOAPAction: ${WSFEV1_SOAPACTION}" \
                --data-binary "$WSFEV1_SOAP_BODY")
  curl_exit=$?
  end=$(date +%s%3N)
  elapsed_ms=$((end - start))

  if [[ $curl_exit -ne 0 || -z "$response" ]]; then
    results+=("WSFEv1|no_response|DOWN|${elapsed_ms}")
    overall_status=1
    return
  fi

  app_status=$(echo "$response"  | grep -oP '(?<=<AppServer>)[^<]+')
  db_status=$(echo "$response"   | grep -oP '(?<=<DbServer>)[^<]+')
  auth_status=$(echo "$response" | grep -oP '(?<=<AuthServer>)[^<]+')

  local status="UP" code=0
  if [[ "$app_status" != "OK" || "$db_status" != "OK" || "$auth_status" != "OK" ]]; then
    status="DOWN"; code=1
  elif (( elapsed_ms > LATENCY_WARN_MS )); then
    status="DEGRADED"; code=2
  fi
  (( code > overall_status )) && overall_status=$code

  results+=("WSFEv1|App=${app_status:-?},Db=${db_status:-?},Auth=${auth_status:-?}|${status}|${elapsed_ms}")
}

check_wsaa
check_wsfev1_dummy

case "$MODE" in
  zabbix)
    echo "$overall_status"
    ;;
  json)
    echo -n '{"overall_status":'"$overall_status"',"checks":['
    first=true
    for r in "${results[@]}"; do
      IFS='|' read -r name detail status ms <<< "$r"
      $first || echo -n ','
      first=false
      printf '{"service":"%s","detail":"%s","status":"%s","latency_ms":%s}' \
        "$name" "$detail" "$status" "$ms"
    done
    echo ']}'
    ;;
  text|*)
    echo "=== ARCA Healthcheck $(date -Iseconds) ==="
    for r in "${results[@]}"; do
      IFS='|' read -r name detail status ms <<< "$r"
      printf "%-8s %-9s %6sms  %s\n" "$name" "$status" "$ms" "$detail"
    done
    case $overall_status in
      0) echo "Resultado: OK - ARCA responde con normalidad." ;;
      1) echo "Resultado: DOWN - al menos un componente no responde OK." ;;
      2) echo "Resultado: DEGRADADO - responde OK pero con latencia alta (> ${LATENCY_WARN_MS}ms)." ;;
    esac
    ;;
esac

exit $overall_status

# OUTPUT (2026-06-06):
# {"overall_status":0,"checks":[{"service":"WSAA","detail":"http=200","status":"UP","latency_ms":724},{"service":"WSFEv1","detail":"App=OK,Db=OK,Auth=OK","status":"UP","latency_ms":730}]}


# CX-02 — Diagnostico permisos: script inaccesible para el usuario zabbix
# El script vivia originalmente en /home/ubuntu/scritps/get-arca-status.sh (chmod 777 en el
# archivo, pero irrelevante: el bloqueo estaba en el directorio padre).
namei -l /home/ubuntu/scritps/get-arca-status.sh

# OUTPUT (2026-06-06):
# /home/ubuntu tenia permisos drwxr-x--- (750), bloqueando el paso de cualquier
# usuario fuera del grupo "ubuntu" (incluido "zabbix").


# CX-03 — Fix de permisos: reubicar el script fuera de un home personal
sudo mkdir -p /opt/scripts
sudo mv /home/ubuntu/scritps/get-arca-status.sh /opt/scripts/get-arca-status.sh
sudo chmod 755 /opt/scripts/get-arca-status.sh
sudo ln -s /opt/scripts/get-arca-status.sh /usr/bin/get-arca-status


# CX-04 — UserParameter del agente Zabbix
# Archivo: /etc/zabbix/zabbix_agent2.d/userparameter_arca.conf
cat /etc/zabbix/zabbix_agent2.d/userparameter_arca.conf

# OUTPUT (2026-06-06):
# UserParameter=arca.status.raw,/usr/bin/get-arca-status --json


# CX-05 — Restart del agente tras crear el UserParameter
# (paso obligatorio: sin restart posterior a la creacion del .conf, el agente
# devuelve ZBX_NOTSUPPORTED [Unknown metric] al testear la key)
sudo systemctl restart zabbix-agent2
journalctl -u zabbix-agent2 --since "10 min ago"


# CX-06 — Verificacion de la key custom en el agente
sudo -u zabbix zabbix_agent2 -t arca.status.raw

# OUTPUT (2026-06-06):
# arca.status.raw [t|{"overall_status":0,"checks":[...]}]
# (test exitoso tras el restart del agente en CX-05)
