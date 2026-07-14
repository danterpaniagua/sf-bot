# ARCA Healthcheck — Zabbix Integration Session

Contexto: SmartFran, host `Zabbix server` (FQDN `sf-monitoreo.smartfran.com`), Zabbix 6.0.32 (agent2). Objetivo: monitorear disponibilidad de los webservices de ARCA (ex-AFIP) — WSAA y WSFEv1 — e integrarlo como item/trigger en Zabbix.

## Script final: `get-arca-status.sh`

Ubicación en el server: `/opt/scripts/get-arca-status.sh`, symlinkeado desde `/usr/bin/get-arca-status`.

Chequea dos cosas:
- **WSAA** (`wsaa.afip.gov.ar`): solo reachability HTTP (no tiene método dummy propio).
- **WSFEv1** (`servicios1.afip.gov.ar`): usa el método oficial `FEDummy` vía SOAP POST, que no requiere certificado ni token, y devuelve el estado de `AppServer`, `DbServer` y `AuthServer` por separado. Esto detecta casos donde el endpoint HTTP responde 200 pero el backend (DB o Auth) está caído — algo que un curl genérico no vería.

Incluye el flag `--ciphers 'DEFAULT@SECLEVEL=1'` en ambos curl porque el server de ARCA todavía negocia DHE con parámetros de clave chicos ("dh key too small"), y OpenSSL 3.0 con el `SECLEVEL` default (2) rechaza el handshake. Esto no es un problema de ARCA estar caída — es un default de seguridad de OpenSSL 3.x más estricto que lo que ese server soporta.

```bash
#!/usr/bin/env bash
#
# healthcheck_arca.sh
# Chequea disponibilidad de los webservices de ARCA (ex-AFIP) en producción.
#
# WSAA: solo reachability (no tiene método dummy).
# WSFEv1: usa FEDummy, el healthcheck oficial de ARCA (sin cert/token),
#         que devuelve el estado de AppServer / DbServer / AuthServer.
#
# Exit codes:
#   0 = OK (todo responde y en OK)
#   1 = DOWN (algún componente no responde o devuelve distinto de OK)
#   2 = DEGRADADO (responde OK pero fuera del umbral de latencia)
#
# Uso:
#   ./healthcheck_arca.sh            -> texto legible
#   ./healthcheck_arca.sh --json     -> salida JSON (para Graylog / webhook / Zabbix dependent items)
#   ./healthcheck_arca.sh --zabbix   -> imprime el overall_status (0/1/2), para UserParameter

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
```

### Salida `--json` de ejemplo (real, capturada en la sesión)

```json
{"overall_status":0,"checks":[{"service":"WSAA","detail":"http=200","status":"UP","latency_ms":724},{"service":"WSFEv1","detail":"App=OK,Db=OK,Auth=OK","status":"UP","latency_ms":730}]}
```

`overall_status`: `0` = OK, `1` = DOWN, `2` = DEGRADADO (latencia > `ARCA_HC_LATENCY_WARN`, default 3000ms).

## Problemas encontrados y resueltos durante la sesión

1. **Falso DOWN por TLS**: primer intento de curl contra WSFEv1 devolvió `curl: (35) OpenSSL/3.0.13: error:0A00018A:SSL routines::dh key too small` en ~300ms (no timeout). Causa: ARCA negocia DHE con parámetros débiles; OpenSSL 3.0 con `SECLEVEL=2` default lo rechaza. Fix: `--ciphers 'DEFAULT@SECLEVEL=1'` en el curl. Confirmado con `FEDummy` devolviendo `App=OK,Db=OK,Auth=OK` una vez aplicado el fix.

2. **Script inaccesible para el usuario `zabbix`**: el script vivía en `/home/ubuntu/scritps/get-arca-status.sh` (chmod 777 en el archivo, pero irrelevante). Diagnóstico con `namei -l` mostró que `/home/ubuntu` tenía permisos `drwxr-x---` (750), bloqueando el paso de cualquier usuario fuera del grupo `ubuntu`. Fix: mover el script a `/opt/scripts/get-arca-status.sh` (fuera del home de un usuario personal) y symlinkear desde `/usr/bin/get-arca-status`.

3. **Confusión Script manual vs. UserParameter**: se había cargado el comando como un "Script" en Alerts → Scripts de Zabbix (ejecución manual on-demand desde el frontend, sin historial ni triggers posibles). Aclarado que para monitoreo continuo con triggers se necesita un **item** respaldado por un **UserParameter** en el agente — son cosas distintas y complementarias, el Script manual sirve para re-chequeos ad-hoc pero no reemplaza al item.

4. **`ZBX_NOTSUPPORTED [Unknown metric]`** al testear `zabbix_agent2 -t arca.status.raw`: causa fue que el agente no había reiniciado *después* de crear el archivo `/etc/zabbix/zabbix_agent2.d/userparameter_arca.conf`. Confirmado vía `journalctl -u zabbix-agent2` comparando timestamps. Tras un restart posterior a la creación del archivo, el test funcionó y devolvió el JSON correctamente.

5. **`Hostname=Zabbix server`**: parecía sospechoso (nombre default de fábrica) pero se confirmó que es correcto — la VM `sf-monitoreo.smartfran.com` es el propio server de Zabbix monitoreándose a sí mismo (`Server=127.0.0.1`), así que el host en el frontend correctamente se llama `Zabbix server`, no `sf-monitoreo`.

## Configuración final del agente

`/etc/zabbix/zabbix_agent2.d/userparameter_arca.conf`:
```
UserParameter=arca.status.raw,/usr/bin/get-arca-status --json
```

Verificación:
```bash
sudo -u zabbix zabbix_agent2 -t arca.status.raw
```

## Configuración pendiente/planeada en el frontend

**Item maestro** (host: `Zabbix server`):
| Campo | Valor |
|---|---|
| Name | ARCA Raw Status |
| Type | Zabbix agent |
| Key | `arca.status.raw` |
| Type of information | Text |
| Update interval | 1m |

**Items dependientes** (Type: Dependent item, Master item: ARCA Raw Status), con preprocessing JSONPath:

| Name | Key | JSONPath | Type of info |
|---|---|---|---|
| ARCA Overall Status | `arca.status.overall` | `$.overall_status` | Numeric (unsigned) |
| ARCA WSAA Status | `arca.status.wsaa` | `$.checks[?(@.service=='WSAA')].status.first()` | Text |
| ARCA WSFEv1 Status | `arca.status.wsfev1` | `$.checks[?(@.service=='WSFEv1')].status.first()` | Text |
| ARCA WSFEv1 Latency | `arca.status.wsfev1.latency` | `$.checks[?(@.service=='WSFEv1')].latency_ms.first()` | Numeric (unsigned) |

**Triggers**:
```
last(/Zabbix server/arca.status.overall)=1   → DOWN (severidad sugerida: High/Disaster)
last(/Zabbix server/arca.status.overall)=2   → DEGRADADO (severidad sugerida: Warning)
nodata(/Zabbix server/arca.status.raw,10m)=1 → sin datos recientes (script/cron caído)
```

## Pendiente / próximos pasos (no completado en esta sesión)

- Crear el item maestro y los dependientes en el frontend de Zabbix (Data collection → Hosts → `Zabbix server` → Items).
- Confirmar en **Monitoring → Latest data** que `arca.status.raw` empieza a poblarse.
- Testear cada JSONPath con el botón "Test" del preprocessing antes de guardar.
- Crear los tres triggers.
- Conectar el trigger de DOWN/DEGRADADO a la alerta de Google Chat (reusando el webhook ya configurado para el service group LOYALTY, de una sesión previa).
- Evaluar agregar reintentos en el script antes de marcar DOWN, para filtrar fallos transitorios de red (discutido pero no implementado).
- Si se agregan más webservices de ARCA en el futuro (WSFEX, WSMTXCA, padrón), sumarlos como nuevas funciones `check_*` siguiendo el mismo patrón, y actualizar los JSONPath dependientes si se quiere exponerlos como items separados.

## Notas de seguridad relevantes al contexto

- Se evitó deliberadamente `system.run[command,<mode>]` de Zabbix (permite al server pedirle al agente ejecutar comandos arbitrarios) en favor de UserParameter (comando fijo, definido localmente en el agente, no modificable desde el server/frontend). Esto es consistente con el perfil de seguridad de SmartFran dado el incidente previo de enumeración/DNI en SmartLoyalty.