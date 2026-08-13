# [OPS] Monitoreo de infraestructura FEPE (Factura Electronica Peru) en Zabbix — pendiente de implementacion

**Fecha:** 2026-07-14
**Estado:** Abierto
**Severidad:** Media
**Host:** `Zabbix server` (FQDN `sf-monitoreo.smartfran.com`), Zabbix 6.0.32 (agent2)

---

## Resumen

No existe monitoreo automatizado de la disponibilidad de la infraestructura de Factura Electronica Peru (FEPE) usada por SmartFran Cloud para facturar ante SUNAT. SmartFran Cloud no integra directamente con SUNAT: depende de dos proveedores PSE/OSE distintos — Xacto Peru (envio de comprobantes, via Sales API) y Bizlinks (consulta de comprobantes, via la Function `TicketProcessAsync`) — y ninguno de los dos tiene visibilidad en Zabbix hoy. Se diseñara e integrara el script `get-fepe-status.sh`, siguiendo el mismo patron ya validado para el monitoreo de ARCA (ex-AFIP), como item/trigger en el host de monitoreo.

Durante la sesion de diseño se validó la logica de deteccion contra los cuatro endpoints reales (ver Comandos ejecutados) y se detectaron dos hallazgos independientes que requieren seguimiento propio: un timeout de conectividad real contra Xacto Peru, y credenciales de Bizlinks expuestas en texto plano en la documentacion versionada del repositorio.

---

## Tabla resumen

| Item | Detalle |
|---|---|
| Host Zabbix | `Zabbix server` (`sf-monitoreo.smartfran.com`, self-monitoring, `Server=127.0.0.1`) |
| Script planeado | `/opt/scripts/get-fepe-status.sh` (symlink `/usr/bin/get-fepe-status`) — **no desplegado todavia** |
| UserParameter planeado | `fepe.status.raw` → `/etc/zabbix/zabbix_agent2.d/userparameter_fepe.conf` — **no creado todavia** |
| Servicios a chequear | Xacto Peru: `WsFeProd`/`WsFeTest`/`ConsultaProd` (reachability REST) / Bizlinks: consulta SOAP con credenciales invalidas a proposito |
| Estado del script | Logica validada manualmente contra los cuatro endpoints reales via `curl` (ver Comandos ejecutados) |
| Estado del agente | Sin cambios — nada desplegado en el server de Zabbix todavia |
| Estado del frontend | Sin item maestro, dependientes, macros ni triggers creados |

---

## Causa raíz

No existia mecanismo de monitoreo proactivo para la disponibilidad de la infraestructura de facturacion electronica de Peru. Ante una caida o degradacion de Xacto Peru o Bizlinks, la deteccion dependeria de reportes reactivos desde el negocio (fallas de facturacion en el POS de franquicias en Peru) en lugar de una alerta temprana desde Zabbix — el mismo gap que ya existia para ARCA antes de esa integracion.

---

## Hallazgos

| # | Hallazgo | Detalle |
|---|---|---|
| 1 | Dos proveedores PSE/OSE distintos, no uno | Xacto Peru (`api.xactoperu.com`, REST, envio) y Bizlinks (`pse.bizlinks.com.pe`, SOAP, consulta) cubren funciones distintas del mismo flujo de facturacion Peru. Bizlinks fue agregado en una version muy posterior (`v2.30.00`) a donde aparece Xacto Peru, y no reemplaza su funcion. |
| 2 | Ninguno de los dos expone un metodo "dummy" publico | A diferencia de `FEDummy` de ARCA, ni Xacto Peru ni Bizlinks tienen un metodo de healthcheck oficial. Se diseño una alternativa: reachability simple para Xacto Peru, e invocacion con credenciales incorrectas a proposito para Bizlinks (el 401/SOAP Fault resultante confirma que el pipeline completo esta vivo, sin necesidad de almacenar una credencial real). |
| 3 | Timeout real contra Xacto Peru (`UrlWsfeProd`, puerto 8099) | Confirmado desde dos origenes de red distintos (maquina local y Azure Cloud Shell), y sostenido en produccion desde el 2026-07-24 (ver `_ops-events.md`, trigger `FEPE DOWN` disparado con 7+ polls consecutivos en DOWN). El timeout ocurre en el SYN TCP sin RST — consistente con un firewall descartando el paquete en silencio o con el servicio cerrado en ese puerto. `api.xactoperu.com` resuelve a IPs distintas entre pruebas (`148.72.152.19` el 2026-07-14, `62.171.163.239` el 2026-07-24), consistente con DNS round-robin sobre multiples backends — no un host fijo. Dato mas preciso obtenido el 2026-07-24: en la **misma IP** (`62.171.163.239`), el puerto 6099 (`ConsultaProd`) responde con normalidad (`401`, Kestrel) mientras el puerto 8099 (`WsFeProd`) timeoutea — descarta una caida total de ese backend especifico, y acota el problema a un bloqueo por puerto (8099, probablemente tambien 3636 de `WsFeTest`) en lugar de por host o de una caida global de Xacto Peru. Sigue sin confirmarse si ese bloqueo por puerto es intencional del lado de Xacto Peru (firewall/whitelisting que no cubre 8099/3636) o una falla de su lado en esos puertos especificos — requiere prueba desde el egress real de produccion (Kudu console del App Service de Sales API) o contacto directo con Xacto Peru. **Este hallazgo es independiente del objetivo de esta sesion y podria requerir su propio ticket de investigacion.** |
| 4 | Credenciales en texto plano en el historial de `Documentation/*/release_notes.md` | Un primer barrido con un heuristico amplio marco 13 archivos; tras clasificar cada coincidencia manualmente (nombre de key + forma del valor, sin exponer valores), el desglose real es: **5 archivos con credenciales confirmadas** (incluye un par de credenciales de AWS access key/secret en texto plano — mas grave que el hallazgo original de Bizlinks, ya que un access key de AWS puede tener alcance a nivel de cuenta segun la policy IAM asociada), **2 archivos con valores de 394-401 caracteres bajo una key `FabricConnections:*`** (forma consistente con un connection string completo, no confirmado con certeza), **2 archivos con valores ambiguos** que requieren revision manual, y **5 archivos que resultaron ser falsos positivos** (URLs de endpoints, no credenciales). Ver tabla detallada mas abajo. Hallazgo de seguridad independiente, adicional al ya conocido sobre `Business.API/appsettings.json` (documentado en `cloud/CLAUDE.md`). |

### Detalle del Hallazgo 4 — archivos, commits y keys afectadas (sin valores)

**Credenciales confirmadas:**

| Archivo | Commit | Fecha | Key(s) |
|---|---|---|---|
| `Documentation/v0.17.00/release_notes.md` | `84a9eb971b8cb24b899aae857f7ff83496d9e607` | 2025-02-04 | `Platform\|PrinterLicense__NeodynamicLicenseKey` |
| `Documentation/v1.17.00/release_notes.md` | `3666ca7debec24d51331c6c680bc75763320c87c` | 2025-02-25 | `Platform\|PrinterLicense__NeodynamicLicenseKey` (misma key repetida) |
| `Documentation/v1.0.6/release_notes.md` | `903cf74b230f2a3bd04af3142cd19a0e64cc5ee0` | 2024-09-05 | `AWS__AwsCredentials__accessKeyId` + `secretAccessKey` (STG y PROD) |
| `Documentation/v1.0.8/release_notes.md` | `95bc15213532fd114184b18327bee9b9369a98c0` | 2024-09-26 | `AWS__AwsCredentials__accessKeyId` + `secretAccessKey` (PROD) |
| `Documentation/v2.30.00/release_notes.md` | `e9fd22f27f833f9b34d6bde0516e89194777cf5f` | 2026-06-14 | `WsFePe__BizlinksPassword` + `BizlinksUser` (STG y PROD) — hallazgo original de la sesion |

**Probables credenciales, sin confirmar (valores de 394-401 caracteres, forma consistente con connection string completo):**

| Archivo | Commit | Fecha | Key(s) |
|---|---|---|---|
| `Documentation/v2.18.00/release_notes.md` | `58ad27c1ebe9910da85b99ca44e7bded0cff679d` | 2026-03-23 | `FabricConnections:Favourites`, `FabricConnections:SalesConsistency` |
| `Documentation/v2.23.00/release_notes.md` | `179f0ddde199b9c8e90dbc723ea3a45dbe260502` | 2026-04-30 | `FabricConnections:StockConsistency` |

**Ambiguos, requieren revision manual:**

| Archivo | Commit | Fecha | Key(s) |
|---|---|---|---|
| `Documentation/v1.0.15/release_notes.md` | `e66467e9b60eeddada3a9655daae4aa525345935` | 2024-12-24 | `Business\|VendorInvoice` |
| `Documentation/v1.17.00/release_notes.md` | `3666ca7debec24d51331c6c680bc75763320c87c` | 2025-02-25 | `GridoOrg` ×4 (Admin/Pos, STG/PRO) — probable identificador de organizacion/conexion Auth0, no necesariamente secreto |

**Falsos positivos descartados** (URLs de endpoints, no credenciales): `v1.0.14` (URL AFIP), `v1.0.16` (URL de cola SQS de AWS), `v1.18.00` y `v1.21.00` (URLs de Xacto Peru, ya conocidas — ver Hallazgo 1), `v2.06.00` (URLs de endpoints WsFeUy Uruguay).

---

## Recursos afectados

| Recurso | Tipo | Ubicacion |
|---|---|---|
| `get-fepe-status.sh` | Script bash (diseñado, no desplegado) | Planeado: `/opt/scripts/get-fepe-status.sh` (symlink `/usr/bin/get-fepe-status`) |
| `userparameter_fepe.conf` | Config agente Zabbix (no creado) | Planeado: `/etc/zabbix/zabbix_agent2.d/userparameter_fepe.conf` |
| `Zabbix server` | Host Zabbix | `sf-monitoreo.smartfran.com` |
| Xacto Peru | PSE — envio de comprobantes | `api.xactoperu.com` (puertos 3636/6099/8099) |
| Bizlinks | PSE — consulta de comprobantes | `pse.bizlinks.com.pe` |
| Sales API | Servicio SmartFran Cloud | `SmartFran.Cloud.Sales.Application/Services/WsFePeService.cs` |
| Function TicketProcessAsync | Servicio SmartFran Cloud | `SmartFran.Cloud.Functions.Sales.TicketProcessAsync/.../WsFePeService.cs` |

---

## Comandos ejecutados

| # | Comando/Script | Proposito |
|---|---|---|
| CX-01 | `20260714_fepe_zabbix_healthcheck_scripts.sh` | Script `get-fepe-status.sh` — healthcheck de los 4 endpoints FEPE |
| CX-02 | `20260714_fepe_zabbix_healthcheck_scripts.sh` | Test de reachability contra Xacto Peru (`UrlWsfeProd`) desde Azure Cloud Shell — timeout confirmado |
| CX-03 | `20260714_fepe_zabbix_healthcheck_scripts.sh` | Obtencion del contrato WSDL publico de Bizlinks |
| CX-04 | `20260714_fepe_zabbix_healthcheck_scripts.sh` | Prueba de reachability autenticada contra Bizlinks con credenciales invalidas a proposito |

---

## Acciones propuestas

### Despliegue en el agente (pendiente, bloquea el monitoreo)

1. Colocar `get-fepe-status.sh` en `/opt/scripts/get-fepe-status.sh` (fuera de cualquier home personal) y symlinkear desde `/usr/bin/get-fepe-status`.
2. Crear `/etc/zabbix/zabbix_agent2.d/userparameter_fepe.conf` con `UserParameter=fepe.status.raw,/usr/bin/get-fepe-status --json`.
3. Reiniciar el agente (`systemctl restart zabbix-agent2`) y confirmar que el restart no afecta el resto de los items del host (incluyendo `arca.status.raw`), revisando `journalctl -u zabbix-agent2` y re-testeando `zabbix_agent2 -t arca.status.raw` despues del restart.
4. Verificar la key con `zabbix_agent2 -t fepe.status.raw`.

### Configuracion de frontend (pendiente)

5. Crear el item maestro `FEPE Raw Status` (Type: Zabbix agent, Key: `fepe.status.raw`, Type of information: Text, Update interval: `{$FEPE.UPDATE.INTERVAL}`).
6. Crear los items dependientes (overall + status/latencia de `wsfeprod`, `wsfetest`, `consultaprod`, `bizlinks`) con preprocessing JSONPath, testeando cada uno antes de guardar.
7. Crear las macros de host `{$FEPE.UPDATE.INTERVAL}`, `{$FEPE.LATENCY.WARN}`, `{$FEPE.LATENCY.HIGH}` y sus `.RECOVERY`, `{$FEPE.LATENCY.AVG.PERIOD}`, `{$FEPE.NODATA.WINDOW}` — valores iniciales sin historial, a retunear tras ~2 semanas de datos reales via Monitoring → Latest data → Graph.
8. Crear los triggers `FEPE DOWN`, `FEPE DEGRADADO`, `FEPE sin datos`, y los pares de Latencia Alta/Critica por servicio, con la cadena de dependencias completa (mismo patron que ARCA).
9. Confirmar cual accion/tag de Zabbix corresponde para rutear las alertas de SmartFran Cloud (no asumir que aplica el mismo tag `LOYALTY` reusado para ARCA) y conectar los triggers de DOWN/DEGRADADO a esa alerta.

### Seguimiento fuera de alcance de este ticket

10. Investigar el timeout real contra Xacto Peru (Hallazgo #3) — confirmar si es whitelisting de IP en Xacto Peru o caida del host, probando desde el egress real de produccion (Kudu console del App Service de Sales API) o contactando directamente a Xacto Peru. Considerar ticket separado.
11. Rotar las credenciales confirmadas expuestas en texto plano (Hallazgo #4): `BizlinksPassword`/`BizlinksUser`, el access key/secret de AWS (`v1.0.6`, `v1.0.8` — prioridad alta dado el alcance potencial a nivel de cuenta), y `NeodynamicLicenseKey`. Revisar manualmente los dos archivos `FabricConnections:*` (`v2.18.00`, `v2.23.00`) para confirmar si son connection strings completos, y los dos hallazgos ambiguos (`VendorInvoice`, `GridoOrg`) para determinar si requieren rotacion. Considerar ticket separado, coordinado con quien administre credenciales de proveedores externos (AWS, Bizlinks, Neodynamic).

---

## Hallazgos secundarios

- El chequeo de Bizlinks evita deliberadamente almacenar una credencial real en Zabbix (a diferencia de lo que hubiera requerido un chequeo `invoke` autenticado exitoso): usa credenciales invalidas a proposito y valida que la respuesta sea el rechazo esperado (`401`/`403` con `Usuario no encontrado`). Esto es consistente con el mismo criterio de seguridad aplicado en ARCA de evitar almacenar secretos innecesarios en el pipeline de monitoreo.
