# GITIN-2269 — [OPE] Integración de Meet Quality

**Tags:** `Operaciones`, `Google Workspace`, `Meet`, `SRE`

## Qué pasó

- Se reportan problemas de conexión en la oficina ([GITIN-2268](https://smartit-ar.atlassian.net/browse/GITIN-2268)).
- Los datos de calidad de Meet de la consola de administración no tienen opción de exportar en esta cuenta, y la API de informes de Google (eventos `call_ended` de Meet) está bloqueada por los controles de API de la consola: la pantalla de autorización indica que el administrador debe revisar el proyecto. Los datos de Meet no se pudieron leer.

## Resumen

La integración de los datos de calidad de Meet no se realizó. En el análisis previo de las conexiones de la oficina ([GITIN-2257](https://smartit-ar.atlassian.net/browse/GITIN-2257)) se probaron la consola de administración, el OAuth Playground y un proyecto de Apps Script ejecutado como administrador: la consola no permite exportar y la API de informes de Meet queda bloqueada por los controles de API de la consola hasta que un super administrador confíe en el proyecto para el permiso de lectura de informes de auditoría. Ese paso no se solicitó, por lo que los datos de Meet nunca se leyeron y no se sabe si habrían sido útiles para distinguir un problema de la red de la oficina de uno de los equipos. El ticket se cierra sin integración; no se hizo ningún trabajo nuevo en este ticket.

## Tabla resumen

| Campo | Valor |
|---|---|
| Ticket Jira | [GITIN-2269](https://smartit-ar.atlassian.net/browse/GITIN-2269) (subtarea de [GITIN-2268](https://smartit-ar.atlassian.net/browse/GITIN-2268)) |
| ID alerta | NA |
| Sistema | Google Workspace (consola de administración y API de informes de Meet) |
| Severidad | NA |
| Detectado | 2026-10-19 (en el análisis de GITIN-2257) |
| Resuelto | No: cerrado sin integración |
| Responsable | SRE |

## Causa raíz

NA

## Hallazgos

| # | Hallazgo | Riesgo |
|---|---|---|
| H1 | La herramienta de calidad de Meet de la consola de administración no ofrece exportar los datos en esta cuenta. | Informativo |
| H2 | La API de informes (eventos `call_ended` de Meet) no es accesible desde el OAuth Playground ni desde un proyecto de Apps Script: los controles de API de la consola bloquean la aplicación ("Acceso bloqueado: el administrador de tu institución debe revisar Proyecto sin título"). Un super administrador tiene que confiar en el proyecto para el permiso de informes de auditoría; no se solicitó. | Medio |
| H3 | Los datos de Meet nunca se leyeron. Se desconocen los campos que devuelve (calidad de red, pérdida de paquetes, tipo de red o dispositivo), si permiten ubicar a los usuarios en la red de la oficina y si la edición de Workspace los incluye. | Informativo |

## Acciones Tomadas

| # | Hora (UTC) | Acción |
|---|---|---|
| 1 | 2026-10-19 | En GITIN-2257 se probaron la consola, el OAuth Playground y un proyecto de Apps Script con el permiso de informes; todos bloqueados. No se hizo ninguna acción nueva en este ticket. |

## Recursos afectados

| Componente | Estado |
|---|---|
| Consola de administración de Google (calidad de Meet) | Sin opción de exportar |
| API de informes de Meet | Bloqueada para el proyecto de Apps Script y el Playground hasta que un super administrador confíe en el proyecto |

## Acciones propuestas

| # | Responsable | Acción | Estado |
|---|---|---|---|
| 1 | SRE | Si se reabre el ticket: pedir a un super administrador que confíe en el proyecto de Apps Script para el permiso de informes de auditoría, ejecutar la exportación de eventos `call_ended` de una ventana corta y revisar qué campos devuelve. | Por decidir (ticket cerrado) |
