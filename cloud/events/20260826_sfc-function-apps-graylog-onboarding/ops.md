# GITIN-1946 — Onboarding de Function Apps SFC-CodeGenerator-PRO / SFC-ScheduledJobs-PRO / SFC-TicketProcessAsync-PRO a Graylog

**Tags:** `SmartCloud`, `Azure`, `Graylog`, `Terraform`, `SRE`

## Resumen

Tres Function Apps de producción de SmartFran Cloud (`SFC-CodeGenerator-PRO`, `SFC-ScheduledJobs-PRO`, `SFC-TicketProcessAsync-PRO`) no tenían ningún Diagnostic Setting configurado, pese a estar recibiendo tráfico de producción real (85, 242 y 2 ejecuciones medidas en una ventana de una hora respectivamente) — sin ninguna visibilidad de sus logs en Graylog. Estas tres apps reemplazan a dos apps con nombre antiguo (`SmartFranCloudFunctionsScheduledJobs-pro`, `SmartFranCloudTicketProcessAsync-pro`) onboardeadas bajo GITIN-1914, que hoy aparecen detenidas (`Stopped`) — sus Diagnostic Settings existentes quedaron apuntando a recursos muertos. `SFC-CodeGenerator-PRO` no tiene predecesor con nombre antiguo, es una app nueva.

Se agregan los Diagnostic Settings correspondientes para las tres apps activas, siguiendo el mismo mecanismo ya aplicado al resto de App Services y Function Apps del proyecto (categoría `FunctionAppLogs`, Event Hub compartido `app-logs`). Durante la verificación post-aplicación se encuentra que, si bien la infraestructura queda correctamente configurada, ninguna de las tres apps emite el formato de log que el pipeline de Graylog espera recibir — el bloqueo real para lograr visibilidad en Graylog es de código de aplicación, no de infraestructura.

## Tabla resumen

| Campo | Valor |
|---|---|
| Ticket Jira | [GITIN-1946](https://smartit-ar.atlassian.net/browse/GITIN-1946) |
| ID alerta | N/A — trabajo planificado, no disparado por alerta |
| Sistema | SmartFran Cloud — Azure Functions / Event Hub / Graylog |
| Severidad | Media |
| Detectado | 2026-08-26 |
| Resuelto | Parcial — infraestructura completada 2026-08-26; pendiente definición con equipo de Dev sobre H3 |
| Responsable | Dante Paniagua, SRE |

## Causa raíz

Las tres apps (`SFC-CodeGenerator-PRO`, `SFC-ScheduledJobs-PRO`, `SFC-TicketProcessAsync-PRO`) comparten el mismo patrón de scaffolding de Functions: su único logger configurado (`AddBusinessLogger`) resuelve en los tres casos a un `IBusinessLoggerProvider` → `CosmosBusinessLogger`, un logger de auditoría de negocio hacia Cosmos DB sin relación con el logging operacional. Ninguna de las tres invoca en ningún punto `AddStateLogger`/`UseSerilog`/`AddSerilog` — el pipeline Serilog Console JSON CLEF que el resto de los servicios de SmartFran Cloud usa (y que el pipeline de Diagnostic Settings → Event Hub → Logstash → Graylog está construido para parsear) nunca se ejecuta. En consecuencia, los `ILogger` que sí se invocan dentro del código de negocio quedan capturados únicamente por el logging nativo del host de Azure Functions (formato `MS_FUNCTION_AZURE_MONITOR_EVENT`), un shape distinto al esperado por el pipeline existente.

## Hallazgos

| # | Hallazgo | Riesgo |
|---|---|---|
| H1 | Las tres apps `SFC-*-PRO` no tenían Diagnostic Settings pese a tráfico de producción real — sin visibilidad en Graylog. Resuelto con este ticket. | Medio |
| H2 | Dos apps con nombre antiguo de GITIN-1914 (`SmartFranCloudFunctionsScheduledJobs-pro`, `SmartFranCloudTicketProcessAsync-pro`) están `Stopped`, con sus Diagnostic Settings aún activos apuntando a recursos sin tráfico. | Bajo |
| H3 | Ninguna de las tres apps invoca el pipeline Serilog Console JSON CLEF — el logger configurado (`AddBusinessLogger`) es un logger de auditoría de negocio no relacionado. Bloquea el objetivo de este ticket por completo, independiente de cualquier trabajo de infraestructura adicional. | Alto |
| H4 | El pipeline de Logstash existente está construido para el shape JSON de App Services (`records[].resultDescription`); el shape nativo de Azure Functions (`MS_FUNCTION_AZURE_MONITOR_EVENT`, fila CSV con blob tipo diccionario Python de comillas simples) no es JSON válido bajo esa lógica de parseo. Relevante si Dev resuelve H3 sin coordinar con el lado del pipeline. | Medio |

## Recursos afectados

| Recurso | Tipo | Estado |
|---|---|---|
| `SFC-CodeGenerator-PRO` | Azure Function App (Linux) | Running — Diagnostic Setting aplicado |
| `SFC-ScheduledJobs-PRO` | Azure Function App (Linux) | Running — Diagnostic Setting aplicado |
| `SFC-TicketProcessAsync-PRO` | Azure Function App (Linux) | Running — Diagnostic Setting aplicado |
| `SmartFranCloudFunctionsScheduledJobs-pro` | Azure Function App (Linux) | Stopped — Diagnostic Setting de GITIN-1914 apunta a recurso sin tráfico |
| `SmartFranCloudTicketProcessAsync-pro` | Azure Function App (Linux) | Stopped — Diagnostic Setting de GITIN-1914 apunta a recurso sin tráfico |
| `smartfran-graylog-evhns-pro` / hub `app-logs` | Azure Event Hub | Sin cambios — consumer saludable, confirmado |
| Pipeline Logstash (`sfcloud-monitoreo`) | Graylog / Logstash | Sin cambios — confirmado saludable, no construido para el shape nativo de Functions |

## Comandos ejecutados

| # | Comando / Script | Propósito |
|---|---|---|
| C1 | confirm-real-app-names-and-state | Confirmar nombres/estado reales antes de escribir Terraform |
| C2 | confirm-no-preexisting-diagnostic-settings | Descartar conflicto con Diagnostic Settings existentes |
| C3 | ⚠️ terraform-plan-scoped | Generar plan acotado a los 3 recursos nuevos |
| C4 | ⚠️ terraform-apply | Aplicar los 3 Diagnostic Settings |
| C5 | confirm-real-invocation-activity | Confirmar tráfico real, descartar "sin invocaciones aún" |
| C6 | graylog-search-by-app-name | Buscar mensajes por nombre de app en Graylog |
| C7 | live-tail-real-output | Capturar el shape real emitido por la app |
| C8 | graylog-search-by-marker-string | Confirmar si el shape nativo llega a Graylog en cualquier forma |
| C9 | confirm-diagnostic-setting-fully-enabled | Descartar configuración incorrecta del Diagnostic Setting |
| C10 | logstash-error-check | Descartar excepciones de parseo en Logstash |
| C11 | logstash-pipeline-stats | Descartar consumer de Event Hub detenido |
| C12 | pull-source-and-inspect-logging-wiring | Descartar sink directo a Graylog; identificar causa raíz real en el código |

Detalle completo en `scripts.sh`.

## Acciones propuestas

1. **Completado (2026-08-26)** — Diagnostic Settings aplicados para las tres apps `SFC-*-PRO`, categoría `FunctionAppLogs`, mismo Event Hub compartido que el resto del proyecto.
2. **Completado (2026-08-26)** — Se descarta configuración incorrecta de infraestructura (Diagnostic Setting, Event Hub, consumer de Logstash) como causa de la falta de datos en Graylog.
3. Coordinar con el equipo de Dev para que las tres apps (`CodeGenerator`, `ScheduledJobs`, `TicketProcessAsync`) inviertan el mismo pipeline Serilog Console JSON CLEF que usa el resto de los servicios de SmartFran Cloud — hoy el logger configurado es un logger de auditoría de negocio no relacionado con logging operacional (H3).
4. Si Dev resuelve H3, validar antes de cerrar el ticket que el shape emitido efectivamente calza con la lógica de parseo del pipeline de Logstash existente (`records[].resultDescription`) — de no calzar, se necesita una rama de parseo específica para Function Apps (H4).
5. Evaluar en un ticket aparte si corresponde dar de baja los Diagnostic Settings de GITIN-1914 sobre las dos apps `Stopped` (H2) — housekeeping, no bloqueante.

## Hallazgos secundarios

Ninguno fuera del alcance ya cubierto en Hallazgos.
