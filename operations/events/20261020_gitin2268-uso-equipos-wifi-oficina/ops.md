# GITIN-2268 — [OPE] Problemas con WiFi

**Tags:** `Operaciones`, `WiFi`, `Notebooks`, `SRE`

## Qué pasó

- Usuarios de la oficina reportan que internet no funciona y problemas con su PC.
- Se reportan, además, algunas computadoras con uso alto de CPU. No está medido qué consume cada equipo.

## Resumen

Se buscó una forma de ver el estado de las conexiones y de los equipos de la oficina. La consola de administración de Google no tiene datos por equipo (no lista dispositivos y la cuenta no tiene Chrome Enterprise), los datos de calidad de Meet no se pueden exportar y su API de informes está bloqueada hasta que un super administrador confíe en el proyecto, y no hay en la oficina un equipo de monitoreo (Zabbix) para medir desde adentro de la red. Por eso no hay mediciones de la red de la oficina que permitan distinguir un problema de la red de uno de los equipos, y la causa de los problemas de conexión no está determinada. Se avanzó en tres frentes: un script de auditoría de notebooks, que completó una primera corrida en una notebook con Windows 10 sin permisos de administrador (faltan Windows 11, una corrida como administrador y una conexión de 2.4 GHz); un correo con la regla de uso de los equipos de trabajo (aprobado para enviar con un cambio, ya incorporado) y un correo con el procedimiento para reportar problemas, mejoras y recambios de equipos (redactado). Ninguno de los dos correos fue enviado. El ticket sigue abierto con acciones pendientes.

## Tabla resumen

| Campo | Valor |
|---|---|
| Ticket Jira | [GITIN-2268](https://smartit-ar.atlassian.net/browse/GITIN-2268) |
| ID alerta | NA |
| Sistema | Red WiFi/internet de la oficina y notebooks de los usuarios |
| Severidad | NA |
| Detectado | 2026-10-19 (reportes de usuarios) |
| Resuelto | No |
| Responsable | SRE |

## Causa raíz

NA

## Hallazgos

| # | Hallazgo | Riesgo |
|---|---|---|
| H1 | Google Admin no tiene datos por equipo de la oficina: la API de telemetría funciona pero no devuelve dispositivos, la consola no lista dispositivos y la cuenta no tiene Chrome Enterprise. Aunque los hubiera, no distinguiría un problema del proveedor o del router de uno de las PC. | Medio |
| H2 | Los datos de calidad de Meet no tienen opción de exportar en la consola, y la API de informes (eventos `call_ended`) está bloqueada por los controles de API de la consola para el OAuth Playground y para un proyecto de Apps Script ("Acceso bloqueado: el administrador de tu institución debe revisar Proyecto sin título"). Un super administrador tiene que confiar en el proyecto para el permiso de informes de auditoría; no se solicitó. Los datos de Meet nunca se leyeron. | Medio |
| H3 | No hay en la oficina un equipo de monitoreo siempre encendido, por lo que no se pueden hacer sondeos desde la red de la oficina (ping, DNS, HTTPS) para medir la estabilidad de la conexión. | Alto |
| H4 | Los reportes de uso alto de CPU de algunas computadoras no están medidos hasta ahora, y no se probó relación con los problemas de conexión. | Medio |
| H5 | La primera corrida completa del script de auditoría (una notebook con Windows 10 Pro 22H2, PowerShell 5.1, sin administrador; 20 secciones sin error en unos 52 s, con reporte HTML y JSON) marcó en ese equipo: 3 % de RAM libre, 2 instalaciones de Windows Update fallidas o canceladas y 4 eventos Application Error 1000 en 14 días. Es una sola notebook y no se relacionó con los problemas de conexión. El escaneo vio 1 punto de acceso, por lo que la lógica de saturación de canales no se ejercitó. | Medio |
| H6 | Dos corridas anteriores del script fallaron con un `ArgumentException` ("Los tipos de argumentos no coinciden") en la sección de ping y jitter y al armar el JSON del reporte; no se repitió en la corrida completa y la causa nunca se identificó, por lo que el error figura como no reproducido, no como corregido. | Bajo |

## Acciones Tomadas

| # | Hora (UTC) | Acción |
|---|---|---|
| 1 | 2026-10-19 | Análisis de las vías de Google Admin (telemetría, Directory, informes de Meet por OAuth Playground y por Apps Script) en [GITIN-2257](https://smartit-ar.atlassian.net/browse/GITIN-2257); cerrado como no viable. |
| 2 | 2026-10-20 | Cierre de [GITIN-2269](https://smartit-ar.atlassian.net/browse/GITIN-2269) (integración de Meet Quality) sin integración. |
| 3 | 2026-10-20 | Escritura del script de auditoría de notebooks de [GITIN-2270](https://smartit-ar.atlassian.net/browse/GITIN-2270) (solo lectura: CPU, RAM y módulos, estado de discos, procesos, aplicaciones y su último uso, navegadores, eventos de falla, Windows Update, banda y canal WiFi, ping y jitter). |
| 4 | 2026-10-20 | Corrección de un error de sintaxis del script (claves duplicadas en una tabla hash) y reescritura para aislar y registrar cada sección que falle. |
| 5 | 2026-10-21 | Primera corrida completa del script en una notebook con Windows 10 sin administrador (H5); se generaron el reporte HTML y JSON y los archivos se conservaron enmascarados (serie, SSID y BSSID). |
| 6 | 2026-10-20 | Redacción de un correo para el personal con la regla de uso de los equipos de trabajo (uso estrictamente laboral, sin aplicaciones ajenas al trabajo como un game hub). Aprobado para enviar con un cambio, ya incorporado ([GITIN-2271](https://smartit-ar.atlassian.net/browse/GITIN-2271)). |
| 7 | 2026-10-20 | Redacción de un correo con el procedimiento para reportar problemas de notebooks y PCs a operaciones@smartfran.com con copia al responsable, y para pedir mejoras de RAM o disco (las analiza Operaciones) y recambios (los pide el responsable y dependen del análisis de Operaciones, del inventario y del rol del usuario). |

## Recursos afectados

| Componente | Estado |
|---|---|
| Red WiFi/internet de la oficina | Sin mediciones; causa de los problemas sin determinar |
| Notebooks y PCs de los usuarios | Una notebook con Windows 10 auditada sin administrador (H5); el resto sin datos de consumo ni de estado |
| Google Workspace (consola de administración, informes de Meet) | Sin datos por equipo; informes de Meet bloqueados hasta que un super administrador confíe en el proyecto |

## Acciones propuestas

| # | Responsable | Acción | Estado |
|---|---|---|---|
| 1 | SRE | Completar la prueba del script de auditoría: Windows 11, corrida como administrador (Prefetch, SMART completo, `FailurePredictStatus`), conexión de 2.4 GHz y una red con varios puntos de acceso; definir cómo se recogen los resultados de los equipos ([GITIN-2270](https://smartit-ar.atlassian.net/browse/GITIN-2270)). | Pendiente |
| 2 | SRE | Unificar los dos correos antes de enviarlos (a quién se reportan los problemas: el correo de la regla dice "a su líder" y el del procedimiento, a Operaciones con copia al responsable) y enviarlos ([GITIN-2271](https://smartit-ar.atlassian.net/browse/GITIN-2271)). | Pendiente de envío |
| 3 | SRE | Medir la estabilidad de la conexión desde la red de la oficina (sondeos de ping, DNS y HTTPS) y revisar los datos del router o del proveedor si existen; hace falta un equipo siempre encendido en la oficina y saber quién administra el router y el enlace. | Por decidir |
| 4 | SRE | Si se reabre la integración de Meet: pedir a un super administrador que confíe en el proyecto para el permiso de informes de auditoría y leer qué campos devuelve ([GITIN-2269](https://smartit-ar.atlassian.net/browse/GITIN-2269)). | Por decidir |
