# Reducir verbosidad de enabled_logs en Diagnostic Settings — GITIN-1882

**Tags:** `SmartCloud`, `Graylog`, `Terraform`, `Azure`, `PROD`

## Resumen

Los 16 Diagnostic Settings de App Services (8 en PROD, 8 en DEV) definidos en `cloud-graylog/terraform/app_services.tf` y `app_services_dev.tf` envían actualmente entre 4 y 9 categorías de log por app hacia el Event Hub compartido (y, en el caso de `pos`, `platform`, `admin` y `catalog` en PROD, también hacia Log Analytics), generando un volumen de ingesta mayor al necesario para el objetivo de diagnóstico del pipeline. Se reconfigurará cada resource para dejar habilitada únicamente la categoría `AppServiceConsoleLogs`, reduciendo la verbosidad de ambos destinos donde aplica. Ticket padre GITIN-1835.

## Tabla resumen

| Campo | Valor |
|---|---|
| Ticket Jira | GITIN-1882 (padre: GITIN-1835) |
| ID alerta | N/A — tarea planificada, no alerta |
| Sistema | SmartFran Cloud — pipeline de logs a Graylog (Diagnostic Settings, Event Hub, Terraform en repo `cloud-graylog`) |
| Severidad | Baja — cambio de configuración planificado, reduce volumen de datos, no afecta disponibilidad |
| Detectado | N/A — trabajo proactivo |
| Resuelto | Sí — 2026-08-18. Objetivo cumplido y verificado en los 16 recursos. Chequeo de volumen en Graylog y actualización de `cloud-graylog/CLAUDE.md` quedan como seguimiento (acciones 5 y 6), no bloquean el cierre |
| Responsable | SRE |

## Causa raíz

Las 16 Diagnostic Settings fueron creadas en tickets previos (GITIN-1794 para DEV, GITIN-1834 para el resto de PROD) replicando siempre el mismo set de 4 categorías (`AppServiceConsoleLogs`, `AppServiceHTTPLogs`, `AppServiceAppLogs`, `AppServicePlatformLogs`) sin una revisión de qué categorías son realmente necesarias para diagnóstico; `pos`, `platform`, `admin` y `catalog` en PROD además heredan 5 categorías de auditoría adicionales (9 en total) que estaban en su Diagnostic Setting original de Log Analytics, restaurado sin filtrar durante GITIN-1834. No hubo hasta ahora una decisión explícita sobre qué categorías aportan valor real vs. volumen innecesario.

## Hallazgos

| # | Hallazgo | Riesgo |
|---|---|---|
| H1 | Los 16 resources de Diagnostic Settings envían entre 4 y 9 categorías de log; el objetivo es dejar únicamente `AppServiceConsoleLogs` en los 16. | Bajo |
| H2 | `pos`, `platform`, `admin` y `catalog` (PROD) comparten el mismo `enabled_log` entre el Event Hub y `log_analytics_workspace_id` — no es posible tener sets de categorías distintos por destino dentro de un mismo resource de Azure. Reducir a solo `AppServiceConsoleLogs` en estos 4 recursos reduce también lo que llega a Log Analytics, no solo a Graylog. Alcance confirmado: el cambio se aplica a ambos destinos por igual, sin excepción. | Medio |
| H3 | Según los datos de volumen documentados en `cloud-graylog/CLAUDE.md` (medición 2026-06-25), `AppServiceConsoleLogs` es la categoría de mayor volumen de la flota (70,5% del total), mientras que `AppServiceHTTPLogs` y `AppServicePlatformLogs` combinadas son menos del 1,5%. Dejar solo `AppServiceConsoleLogs` retiene la categoría de mayor volumen y elimina las de menor volumen — a confirmar por quien apruebe el ticket que ese es el resultado buscado. | Bajo |
| H4 | Sales, Business y Person (PRO) tienen, además del Diagnostic Setting gestionado por Terraform (correctamente reducido), un segundo objeto preexistente fuera de Terraform (nombre con espacio inicial, ya documentado en GITIN-1834) que sigue con las 9 categorías habilitadas. Verificado que ese objeto solo tiene `workspaceId` (Log Analytics) — `eventHubName`/`eventHubAuthorizationRuleId` son `null` — por lo que no envía datos a Graylog; el objetivo de este ticket no se ve afectado. Fuera de alcance de GITIN-1882, pero afecta volumen/costo de Log Analytics. | Bajo |
| H5 | El `workspaceId` del objeto huérfano en Business y Person apunta a la subscripción `d6ab1add-4bc8-40b0-8cf8-e7291f7171b0`, ya reportada como inexistente (`SubscriptionNotFound`) durante GITIN-1834 — es probable que ese objeto no esté entregando datos a Log Analytics con éxito, aunque esto no fue confirmado directamente en este ticket. | Bajo |

## Recursos afectados

| Recurso | Detalle |
|---|---|
| App Services PROD | `SmartFran-Cloud-{Sales,Business,Pos,Platform,Person,Admin,Catalog,Orders}-PRO` (RG `SmartFran.Cloud.PRO`, subscription `SmartIT Cloud` `85c76dea-3304-4310-8656-bf21b28e4f4b`) |
| App Services DEV | `SmartFran-Cloud-{Sales,Pos,Catalog,Platform,Admin,Person,Business,Orders}-DEV` (subscription `Smart IT - Grido` `0190fa7d...`, provider `azurerm.development`) |
| Terraform | `cloud-graylog/terraform/app_services.tf`, `app_services_dev.tf` (repo separado, no forma parte de este monorepo) |
| Log Analytics Workspace | `SmartFranCloudPro` (customerId `76536d4a-5616-44ae-bee4-0aa6963b5d28`) — afectada indirectamente en `pos`/`platform`/`admin`/`catalog` (ver H2) |

## Comandos ejecutados

| # | Comando/Script | Propósito |
|---|---|---|
| — | Edición directa de `app_services.tf` / `app_services_dev.tf` (sin script, edición de archivo) | Reducir los 16 `enabled_log` a un único bloque `AppServiceConsoleLogs` por recurso |
| C1 | `scripts.sh` — `terraform fmt -check -diff` | Confirmar formato correcto tras la edición (sin cambios pendientes) |
| C2 | `scripts.sh` — `terraform plan` acotado a los 16 recursos | Validar el alcance antes de aplicar — resultado: `0 to add, 16 to change, 0 to destroy`, coincide con lo esperado |
| C3 | `scripts.sh` — `terraform apply` del plan guardado | Aplicar el cambio en Azure — resultado: `0 added, 16 changed, 0 destroyed`, coincide con el plan |

| C4 | `scripts.sh` — `az monitor diagnostic-settings list` por app (16 archivos JSON en `diag-verify/`) | Confirmar categoría única habilitada por recurso — resultado: los 16 recursos gestionados por Terraform quedaron correctos |

Chequeo de volumen en Graylog (C5) aún pendiente.

## Acciones propuestas

1. ~~Editar `cloud-graylog/terraform/app_services.tf` y `app_services_dev.tf`~~ — **HECHO 2026-08-18.** Los 16 resources `azurerm_monitor_diagnostic_setting` quedaron con un único `enabled_log { category = "AppServiceConsoleLogs" }`, removiendo el resto (incluidas las 5 categorías de auditoría en `pos`/`platform`/`admin`/`catalog`).
2. ~~Correr `terraform plan` acotado a los 16 resources~~ — **HECHO 2026-08-18.** Resultado `0 to add, 16 to change, 0 to destroy`, sin recursos fuera de alcance.
3. ~~Aplicar el cambio~~ — **HECHO 2026-08-18.** `Apply complete! Resources: 0 added, 16 changed, 0 destroyed`, coincide con el plan.
4. ~~Verificar por `az monitor diagnostic-settings list` por app~~ — **HECHO 2026-08-18.** Los 16 recursos gestionados por Terraform (PRO y DEV) quedaron con una única categoría habilitada (`AppServiceConsoleLogs`); en Pos/Platform/Admin/Catalog el `workspaceId` de Log Analytics sigue activo, solo con la categoría reducida — sin repetir la sobrescritura de GITIN-1834. Ver hallazgo H4 sobre un objeto adicional fuera de alcance en Sales/Business/Person.
5. Confirmar en Graylog (Views Search, ventana corta post-cambio) que el volumen de ingesta cae y que solo se siguen recibiendo mensajes de categoría `AppServiceConsoleLogs` por app.
6. Actualizar `cloud-graylog/CLAUDE.md` (sección "Key Decisions" y la tabla de volumen) para reflejar el nuevo set de categorías una vez aplicado.
