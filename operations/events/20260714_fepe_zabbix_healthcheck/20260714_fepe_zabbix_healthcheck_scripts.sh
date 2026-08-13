#!/usr/bin/env bash
#
# CX-01 — get-fepe-status.sh (v2 — corregido 2026-07-24, ver CX-05/CX-06 mas
# abajo para la evidencia del bug de la v1)
# Healthcheck de disponibilidad de la infraestructura de Factura Electronica
# Peru (FEPE) utilizada por SmartFran Cloud: Xacto Peru (envio de
# comprobantes, WsFePeService.cs en Sales API) y Bizlinks (consulta de
# comprobantes, WsFePeService.cs en la Function TicketProcessAsync).
# SmartFran Cloud no integra directamente con SUNAT - ambos son PSE/OSE
# intermediarios.
#
# Deployado en: /opt/scripts/get-fepe-status.sh
# Symlink: /usr/bin/get-fepe-status
#
# Los cuatro checks corren en paralelo (background jobs + wait, resultados
# via archivos temporales) para acotar el tiempo total al del check mas
# lento en vez de a la suma de los cuatro. La v1 (documentada como paralela
# en el log de la sesion 2026-07-14 21:30 pero deployada secuencial por
# error — ver Hallazgo 2026-07-24 en _ops-events.md) llamaba a las cuatro
# funciones una atras de otra, lo cual sumaba hasta ~16s cuando dos
# endpoints de Xacto Peru estaban caidos a la vez, superando el
# Timeout=15 del lado servidor (zabbix_server.conf) y generando
# "network error" intermitente en el log del servidor Zabbix.
#
# Ninguno de los dos proveedores expone un metodo "dummy" publico como
# FEDummy de ARCA:
#   - Xacto Peru (REST, puertos no estandar 3636/6099/8099): se mide
#     reachability - cualquier respuesta HTTP (incluido 401/403 sin token
#     valido) cuenta como UP; timeout/connection refused cuenta como DOWN.
#   - Bizlinks (SOAP sobre HTTPS): se invoca con credenciales incorrectas a
#     proposito (nunca credenciales reales); un 401/403 con SOAP Fault
#     "Usuario no encontrado" prueba que el pipeline completo (parsing SOAP,
#     autenticacion, backend) esta vivo. Cualquier otra respuesta (200, 5xx,
#     timeout) es DOWN - un 200 en particular seria indicio de bypass de
#     autenticacion, no de servicio saludable.
#
# Exit codes:
#   0 = OK (todos los endpoints responden)
#   1 = DOWN (algun endpoint no responde / timeout / respuesta inesperada)
#   2 = DEGRADADO (responde pero fuera del umbral de latencia)
#
# Uso:
#   ./get-fepe-status.sh            -> texto legible
#   ./get-fepe-status.sh --json     -> salida JSON (Zabbix dependent items)
#   ./get-fepe-status.sh --zabbix   -> imprime el overall_status (0/1/2)

set -uo pipefail

TIMEOUT="${FEPE_HC_TIMEOUT:-8}"
LATENCY_WARN_MS="${FEPE_HC_LATENCY_WARN:-3000}"

WSFE_PROD_URL="http://api.xactoperu.com:8099/api/DocumentoCabeceras"
WSFE_TEST_URL="http://api.xactoperu.com:3636/api/DocumentoCabeceras"
CONSULTA_PROD_URL="http://api.xactoperu.com:6099/api/DocumentoCabeceras/ConsultaDocs"
BIZLINKS_URL="https://pse.bizlinks.com.pe/ws/invoker"

MODE="text"
[[ "${1:-}" == "--json" ]] && MODE="json"
[[ "${1:-}" == "--zabbix" ]] && MODE="zabbix"

TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT

check_endpoint() {
  local name="$1" url="$2" outfile="$3"
  local start end elapsed_ms http_code curl_exit

  start=$(date +%s%3N)
  http_code=$(curl -s -o /dev/null -w '%{http_code}' \
                --max-time "$TIMEOUT" --connect-timeout "$TIMEOUT" \
                -X POST "$url" \
                -H "Content-Type: application/json" \
                -d '{}')
  curl_exit=$?
  end=$(date +%s%3N)
  elapsed_ms=$((end - start))

  local status="UP" code=0
  if [[ $curl_exit -ne 0 || "$http_code" == "000" ]]; then
    status="DOWN"; code=1
  elif (( elapsed_ms > LATENCY_WARN_MS )); then
    status="DEGRADED"; code=2
  fi
  echo "${name}|http=${http_code}|${status}|${elapsed_ms}|${code}" > "$outfile"
}

check_bizlinks() {
  local outfile="$1"
  local soap_body='<soapenv:Envelope xmlns:soapenv="http://schemas.xmlsoap.org/soap/envelope/" xmlns:ws="http://pse.bizlinks.com/">
  <soapenv:Header/>
  <soapenv:Body>
    <ws:invoke>
      <command><![CDATA[<ConsultCmd output="JSON"><parametros/><parameter value="0" name="idEmisor"/></ConsultCmd>]]></command>
    </ws:invoke>
  </soapenv:Body>
</soapenv:Envelope>'
  local start end elapsed_ms http_code curl_exit response body faultstring

  start=$(date +%s%3N)
  response=$(curl -s -w '\n%{http_code}' \
                --max-time "$TIMEOUT" --connect-timeout "$TIMEOUT" \
                -X POST "$BIZLINKS_URL" \
                -H "Content-Type: text/xml; charset=utf-8" \
                -u "healthcheck-probe:not-a-real-password" \
                --data-binary "$soap_body")
  curl_exit=$?
  end=$(date +%s%3N)
  elapsed_ms=$((end - start))

  http_code=$(echo "$response" | tail -n1)
  body=$(echo "$response" | sed '$d')
  faultstring=$(echo "$body" | grep -oP '(?<=<faultstring>)[^<]+')

  local status="UP" code=0
  if [[ $curl_exit -ne 0 || "$http_code" == "000" ]]; then
    status="DOWN"; code=1
  elif [[ "$http_code" != "401" && "$http_code" != "403" ]]; then
    status="DOWN"; code=1   # respuesta inesperada a credenciales invalidas
  elif (( elapsed_ms > LATENCY_WARN_MS )); then
    status="DEGRADED"; code=2
  fi
  echo "Bizlinks|http=${http_code},fault=${faultstring:-none}|${status}|${elapsed_ms}|${code}" > "$outfile"
}

check_endpoint "WsFeProd" "$WSFE_PROD_URL" "$TMPDIR/wsfeprod" &
check_endpoint "WsFeTest" "$WSFE_TEST_URL" "$TMPDIR/wsfetest" &
check_endpoint "ConsultaProd" "$CONSULTA_PROD_URL" "$TMPDIR/consultaprod" &
check_bizlinks "$TMPDIR/bizlinks" &
wait

overall_status=0
results=()
for f in "$TMPDIR/wsfeprod" "$TMPDIR/wsfetest" "$TMPDIR/consultaprod" "$TMPDIR/bizlinks"; do
  IFS='|' read -r name detail status ms code < "$f"
  results+=("${name}|${detail}|${status}|${ms}")
  (( code > overall_status )) && overall_status=$code
done

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
    echo "=== FEPE (Factura Electronica Peru) Healthcheck $(date -Iseconds) ==="
    for r in "${results[@]}"; do
      IFS='|' read -r name detail status ms <<< "$r"
      printf "%-14s %-9s %6sms  %s\n" "$name" "$status" "$ms" "$detail"
    done
    case $overall_status in
      0) echo "Resultado: OK - infraestructura FEPE responde con normalidad." ;;
      1) echo "Resultado: DOWN - al menos un endpoint no responde." ;;
      2) echo "Resultado: DEGRADADO - responde pero con latencia alta (> ${LATENCY_WARN_MS}ms)." ;;
    esac
    ;;
esac

exit $overall_status

# OUTPUT (2026-07-14) - ejecucion ilustrativa de la v1 (secuencial), combinando
# los resultados reales capturados durante la sesion de diseno (ver CX-02 y
# CX-04 mas abajo):
# {"overall_status":1,"checks":[{"service":"WsFeProd","detail":"http=000","status":"DOWN","latency_ms":8003},{"service":"WsFeTest","detail":"http=000","status":"DOWN","latency_ms":8002},{"service":"ConsultaProd","detail":"http=000","status":"DOWN","latency_ms":8001},{"service":"Bizlinks","detail":"http=401,fault=Usuario no encontrado","status":"UP","latency_ms":917}]}
#
# NOTA: la v2 de arriba fue deployada y confirmada en produccion el
# 2026-07-24 — ver CX-08 mas abajo (tiempo total bajo de ~16s a ~8s).


# CX-02 — Test de reachability contra Xacto Peru (UrlWsfeProd) desde Azure Cloud Shell
curl -v --max-time 8 http://api.xactoperu.com:8099/api/DocumentoCabeceras

# OUTPUT (2026-07-14):
# * Host api.xactoperu.com:8099 was resolved.
# * IPv4: 148.72.152.19
# *   Trying 148.72.152.19:8099...
# * Connection timed out after 8000 milliseconds
# * Closing connection
# curl: (28) Connection timed out after 8000 milliseconds
#
# DNS resuelve correctamente; el timeout ocurre en el SYN TCP (sin RST de
# puerto cerrado), consistente con un firewall descartando el paquete en
# silencio para el origen probado, o con el host caido. Ejecutado desde Azure
# Cloud Shell (origen distinto a la maquina local, que tambien timeouteo) -
# descarta que sea un bloqueo del ISP/red local unicamente.


# CX-03 — Obtencion del contrato WSDL publico de Bizlinks (sin credenciales)
curl -s https://pse.bizlinks.com.pe/ws/invoker?wsdl

# OUTPUT (2026-07-14) - resumen (WSDL completo disponible en el endpoint):
# Target namespace: http://pse.bizlinks.com/
# Endpoint: http://pse.bizlinks.com.pe/ws/invoker
# Operaciones: invoke(command:string)->return:string,
#              replicateXml(command:string,xmlSunat:base64,adjuntos:base64)->return:string,
#              updateAttachment(adjuntoCliente:eAdjunto)->return:defaultResult
# Binding: document/literal sobre SOAP/HTTP
#
# El contrato es publico y no requiere autenticacion para consultarse, pero
# la operacion "invoke" es un wrapper opaco (string in/out) - no describe el
# formato real del comando de negocio (ConsultCmd), que fue provisto
# directamente por Bizlinks durante el onboarding, no documentado
# publicamente.


# CX-04 — Prueba de reachability autenticada contra Bizlinks con credenciales
# incorrectas a proposito (nunca se usan credenciales reales de produccion)
curl -s -w '\nHTTP_CODE:%{http_code}\nTIME_MS:%{time_total}\n' \
  --max-time 8 \
  -X POST "https://pse.bizlinks.com.pe/ws/invoker" \
  -H "Content-Type: text/xml; charset=utf-8" \
  -u "healthcheck-probe:not-a-real-password" \
  --data-binary '<soapenv:Envelope xmlns:soapenv="http://schemas.xmlsoap.org/soap/envelope/" xmlns:ws="http://pse.bizlinks.com/">
  <soapenv:Header/>
  <soapenv:Body>
    <ws:invoke>
      <command><![CDATA[<ConsultCmd output="JSON"><parametros/><parameter value="0" name="idEmisor"/></ConsultCmd>]]></command>
    </ws:invoke>
  </soapenv:Body>
</soapenv:Envelope>'

# OUTPUT (2026-07-14):
# <soap:Envelope xmlns:soap="http://schemas.xmlsoap.org/soap/envelope/"><soap:Body><soap:Fault><faultcode>soap:Server</faultcode><faultstring>Usuario no encontrado</faultstring></soap:Fault></soap:Body></soap:Envelope>
# HTTP_CODE:401
# TIME_MS:0.916668
#
# Respuesta esperada: 401 con SOAP Fault "Usuario no encontrado" confirma que
# el pipeline completo (parsing SOAP, extraccion de Basic Auth, validacion
# contra el store de usuarios de Bizlinks) esta operativo, sin necesidad de
# usar ni almacenar una credencial real en el healthcheck.


# CX-05 — Tiempo real de ejecucion de la v1 deployada (2026-07-24), con dos
# endpoints de Xacto Peru caidos simultaneamente
time /usr/bin/get-fepe-status --json

# OUTPUT (2026-07-24):
# {"overall_status":1,"checks":[{"service":"WsFeProd","detail":"http=000","status":"DOWN","latency_ms":8013},{"service":"WsFeTest","detail":"http=000","status":"DOWN","latency_ms":8013},{"service":"ConsultaProd","detail":"http=401","status":"UP","latency_ms":213},{"service":"Bizlinks","detail":"http=401,fault=Usuario no encontrado","status":"UP","latency_ms":108}]}
#
# real    0m16.385s
# user    0m0.094s
# sys     0m0.090s
#
# 16.385s ≈ 8013+8013+213+108 (16.347s) + overhead — suma secuencial, no el
# maximo de los cuatro checks (~8s). Confirma que la v1 deployada corre
# secuencial pese a estar documentada como paralela en el log de la sesion
# 2026-07-14 21:30. Root cause probable: un intento anterior de
# paralelizacion con `&` sobre las funciones originales (que mutan
# `results`/`overall_status` directamente) habria perdido esos resultados en
# la subshell, y probablemente se revirtio sin quedar documentado — de ahi la
# v2 con recoleccion via archivos temporales (ver CX-01 arriba).


# CX-06 — Confirmacion de que el script deployado en el server es la v1
# secuencial (no la version paralela que describe el log de 21:30)
cat /opt/scripts/get-fepe-status.sh

# OUTPUT (2026-07-24): contenido identico a la v1 original de CX-01 (sin
# background jobs, sin `wait`, cuatro llamadas secuenciales al final del
# archivo) — confirmado via lectura completa del archivo en el server.


# CX-07 — Verificacion de Timeout de agente y servidor (descartar drift de
# configuracion como causa alternativa)
grep -n "^Timeout" /etc/zabbix/zabbix_agent2.conf
grep -n "^Timeout" /etc/zabbix/zabbix_server.conf

# OUTPUT (2026-07-24):
# zabbix_agent2.conf:271:Timeout=30
# zabbix_server.conf:516:Timeout=15
#
# Sin drift respecto a lo configurado el 2026-07-14 — descarta un cambio de
# configuracion como causa; la causa raiz es exclusivamente la ejecucion
# secuencial de la v1 (ver CX-05).


# CX-08 — Deploy de la v2 (paralela) y re-test de tiempo real de ejecucion
# ⚠️ ACTION — sobrescribe el script deployado
sudo cp /opt/scripts/get-fepe-status.sh /opt/scripts/get-fepe-status.sh.bak-20260724
# (pegar contenido de la v2, CX-01 arriba, en /opt/scripts/get-fepe-status.sh)
sudo chmod 755 /opt/scripts/get-fepe-status.sh
time /usr/bin/get-fepe-status --json

# OUTPUT (2026-07-24):
# {"overall_status":1,"checks":[{"service":"WsFeProd","detail":"http=000","status":"DOWN","latency_ms":8013},{"service":"WsFeTest","detail":"http=000","status":"DOWN","latency_ms":8014},{"service":"ConsultaProd","detail":"http=401","status":"UP","latency_ms":187},{"service":"Bizlinks","detail":"http=401,fault=Usuario no encontrado","status":"UP","latency_ms":90}]}
#
# real    0m8.028s
# user    0m0.080s
# sys     0m0.064s
#
# 8.028s ≈ max(8013,8014,187,90) — confirma que la v2 acota el tiempo total al
# checkeo mas lento en vez de sumarlos. Con los mismos dos endpoints de Xacto
# Peru caidos que en CX-05 (16.385s con la v1), el tiempo bajo a la mitad y
# queda ampliamente por debajo del Timeout=15 del servidor — resuelve la
# causa raiz del "network error" intermitente visto en el log del servidor
# Zabbix el 2026-07-24 17:19-17:22.
