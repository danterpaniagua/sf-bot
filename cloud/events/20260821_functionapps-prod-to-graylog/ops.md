# Conectar Function Apps PROD/DEV a Graylog vía Event Hub — GITIN-1914

**Tags:** `SmartCloud`, `Graylog`, `Azure`, `Terraform`

## Resumen

Tres Function Apps PROD de SmartFran Cloud (`SmartFranCloudBusinessFunPro`, `SmartFranCloudFunctionsScheduledJobs-pro`, `SmartFranCloudTicketProcessAsync-pro`) no tenían ningún Diagnostic Setting configurado — a diferencia de los 6 servicios API ya conectados a Graylog vía Event Hub (GITIN-1883/1892/1835), sin ningún camino hacia Graylog para su salida de consola. La brecha había quedado señalada como pendiente no bloqueante en GITIN-1901, donde una búsqueda de estos tres nombres contra la suscripción equivocada (Smart IT - Grido) no encontró coincidencias. Este ticket confirma los tres recursos en la suscripción correcta (SmartIT Cloud), agrega sus Diagnostic Settings, y hace lo mismo para los equivalentes DEV que efectivamente existen (dos de los tres).

## Tabla resumen

| Campo | Valor |
|---|---|
| Ticket Jira | GITIN-1914 |
| ID alerta | N/A — trabajo planificado, no alerta |
| Sistema | SmartFran Cloud — Function Apps PROD (suscripción SmartIT Cloud) y DEV (suscripción Smart IT - Grido), pipeline Event Hub → Graylog (repo `cloud-graylog`) |
| Severidad | Baja |
| Detectado | 2026-08-21 |
| Resuelto | Parcial — Diagnostic Settings desplegados y confirmados (`terraform apply`, 5 added). Entrega end-to-end sin verificar (ver H3/H4) |
| Responsable | SRE |

## Causa raíz

Los tres Function Apps PROD son recursos ya provisionados y en ejecución que nunca tuvieron un Diagnostic Setting configurado — no es una regresión, sino trabajo de habilitación pendiente sobre la flota, en la misma línea que GITIN-1901/1794/1834 para el resto de los servicios. La búsqueda previa en GITIN-1901 había fallado por apuntar a la suscripción Smart IT - Grido, que no contiene estos recursos PROD — los tres viven en `SmartFran.Cloud.PRO`, suscripción SmartIT Cloud, confirmado en este ticket.

## Hallazgos

| # | Hallazgo | Riesgo |
|---|---|---|
| H1 | Los tres Function Apps PROD confirmados en la suscripción SmartIT Cloud (`SmartFran.Cloud.PRO`, `functionapp,linux`, `Running`) — la búsqueda previa de GITIN-1901 había apuntado a la suscripción Smart IT - Grido, que no los contiene. | Bajo (ya resuelto) |
| H2 | De los tres, solo dos tienen equivalente DEV en la suscripción Smart IT - Grido: `SmartFranCloudBusinessFun-DEV` y `SmartFranCloudFunctionsScheduledJobs-dev`. `TicketProcessAsync` no tiene equivalente DEV — solo existen variantes STG bajo dos convenciones de nombre distintas (`SFC-TicketProcessAsync-STG`, `SmartFranCloudTicketProcessAsync-stg`). | Bajo |
| H3 | El stream `DEV` existente en Graylog (creado en GITIN-1794) enruta por una regla regex `.*-DEV` sobre el campo `name` — no está confirmado si esa regex es case-sensitive. `SmartFranCloudFunctionsScheduledJobs-dev` tiene el sufijo en minúscula (`-dev`), a diferencia de `SmartFranCloudBusinessFun-DEV` (mayúscula) y del resto de la flota DEV ya conectada. Si la regla es case-sensitive, los mensajes de este recurso llegarán al Event Hub pero no al stream `DEV` — quedarán en el stream por defecto. | Medio |
| H4 | Entrega end-to-end sin verificar para los 5 recursos — un `terraform apply` exitoso confirma que el Diagnostic Setting existe, no que los datos efectivamente fluyen hacia Graylog (mismo caveat ya documentado para Business en `app_services.tf` por su integración VNet). Tampoco está confirmado si los mensajes PROD de estos 3 recursos caen dentro del enrutamiento de stream PRO existente. | Medio |

## Recursos afectados

| Recurso | Detalle |
|---|---|
| Azure Function App (PROD) | `SmartFranCloudBusinessFunPro`, `SmartFranCloudFunctionsScheduledJobs-pro`, `SmartFranCloudTicketProcessAsync-pro` — RG `SmartFran.Cloud.PRO`, suscripción SmartIT Cloud (`85c76dea...`) — nuevo Diagnostic Setting c/u |
| Azure Function App (DEV) | `SmartFranCloudBusinessFun-DEV`, `SmartFranCloudFunctionsScheduledJobs-dev` — RG `SmartFran.Cloud`, suscripción Smart IT - Grido (`0190fa7d...`) — nuevo Diagnostic Setting c/u |
| Event Hub | Namespace `smartfran-graylog-evhns-pro`, hub compartido `app-logs` (suscripción SmartIT Cloud) — recibe ahora también el tráfico de estos 5 recursos |
| Repo `cloud-graylog` | `terraform/function_app_pro.tf` (nuevo, 3 recursos) + `terraform/function_app_dev.tf` (ampliado, 2 recursos nuevos) |
| Graylog | Stream `DEV` (creado en GITIN-1794) — se espera que capture automáticamente los mensajes de los 2 recursos DEV vía el campo `name` (regex `.*-DEV`); ver H3 sobre el riesgo de case-sensitivity para uno de los dos |

## Comandos ejecutados

| # | Comando/Script | Propósito |
|---|---|---|
| C1 | `scripts.sh` — listado filtrado de Function Apps PROD | Confirmar existencia de los tres recursos PROD en la suscripción correcta |
| C2 | `scripts.sh` — listado filtrado de Function Apps en Grido | Ubicar equivalentes DEV de los tres nombres PROD |
| C3 | `scripts.sh` — `az monitor diagnostic-settings list` contra los 5 recursos | Confirmar ausencia de Diagnostic Settings previos, sin conflicto |
| C4 | `scripts.sh` — `terraform plan` acotado (`-target`), guardado en `gitin-1914.tfplan` | Acotar el plan a los 5 recursos nuevos, sin arrastrar drift pendiente no relacionado |
| C5 ⚠️ | `scripts.sh` — `terraform apply gitin-1914.tfplan` | Aplicar los 5 Diagnostic Settings — resultado: `5 added, 0 changed, 0 destroyed` |

## Acciones propuestas

1. ~~Confirmar existencia real de los tres Function Apps PROD en la suscripción correcta~~ — **HECHO 2026-08-21** (ver H1).
2. ~~Confirmar equivalentes DEV de los tres nombres~~ — **HECHO 2026-08-21** (ver H2).
3. ~~Redactar y aplicar los recursos Terraform~~ — **HECHO 2026-08-21.** `Apply complete! Resources: 5 added, 0 changed, 0 destroyed`.
4. **(SRE, seguimiento)** Confirmar que los mensajes de los 5 recursos llegan efectivamente a Graylog una vez exista tráfico real — no bloqueante para el cierre de este ticket, pero bloqueante para dar la integración por completa validada end-to-end.
5. **(SRE, seguimiento)** Confirmar si la regla del stream `DEV` (`.*-DEV`) es case-sensitive; si lo es, ajustar la regla o agregar una regla equivalente para que `SmartFranCloudFunctionsScheduledJobs-dev` también caiga en el stream `DEV` (ver H3).
6. **(SRE, seguimiento)** Confirmar el enrutamiento de stream para los mensajes PROD de estos 3 recursos dentro de las reglas de stream PRO existentes (ver H4).
