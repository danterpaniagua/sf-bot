# Eventos — Integración de healthcheck ARCA (ex-AFIP) en Zabbix

_Nota: la transcripción original de la sesión no incluye marcas horarias; las entradas se registran solo con fecha._

## 2026-06-06 — Desarrollo del script get-arca-status.sh

**Comando:** CX-01 — `get-arca-status.sh`
**Resultado:**
```
{"overall_status":0,"checks":[{"service":"WSAA","detail":"http=200","status":"UP","latency_ms":724},{"service":"WSFEv1","detail":"App=OK,Db=OK,Auth=OK","status":"UP","latency_ms":730}]}
```

He confirmado que WSAA y WSFEv1 responden OK una vez agregado `--ciphers 'DEFAULT@SECLEVEL=1'` a los curl; sin ese flag, WSFEv1 fallaba con `dh key too small` (OpenSSL 3.0 rechazando el DHE débil de ARCA).

## 2026-06-06 — Diagnóstico de permisos del script

**Comando:** CX-02 — `namei -l /home/ubuntu/scritps/get-arca-status.sh`
**Resultado:**
```
/home/ubuntu con permisos drwxr-x--- (750)
```

He identificado que el bloqueo para el usuario `zabbix` estaba en el permiso del directorio `/home/ubuntu`, no en el archivo (que ya tenía 777).

## 2026-06-06 — Reubicación del script

**Comando:** CX-03 — reubicación a `/opt/scripts` y symlink
**Resultado:**
```
/opt/scripts/get-arca-status.sh (755) -> symlink /usr/bin/get-arca-status
```

He movido el script fuera del home personal para eliminar el bloqueo de permisos sobre el usuario `zabbix`.

## 2026-06-06 — Creación del UserParameter

**Comando:** CX-04 — `/etc/zabbix/zabbix_agent2.d/userparameter_arca.conf`
**Resultado:**
```
UserParameter=arca.status.raw,/usr/bin/get-arca-status --json
```

He creado el UserParameter que expone el healthcheck como key `arca.status.raw` para el agente Zabbix.

## 2026-06-06 — Restart del agente y validación de la key

**Comando:** CX-05 / CX-06 — restart de `zabbix-agent2` + `zabbix_agent2 -t arca.status.raw`
**Resultado:**
```
Antes del restart: ZBX_NOTSUPPORTED [Unknown metric]
Después del restart: arca.status.raw [t|{"overall_status":0,"checks":[...]}]
```

He confirmado vía `journalctl -u zabbix-agent2` que el error inicial se debía a que el agente no había recargado el `.conf`; tras el restart, la key responde correctamente. Queda pendiente la configuración del item maestro, items dependientes y triggers en el frontend de Zabbix.

## 2026-07-14 — Verificación de items en Latest data

**Resultado:**
```
ARCA Raw Status              arca.status.raw               Zabbix agent      Enabled
ARCA Raw Status: ARCA Overall Status    arca.status.overall       Dependent item    Enabled
ARCA Raw Status: ARCA WSAA Status       arca.status.wsaa          Dependent item    Enabled
ARCA Raw Status: ARCA WSFEv1 Status     arca.status.wsfev1        Dependent item    Enabled
ARCA Raw Status: ARCA WSFEv1 Latency    arca.status.wsfev1.latency Dependent item   Enabled
```

He confirmado que el item maestro y los 4 items dependientes están creados, habilitados y poblando datos desde el 2026-06-06. Queda pendiente crear los triggers y aplicar el tag `service_group: CLOUD` para que la acción "Google Chat Loyalty to Operaciones" enrute las alertas.

## 2026-07-14 — Creación de los 5 triggers ARCA

**Resultado:**
```
ARCA DOWN                     — High     — Enabled — Depends on: ARCA sin datos
ARCA DEGRADADO                — Warning  — Enabled — Depends on: ARCA sin datos
ARCA sin datos                — Average  — Enabled — (sin dependencias)
ARCA WSFEv1 Latencia Alta     — Warning  — Enabled — Depends on: ARCA WSFEv1 Latencia Crítica, ARCA DOWN, ARCA sin datos
ARCA WSFEv1 Latencia Crítica  — High     — Enabled — Depends on: ARCA DOWN, ARCA sin datos
```

He creado los 5 triggers con umbrales derivados de 30 días de latencia real (min 396ms, avg 773ms, max 2172ms → Warning 2500ms, High 5000ms), recovery expressions con histéresis (`{$ARCA.LATENCY.WARN.RECOVERY}=2000`, `{$ARCA.LATENCY.HIGH.RECOVERY}=4000`) para evitar flapping, Operational data exponiendo el estado de WSAA/WSFEv1 y la latencia actual en la lista de problemas, y la cadena completa de dependencias para evitar alertas duplicadas por la misma causa raíz. Durante la configuración, `length(/host/key,#1)>=0` como cláusula no-op falló con `incorrect usage of function "length"` — esa función no existe en Zabbix 6.0 (agregada recién en 6.4) — se reemplazó por `last(/host/key)<>"__unused__"`, válido en 6.0. Este hallazgo se documentó en el skill `/ope-zabbix`. Queda pendiente aplicar el tag `service_group: CLOUD` en los 5 triggers para que la acción "Google Chat Loyalty to Operaciones" enrute las alertas.

## 2026-07-14 — Macro para Update interval del item maestro

**Resultado:**
```
{$ARCA.UPDATE.INTERVAL} = 1m
Item "ARCA Raw Status" → Update interval: {$ARCA.UPDATE.INTERVAL} (reemplaza el valor fijo "1m")
```

He movido el intervalo de polling del item maestro a un macro para evitar el valor fijo en el item, consistente con el resto de los umbrales. `{$ARCA.NODATA.WINDOW}` (10m) se deriva proporcionalmente de este intervalo (~10x) — si se cambia `{$ARCA.UPDATE.INTERVAL}` a futuro, revisar también `{$ARCA.NODATA.WINDOW}`. Patrón documentado en el skill `/ope-zabbix`.
