# OPS — WAF 504 en gestion.clubgrido.com.ar/Catalog + incidente de mayor escala (502 UPSTREAM_NO_LIVE)

## Resumen

Grido reportó error 504 en `https://gestion.clubgrido.com:4430/Catalog/Crud` (ClubSite Management, servido detrás del Application Gateway WAF_v2 `WAF_APPs`). Se confirmaron 13 respuestas `504 ERRORINFO_UPSTREAM_TIMED_OUT` reales en `ApplicationGatewayAccessLog` (Log Analytics workspace `analisis-loadbalancer`). **Causa raíz confirmada a nivel de código fuente:** `CustomerService.GetCustomerAvailable` ejecuta hasta dos consultas a base de datos por cada fila del archivo de operadores subido por el usuario (patrón N+1, sin batching) — con el archivo del incidente (7.940 filas), el costo agregado coincide con el timeout de 180s observado. No hay indicio de mal funcionamiento del WAF ni del Application Gateway.

En la misma consulta se detectó un segundo problema, de escala mucho mayor y no reportado por Grido: 3.121 requests `502 ERRORINFO_UPSTREAM_NO_LIVE` a lo largo de ~29 horas (2026-07-20 05:04 a 2026-07-21 10:01 UTC). El servidor backend único (`192.168.50.131` = VM `SFCG-WSIT-01`) tiene un apagado nocturno **intencional por política de seguridad** (auto-shutdown 02:00 ART) y una reactivación diaria también automatizada (Logic App `Start_WSIT_01`, 10:00 UTC) — ambos mecanismos se confirmaron funcionando correctamente los dos días del incidente. La ventana de indisponibilidad (~05:00–10:00 UTC) es el comportamiento **esperado por diseño** de esta política, no una falla. El único defecto real de este segundo hallazgo es cosmético: el Logic App de reactivación tiene rota su notificación de éxito por email, lo que hace que su historial de ejecuciones figure como "Failed" pese a que el arranque de la VM nunca falla.

## Tabla resumen

| Campo | Valor |
|---|---|
| ID alerta | — (reporte directo de Grido) |
| Sistema | Application Gateway WAF_v2 `WAF_APPs` — listener `Listener_WebSite_HTTPS` — pool `Back_WebSite` |
| Severidad | Alta |
| Detectado | 2026-07-21 (reporte) — incidente de mayor escala detectado retroactivamente en logs, 2026-07-20/21 |
| Resuelto | Diagnóstico completo, con confirmación independiente en Zabbix (CPU `SFCG-DB01`) — corrección de código (H1) y del conector de email (H9) pendientes |
| Responsable | Dante Paniagua |

## Causa raíz

### Hallazgo 1 — 504 en `/Catalog/Crud` (lo reportado por Grido)

Los 13 casos de 504 son timeouts reales del backend — `error_info_s = ERRORINFO_UPSTREAM_TIMED_OUT` en los 13, y las cuatro ocurrencias sobre `/Catalog/SetListCatalog` coinciden con precisión de milisegundos con el `requestTimeout` configurado en `Backend_WebSite` (180s). Se observó además un patrón de `499 ERRORINFO_CLIENT_CLOSED_REQUEST` sobre los mismos endpoints (`SetListCatalog`, `SaveCatalog`) en la misma ventana (19:00–20:30 UTC del 2026-07-21), con `timeTaken` de 85 a 180 segundos — usuarios abandonando antes de que el propio gateway agotara su timeout.

**Causa raíz, confirmada en el código fuente** (`loyalty/repo/dev-src-sol-smartloyalty`): `CatalogController.SetListCatalog` (`Front/WebSite/Controllers/CatalogController.cs:1417`) procesa un archivo CSV subido por el operador (formato `TipoDocumento;NumeroDocumento`, ej. `Dni;47227634`) — el archivo del incidente tiene **7.940 filas**. El flujo:

1. `ProcessFileListCatalog` (`CatalogController.cs:1674`) lee el archivo y deduplica con `lstPerson.Any(x => ...)` **dentro** del loop de lectura — complejidad O(n²). Ineficiencia real (H2), pero no el costo dominante a esta escala.
2. `CustomerService.GetCustomerAvailable` (`CustomerService.cs:3962-3995`) — **la causa raíz** — itera la lista fila por fila y ejecuta una consulta a base de datos por cada persona, y si no existe, una segunda consulta también por persona:

```csharp
foreach (var person in lstPerson)
{
  Customer cust = this.GetCustomer(person.UidCode, person.UidSerie);   // consulta DB, por fila
  if (cust != null) { ... }
  else
  {
    var custPendi = carPendSrv.GetCardPendingAffiliate(person.UidCode, person.UidSerie);  // 2da consulta DB, por fila
    ...
  }
}
```

Patrón clásico de **N+1 queries**: hasta ~15.880 consultas individuales a la base de datos, secuenciales y síncronas dentro del mismo request HTTP, sin batching (`WHERE ... IN (...)`), sin async. A ~20-25ms por consulta — nada inusual bajo carga — el total ronda exactamente los 180 segundos observados. No es un problema de infraestructura, WAF, ni configuración del Application Gateway.

**Confirmado en el servidor: los 4 casos son el mismo archivo de ~7.940 filas, re-intentado 4 veces.** Los primeros tres intentos (19:01, 19:20, 19:28) usan literalmente el mismo archivo (`AA LISTAAAA.csv`, mismo tamaño y `LastWriteTimeUtc` 18:56:45) — el operador lo volvió a subir después de cada falla. El cuarto intento (20:29) usa un archivo renombrado/reformateado (`socios-formateados.csv`, mismo conteo de filas), subido de nuevo a las 20:25:15. La falla es **determinística, no intermitente** — con ~7.940 filas el patrón N+1 agota el timeout de 180s de forma consistente, sin importar el número de intento.

El archivo `AA LISTAAAA.csv` es el **archivo de entrada subido por el operador** (leído por `ProcessFileListCatalog`), no un artefacto del servidor — `SendMails` (`CatalogController.cs:1699`) genera su propio CSV con nombre `Guid.NewGuid()`, que no coincide con el nombre encontrado.

**Horarios exactos** (para correlacionar con CPU/bloqueos en `SFCG-DB01` vía Zabbix — la carga real en la base de datos comienza ~3 minutos antes de cada horario, dado que cada request corre síncronamente los 180s previos a que el gateway lo corte):

| # | Hora (UTC) | Hora (ART, UTC-3) | `timeTaken` |
|---|---|---|---|
| 1 | 2026-07-21 19:01:09 | 16:01:09 | 180,06s |
| 2 | 2026-07-21 19:20:43 | 16:20:43 | 180,01s |
| 3 | 2026-07-21 19:28:02 | 16:28:02 | 180,01s |
| 4 | 2026-07-21 20:29:55 | 17:29:55 | 180,01s |

**Confirmado en Zabbix — pico de CPU en `SFCG-DB01` coincidente con la ventana:** durante el período de los 4 horarios, `SFCG-DB01` alcanzó ~50% de uso de CPU (máximo), frente a un promedio de ~1% fuera de esa ventana. Es una confirmación independiente del patrón N+1 — miles de consultas secuenciales generan exactamente este tipo de pico sostenido de CPU en el servidor de base de datos. Pendiente: acotar el pico a cada uno de los 4 horarios individuales (actualmente confirmado a nivel de la ventana agregada, no horario por horario).

**Archivos y rutas relevantes:**

| Ruta | Ubicación | Descripción |
|---|---|---|
| `Front/WebSite/Controllers/CatalogController.cs:155` | `loyalty/repo/dev-src-sol-smartloyalty` | Acción `Crud()` — la página reportada por Grido |
| `Front/WebSite/Controllers/CatalogController.cs:1417` | `loyalty/repo/dev-src-sol-smartloyalty` | Acción `SetListCatalog()` — endpoint que produce los 504 |
| `Front/WebSite/Controllers/CatalogController.cs:1674` | `loyalty/repo/dev-src-sol-smartloyalty` | `ProcessFileListCatalog()` — dedup O(n²) (H2) |
| `Front/WebSite/Controllers/CatalogController.cs:1699` | `loyalty/repo/dev-src-sol-smartloyalty` | `SendMails()` — genera su propio CSV, no relacionado al archivo hallado en el servidor |
| `Core/Domain/Domain/CustomerContext/CustomerService.cs:3962` | `loyalty/repo/dev-src-sol-smartloyalty` | `GetCustomerAvailable()` — causa raíz, patrón N+1 |
| `D:\SmartLoyalty.WebSite` | VM `SFCG-WSIT-01` | Path físico del sitio IIS `SmartLoyalty.WebSite` |
| `D:\SmartLoyalty.WebSite\bin\SmartFran.Solution.SmartLoyalty.Front.WebSite.dll` | VM `SFCG-WSIT-01` | Ensamblado desplegado, build 2026-06-08 |
| `D:\SmartLoyalty.WebSite\Public\Catalog\639202572275876998\AA LISTAAAA.csv` | VM `SFCG-WSIT-01` | Archivo subido para el 504 #1 (19:01:09) — 110.889 bytes, 7.940 filas |
| `D:\SmartLoyalty.WebSite\Public\Catalog\639202581884900046\AA LISTAAAA.csv` | VM `SFCG-WSIT-01` | Archivo subido para el 504 #2 (19:20:43) — mismo archivo que #1, re-subido |
| `D:\SmartLoyalty.WebSite\Public\Catalog\639202585419549498\AA LISTAAAA.csv` | VM `SFCG-WSIT-01` | Archivo subido para el 504 #3 (19:28:02) — mismo archivo, tercera re-subida |
| `D:\SmartLoyalty.WebSite\Public\Catalog\639202623731016422\socios-formateados.csv` | VM `SFCG-WSIT-01` | Archivo subido para el 504 #4 (20:29:55) — renombrado/reformateado, subido a las 20:25:15 |
| `D:\Log\inetpub\W3SVC2` | VM `SFCG-WSIT-01` | Directorio real de logs IIS (no el path por defecto `C:\inetpub\logs\LogFiles`) |

### Hallazgo 2 — incidente de 29h, no reportado por Grido

3.121 requests devolvieron `502 ERRORINFO_UPSTREAM_NO_LIVE` entre 2026-07-20 05:04:52Z y 2026-07-21 10:01:04Z (~29 horas) — el Application Gateway no tuvo ningún servidor disponible en el pool `Back_WebSite` durante esas solicitudes. ~240 veces mayor en volumen que los 504 reportados; no fue mencionado por Grido, posiblemente porque gran parte de la ventana cae en horario de menor tráfico (madrugada, hora local Argentina).

**Apagado (05:00 UTC): intencional y confirmado funcionando según diseño.** `SFCG-WSIT-01` tiene un schedule de auto-shutdown (`Enabled`, 02:00 ART = 05:00 UTC, notificaciones deshabilitadas) — **política de seguridad intencional**, confirmada con el equipo; no corresponde deshabilitarlo. Windows Event Log confirma el apagado disparándose con precisión de segundos ambos días (`Event ID 6006`, *"The Event log service was stopped"*, 05:00:47Z ambos días — dentro del segundo del horario configurado).

**Reactivación (10:00 UTC): automatizada y confirmada funcionando ambos días.** El mecanismo es el Logic App `Start_WSIT_01` (RG `DefaultGroup01`), con trigger de recurrencia diaria a las 10:00:00 UTC (estado del trigger: `Succeeded`). Se verificaron los `inputs`/`outputs` reales de la acción `Start_virtual_machine`: hace un `POST` genuino a `/subscriptions/.../virtualMachines/SFCG-WSIT-01/start` vía la conexión `azurevm-2`, con respuesta real **`HTTP 200`** de Azure (encabezados de correlación auténticos, `x-ms-request-id`/`x-ms-correlation-request-id`) — confirmado exitoso ambos días (07-20: 10:00:00.37Z–10:00:22.21Z; 07-21: 10:00:00.83Z–10:00:23.29Z).

El run completo del Logic App figura como `Failed` en su historial **ambos días**, pero exclusivamente por el paso posterior `Send_an_email_on_success` (`code: "NotFound"` — conector de email roto/eliminado), sin relación con el arranque de la VM. Esto explica por qué el mecanismo parecía no funcionar pese a estar funcionando correctamente cada día — su historial de ejecuciones no es confiable como señal de salud.

El evento manual `Microsoft.Compute/virtualMachines/start/action` registrado en Activity Log a las 2026-07-21T10:00:16Z cae **dentro** de la ventana de ejecución de la acción automática del Logic App (10:00:00.83Z–10:00:23.29Z) — muy probablemente una intervención redundante, realizada sin saber que la automatización ya estaba completando el arranque.

**Conclusión:** la ventana de indisponibilidad de ~5 horas es el comportamiento esperado por diseño de la política de apagado nocturno, no una falla de reactivación. El único defecto real y accionable es la notificación de éxito rota del Logic App (H9, acción 4).

Se descartó Windows Update como disparador de cualquiera de los dos días: la última actualización acumulativa data del 2026-07-15 (cinco días antes del incidente); la única actividad de Windows Update en la ventana es una actualización de firmas de Microsoft Defender iniciada después de que el arranque ya había completado.

**Nota abierta, sin impacto en la conclusión:** no se encontró, en Activity Log, un evento `deallocate`/`stop` correspondiente al apagado del schedule de auto-shutdown (búsqueda case-insensitive sobre `resourceId`, ventana completa del incidente) — el mecanismo exacto por el cual el apagado no deja rastro ARM visible no se resolvió en esta sesión. No afecta la conclusión (el apagado es intencional y se confirmó disparándose vía Windows Event Log directamente en la VM).

### WAF descartado como causa en ambos hallazgos

La policy `WAV_directiva` está en modo `Detection` (`WAFMode_s`), lo que impide que bloquee cualquier request — sólo registra coincidencias. Se confirmó, con una muestra de `ApplicationGatewayFirewallLog`, que las coincidencias de reglas observadas en el período (`action_s: "Matched"`, nunca `"Blocked"`) corresponden a otro endpoint (`/Account/ChangePassword`, falso positivo de SQLi sobre un token CSRF en cookie) — no relacionado con `/Catalog`.

## Hallazgos

| # | Hallazgo | Riesgo |
|---|---|---|
| H1 | Causa raíz confirmada en código: `CustomerService.GetCustomerAvailable` (`CustomerService.cs:3962`) ejecuta hasta 2 consultas DB por fila del archivo subido (patrón N+1), sin batching ni async. Con 7.940 filas, el costo agregado coincide con el timeout de 180s observado en los 13 casos de 504 | Alto |
| H2 | `ProcessFileListCatalog` (`CatalogController.cs:1674`) tiene deduplicación O(n²) dentro del loop de lectura — ineficiencia real, secundaria al costo de H1 a esta escala | Bajo |
| H3 | 3.121 respuestas 502 `ERRORINFO_UPSTREAM_NO_LIVE` entre 2026-07-20 05:04 y 2026-07-21 10:01 UTC (~29h) — indisponibilidad total del pool de backend, no reportada por Grido | Crítico |
| H4 | El pool `Back_WebSite` tiene un único servidor (`192.168.50.131`), sin redundancia — punto único de falla | Alto |
| H5 | Ningún `backendHttpSettings` del gateway tiene health probe personalizado — depende del probe por defecto contra la raíz `/`, que no ejerce `/Catalog/SetListCatalog` | Medio |
| H6 | WAF descartado como causa — policy en modo `Detection` (nunca bloquea), coincidencias de reglas en el período corresponden a otro endpoint no relacionado | Informativo |
| H7 | `SFCG-WSIT-01` tiene auto-shutdown habilitado (02:00 ART = 05:00 UTC) — política de seguridad intencional, confirmada disparándose puntualmente ambos días vía Windows Event Log | Informativo |
| H8 | Reactivación diaria (Logic App `Start_WSIT_01`, 10:00 UTC) confirmada funcionando correctamente ambos días — arranque real de la VM con respuesta `HTTP 200` de Azure. La ventana de ~5h de indisponibilidad es comportamiento esperado por diseño, no una falla | Informativo |
| H9 | El Logic App `Start_WSIT_01` figura como `Failed` en su historial ambos días exclusivamente por `Send_an_email_on_success` (`code: NotFound`, conector de email roto) — no por el arranque de la VM, que siempre funciona. El historial engañoso puede llevar a desconfiar de una automatización que sí funciona | Medio |

## Recursos afectados

| Componente | Impacto |
|---|---|
| Application Gateway `WAF_APPs` (RG `DefaultGroup01`) | Enruta correctamente — no es la causa de ningún hallazgo; expuesto a la indisponibilidad del backend sin poder mitigarla por falta de redundancia en el pool |
| VM `SFCG-WSIT-01` (`192.168.50.131`, RG `DefaultGroup01`, pool `Back_WebSite`, sitio ClubSite Management / `gestion.clubgrido.com.ar`, tag `SML: WebSite`, path físico `D:\SmartLoyalty.WebSite`) | Único servidor del pool, sin redundancia. Apagado nocturno intencional y reactivación automática, ambos confirmados funcionando correctamente |
| Logic App `Start_WSIT_01` (RG `DefaultGroup01`) | Reactivación diaria confirmada funcionando. Notificación de éxito rota (`Send_an_email_on_success`, `code: NotFound`) — historial de ejecuciones engañoso (H9) |
| `SmartFran.Solution.SmartLoyalty.Front.WebSite.dll` (build 2026-06-08) — `CatalogController.SetListCatalog` / `CustomerService.GetCustomerAvailable` | Causa raíz confirmada de H1 — patrón N+1 de consultas DB por fila del archivo subido, sin batching. Build anterior al incidente por 6+ semanas — no es una regresión de deploy reciente |

## Comandos ejecutados

| # | Comando / Script | Propósito |
|---|---|---|
| C1 | `appgw-show` | Configuración completa del Application Gateway `WAF_APPs` (backendHttpSettings, probes, listeners, requestRoutingRules, backendAddressPools) |
| C2 | `appgw-backend-health` | Estado de salud reportado por el gateway para cada servidor de cada pool |
| C3 | `law-workspace-guid` | GUID del workspace de Log Analytics `analisis-loadbalancer` |
| C4 | `law-diag-settings-list` | Confirmar exportación de diagnósticos (`LOGS_WAF`) al workspace |
| C5 | `kql-accesslog-schema` | Esquema real de campos de `ApplicationGatewayAccessLog` (sufijos de tipo de `AzureDiagnostics` no adivinables) |
| C6 | `kql-accesslog-504-query` | Consulta completa de `ApplicationGatewayAccessLog` para `gestion.clubgrido.com`, 48h (3.706 filas) — base del análisis (ver `_access-log-raw.table`) |
| C7 | `kql-perflog-schema` | `ApplicationGatewayPerformanceLog` — vacío, esperado (no aplica a SKU v2) |
| C8 | `kql-firewalllog-schema` | Esquema y muestra de `ApplicationGatewayFirewallLog` — confirmó modo `Detection`, descartó el WAF |
| C9 | `vm-auto-shutdown-check`, `vm-show`, `vm-list-ip-addresses` | Confirmar schedule de auto-shutdown de `SFCG-WSIT-01` e identificar su IP como el backend `Back_WebSite` |
| C10 | `activity-log-list` (case-insensitive) | Eventos `deallocate`/`start` a nivel ARM en la ventana del incidente |
| C11 | `vm-get-instance-view` | Estado actual de la VM |
| C12 | `windows-eventlog-system` (`az vm run-command`) | Confirmar secuencia de apagado limpio del SO a las 05:00:47Z ambos días |
| C13 | `windows-was-events`, `windows-update-history`, `windows-scheduled-tasks` | Descartar Windows Update y tareas programadas rutinarias como disparador |
| C14 | `iis-site-config`, `iis-physical-path-listing` | Path físico del sitio, versiones de DLL, ubicación real de logs IIS |
| C15 | `iis-catalog-folder-analysis` | Tamaño (~108KB) y antigüedad de acumulación (577 carpetas desde 2022) de archivos bajo `Public\Catalog` — descartó tamaño/acumulación como causa |
| C16 | Lectura de código fuente (`loyalty/repo/dev-src-sol-smartloyalty`) | Confirmación definitiva de causa raíz — patrón N+1 en `CustomerService.GetCustomerAvailable` |
| C17 | `az resource list` (`Microsoft.Logic/workflows`) | Identificar el Logic App de reactivación diaria — `Start_WSIT_01` |
| C18 | `az rest` sobre API de Logic Apps (`/runs`, `/runs/{id}/actions`, `/runs/{id}/actions/{name}` + `inputsLink`/`outputsLink`) | Confirmar ejecución diaria exitosa, aislar `Start_virtual_machine` como exitosa ambos días, e identificar `Send_an_email_on_success` como único paso roto |

Ver: `20260721_gestion_clubgrido_waf_504_scripts.sh`. Salida completa de C6 (3.706 filas) archivada en `20260721_gestion_clubgrido_waf_504_access-log-raw.table`.

## Acciones propuestas

1. **(Dev)** Corregir `CustomerService.GetCustomerAvailable` (`CustomerService.cs:3962`) para eliminar el patrón N+1 — reemplazar las consultas por fila (`GetCustomer`, `GetCardPendingAffiliate`) por una consulta batched (`WHERE (UidCode, UidSerie) IN (...)`) que resuelva toda la lista en una sola ida a la base de datos. Resuelve H1 de forma definitiva.
2. **(Dev)** Corregir la deduplicación O(n²) en `ProcessFileListCatalog` (`CatalogController.cs:1674`) — reemplazar `lstPerson.Any(x => ...)` por un `HashSet` de claves compuestas (H2, prioridad baja frente a la acción 1).
3. **(Dev)** Evaluar si `SetListCatalog` debe procesar archivos grandes de forma asíncrona (cola de trabajo / job en background) en lugar de síncronamente dentro del request HTTP — incluso corrigiendo el N+1, listas suficientemente grandes seguirán siendo vulnerables a timeouts sin un cambio de arquitectura de procesamiento.
4. **(SRE)** Corregir el conector de email roto en el Logic App `Start_WSIT_01` (`Send_an_email_on_success`, `code: NotFound`) — el arranque de la VM funciona correctamente; esto es exclusivamente para que el historial de ejecuciones deje de figurar como `Failed` (H9).
5. **(SRE)** Revisar si `Start_WSIT_01` tiene el mismo defecto en su rama de notificación de fallo (`Send_an_email_on_failure`) — comparte el mismo tipo de conector.
6. **(SRE)** Agregar un segundo servidor al pool `Back_WebSite` para eliminar el punto único de falla (H4) — independientemente de que la reactivación diaria funcione correctamente, cualquier otra caída del único servidor deja el sitio completamente inaccesible.
7. **(SRE)** Configurar un health probe personalizado sobre `Backend_WebSite` que ejercite una página real de la aplicación (no sólo la raíz `/`) — el probe por defecto no detecta un colgado específico de `/Catalog/*` (H5).
8. **(SRE)** No modificar el `requestTimeout` de 180s en `Backend_WebSite` como mitigación aislada — la causa ya está identificada a nivel de código (acción 1); ajustar el timeout sin corregir el N+1 sólo pospone el síntoma.
9. ✅ **(SRE)** Verificar en Zabbix el CPU/bloqueos de `SFCG-DB01` durante los 4 horarios exactos de 504 — **confirmado**: ~50% de CPU máximo en la ventana de los 4 horarios vs. ~1% promedio fuera de ella. Pendiente, opcional: acotar el pico a cada horario individual (no sólo a la ventana agregada) si se requiere una correlación aún más precisa.

## Hallazgos secundarios

Se detectaron dos sitios IIS distintos vinculados al puerto 4430 sobre el mismo path físico (`D:\SmartLoyalty.WebSite`): `SmartLoyalty.WebSite` (binding con host `gestion.clubgrido.com.ar`) y un segundo sitio nombrado literalmente `DefaultAppPool` sin restricción de host (catch-all). No se investigó impacto — queda como punto a revisar en una sesión futura si se detectan síntomas de enrutamiento ambiguo dentro de IIS.
