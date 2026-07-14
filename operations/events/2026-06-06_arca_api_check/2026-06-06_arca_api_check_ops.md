# [OPS] Integración de healthcheck ARCA (ex-AFIP) en Zabbix — items y triggers pendientes

**Fecha:** 2026-06-06
**Estado:** Abierto
**Severidad:** Media
**Host:** `Zabbix server` (FQDN `sf-monitoreo.smartfran.com`), Zabbix 6.0.32 (agent2)

---

## Resumen

No existe monitoreo automatizado de la disponibilidad de los webservices de ARCA (ex-AFIP) — WSAA y WSFEv1 — utilizados para facturación electrónica en el POS de SmartFran. Se desarrolló y validó en el servidor de monitoreo el script `get-arca-status.sh`, que chequea ambos servicios y expone el resultado en JSON vía un `UserParameter` del agente Zabbix (`arca.status.raw`). El script funciona correctamente de forma manual (`zabbix_agent2 -t arca.status.raw`), pero falta crear el item maestro, los items dependientes, los triggers y la conexión a la alerta de Google Chat en el frontend de Zabbix para que el monitoreo quede activo.

---

## Tabla resumen

| Ítem | Detalle |
|---|---|
| Host Zabbix | `Zabbix server` (`sf-monitoreo.smartfran.com`, self-monitoring, `Server=127.0.0.1`) |
| Script | `/opt/scripts/get-arca-status.sh` (symlink `/usr/bin/get-arca-status`) |
| UserParameter | `arca.status.raw` → `/etc/zabbix/zabbix_agent2.d/userparameter_arca.conf` |
| Servicios chequeados | WSAA (`wsaa.afip.gov.ar`, solo reachability) / WSFEv1 (`servicios1.afip.gov.ar`, método oficial `FEDummy`) |
| Estado del agente | UserParameter validado (`zabbix_agent2 -t arca.status.raw` OK) |
| Estado del frontend | Sin item maestro ni items dependientes ni triggers creados |

---

## Causa raíz

No existía mecanismo de monitoreo proactivo para la disponibilidad de ARCA. Ante una caída o degradación del servicio, la detección dependía de reportes reactivos desde el negocio (fallas de facturación en el POS) en lugar de una alerta temprana desde Zabbix.

---

## Hallazgos

Durante el desarrollo y prueba del script se identificaron y resolvieron los siguientes problemas:

| # | Hallazgo | Causa | Resolución |
|---|---|---|---|
| 1 | Falso DOWN por TLS al contra WSFEv1 (`curl: (35) ... dh key too small`) | ARCA negocia DHE con parámetros de clave chicos; OpenSSL 3.0 con `SECLEVEL=2` (default) rechaza el handshake | Se agregó `--ciphers 'DEFAULT@SECLEVEL=1'` a ambos `curl` del script |
| 2 | Script inaccesible para el usuario `zabbix` | `/home/ubuntu` tenía permisos `drwxr-x---` (750), bloqueando a cualquier usuario fuera del grupo `ubuntu` — el `chmod 777` del archivo era irrelevante | Script reubicado a `/opt/scripts/get-arca-status.sh` con symlink desde `/usr/bin/get-arca-status` |
| 3 | Confusión entre Script manual y UserParameter en Zabbix | El comando se había cargado como "Script" en Alerts → Scripts (ejecución manual on-demand, sin historial ni triggers) | Se aclaró que el monitoreo continuo con triggers requiere un item respaldado por un UserParameter en el agente; el Script manual queda como herramienta complementaria para re-chequeos ad-hoc |
| 4 | `ZBX_NOTSUPPORTED [Unknown metric]` al testear `arca.status.raw` | El agente no se reinició después de crear `userparameter_arca.conf` (confirmado comparando timestamps en `journalctl -u zabbix-agent2`) | Restart del agente posterior a la creación del archivo; test posterior devolvió el JSON correctamente |
| 5 | Nombre de host `Zabbix server` parecía default de fábrica | Se confirmó que es correcto: `sf-monitoreo.smartfran.com` es el propio server de Zabbix monitoreándose a sí mismo | Sin acción — comportamiento esperado |

---

## Recursos afectados

| Recurso | Tipo | Ubicación |
|---|---|---|
| `get-arca-status.sh` | Script bash | `/opt/scripts/get-arca-status.sh` (symlink `/usr/bin/get-arca-status`) |
| `userparameter_arca.conf` | Config agente Zabbix | `/etc/zabbix/zabbix_agent2.d/userparameter_arca.conf` |
| `Zabbix server` | Host Zabbix | `sf-monitoreo.smartfran.com` |
| WSAA | Webservice ARCA | `wsaa.afip.gov.ar` |
| WSFEv1 | Webservice ARCA | `servicios1.afip.gov.ar` |

---

## Comandos ejecutados

| # | Comando/Script | Propósito |
|---|---|---|
| CX-01 | `2026-06-06_arca_api_check_scripts.sh` | Script `get-arca-status.sh` — healthcheck WSAA/WSFEv1 |
| CX-02 | `2026-06-06_arca_api_check_scripts.sh` | Diagnóstico de permisos con `namei -l` |
| CX-03 | `2026-06-06_arca_api_check_scripts.sh` | Reubicación del script a `/opt/scripts` y symlink |
| CX-04 | `2026-06-06_arca_api_check_scripts.sh` | Creación del UserParameter `arca.status.raw` |
| CX-05 | `2026-06-06_arca_api_check_scripts.sh` | Restart del agente Zabbix |
| CX-06 | `2026-06-06_arca_api_check_scripts.sh` | Verificación de la key con `zabbix_agent2 -t` |

---

## Acciones propuestas

### Configuración de frontend (pendiente, bloquea el monitoreo activo)

1. **Crear el item maestro** en `Data collection → Hosts → Zabbix server → Items`: Name `ARCA Raw Status`, Type `Zabbix agent`, Key `arca.status.raw`, Type of information `Text`, Update interval `1m`.
2. **Crear los items dependientes** (Type: Dependent item, Master item: `ARCA Raw Status`) con preprocessing JSONPath:

   | Name | Key | JSONPath | Type of info |
   |---|---|---|---|
   | ARCA Overall Status | `arca.status.overall` | `$.overall_status` | Numeric (unsigned) |
   | ARCA WSAA Status | `arca.status.wsaa` | `$.checks[?(@.service=='WSAA')].status.first()` | Text |
   | ARCA WSFEv1 Status | `arca.status.wsfev1` | `$.checks[?(@.service=='WSFEv1')].status.first()` | Text |
   | ARCA WSFEv1 Latency | `arca.status.wsfev1.latency` | `$.checks[?(@.service=='WSFEv1')].latency_ms.first()` | Numeric (unsigned) |

3. **Testear cada JSONPath** con el botón "Test" del preprocessing antes de guardar cada item dependiente.
4. **Confirmar en `Monitoring → Latest data`** que `arca.status.raw` y los items dependientes empiezan a poblarse.
5. **Crear los tres triggers:**
   ```
   last(/Zabbix server/arca.status.overall)=1   → DOWN (severidad sugerida: High/Disaster)
   last(/Zabbix server/arca.status.overall)=2   → DEGRADADO (severidad sugerida: Warning)
   nodata(/Zabbix server/arca.status.raw,10m)=1 → sin datos recientes (script/cron caído)
   ```
6. **Conectar los triggers de DOWN/DEGRADADO a la alerta de Google Chat**, reutilizando el webhook ya configurado para el service group LOYALTY.

### Mejoras evaluadas, no implementadas

7. **Evaluar reintentos en el script** antes de marcar DOWN, para filtrar fallos transitorios de red.
8. **Extender a otros webservices de ARCA** (WSFEX, WSMTXCA, padrón) si se requieren en el futuro — agregar como nuevas funciones `check_*` siguiendo el mismo patrón y sumar los JSONPath dependientes correspondientes.

---

## Hallazgos secundarios

- Se evitó deliberadamente `system.run[command,<mode>]` de Zabbix (permite al server pedirle al agente ejecutar comandos arbitrarios) en favor de UserParameter (comando fijo, definido localmente en el agente, no modificable desde el server/frontend). Esto es consistente con el perfil de seguridad de SmartFran dado el incidente previo de enumeración/DNI en SmartLoyalty.
