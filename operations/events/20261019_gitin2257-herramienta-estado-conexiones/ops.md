# GITIN-2257 — [OPE] Herramienta para ver estado de conexiones

**Tags:** `Operaciones`, `Red`, `Oficina`, `Google Workspace`, `SRE`

## Qué pasó

Varios usuarios de la oficina reportan que internet no funciona. Se necesita obtener datos por equipo desde Google Admin para evaluar la estabilidad de la conexión y los problemas en las PCs de los usuarios.

## Resumen

Se probó obtener datos por equipo desde Google Admin mediante las APIs de Chrome Management y de Reports, y la herramienta de calidad de Meet de la consola. Con la configuración actual no se obtuvieron datos: la telemetría de Chrome respondió vacía, la consola no lista dispositivos Chrome, la API de Reports quedó bloqueada por los controles de API de la consola y la página de calidad de Meet no ofrece exportación. Se cierra el ticket como no viable por esta vía. Tampoco hay en la oficina un Zabbix ni otro equipo siempre encendido desde el cual medir la conexión.

## Tabla resumen

| Campo | Valor |
|---|---|
| Ticket Jira | [GITIN-2257](https://smartit-ar.atlassian.net/browse/GITIN-2257) |
| ID alerta | N/A — reporte de usuarios |
| Sistema | Google Workspace (consola de administración, APIs Chrome Management y Reports); red de la oficina |
| Severidad | No definida |
| Detectado | 2026-10-19 |
| Resuelto | No — cerrado como no viable |
| Responsable | SRE |

## Causa raíz

NA

## Hallazgos

| # | Hallazgo | Riesgo |
|---|---|---|
| H1 | La API de telemetría de Chrome Management respondió `{}` con un token válido: ningún dispositivo reporta telemetría. La consola no lista dispositivos Chrome y la organización no tiene licencia de Chrome Enterprise (informado, sin captura). Los equipos de la oficina usan Firefox (informado). | Bajo |
| H2 | Los permisos de la API de Directory (dispositivos ChromeOS y navegadores) quedaron bloqueados en el OAuth Playground (`access_not_configured`): los controles de API de la consola no confían en esa aplicación. | Bajo |
| H3 | El permiso de Reports (`admin.reports.audit.readonly`), necesario para leer los eventos de Meet, quedó bloqueado en el Playground y en un proyecto de Apps Script ("Acceso bloqueado: el administrador de tu institución debe revisar"). Un primer 403 del script se debió a que el permiso no estaba declarado en el manifiesto. Para habilitarlo, un super administrador tendría que confiar en el proyecto; no se solicitó. | Bajo |
| H4 | La página de calidad de Meet (`admin.google.com/ac/meet/quality`) no ofrece exportación en esta cuenta (informado). Los datos de Meet nunca se leyeron, por lo que no se probó si habrían servido para evaluar la conexión. | Bajo |
| H5 | No hay Zabbix ni otro equipo siempre encendido en la red de la oficina (informado), así que no se puede medir la conexión desde dentro con las herramientas actuales. | Medio |

## Acciones Tomadas

| # | Hora (UTC) | Acción |
|---|---|---|
| 1 | 2026-10-19 | Consultas a la API de telemetría de Chrome Management con un token del OAuth Playground: 401 (token inválido), 400 (falta `readMask`) y `{}` con máscara |
| 2 | 2026-10-19 | Intento de autorizar los permisos de Directory en el Playground: bloqueado (`access_not_configured`) |
| 3 | 2026-10-19 | Revisión de Dispositivos → Chrome en la consola de administración: sin dispositivos |
| 4 | 2026-10-19 | Script de Apps Script para leer eventos `call_ended` de Meet (Reports API): 403 por permiso no declarado; con el permiso declarado, autorización bloqueada |

## Acciones propuestas (no decididas)

- Pedir a un super administrador que confíe en un proyecto propio para el permiso de Reports y leer los eventos de Meet; no se sabe si esos datos alcanzan para evaluar la estabilidad de la conexión.
- Medir desde la red de la oficina (ping al gateway y a direcciones públicas, tiempo de DNS, chequeo HTTPS), lo que requeriría un equipo siempre encendido allí.
