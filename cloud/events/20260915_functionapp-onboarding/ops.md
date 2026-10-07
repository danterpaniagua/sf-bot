# GITIN-2050 — Onboarding de Function Apps a Graylog

**Tags:** `SmartCloud`, `Azure`, `Graylog`, `Terraform`

## Resumen

Las 4 Function Apps de SmartFran Cloud bajo `SFC-FunctionAPP-Linux-Plan-PRO` (`SFC-CodeGenerator-PRO`, `SFC-ScheduledJobs-PRO`, `SFC-PosWasmRelay-PRO`, `SFC-TicketProcess-PRO`) no estaban onboardeadas al pipeline de ingesta de Graylog, y la categoría `FunctionAppLogs` nunca tuvo ninguna promoción de campos — todo mensaje quedaba con el fallback genérico de Azure `"Microsoft.Web/sites/functions/log"`, sin contenido real indexado, porque su `properties` llega como un string con repr de diccionario Python (comillas simples), no JSON, y ningún guard `JSON.parse` existente en el pipeline lo reconocía. Esta ticket cierra ambas brechas: onboarding vía Terraform, separación a streams dedicados, y un parser nuevo para la promoción de campos, desplegado y verificado en producción el mismo día — con una segunda verificación posterior confirmando el pendiente que había quedado abierto (`SFC-TicketProcess-PRO`) y validando el propio pipeline recién desplegado.

## Tabla resumen

| Campo | Valor |
|---|---|
| Ticket Jira | GITIN-2050 |
| ID alerta | N/A — trabajo de onboarding planificado, no incidente |
| Sistema | Graylog / Logstash / Azure Event Hub (`smartfran-graylog-evhns-pro`) |
| Severidad | Informativo |
| Detectado | N/A |
| Resuelto | 2026-09-15 |
| Responsable | Dante Paniagua |

## Causa raíz

Dos brechas preexistentes quedaron expuestas y corregidas: (1) la categoría `FunctionAppLogs` nunca tuvo lógica de promoción de campos en el pipeline porque su `properties` llega como repr de diccionario Python, no JSON — ningún guard `JSON.parse` existente lo reconocía. (2) La copia del pipeline en el repo estaba desactualizada respecto a la desplegada en la VM — le faltaba el fix `GITIN-2034` (manejo de `properties` en dos shapes distintos), ya aplicado en producción pero nunca sincronizado de vuelta al repo.

## Hallazgos

| # | Hallazgo | Riesgo |
|---|---|---|
| H1 | El campo `name` en Graylog queda indexado en mayúsculas (viene de `resourceId`) — una query con el casing exacto de Azure devuelve 0 resultados de forma silenciosa, sin error. Causó un falso negativo real durante la verificación de esta sesión. | Medio |
| H2 | `FunctionAppLogs.properties` usa repr de diccionario Python (comillas simples), no JSON — ningún filtro `JSON.parse` existente lo procesaba. Todo mensaje de Function App quedaba sin campos promovidos y con mensaje genérico. | Medio |
| H3 | La copia del repo del pipeline de Logstash estaba desactualizada respecto a la versión real desplegada (le faltaba `GITIN-2034`) — desplegar la copia del repo tal cual hubiera revertido ese fix. | Alto |
| H4 | La copia del repo tiene las connection strings de Event Hub/Storage redactadas (`"NO"`) — desplegarla tal cual hubiera roto la conexión a Event Hub en producción. | Alto |
| H5 | Dentro de `EntryProperties` (mensajes de `SFC-PosWasmRelay-PRO`), todos los valores string salvo `StatusCode`/`ElapsedMs` llegan con un caracter de comilla simple envolvente como parte literal del valor (no artefacto de parseo) — mismo tipo de quirk ya documentado para `TraceKey`/`SourceContext` (GITIN-1924) pero confirmado ahora en el resto de los campos. | Bajo |
| H6 | `properties.message.Properties.Service` y `properties.message.Properties.EntryProperties.Service` son dos valores distintos en dos niveles de anidamiento — de promoverse ambos al mismo campo plano, uno pisa al otro silenciosamente. Resuelto usando `Service` para el externo y `ClientService` para el interno. | Bajo |
| H7 | El diagnostic setting viejo `ticketprocessasync_pro_sfc` (Terraform) apunta a un nombre de recurso que ya no existe en Azure (`SFC-TicketProcessAsync-PRO` → `SFC-TicketProcess-PRO`) — queda huérfano hasta el próximo `terraform apply` sin acotar. | Bajo |
| H8 | Verificación posterior (mismo día): la descarga cruda de la config en vivo, hecha para confirmar que el repo coincide con lo desplegado, quedó escrita en 2 archivos con el `SharedAccessKey`/`AccountKey` reales en texto plano (más 2 diffs derivados que también los contenían). Redactados los 4 archivos in-place al detectarlo, ninguno llegó a estar staged — evaluar si amerita rotar las credenciales. | Medio |

## Recursos afectados

| Recurso | Detalle |
|---|---|
| `SFC-CodeGenerator-PRO` | Function App — onboarding completo, verificado en vivo (incl. verificación posterior, confirma versión `LiteEditionV2`) |
| `SFC-ScheduledJobs-PRO` | Function App — onboarding completo, verificado en vivo. `FunctionName` confirmado en verificación posterior, separa `RegisterBusinessLog` (tráfico HTTP real) de sus 4 jobs internos por timer |
| `SFC-PosWasmRelay-PRO` | Function App — onboarding completo, verificado en vivo. Cada mensaje relayado incluye el detalle real de la llamada HTTP original del cliente POS |
| `SFC-TicketProcess-PRO` | Function App (renombrado desde `SFC-TicketProcessAsync-PRO`) — onboarding completo; verificación en vivo pendiente al cierre de la sesión original, **confirmada en la verificación posterior** (`ProcessTicketsHourly`) |
| Slots `stg2` (las 4 apps) | Diagnostic settings creados, sin verificar entrega |
| `smartfran-graylog-evhns-pro` | Namespace de Event Hub compartido — sin cambios de infraestructura, solo receptor de las 4 nuevas diagnostic settings |
| `sfcloud-monitoreo` (VM Graylog) | Pipeline de Logstash actualizado y reiniciado; re-verificado contra el repo en la sesión posterior, coincide exactamente salvo los 2 campos redactados por diseño |
| Graylog — Index Sets/Streams | 4 nuevos: `SFC-CodeGenerator-prod`, `SFC-ScheduledJobs-prod`, `SFC-PosWasmRelay-prod`, `SFC-TicketProcess-prod`. IDs hex no capturados en ningún repo — pull vía `GET /streams` antes de scriptear contra ellos |

## Comandos ejecutados

Ver `scripts.sh` para el detalle completo, agrupado por fase (Investigation / Audit / Remediation / Verification).

| # | Comando / Script | Propósito |
|---|---|---|
| C1 | terraform-plan-targeted | Plan acotado a los 5 recursos nuevos |
| C2 | az-function-execution-count | Descartar "app inactiva" antes de sospechar del pipeline |
| C3 | az-diagnostic-settings-check | Confirmar configuración correcta de cada diagnostic setting |
| C4 | graylog-search-by-app-category | Verificación de entrega end-to-end |
| C5 | reference-index-set-pull | Plantilla real para el shape de `data_tiering` |
| C6 | reference-stream-rules-pull | Plantilla real para la regla de stream |
| C7 | ruby-parser-standalone-test | Validación del parser antes de tocar el pipeline en vivo |
| C8 ⚠️ | terraform-apply-targeted | Aplica los 5 recursos de onboarding |
| C9 ⚠️ | graylog-create-index-set | Crea los 4 Index Sets dedicados |
| C10 ⚠️ | graylog-create-stream | Crea los 4 Streams dedicados |
| C11 ⚠️ | graylog-resume-stream | Activa el enrutamiento (los streams nacen pausados) |
| C12 ⚠️ | logstash-pull-live-config | Descarga la config real desplegada (no la del repo) |
| C13 ⚠️ | logstash-deploy-updated-config | Despliega con verificación de hash + `logstash -t` |
| C14 ⚠️ | logstash-restart-and-monitor | Restart + verificación activa de `NRestarts` |
| C15 | verify-live-config-pull | Verificación posterior: re-descarga la config en vivo, sin desplegar nada — comparar contra el repo |
| C16 | verify-config-diff-normalized | Diff repo vs. VM, normalizado a LF (el CRLF del `-t` de SSH hacía ver el archivo entero como distinto) |
| C17 | verify-fields-per-app | 1 query por app, `category:"FunctionAppLogs" AND name:"<APP>"`, 6h, confirma campos promovidos con datos reales |
| C18 | verify-functionname-exists-fleet | Conteo fleet-wide de `_exists_:FunctionName`, 24h |

## Acciones propuestas

1. **Completado** — Onboarding Terraform de las 4 Function Apps + slots `stg2` (`terraform apply` acotado: 5 added, 0 changed, 0 destroyed).
2. **Completado** — Verificación de entrega end-to-end para las 4 apps (tráfico real confirmado en Graylog) — `SFC-TicketProcess-PRO` cerrado en la verificación posterior, no en la sesión original.
3. **Completado** — Separación de las 4 apps del Default Stream a Streams/Index Sets dedicados, sin afectar al resto de las apps en Default.
4. **Completado** — Promoción de campos de `FunctionAppLogs` en el pipeline de Logstash, probada localmente contra 9 mensajes reales antes de desplegar, y reconfirmada en la verificación posterior contra mensajes reales de las 4 apps.
5. **Completado** — Sincronización del repo con el fix `GITIN-2034` ya presente en producción, evitando revertirlo al desplegar. Reconfirmado en la verificación posterior: repo y VM coinciden exactamente salvo las 2 connection strings redactadas por diseño.
6. **Completado** — Despliegue a producción con verificación de hash, `logstash -t` limpio y restart sin crash loop (`NRestarts=0`, reconfirmado varios minutos después).
7. **Completado** — Redacción inmediata de las 2 credenciales reales expuestas durante la verificación posterior (H8), antes de que llegaran a estar staged.
8. **Pendiente** — `terraform apply` sin acotar (`-target`) para destruir el diagnostic setting huérfano `ticketprocessasync_pro_sfc`.
9. **Pendiente** — Compartir (`Everyone`/`Viewer`) los 4 streams nuevos, igual que se hizo para el stream de DEV en GITIN-1794.
10. **Pendiente** — Decidir si el `SharedAccessKey`/`AccountKey` expuestos en H8 ameritan rotación.

## Hallazgos secundarios

- El campo top-level `message`/`full_message` de Graylog para `FunctionAppLogs` sigue siendo el genérico `"Microsoft.Web/sites/functions/log"` salvo que se haya promovido explícitamente vía el nuevo bloque — cualquier búsqueda guardada o alerta que asuma contenido útil en `message` para esta categoría debe revisarse.
- `SFC-PosWasmRelay-PRO` es por lejos la app de mayor volumen de las 4 (766.766 msgs/24h), muy por encima de lo esperado para un relay de logs de POS — no investigado si es tráfico real o verbosidad, similar al hallazgo de Catalog en GITIN-1834.
- La duración de ejecución (`Duration=Xms`) y el resultado (`Succeeded`/`Failed`) de las líneas `Function.<nombre>` quedan como texto libre dentro de `message`, no como campos estructurados — extracción posible vía regex, fuera de alcance.
- El nuevo campo `FunctionName` de `SFC-ScheduledJobs-PRO` habilita separar su tráfico HTTP real (`RegisterBusinessLog`) de sus 4 jobs internos por timer — intentado como parte de la estimación de costo de WAF en `cloud/events/20260915_gitin2042-waf-cost-estimate/` (H6 de esa ticket), pero solo funciona hacia adelante desde el despliegue de este mismo día — no retroactivo para ventanas de medición anteriores.
