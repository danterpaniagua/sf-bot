# Eventos — 20260821_functionapps-prod-to-graylog

## 2026-08-21 — Apertura de GITIN-1914

He abierto este ticket a partir del pedido de agregar tres Function Apps a Graylog: `SmartFranCloudBusinessFunPro`, `SmartFranCloudFunctionsScheduledJobs-pro`, `SmartFranCloudTicketProcessAsync-pro`, cubriendo producción y desarrollo donde exista. He identificado que estos tres nombres ya habían aparecido en GITIN-1901 como una discrepancia sin resolver: no coincidían con nada en `az functionapp list` contra la suscripción Smart IT - Grido. Al revisar `cloud/docs/infrastructure.md` he confirmado que la búsqueda de GITIN-1901 apuntó a la suscripción equivocada — estos tres recursos PROD viven en la suscripción SmartIT Cloud, no en Grido.

## 2026-08-21 — Confirmación de los tres Function Apps PROD

**Comando:** C1 — listado filtrado de Function Apps PROD
**Resultado:**
Los tres recursos confirmados: `SmartFranCloudFunctionsScheduledJobs-pro`, `SmartFranCloudBusinessFunPro`, `SmartFranCloudTicketProcessAsync-pro` — RG `SmartFran.Cloud.PRO`, estado `Running`, kind `functionapp,linux`.

He confirmado que la suscripción correcta era SmartIT Cloud, resolviendo la discrepancia dejada abierta en GITIN-1901.

## 2026-08-21 — Búsqueda de equivalentes DEV

**Comando:** C2 — listado filtrado de Function Apps en la suscripción Grido
**Resultado:**
He encontrado equivalentes DEV para dos de los tres nombres (`SmartFranCloudBusinessFun-DEV`, `SmartFranCloudFunctionsScheduledJobs-dev`), además de variantes DEV2/STG/TEST fuera de alcance. Para `TicketProcessAsync` no apareció ningún recurso DEV — solo dos variantes STG bajo convenciones de nombre distintas (`SFC-TicketProcessAsync-STG`, `SmartFranCloudTicketProcessAsync-stg`).

He confirmado que `TicketProcessAsync` queda fuera del alcance DEV de este ticket, ya que no existe ese equivalente — coherente con el pedido original de cubrir DEV solo donde exista.

## 2026-08-21 — Verificación de Diagnostic Settings preexistentes

Mi primer intento de comando falló por un error de sintaxis de shell y un error de uso de `az`, aparentemente por el placeholder `<RESOURCE_ID>` sin sustituir. He reformulado el comando como cinco líneas independientes con los resource IDs reales ya reemplazados.

**Comando:** C3 — `az monitor diagnostic-settings list` contra los 5 recursos en alcance
**Resultado:**
Los cinco resultados vinieron vacíos.

He confirmado que ninguno de los 5 recursos tenía un Diagnostic Setting previo — sin riesgo de conflicto para el nuevo recurso Terraform.

## 2026-08-21 — Redacción de Terraform

He redactado `cloud-graylog/terraform/function_app_pro.tf` (archivo nuevo) con los tres recursos PROD, siguiendo el patrón ya usado en `app_services.tf` (proveedor por defecto, `var.resource_group_name`). He agregado los dos recursos DEV a `function_app_dev.tf`, el archivo ya creado en GITIN-1901 para Function Apps DEV, en vez de crear un archivo nuevo, para mantener agrupados todos los recursos DEV de este tipo. En los cinco casos he reutilizado la categoría `FunctionAppLogs`, ya confirmada en GITIN-1901 para un Function App Linux en la misma suscripción Grido.

## 2026-08-21 — Plan y aplicación de Terraform

**Comando:** C4 — `terraform plan` acotado (`-target`) a los 5 recursos nuevos, guardado en `gitin-1914.tfplan`
**Resultado:**
`Plan: 5 to add, 0 to change, 0 to destroy.` Advertencia estándar de Terraform sobre el uso de `-target`, sin relevancia adicional.

He confirmado que el plan quedó acotado exclusivamente a los recursos de este ticket, sin arrastrar el drift pendiente no relacionado ya señalado en GITIN-1901 (bloques `metric` obsoletos, recurso `service_bus_grido` sin commitear).

**Comando:** C5 ⚠️ — `terraform apply gitin-1914.tfplan`
**Resultado:**
`Apply complete! Resources: 5 added, 0 changed, 0 destroyed.`

He confirmado el despliegue exitoso de los cinco Diagnostic Settings. He dejado el ticket en estado parcial — la infraestructura está lista, pero la entrega end-to-end sigue sin poder verificarse hasta que exista tráfico real, y queda abierto un riesgo sobre si la regla del stream `DEV` (regex `.*-DEV`) es case-sensitive, dado que `SmartFranCloudFunctionsScheduledJobs-dev` tiene el sufijo en minúscula.
