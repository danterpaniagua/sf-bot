# FEPE (Factura Electronica Peru) Healthcheck — Zabbix Integration Session

Contexto: SmartFran Cloud, Sales API + Function `SmartFran.Cloud.Functions.Sales.TicketProcessAsync`, host de monitoreo `Zabbix server` (FQDN `sf-monitoreo.smartfran.com`), Zabbix 6.0.32 (agent2). Objetivo: monitorear disponibilidad de la infraestructura de Factura Electronica Peru (FEPE) usada para facturar ante SUNAT, e integrarla como item/trigger en Zabbix, siguiendo el mismo patron ya usado para ARCA (ex-AFIP).

## Dependencias identificadas

SmartFran Cloud no integra directamente con SUNAT - factura a traves de dos PSE/OSE intermediarios distintos, cada uno cubriendo una funcion distinta del flujo:

| Proveedor | Funcion | Protocolo | Componente | Config |
|---|---|---|---|---|
| Xacto Peru (`api.xactoperu.com`) | Envio de comprobantes (submission) | REST, puertos no estandar (3636/6099/8099), HTTP plano | `WsFePeService.cs` — Sales API (`SmartFran.Cloud.Sales.Application`) | `appsettings.sample.json`, `Ci.Cd/.../Sales.API_Settings_{TEST,DEV}.json` |
| Bizlinks (`pse.bizlinks.com.pe`) | Consulta de estado de comprobantes ya emitidos | SOAP sobre HTTPS, Basic Auth | `WsFePeService.cs` — Function `TicketProcessAsync` (`DocumentConsultationAsync`) | Agregado en `Documentation/v2.30.00/release_notes.md`, version muy posterior a donde aparece Xacto Peru |

Se confirmo via `git log` que las URLs de Xacto Peru siguen presentes en el commit HEAD del repositorio (`cca9f7cc7`, 2026-07-07), tanto en `appsettings.sample.json` como en los archivos `Ci.Cd/Azure.AppService.Environment/Sales.API_Settings_{TEST,DEV}.json` — no son referencias obsoletas de documentacion antigua. No hay archivo de settings de PROD committeado en el repo para confirmar el valor exacto en produccion.

## Script final: `get-fepe-status.sh`

Ubicacion planeada en el server: `/opt/scripts/get-fepe-status.sh`, symlinkeado desde `/usr/bin/get-fepe-status`.

Chequea cuatro endpoints:
- **WsFeProd / WsFeTest / ConsultaProd** (Xacto Peru): solo reachability HTTP - no existe un metodo "dummy" publico como `FEDummy` de ARCA. Cualquier respuesta HTTP (incluido 401/403 sin token valido) cuenta como UP; timeout/connection refused cuenta como DOWN.
- **Bizlinks**: se invoca la operacion SOAP `invoke` con credenciales Basic Auth incorrectas **a proposito** (nunca se usan ni almacenan credenciales reales en el healthcheck). Un `401`/`403` con SOAP Fault `Usuario no encontrado` prueba que el pipeline completo (parsing SOAP, autenticacion, backend) esta vivo — una señal mas fuerte que solo pedir el WSDL estatico, que puede seguir respondiendo aunque el backend de negocio este caido.

```bash
#!/usr/bin/env bash
#
# get-fepe-status.sh
# Healthcheck de disponibilidad de la infraestructura de Factura Electronica
# Peru (FEPE): Xacto Peru (envio) + Bizlinks (consulta).
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

overall_status=0
results=()

check_endpoint() {
  local name="$1" url="$2"
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
  (( code > overall_status )) && overall_status=$code
  results+=("${name}|http=${http_code}|${status}|${elapsed_ms}")
}

check_bizlinks() {
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
  (( code > overall_status )) && overall_status=$code
  results+=("Bizlinks|http=${http_code},fault=${faultstring:-none}|${status}|${elapsed_ms}")
}

check_endpoint "WsFeProd" "$WSFE_PROD_URL"
check_endpoint "WsFeTest" "$WSFE_TEST_URL"
check_endpoint "ConsultaProd" "$CONSULTA_PROD_URL"
check_bizlinks

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
```

### Salida `--json` de ejemplo

Combinando los resultados reales capturados durante la sesion (CX-02 y CX-04 en el script de comandos):
```json
{"overall_status":1,"checks":[{"service":"WsFeProd","detail":"http=000","status":"DOWN","latency_ms":8003},{"service":"WsFeTest","detail":"http=000","status":"DOWN","latency_ms":8002},{"service":"ConsultaProd","detail":"http=000","status":"DOWN","latency_ms":8001},{"service":"Bizlinks","detail":"http=401,fault=Usuario no encontrado","status":"UP","latency_ms":917}]}
```

`overall_status`: `0` = OK, `1` = DOWN, `2` = DEGRADADO (latencia > `FEPE_HC_LATENCY_WARN`, default 3000ms).

## Hallazgos durante la sesion

1. **Timeout real contra Xacto Peru**: la prueba de conectividad contra `UrlWsfeProd` (puerto 8099) timeouteo tanto desde una maquina local como desde Azure Cloud Shell (dos origenes de red distintos). El DNS resuelve correctamente (`148.72.152.19`); el timeout ocurre en el SYN TCP sin RST — consistente con un firewall descartando el paquete en silencio (posible whitelisting de IP en Xacto Peru) o con el host caido. No se confirmo cual de las dos causas aplica sin probar desde el egress real de produccion (NAT Gateway usado por el App Service de Sales API, via Kudu console) o sin contactar directamente a Xacto Peru.

2. **Segundo proveedor descubierto (Bizlinks)**: no visible al iniciar la sesion; se identifico revisando `Documentation/v2.30.00/release_notes.md`, una version muy posterior a donde aparece Xacto Peru. Bizlinks cubre solo la funcion de consulta (`DocumentConsultationAsync`), no reemplaza la funcion de envio de Xacto Peru.

3. **Credenciales expuestas en texto plano en el repositorio**: `WsFePe__BizlinksUser` y `WsFePe__BizlinksPassword` aparecen en texto plano en `Documentation/v2.30.00/release_notes.md`, committeadas al historial de git. Un grep mas amplio encontro el mismo patron (valores con forma de secreto junto al nombre de su key) en 13 archivos `release_notes.md` distintos a lo largo del arbol de `Documentation/`. Esto es adicional al problema ya conocido y documentado en `cloud/CLAUDE.md` sobre `Business.API/appsettings.json`.

4. **Contrato WSDL de Bizlinks es publico, pero su operacion es opaca**: `https://pse.bizlinks.com.pe/ws/invoker?wsdl` es consultable sin autenticacion, pero solo describe una operacion generica `invoke(command:string)`. El formato real del comando de negocio (`<ConsultCmd>`) no esta documentado publicamente en ningun lado — proviene directamente de lo que Bizlinks entrego a SmartFran durante el onboarding, tal como esta implementado en `WsFePeService.cs:196`.

## Configuracion pendiente (actualizado — ver `_ops-events.md` para el detalle paso a paso de cada sesion)

### Lado agente (Zabbix server) — completado (sesion 2026-07-14 21:30-22:45)
1. ~~Colocar el script en `/opt/scripts/get-fepe-status.sh` con symlink desde `/usr/bin/get-fepe-status`.~~ Hecho.
2. ~~Crear `/etc/zabbix/zabbix_agent2.d/userparameter_fepe.conf` con `UserParameter=fepe.status.raw,/usr/bin/get-fepe-status --json`.~~ Hecho.
3. ~~Reiniciar el agente y verificar con `zabbix_agent2 -t fepe.status.raw`.~~ Hecho, incluyendo el ajuste de `Timeout` en agente y servidor documentado en los Hallazgos de sesion.

### Lado frontend — parcialmente completado (sesion 2026-07-14 22:45-22:50)
4. ~~Item maestro `FEPE Raw Status`~~ Hecho.
5. Items dependientes: **8 de 9 creados** (`overall`, `wsfeprod` status+latencia, `wsfetest` status+latencia, `consultaprod` status, `bizlinks` status+latencia) — `wsfetest` status+latencia creados 2026-07-24, confirmado via listado real de items en el frontend. **Pendiente:** `FEPE ConsultaProd Latency` (diferido).
6. ~~Macros de host~~ Hecho: `{$FEPE.UPDATE.INTERVAL}=1m`, `{$FEPE.LATENCY.WARN}=3000`, `{$FEPE.LATENCY.HIGH}=6000`, `{$FEPE.LATENCY.WARN.RECOVERY}=2400`, `{$FEPE.LATENCY.HIGH.RECOVERY}=4800`, `{$FEPE.LATENCY.AVG.PERIOD}=5m`, `{$FEPE.NODATA.WINDOW}=10m` — valores iniciales sin historial previo, a retunear tras ~2 semanas de datos reales (mismo criterio aplicado a ARCA, que se retuneo con 30 dias de historial real).
7. **Triggers — disenados esta sesion, pendientes de creacion en el frontend.** 9 triggers en total: `FEPE sin datos`, `FEPE DOWN`, `FEPE DEGRADADO`, y pares Latencia Alta/Critica para `WsFeProd`, `WsFeTest` y `Bizlinks` (`ConsultaProd` diferido — su item de latencia todavia no existe, ver punto 5). Mismo patron que ARCA (`ope-zabbix` skill, Step 6), con el no-op `<>"__unused__"` para exponer los cuatro status por servicio en Operational data de DOWN/DEGRADADO. ~~**Bloqueado parcialmente**~~ Desbloqueado 2026-07-24: los items `fepe.status.wsfetest`/`.latency` fueron creados (ver punto 5), asi que `FEPE DOWN`, `FEPE DEGRADADO` y los dos triggers `WsFeTest Latencia` ya pueden guardarse.

```
Name: FEPE sin datos
Severity: Average
Expression: nodata(/Zabbix server/fepe.status.raw,{$FEPE.NODATA.WINDOW})=1
OK event generation: Expression
Operational data: Sin datos hace más de {$FEPE.NODATA.WINDOW}
Depends on: (ninguno)
Tags: service_group = CLOUD
```

```
Name: FEPE DOWN
Severity: High
Expression: last(/Zabbix server/fepe.status.overall)=1 and last(/Zabbix server/fepe.status.wsfeprod)<>"__unused__" and last(/Zabbix server/fepe.status.wsfetest)<>"__unused__" and last(/Zabbix server/fepe.status.consultaprod)<>"__unused__" and last(/Zabbix server/fepe.status.bizlinks)<>"__unused__"
OK event generation: Expression
Operational data: WsFeProd: {ITEM.LASTVALUE2} | WsFeTest: {ITEM.LASTVALUE3} | ConsultaProd: {ITEM.LASTVALUE4} | Bizlinks: {ITEM.LASTVALUE5}
Depends on: FEPE sin datos
Tags: service_group = CLOUD
```

```
Name: FEPE DEGRADADO
Severity: Warning
Expression: last(/Zabbix server/fepe.status.overall)=2 and last(/Zabbix server/fepe.status.wsfeprod)<>"__unused__" and last(/Zabbix server/fepe.status.wsfetest)<>"__unused__" and last(/Zabbix server/fepe.status.consultaprod)<>"__unused__" and last(/Zabbix server/fepe.status.bizlinks)<>"__unused__"
OK event generation: Expression
Operational data: WsFeProd: {ITEM.LASTVALUE2} | WsFeTest: {ITEM.LASTVALUE3} | ConsultaProd: {ITEM.LASTVALUE4} | Bizlinks: {ITEM.LASTVALUE5}
Depends on: FEPE sin datos
Tags: service_group = CLOUD
```

```
Name: FEPE WsFeProd Latencia Alta
Severity: Warning
Expression: avg(/Zabbix server/fepe.status.wsfeprod.latency,{$FEPE.LATENCY.AVG.PERIOD})>{$FEPE.LATENCY.WARN}
OK event generation: Recovery expression
Recovery expression: avg(/Zabbix server/fepe.status.wsfeprod.latency,{$FEPE.LATENCY.AVG.PERIOD})<{$FEPE.LATENCY.WARN.RECOVERY}
Operational data: Latencia promedio: {ITEM.LASTVALUE1}ms (umbral: {$FEPE.LATENCY.WARN}ms)
Depends on: FEPE WsFeProd Latencia Crítica, FEPE DOWN, FEPE sin datos
Tags: service_group = CLOUD
```

```
Name: FEPE WsFeProd Latencia Crítica
Severity: High
Expression: avg(/Zabbix server/fepe.status.wsfeprod.latency,{$FEPE.LATENCY.AVG.PERIOD})>{$FEPE.LATENCY.HIGH}
OK event generation: Recovery expression
Recovery expression: avg(/Zabbix server/fepe.status.wsfeprod.latency,{$FEPE.LATENCY.AVG.PERIOD})<{$FEPE.LATENCY.HIGH.RECOVERY}
Operational data: Latencia promedio: {ITEM.LASTVALUE1}ms (umbral: {$FEPE.LATENCY.HIGH}ms)
Depends on: FEPE DOWN, FEPE sin datos
Tags: service_group = CLOUD
```

```
Name: FEPE WsFeTest Latencia Alta
Severity: Warning
Expression: avg(/Zabbix server/fepe.status.wsfetest.latency,{$FEPE.LATENCY.AVG.PERIOD})>{$FEPE.LATENCY.WARN}
OK event generation: Recovery expression
Recovery expression: avg(/Zabbix server/fepe.status.wsfetest.latency,{$FEPE.LATENCY.AVG.PERIOD})<{$FEPE.LATENCY.WARN.RECOVERY}
Operational data: Latencia promedio: {ITEM.LASTVALUE1}ms (umbral: {$FEPE.LATENCY.WARN}ms)
Depends on: FEPE WsFeTest Latencia Crítica, FEPE DOWN, FEPE sin datos
Tags: service_group = CLOUD
```

```
Name: FEPE WsFeTest Latencia Crítica
Severity: High
Expression: avg(/Zabbix server/fepe.status.wsfetest.latency,{$FEPE.LATENCY.AVG.PERIOD})>{$FEPE.LATENCY.HIGH}
OK event generation: Recovery expression
Recovery expression: avg(/Zabbix server/fepe.status.wsfetest.latency,{$FEPE.LATENCY.AVG.PERIOD})<{$FEPE.LATENCY.HIGH.RECOVERY}
Operational data: Latencia promedio: {ITEM.LASTVALUE1}ms (umbral: {$FEPE.LATENCY.HIGH}ms)
Depends on: FEPE DOWN, FEPE sin datos
Tags: service_group = CLOUD
```

```
Name: FEPE Bizlinks Latencia Alta
Severity: Warning
Expression: avg(/Zabbix server/fepe.status.bizlinks.latency,{$FEPE.LATENCY.AVG.PERIOD})>{$FEPE.LATENCY.WARN}
OK event generation: Recovery expression
Recovery expression: avg(/Zabbix server/fepe.status.bizlinks.latency,{$FEPE.LATENCY.AVG.PERIOD})<{$FEPE.LATENCY.WARN.RECOVERY}
Operational data: Latencia promedio: {ITEM.LASTVALUE1}ms (umbral: {$FEPE.LATENCY.WARN}ms)
Depends on: FEPE Bizlinks Latencia Crítica, FEPE DOWN, FEPE sin datos
Tags: service_group = CLOUD
```

```
Name: FEPE Bizlinks Latencia Crítica
Severity: High
Expression: avg(/Zabbix server/fepe.status.bizlinks.latency,{$FEPE.LATENCY.AVG.PERIOD})>{$FEPE.LATENCY.HIGH}
OK event generation: Recovery expression
Recovery expression: avg(/Zabbix server/fepe.status.bizlinks.latency,{$FEPE.LATENCY.AVG.PERIOD})<{$FEPE.LATENCY.HIGH.RECOVERY}
Operational data: Latencia promedio: {ITEM.LASTVALUE1}ms (umbral: {$FEPE.LATENCY.HIGH}ms)
Depends on: FEPE DOWN, FEPE sin datos
Tags: service_group = CLOUD
```

8. Los 9 triggers llevan el tag `service_group = CLOUD` — el mismo que documenta el ticket de ARCA (`2026-06-06_arca_api_check_ops-events.md`) para rutear a la accion "Google Chat Loyalty to Operaciones", corrigiendo la referencia previa a `LOYALTY` en este ticket (esa era una nota de diseño temprana de ARCA, superada por su propio `_ops-events.md`). **No confirmado de forma independiente para FEPE/SmartFran Cloud** — antes de guardar los triggers en el frontend, verificar en `Alerts → Actions → Trigger actions` que la condicion de esa accion efectivamente matchea `service_group = CLOUD` (o el tag/condicion que corresponda) para el host `Zabbix server`, per skill `ope-zabbix` Step 7.

## Notas de seguridad relevantes al contexto

- El chequeo de Bizlinks usa credenciales deliberadamente invalidas (`healthcheck-probe:not-a-real-password`) en lugar de almacenar una credencial real en un macro de Zabbix — evita el problema de manejo de secretos por completo para este caso de uso, a costa de no poder validar el camino de autenticacion *exitosa* (solo el camino de rechazo, que es suficiente para el proposito de reachability).
- Se encontraron credenciales de produccion (`BizlinksUser`/`BizlinksPassword`) expuestas en texto plano en el historial de git del repositorio (`Documentation/v2.30.00/release_notes.md` y 12 archivos mas) — hallazgo de seguridad independiente del objetivo original de la sesion, documentado en Hallazgos #3.
