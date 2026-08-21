# Habilitar Diagnostic Settings de SFC-PosWasmRelay-DEV hacia Graylog — GITIN-1901

**Tags:** `SmartCloud`, `Graylog`, `Azure`, `Terraform`

## Resumen

La Function App `SFC-PosWasmRelay-DEV` (relay planificado para logs del POS, aplicación Blazor WASM/SPA) no tenía ningún Diagnostic Setting configurado — a diferencia de los 6 servicios API de SmartFran Cloud, ya conectados a Graylog vía Event Hub desde GITIN-1883/1892/1835, esta Function App no tenía ningún camino hacia Graylog para su salida de consola. La brecha se detectó el 2026-08-20 al alcance de GITIN-1901 (hijo de GITIN-1835), como trabajo de habilitación proactivo — la Function App todavía no tiene código de función desplegado (recurso provisionado, vacío). Este ticket agrega el Diagnostic Setting correspondiente, con el mismo mecanismo (Event Hub compartido `app-logs`) que ya usan los servicios API, para que la salida de consola de esta Function App llegue a Graylog en cuanto exista código real desplegado.

## Tabla resumen

| Campo | Valor |
|---|---|
| Ticket Jira | GITIN-1901 (padre: GITIN-1835) |
| ID alerta | N/A — tarea planificada, no alerta |
| Sistema | SmartFran Cloud — Azure Function App `SFC-PosWasmRelay-DEV` (suscripción Smart IT - Grido), pipeline Event Hub → Graylog (repo `cloud-graylog`) |
| Severidad | Baja — habilitación proactiva, sin pérdida de datos actual (la Function App no tiene código desplegado todavía) |
| Detectado | 2026-08-20 |
| Resuelto | Parcial — Diagnostic Setting desplegado y confirmado (`terraform apply` exitoso). Entrega end-to-end **sin verificar**: no hay código real desplegado en la Function App todavía, y queda un riesgo abierto sin confirmar sobre si la categoría usada captura la salida de consola del código que se planea escribir (ver H3/H4) |
| Responsable | SRE |

## Causa raíz

`SFC-PosWasmRelay-DEV` es un recurso nuevo, provisionado sin ningún Diagnostic Setting configurado — no es una regresión ni una falla de otro ticket, simplemente nunca se había hecho el trabajo de conectarlo al pipeline de Graylog que ya existe para el resto de la flota (GITIN-1883/1892/1794/1834). Adicionalmente, al tratarse de una Function App y no de un Web App como los 6 servicios API ya conectados, el patrón de Terraform existente (`app_services_dev.tf`) no aplica directamente — Function Apps exponen un conjunto de categorías de Diagnostic Settings distinto (`FunctionAppLogs`, no `AppServiceConsoleLogs`), lo que requirió un archivo Terraform separado con un tipo de data source distinto (`azurerm_linux_function_app`) en vez de replicar el patrón de Web App sin verificar.

## Hallazgos

| # | Hallazgo | Riesgo |
|---|---|---|
| H1 | `SFC-PosWasmRelay-DEV` confirmado sin código de función desplegado (`az functionapp function list` vacío, sin error) — estado esperado, no bloquea el despliegue del Diagnostic Setting, pero implica que no habrá datos reales en Graylog hasta que Desarrollo despliegue código real. | Bajo |
| H2 | Confirmado que Function Apps exponen un conjunto de categorías de Diagnostic Settings distinto al de los Web Apps ya conectados: `AppServiceConsoleLogs`/`AppServiceAppLogs` (usadas en `app_services_dev.tf`) no están disponibles para este recurso. La categoría real es `FunctionAppLogs` ("Function Application Logs" en Azure Portal). El endpoint `az monitor diagnostic-settings categories list` devolvió vacío contra este recurso — mismo comportamiento ya documentado en `cloud-graylog/terraform/service_bus.tf` para Service Bus Grido, no exclusivo de ese tipo de recurso. Confirmado en su lugar directamente en Azure Portal. | Bajo (ya resuelto) |
| H3 | **Riesgo abierto, sin confirmar:** no está verificado si la categoría `FunctionAppLogs` captura la salida de consola cruda (stdout) de la forma en que `AppServiceConsoleLogs` lo hace para un Web App, o si está limitada a los logs de invocación mediados por `ILogger` del host de Functions. `devs-log-structure.md` agrupa "Functions" junto con los hosts de API como emisores del mismo sink de consola de Serilog, pero una Function App media el logging de forma distinta a un Web App (especialmente bajo el modelo de worker aislado) — no hay garantía de que ambos puntos de captura sean equivalentes. Si Desarrollo construye el relay usando el mismo patrón Serilog→stdout que las APIs, esto podría no llegar a Graylog pese a que el Diagnostic Setting esté correctamente configurado. | Medio |
| H4 | Según lo reportado, Desarrollo estaría probando la función localmente como bloque de código aislado, no contra un despliegue real de la Function App — inferido de que no se solicitó ningún recurso de Azure para este trabajo hasta ahora. La ejecución local no pasa por el pipeline real de Diagnostic Settings: un test local exitoso no confirma que la misma salida llegue a `FunctionAppLogs` en el recurso real. Compone directamente con H3 — sin un despliegue real mínimo, ninguno de los dos riesgos puede descartarse. | Medio |

## Recursos afectados

| Recurso | Detalle |
|---|---|
| Azure Function App | `SFC-PosWasmRelay-DEV`, grupo de recursos `SmartFran.Cloud`, suscripción Smart IT - Grido (`0190fa7d-4ccf-4e3d-beb1-323b5780bfc8`) — nuevo Diagnostic Setting creado |
| Event Hub | Namespace `smartfran-graylog-evhns-pro`, hub compartido `app-logs` (suscripción SmartIT Cloud) — recibe ahora también el tráfico de este recurso, cross-subscription (mismo patrón ya validado en GITIN-1794) |
| Repo `cloud-graylog` | `terraform/function_app_dev.tf` (nuevo) — recurso `azurerm_monitor_diagnostic_setting.poswasmrelay_dev` + data source `azurerm_linux_function_app.poswasmrelay_dev` |
| Graylog | Stream `DEV` (creado en GITIN-1794) — se espera que capture automáticamente los mensajes de este recurso vía el campo `name` (regex `.*-DEV`), a confirmar una vez exista tráfico real |

## Comandos ejecutados

| # | Comando/Script | Propósito |
|---|---|---|
| C1 | `scripts.sh` — listado de Function Apps de la suscripción | Ubicar `SFC-PosWasmRelay-DEV` e inventariar el resto de la flota |
| C2 | `scripts.sh` — listado de funciones dentro de `SFC-PosWasmRelay-DEV` | Confirmar ausencia de código desplegado (ver H1) |
| C3 | `scripts.sh` — obtener resource ID del recurso | Insumo para C4 y para el Terraform |
| C4 | `scripts.sh` — intento de listar categorías de Diagnostic Settings vía CLI | Confirmar categoría real — resultado vacío (ver H2), confirmado en su lugar vía Azure Portal |
| C5 | `scripts.sh` — `terraform plan` sin acotar | Confirmar resolución de un drift de disco no relacionado (ver Hallazgos secundarios) |
| C6 | `scripts.sh` — `terraform plan -target=...` guardado en `gitin-1901.tfplan` | Acotar el plan al recurso de este ticket, sin mezclar cambios pendientes no relacionados |
| C7 ⚠️ | `scripts.sh` — `terraform apply gitin-1901.tfplan` | Aplicar el Diagnostic Setting — resultado: `1 added, 0 changed, 0 destroyed` |

## Acciones propuestas

1. ~~Confirmar estado real de `SFC-PosWasmRelay-DEV` (código desplegado o no)~~ — **HECHO 2026-08-20** (ver H1).
2. ~~Confirmar la categoría real de Diagnostic Settings para Function Apps~~ — **HECHO 2026-08-20** (ver H2).
3. ~~Redactar y aplicar el recurso Terraform (`function_app_dev.tf`)~~ — **HECHO 2026-08-20.** `Apply complete! Resources: 1 added, 0 changed, 0 destroyed`.
4. **(SRE, seguimiento)** Confirmar que los mensajes de este recurso llegan automáticamente al stream `DEV` existente en Graylog, una vez exista tráfico real — no bloqueante, se espera automático vía la regla de stream ya creada en GITIN-1794.
5. **(Dev + SRE, seguimiento — no bloqueante para el cierre de este ticket, pero bloqueante para dar la integración por completa)** Confirmar si `FunctionAppLogs` captura la salida de consola cruda (Serilog Console sink) o solo logs de invocación mediados por `ILogger` — requiere un despliegue real mínimo de código a `SFC-PosWasmRelay-DEV` (no solo pruebas locales, ver H3/H4) antes de considerar la integración validada end-to-end.
6. **(SRE, seguimiento, no bloqueante)** `cloud/docs/infrastructure.md` documenta nombres de Function Apps PROD (`SmartFranCloudBusinessFunPro`, `SmartFranCloudTicketProcessAsync-pro`, `SmartFranCloudFunctionsScheduledJobs-pro`) que no coinciden con ningún recurso real de la suscripción Smart IT - Grido (`az functionapp list` completo, sin resultados `-pro`/`-PRO`) — no relacionado con el alcance de este ticket, requiere corrección o confirmación de en qué suscripción viven realmente.

## Hallazgos secundarios

| # | Hallazgo | Riesgo |
|---|---|---|
| H5 | Drift de disco no relacionado, encontrado y corregido en la misma sesión de trabajo sobre el repo `cloud-graylog`: `azurerm_managed_disk.opensearch` seguía configurado en Terraform (`main.tf`, fase `pilot`) en 128GB, mientras el disco real había sido redimensionado manualmente fuera de Terraform a 512GB (Premium SSD P20, 2300 IOPS). Corregido alineando `local.phase_config.pilot.opensearch_disk_size` a 512 — confirmado sin diferencia en `terraform plan` tras el cambio (C5). Mencionado por transparencia, ya que de no corregirse hubiera bloqueado cualquier `apply` posterior en el repo (Azure no permite reducir el tamaño de un disco administrado). | Bajo (ya corregido) |
| H6 | El mismo `terraform plan` sin acotar (C5) mostró 16 cambios y 1 recurso nuevo (`azurerm_monitor_diagnostic_setting.service_bus_grido`) ya existentes sin commitear en el repo `cloud-graylog` antes de esta sesión — trabajo de otra sesión, no tocado ni aplicado en el marco de este ticket. Queda a criterio del equipo cuándo revisar y aplicar ese trabajo pendiente. | Bajo |
