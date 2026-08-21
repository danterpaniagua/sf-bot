# Eventos — 20260820_azure-functions-to-graylog

## 2026-08-20 — Apertura de GITIN-1901 y corrección de alcance

He abierto la investigación a partir del título de GITIN-1901 ("agregar Azure Functions a Graylog"), asumiendo inicialmente que se trataba de promover los logs operativos propios de las Function Apps existentes, en paralelo a lo que hizo GITIN-1892 para las APIs. He confirmado que el alcance real es distinto: una Function App específica, `SFC-PosWasmRelay-DEV`, que actuará como relay de logs del POS (SPA Blazor WASM), necesita que su salida de consola llegue a Graylog. He descartado la exploración inicial que había hecho sobre `LogEndpoints.RegisterLog`/Cosmos (un flujo ya existente y no relacionado) al corregir el alcance.

## 2026-08-20 — Inventario de Function Apps en la suscripción Smart IT - Grido

**Comando:** C1 — listado de Function Apps
**Resultado:**
17 Function Apps listadas, ninguna con sufijo `-pro`/`-PRO`. `SFC-PosWasmRelay-DEV` presente, grupo de recursos `SmartFran.Cloud`, estado `Running`.

He confirmado que el listado está completo. Esto deja sin resolver una discrepancia con `cloud/docs/infrastructure.md`, que documenta nombres de Function Apps PROD que no aparecen en este listado — la dejo registrada como acción de seguimiento no bloqueante, fuera del alcance de este ticket.

## 2026-08-20 — Confirmación de que SFC-PosWasmRelay-DEV no tiene código desplegado

**Comando:** C2 — listado de funciones dentro de `SFC-PosWasmRelay-DEV`
**Resultado:**
Vacío, sin error.

Este resultado es el esperado: la Function App está provisionada pero sin código de función desplegado todavía. He ajustado el alcance de la investigación en consecuencia — este ticket puede avanzar sobre la configuración de Diagnostic Settings de forma independiente al código de la aplicación, que queda fuera de mi alcance.

## 2026-08-20 — Confirmación de que el proyecto de infraestructura real es cloud-graylog

El repo `~/Documentos/git/cloud-graylog/` es el proyecto principal para este trabajo, con su propio `CLAUDE.md`. He leído ese archivo y confirmado el patrón ya usado en GITIN-1794/1834 para conectar App Services DEV al Event Hub compartido (`app_services_dev.tf`). Queda establecida la división de responsabilidades: el seguimiento del ticket permanece en este repo (`bots/cloud/events/`), la implementación real de Terraform va en `cloud-graylog`.

## 2026-08-20 — Drift de disco no relacionado encontrado y corregido

El disco de OpenSearch fue redimensionado manualmente fuera de Terraform, en `cloud-graylog/terraform/disks.tf`. He confirmado contra `terraform.tfstate` que el estado sigue registrando la fase `pilot` (128GB) mientras el disco real es de 512GB (Premium SSD P20, 2300 IOPS). He corregido `main.tf` (`local.phase_config.pilot.opensearch_disk_size`, 128 → 512) para alinear la configuración con la realidad, ya que Azure no permite reducir el tamaño de un disco administrado.

**Comando:** C5 — `terraform plan` sin acotar
**Resultado:**
`azurerm_managed_disk.opensearch` no aparece en el plan — drift resuelto. El plan muestra además 16 cambios (bloques `metric` obsoletos) y 1 recurso nuevo (`service_bus_grido`) ya existentes sin commitear en el repo antes de esta sesión.

He confirmado que ninguno de esos 16 cambios ni el recurso `service_bus_grido` corresponden a esta sesión — quedan señalados como trabajo pendiente de otra sesión, sin tocar.

## 2026-08-20 — Borrador de Terraform y verificación de categoría de Diagnostic Settings

He redactado `cloud-graylog/terraform/function_app_dev.tf` en un archivo separado, replicando el patrón de `app_services_dev.tf` pero con `data.azurerm_linux_function_app` en vez de `azurerm_linux_web_app`, dado que se trata de una Function App.

**Comando:** C4 — intento de listar categorías de Diagnostic Settings vía CLI contra `SFC-PosWasmRelay-DEV`
**Resultado:**
Vacío, sin error.

He confirmado que el resource ID se resolvió correctamente, descartando que el vacío se deba a un error de variable. Este comportamiento coincide con un quirk ya documentado en `service_bus.tf` para Service Bus Grido — el endpoint de categorías no enumera para ciertos tipos de recurso. Sin datos de log existentes para cruzar vía KQL (a diferencia de Service Bus), la verificación directa en el Portal de Azure queda como la alternativa más confiable.

Las categorías reales disponibles para este recurso quedan confirmadas en el Portal: "Function Application Logs" (= `FunctionAppLogs`), "Site Content Change Audit Logs", "Access Audit Logs", "IPSecurity Audit logs", "App Service Authentication logs (preview)" — ninguna coincide con `AppServiceConsoleLogs`/`AppServiceAppLogs`, usadas para los Web Apps. He actualizado `function_app_dev.tf` para reflejar `FunctionAppLogs` como categoría confirmada, no como supuesto.

## 2026-08-20 — Riesgo abierto: punto de captura de FunctionAppLogs sin confirmar

El equipo de desarrollo está construyendo este relay siguiendo el mismo patrón de logging que las APIs (Serilog → sink de consola → stdout), documentado en `devs-log-structure.md`. He identificado que no está confirmado si la categoría `FunctionAppLogs` captura stdout crudo de la misma forma en que `AppServiceConsoleLogs` lo hace para un Web App, dado que una Function App media el logging de forma distinta bajo el modelo de worker aislado. El desarrollador estaría probando la función localmente como bloque de código aislado, no contra un despliegue real — inferido de que nunca se solicitaron recursos de Azure para este trabajo. He dejado ambos riesgos documentados en `investigation.md` y en este ticket (H3/H4) como seguimiento no bloqueante para el cierre de este ticket, pero sí bloqueante para dar la integración por completa validada end-to-end.

## 2026-08-20 — Despliegue del Diagnostic Setting

**Comando:** C6 — `terraform plan` acotado (`-target`), guardado en `gitin-1901.tfplan`
**Resultado:**
`Plan: 1 to add, 0 to change, 0 to destroy.` Advertencia estándar de Terraform sobre el uso de `-target`, sin relevancia adicional.

He confirmado que el plan quedó acotado exclusivamente al recurso de este ticket, sin arrastrar los cambios pendientes no relacionados (H6).

**Comando:** C7 ⚠️ — `terraform apply gitin-1901.tfplan`
**Resultado:**
`Apply complete! Resources: 1 added, 0 changed, 0 destroyed.`

He confirmado el despliegue exitoso del Diagnostic Setting sobre `SFC-PosWasmRelay-DEV`. He dejado el ticket en estado parcial — la infraestructura está lista, pero la entrega end-to-end sigue sin poder verificarse hasta que exista código real desplegado en la Function App (H1) y se resuelva el riesgo abierto sobre el punto de captura (H3/H4).
