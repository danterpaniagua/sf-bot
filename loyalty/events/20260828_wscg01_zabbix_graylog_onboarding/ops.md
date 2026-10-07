# GITIN-1961 — Onboarding de SFCG-WSCG-01 a Zabbix y Graylog

**Estado: Cerrado (2026-09-05, usuario)**

**Tags:** SmartLoyalty, WebserviceCG, Obserbavilidad, SRE

## Descripción

El ticket pide incorporar `SFCG-WSCG-01` (WebServiceCG) a Zabbix y Graylog. Al revisar, el host ya estaba dado de alta en Zabbix, por lo que el trabajo se reorientó a auditar qué tan completa era esa cobertura contra el checklist estándar de onboarding — y a partir de esa auditoría surgieron gaps reales, no solo de documentación. El lado Graylog del onboarding no había arrancado.

## Hallazgos

| # | Hallazgo | Riesgo |
|---|---|---|
| H1 | `SFCG-WSCG-01` no tenía ningún trigger sobre el ítem de tasa total de requests IIS (`53770`, `_Total`) — la métrica se recolectaba pero no generaba ninguna alerta | Alto |
| H2 | El ítem `54600` (POST rate por app) tenía el nombre incorrecto (`SmartLoyalty.WebServiceV2` en vez de `SmartLoyalty.WebServiceCG`) — cosmético, la `key_` ya resolvía el macro correcto | Bajo |
| H3 | Los ítems `54599`/`54600` (GET/POST por app, no el `_Total`) nunca recolectaron datos (`lastclock:0`) — mismo patrón de falla que `GITIN-1956` en `SFCG-WSV2-02`, causa raíz no confirmada | Medio |
| H4 | La brecha de enrutamiento de tags de trigger hacia acciones de alerta habilitadas es una condición de toda la flota, no específica de este host — ya se está tratando en `GITIN-1966` | Bajo |
| H5 | Logs de acceso IIS de `SFCG-WSCG-01` sí llegan a Graylog vía NXLog (confirmado 2026-09-04) — pero caen en el stream por defecto ("All Messages"), no en uno dedicado. Sin definir si eso es requisito de cierre | Medio |
| H6 | Pathway de logging a nivel de aplicación (`SmartLoyalty.WebServiceCG` `.svclog` + carpeta `csv`), inicialmente inactivo por falta de `delimitedListener` en el trace config. **Decisión (2026-09-04): entra en alcance. Desplegado y validado con datos reales (2026-09-05)** — la extracción de campos (`ErrorId`/`Email`/`UidType`/`UidId`/`Usuario`/`Endpoint`) funciona correctamente. Bug encontrado el mismo día: cada evento generaba 3 líneas CSV físicas (una con el dato útil, una solo con la clasificación de excepción, una en blanco sin señal) — la línea en blanco ya se filtra, corregido en `svclog.conf`; falta re-validar contra datos frescos | Medio |

## Recursos afectados

| Recurso | Detalle |
|---|---|
| Host | `SFCG-WSCG-01` (hostid `10676`), WebServiceCG |
| Ítem Zabbix | `53770` — `IIS: Method Total requests per second` (`_Total`), sin trigger antes de este ticket |
| Ítem Zabbix | `54599`/`54600` — GET/POST por app, nunca recolectan datos |
| Macros nuevas | Contexto `WEBSCG01`: `{$PERF_COUNT_TRIG_WARNING/AVERAGE/HIGH/OK/TIME_NOK:WEBSCG01}` |
| Triggers nuevos | `26862` (Warning) → `26863` (Average) → `26864` (High), cadena de dependencias sobre `53770` |
| Zabbix server | Monitoreo de vencimiento SSL centralizado — confirmado correcto para este servicio (`get_ssl_enddate_webservicecg`), no es un gap |

## Criterios de aceptación

Checklist estándar de onboarding (ver `investigation.md` para el detalle de cada verificación):

- [x] Host polled a través del Zabbix Proxy (`sfcg-monitoreo`)
- [x] Alerta de latencia de disco (Warning+)
- [x] Alerta de espacio bajo en disco (Warning+)
- [x] Alerta de CPU (Warning+)
- [x] Alerta de RAM (Warning+)
- [x] Alerta de puerto IIS caído
- [x] Alerta de vencimiento de certificado (arquitectura centralizada en Zabbix server, confirmada correcta)
- [x] Alerta de tasa de requests IIS (`_Total`) — creada y verificada en este ticket
- [ ] Causa raíz de por qué `54599`/`54600` nunca recolectan datos (opcional, no bloqueante — ninguno de los dos tiene trigger)
- [x] Onboarding a Graylog completo — cerrado por el usuario (2026-09-05). Logs de acceso IIS (NXLog) y logs de aplicación (`.svclog`/CSV vía `delimitedListener`) confirmados llegando a Graylog con datos reales. Queda como seguimiento no bloqueante, fuera de este cierre: si el stream por defecto ("All Messages") alcanza o si hace falta uno dedicado — no fue evaluado como parte de este ticket

## Sub-tareas

| # | Sub-tarea | Estado |
|---|---|---|
| ST1 | Corregir nombre del ítem `54600` (`item.update`) | Completado |
| ST2 | Crear macros de contexto `WEBSCG01` y cadena de 3 triggers (Warning/Average/High) sobre el ítem `53770` | Completado |
| ST3 | Investigar causa raíz de que `54599`/`54600` nunca recolecten datos (candidato: mismo bug que `GITIN-1956`, `Get-Counter -ListSet "Web Service"` en `SFCG-WSCG-01`) | Pendiente, opcional |
| ST4 | Definir mecanismo de envío de logs (NXLog vs. aplicación) e iniciar el onboarding real a Graylog | En progreso — logs de acceso IIS confirmados vía NXLog; falta decidir stream |
| ST5 | Desplegar el pathway de logs de aplicación: agregar `delimitedListener` al trace config de `SFCG-WSCG-01`, desplegar `svclog.conf` en NXLog, validar contra una muestra CSV real | **Desplegado y validado (2026-09-05)** — datos reales llegando a Graylog, regex de extracción confirmada correcta. Bug encontrado y corregido el mismo día (una línea en blanco por evento se enviaba sin filtrar); falta re-validar contra datos frescos post-fix |

## Comandos ejecutados

| # | Comando / Script | Propósito |
|---|---|---|
| C1 | `host.get` / `trigger.get` / `item.get` sobre `SFCG-WSCG-01` | Relevar estado actual contra el checklist de onboarding |
| C2 | `usermacro.createglobal` | Crear los macros de contexto `WEBSCG01` (el primer intento usó `usermacro.create`, host-scoped, y falló — corregido) |
| C3 | `trigger.create` x3 | Crear la cadena Warning/Average/High sobre el ítem `53770` |
| C4 | `item.update` | Corregir el nombre del ítem `54600` |
| C5 | `trigger.get` (verificación) | Confirmar `state:0`/`error:""` en los 3 triggers nuevos |

Detalle completo en `scripts.sh` y `apply-fix-getpost-alert.sh`.

## Acciones propuestas

1. **(SRE) Completado** — Corrección del nombre del ítem `54600`.
2. **(SRE) Completado** — Creación de macros `WEBSCG01` y cadena de triggers sobre el ítem `53770`, verificada limpia.
3. **(SRE) Pendiente, opcional** — Investigar por qué `54599`/`54600` nunca recolectan datos. No bloqueante porque ninguno de los dos tiene trigger asociado.
4. **(SRE) Completado** — Logs de acceso IIS confirmados llegando a Graylog vía NXLog. Pathway de logs de aplicación (`.svclog`/CSV) desplegado y validado con datos reales (2026-09-05). Ticket cerrado por el usuario con este alcance; el stream por defecto ("All Messages") queda como está, sin evaluar dedicado.
5. **(SRE) Fuera de alcance de este ticket** — La brecha de enrutamiento de tags a acciones habilitadas es de toda la flota, no específica de `SFCG-WSCG-01`; se está tratando en `GITIN-1966`.

## Hallazgos secundarios

Se confirmó la arquitectura real de monitoreo de vencimiento de certificados SSL: es centralizada en el host `Zabbix server` (un ítem por servicio, no por VM), no algo que deba buscarse en cada host onboardeado. Vale como referencia para futuros onboardings — ya documentado en `docs/zabbix_observability.md`.
