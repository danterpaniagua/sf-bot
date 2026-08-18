# Eventos — 20260818_reduce-enabled-logs-verbosity

## 2026-08-18 09:00 — Apertura del ticket GITIN-1882

He revisado `cloud-graylog/terraform/app_services.tf` y `app_services_dev.tf` para relevar el estado actual de `enabled_log` en los 16 Diagnostic Settings. He confirmado que 12 de los 16 recursos (Sales/Business/Person/Orders en PROD, y los 8 de DEV) coinciden con el estado de 4 categorías descripto inicialmente, pero Pos/Platform/Admin/Catalog en PROD tienen 9 categorías habilitadas y comparten el mismo `enabled_log` entre Event Hub y Log Analytics. He definido aplicar la reducción a `AppServiceConsoleLogs` únicamente en los 16 recursos, ambos destinos incluidos, tras confirmar el alcance para estos 4 recursos. He dejado registrada la investigación y el ticket; el cambio de Terraform en sí queda pendiente de implementación.

## 2026-08-18 09:20 — Edición de Terraform aplicada

He editado los 16 resources `azurerm_monitor_diagnostic_setting` en `cloud-graylog/terraform/app_services.tf` (8 recursos PROD) y `app_services_dev.tf` (8 recursos DEV), dejando en cada uno un único bloque `enabled_log { category = "AppServiceConsoleLogs" }` y removiendo el resto de las categorías (incluidas las 5 de auditoría en `pos`/`platform`/`admin`/`catalog`). He confirmado por `grep` que los 16 recursos quedaron con exactamente una línea `enabled_log` cada uno, y he corrido `terraform fmt -check -diff` sobre ambos archivos, sin diferencias de formato. No he corrido `terraform plan`/`apply` — esta sesión no tiene credenciales de Azure; quedan armados como C2-C5 en `scripts.sh`, pendientes de ejecución.

## 2026-08-18 09:35 — Plan confirmado

He corrido `terraform plan` acotado a los 16 recursos: `Plan: 0 to add, 16 to change, 0 to destroy`. Coincide exactamente con lo esperado — ningún recurso fuera de los 16 objetivo, sin altas ni bajas, solo cambios. Queda pendiente el `apply` del plan guardado y la verificación posterior por `az monitor diagnostic-settings list`.

## 2026-08-18 09:42 — Apply aplicado

He aplicado el plan guardado con `terraform apply`: `Apply complete! Resources: 0 added, 16 changed, 0 destroyed`. Coincide exactamente con el plan validado en el paso anterior. Queda pendiente la verificación por `az monitor diagnostic-settings list` por app (Comando C4/C5 en `scripts.sh`) para confirmar que cada Diagnostic Setting quedó con una única categoría habilitada en ambos destinos donde corresponde, y la verificación en Graylog de la caída de volumen.

## 2026-08-18 09:55 — Verificación post-apply (16 archivos JSON)

He leído los 16 archivos JSON (`az monitor diagnostic-settings list` por app, PRO y DEV) guardados en `diag-verify/`. He confirmado que los 16 recursos gestionados por Terraform quedaron con una única categoría habilitada (`AppServiceConsoleLogs`), y que en Pos/Platform/Admin/Catalog (PRO) el `workspaceId` de Log Analytics sigue presente, solo con la categoría reducida — sin repetir la sobrescritura de GITIN-1834.

He encontrado además que Sales, Business y Person (PRO) devuelven un segundo objeto de Diagnostic Setting cada uno, con un espacio inicial en el nombre (`" SmartFran.Cloud.PRO.{App}_DiagnosticSettings"`) — el mismo objeto preexistente fuera de Terraform ya documentado en GITIN-1834. Ese objeto sigue con las 9 categorías habilitadas, sin cambios de este ticket. He verificado que ese objeto solo apunta a `workspaceId` (Log Analytics) — `eventHubName`/`eventHubAuthorizationRuleId` son `null` en los tres — por lo que no envía datos al Event Hub ni a Graylog. El objetivo de este ticket (reducir verbosidad en el pipeline de Graylog) está cumplido en los 16 recursos. El objeto huérfano de Log Analytics en Sales/Business/Person queda fuera del alcance de GITIN-1882, pero lo dejo registrado como hallazgo secundario — Business y Person además apuntan a la subscripción inválida `d6ab1add-4bc8-40b0-8cf8-e7291f7171b0` (ya reportada como `SubscriptionNotFound` en GITIN-1834), por lo que ese objeto probablemente ni siquiera está entregando datos a Log Analytics con éxito.

## 2026-08-18 10:05 — Cierre del ticket GITIN-1882

Cierro el ticket. El objetivo (reducir a `AppServiceConsoleLogs` los 16 Diagnostic Settings que alimentan el Event Hub/Graylog) está cumplido y verificado en los 16 recursos, en PROD y DEV. Dejo dos acciones de seguimiento sin bloquear el cierre: confirmar en Graylog la caída real de volumen de ingesta, y actualizar `cloud-graylog/CLAUDE.md` con el nuevo set de categorías. El hallazgo del objeto huérfano de Log Analytics en Sales/Business/Person (H4/H5) queda documentado pero fuera de alcance de este ticket.
