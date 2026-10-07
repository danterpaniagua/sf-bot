# Eventos — 20260826_sfc-function-apps-graylog-onboarding

## 2026-08-26 09:00 — Verificación de nombres reales antes de escribir Terraform

**Comando:** C1 — confirm-real-app-names-and-state
**Resultado:**
He encontrado 5 apps, no 3: los dos nombres antiguos de GITIN-1914 (`SmartFranCloudFunctionsScheduledJobs-pro`, `SmartFranCloudTicketProcessAsync-pro`) aparecen `Stopped`, y las tres apps `SFC-*-PRO` pedidas aparecen `Running`.

He confirmado que las tres apps `SFC-*-PRO` son reemplazos reales de las apps antiguas (dos de tres) y no duplicados con nombre alternativo — las apps antiguas ya no reciben tráfico. `SFC-CodeGenerator-PRO` no tiene predecesor con nombre antiguo, es genuinamente nueva.

## 2026-08-26 09:05 — Confirmación de ausencia de Diagnostic Settings previos

**Comando:** C2 — confirm-no-preexisting-diagnostic-settings
**Resultado:**
He verificado las tres apps `SFC-*-PRO` sin ningún Diagnostic Setting existente — nada con qué entrar en conflicto antes de aplicar Terraform.

## 2026-08-26 09:15 — Terraform escrito y aplicado

He agregado tres recursos `azurerm_monitor_diagnostic_setting` a `terraform/function_app_pro.tf` siguiendo el patrón exacto ya usado en el mismo archivo (categoría `FunctionAppLogs`, mismo Event Hub compartido `app-logs`).

**Comando:** C3 — terraform-plan-scoped
**Resultado:**
Un primer `terraform plan` sin `-target` devolvió `4 to add, 23 to change` — drift preexistente no relacionado (ya señalado en tickets previos, `metric` blocks y un recurso `service_bus_grido` sin aplicar). He re-planificado con `-target` sobre los tres recursos nuevos únicamente: `Plan: 3 to add, 0 to change, 0 to destroy`.

**Comando:** C4 — terraform-apply
**Resultado:**
`Apply complete! Resources: 3 added, 0 changed, 0 destroyed.` Los Diagnostic Settings quedan activos para las tres apps.

## 2026-08-26 09:40 — Confirmación de tráfico real (descarta "todavía no se invocó")

**Comando:** C5 — confirm-real-invocation-activity
**Resultado:**
He medido 85 ejecuciones (CodeGenerator), 242 (ScheduledJobs) y 2 (TicketProcessAsync) en la última hora vía `FunctionExecutionCount`. He descartado que la ausencia de datos en Graylog se deba a falta de invocaciones — las tres apps están recibiendo tráfico real.

## 2026-08-26 09:50 — Primera búsqueda en Graylog: 0 resultados

**Comando:** C6 — graylog-search-by-app-name
**Resultado:**
He buscado por nombre de cada app, tanto por campo estructurado `name` como por texto completo entre comillas: `total_results: 0` en ambos casos. Una primera consulta sin comillas había devuelto resultados no relacionados (Sales/Orders) por un error mío al construir la query — corregido, el 0 real se confirma con la consulta entre comillas.

## 2026-08-26 10:00 — Tail en vivo revela el shape real emitido

**Comando:** C7 — live-tail-real-output
**Resultado:**
He capturado la salida real de `SFC-CodeGenerator-PRO` mientras recibía tráfico de producción. El shape no es el JSON CLEF (`Timestamp`/`Level`/`MessageTemplate`/`Properties`) documentado en `devs-log-structure.md` — es el formato nativo del host de Azure Functions, `MS_FUNCTION_AZURE_MONITOR_EVENT`, una fila CSV con un blob tipo diccionario Python de comillas simples, no JSON válido. Esto responde una pregunta que había quedado abierta en GITIN-1901 sobre si `FunctionAppLogs` captura el mismo stdout Serilog que `AppServiceConsoleLogs` — no lo hace.

## 2026-08-26 10:10 — El marcador nativo tampoco llega a Graylog

**Comando:** C8 — graylog-search-by-marker-string
**Resultado:**
He buscado el string literal `MS_FUNCTION_AZURE_MONITOR_EVENT` en Graylog, sin restringir a ningún campo: `total_results: 0`, `used_indices: []`. He confirmado que este tipo de evento no llega a Graylog en ninguna forma, ni parseada ni cruda.

## 2026-08-26 10:20 — Diagnostic Setting mal configurado descartado

**Comando:** C9 — confirm-diagnostic-setting-fully-enabled
**Resultado:**
He revisado el JSON completo del Diagnostic Setting: `FunctionAppLogs` con `enabled: true`, `eventHubName`/`eventHubAuthorizationRuleId` correctos. He descartado un error de configuración en Terraform o en el recurso aplicado.

## 2026-08-26 10:25 — Sin excepciones en Logstash (inconcluso)

**Comando:** C10 — logstash-error-check
**Resultado:**
No he encontrado errores ni excepciones en el journal de Logstash en la ventana relevante. Considero este resultado inconcluso — Logstash no loguea contenido por mensaje, así que la ausencia de errores no confirma que los mensajes estén llegando al consumer.

## 2026-08-26 10:30 — Consumer de Event Hub saludable

**Comando:** C11 — logstash-pipeline-stats
**Resultado:**
He revisado las estadísticas del pipeline principal de Logstash: el input `azure_event_hubs` está activo, con `events.in` creciendo de forma consistente con el tráfico real ya conocido (Sales/Business/Orders). He descartado que el consumer esté detenido o con backlog.

## 2026-08-26 10:45 — Causa raíz encontrada en el código fuente

He traído `cloud/repo/SmartFran.Cloud` a `origin/dev` y he revisado la configuración de logging de las tres apps para verificar la hipótesis de un sink directo a Graylog.

**Comando:** C12 — pull-source-and-inspect-logging-wiring
**Resultado:**
No he encontrado ningún sink directo a Graylog — los campos `GraylogHost`/`GraylogPort`/`GraylogUdpEnabled` existen en el código pero están explícitamente documentados como reservados para uso futuro, no activos. En cambio, he confirmado que las tres apps (`CodeGenerator`, `ScheduledJobs`, `TicketProcessAsync`) llaman a `AddBusinessLogger`, y en las tres esa función resuelve a un `IBusinessLoggerProvider` → `CosmosBusinessLogger` — un logger de auditoría de negocio hacia Cosmos DB, sin relación con el logging operacional. Ninguna de las tres apps invoca `AddStateLogger`/`UseSerilog`/`AddSerilog` en ningún punto. He concluido que el pipeline Serilog Console JSON CLEF, que es lo que el pipeline de Graylog espera recibir, nunca se ejecuta para estas tres apps — el bloqueo no es de infraestructura, es de código de aplicación.

## 2026-08-26 11:00 — Cierre de la fase de infraestructura

He dado por completada la parte de infraestructura de este ticket: los tres Diagnostic Settings están activos y correctamente configurados. No he avanzado más sobre el pipeline de Logstash ni sobre el código de las apps — he dejado este hallazgo documentado para coordinar con el equipo de Dev.

## 2026-08-27 13:00 — Re-verificación posterior de la configuración

**Comando:** C13 — re-confirm-diagnostic-settings-all-3
**Resultado:**
He vuelto a revisar el Diagnostic Setting completo de las tres apps: he confirmado `FunctionAppLogs` con `enabled: true`, mismo `eventHubName` (`app-logs`) y misma `eventHubAuthorizationRuleId` en las tres, sin ninguna diferencia entre ellas ni drift respecto a lo aplicado originalmente. Sostengo la misma conclusión que en el cierre anterior: la configuración de infraestructura es correcta; la falta de datos útiles en Graylog sigue siendo un bloqueo de código de aplicación, no de infraestructura.
