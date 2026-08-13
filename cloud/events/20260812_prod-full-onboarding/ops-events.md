# Bitácora — Onboarding completo de PROD a Graylog (GITIN-1834)

## 2026-08-12 — Alcance confirmado y Terraform extendido para los 6 apps restantes

He confirmado con el usuario el alcance: los 6 App Services de PROD que faltaban (Pos, Platform, Person, Admin, Catalog, Orders), incluyendo Orders pese a no tener ningún Diagnostic Setting previo. He extendido `terraform/app_services.tf` en el repo `cloud-graylog` con el mismo patrón ya usado para Sales y Business (`data` source + `azurerm_monitor_diagnostic_setting` apuntando al Event Hub compartido). `terraform fmt`, `validate` y `plan` (acotado con `-target` a los 6 recursos nuevos) confirmaron "6 to add, 0 to change, 0 to destroy".

## 2026-08-12 — Apply inicial aplicado

He entregado el comando `terraform apply` con el banner de comando destructivo. Confirmé el resultado: "Apply complete! Resources: 6 added, 0 changed, 0 destroyed." Los 6 Diagnostic Settings quedaron creados.

## 2026-08-12 — Verificación de entrega real de datos

Pedí la métrica `IncomingMessages` del Event Hub y encontré una ventana de `0.0` sostenida (~20 min) poco después del apply. Descarté la hipótesis de throttling por capacidad de 1 TU verificando `ThrottledRequests` (plano en `0.0` durante toda la ventana). Confirmé entrega real end-to-end para Orders con un mensaje real de Graylog (`resourceId` → `SMARTFRAN-CLOUD-ORDERS-PRO`, parseado correctamente).

## 2026-08-12 — Encontré una regresión: Log Analytics sobrescrito en 4 apps

Al verificar `az monitor diagnostic-settings list` para los 6 apps nuevos, encontré que Pos, Platform, Admin y Catalog perdieron por completo su Diagnostic Setting de Log Analytics preexistente. Identifiqué la causa: los Diagnostic Settings de Azure son un PUT de reemplazo total indexado por `name`, no aditivo — nuestro Terraform reutilizó el mismo nombre que ya usaba el setting de Log Analytics preexistente (creado fuera de Terraform), así que el apply lo sobrescribió con un objeto que solo tenía Event Hub. Person fue el único de los 5 apps que sobrevivió, y solo por accidente: su setting original tiene un espacio inicial en el `name`, lo que lo volvió un string técnicamente distinto y evitó la colisión.

## 2026-08-12 — Restauré Log Analytics para los 4 apps afectados

Consolidé ambos destinos (Event Hub + Log Analytics) en los mismos recursos de Terraform ya gestionados, en vez de crear un objeto temporal separado, para evitar una ventana de doble ingesta al mismo workspace de Log Analytics. Agregué `log_analytics_workspace_id` y las 5 categorías de log faltantes (usando el objeto sobreviviente de Person como referencia — las 9 categorías estaban habilitadas originalmente). El primer intento de apply falló: la referencia de `workspaceId` que tenía el setting sobreviviente de Person apuntaba a una subscripción (`d6ab1add...`) que no existe (`SubscriptionNotFound`, no un problema de permisos). Confirmé el workspace real vía `az monitor log-analytics workspace show` contra la subscripción `85c76dea...` (coincide con el `customerId` ya documentado en `cloud-graylog/CLAUDE.md`). Corregí la referencia y reapliqué: "Apply complete! Resources: 0 added, 4 changed, 0 destroyed." Verifiqué de forma independiente vía `diagnostic-settings list` que los 4 apps ahora tienen ambos destinos activos. Esta regresión quedó cerrada.

## 2026-08-12 — Confirmé entrega real para los 6 apps y encontré el origen de un pico de volumen

Repetí la consulta de conteo por app contra la API de Graylog (Views Search, pivot sobre el campo `name`) y confirmé que los 6 apps ya están entregando datos reales, incluidos los 5 que antes mostraban cero mensajes. Identifiqué que el salto de volumen reportado por el usuario (~15k a ~200k mensajes) viene de Catalog: 62.809 de 72.485 mensajes en una ventana de 15 minutos (86,7% del total). Desglosé por categoría y confirmé que es verbosidad de logging, no tráfico real: `AppServiceConsoleLogs` 44.904 vs `AppServiceHTTPLogs` 280 (relación 160:1) — el volumen de líneas de log está desacoplado del volumen real de requests HTTP. Queda registrado como hallazgo para el equipo dueño de Catalog, fuera del alcance de este ticket.

## 2026-08-12 — Chequeo de indexer failures, inconcluso

Revisé `/api/system/indexer/failures` buscando fallos recientes relacionados al hallazgo de `event_original` con el batch completo en vez del registro único (contradice el fix documentado en CG-005). El endpoint devolvió únicamente entradas históricas del 31/07 (mismo incidente de Business ya documentado), confirmando la advertencia ya conocida de que este endpoint no refleja el estado en tiempo real. Como evidencia indirecta, los 62.809 mensajes de Catalog contados en el chequeo anterior están indexados exitosamente (un documento rechazado no aparecería en ese conteo), lo que sugiere que el problema, si sigue vivo, no está fallando la mayoría del tráfico.

## 2026-08-12 — Encontré un ticket relacionado bloqueado con riesgo real (CG-006)

Antes de crear los 6 streams individuales de PROD, revisé la documentación existente y encontré `operations/events/20260703_index-separation` (CG-006, tarea padre CG-001) — sigue en estado **Bloqueado** desde el 03/07. El stream `PROD-Business-AppServicePlan` ya tiene `remove_matches_from_default_stream: true` habilitado con una regla que, a esa fecha, no estaba matcheando nada. El ticket documenta explícitamente el riesgo de repetir el incidente H6 (`20260630_graylog-vm-terraform`): un stream con esa bandera activa y una regla mal acotada terminó vaciando el Default Stream por completo. No toqué ningún stream existente todavía — voy a verificar el estado actual antes de crear nada nuevo, dado este precedente.

## 2026-08-12 — Confirmé que Sales y Business ya usan el patrón seguro

Consulté las reglas reales de `PROD-Sales-AppServicePlan` y `PROD-Business-AppServicePlan` vía la API. Ambos ya usan el mismo patrón preciso: campo `name`, match exacto (no `contains` ni regex), sin invertir. Esto confirma que CG-006 avanzó informalmente después de quedar "Bloqueado" en la documentación, sin que esta quedara actualizada. Tomé este patrón exacto como base para los 6 streams nuevos.

## 2026-08-12 — Creé los 6 Index Sets, Streams y reglas para PROD

Escribí `create_streams.sh` para crear, por cada app (Pos, Platform, Person, Admin, Catalog, Orders): un Index Set dedicado (`SFC-{App}-prod`, 1 shard/0 réplicas, mismo criterio que el Index Set de DEV dado que el cluster es single-node), un Stream (`PROD-{App}-AppServicePlan`) y una regla de match exacto sobre `name`. Dejé `remove_matches_from_default_stream` en `false` deliberadamente en la creación, para no repetir el riesgo de H6 con una regla recién creada y sin verificar. Encontré y corregí en el camino dos particularidades de la API de este Graylog no documentadas antes en el proyecto: el endpoint de Index Sets rechaza `can_be_default` y exige `data_tiering` no nulo; el endpoint de Streams requiere el payload envuelto en `{"entity": {...}}`, un mecanismo de sharing más nuevo. Tras corregir ambos, los 6 recursos se crearon limpios en una sola pasada.

## 2026-08-12 — Verifiqué las 6 reglas contra tráfico real antes de activar la bandera de riesgo

Con una búsqueda acotada a cada Stream nuevo (ventana de 5 minutos), confirmé que cada uno matchea única y exclusivamente su app correspondiente, sin superposición entre ellos. Recién después de esta verificación activé `remove_matches_from_default_stream: true` en los 6 (HTTP 200 en todos). Confirmé que el cambio funcionó correctamente: una ventana de 60 segundos posterior al cambio mostró cero mensajes de las 6 apps en el Default Stream (el resultado inicial de 5 minutos que sí las mostraba era tráfico residual previo al cambio, no un fallo).

## 2026-08-12 — Otorgué visibilidad "Everyone: Viewer" a los 6 streams nuevos

Encontré la forma correcta de otorgar el permiso vía el endpoint de entity sharing (`POST /api/authz/shares/entities/{grn}`, ya que `GET` no está permitido en esta ruta — el mismo endpoint sirve para leer y escribir). Usé como referencia el sharing de `PROD-Sales-AppServicePlan` para identificar los IDs correctos (`grn::::builtin-team:everyone` para "Everyone", `view` para "Viewer"). Apliqué el grant a los 6 streams nuevos, todos con HTTP 200.

Durante la verificación cometí un error que corregí en el momento: asumí que llamar al mismo endpoint con un body vacío (`{}`) era una lectura inofensiva del estado actual — en realidad el endpoint reemplaza el conjunto de grants con lo que venga en el body, así que ese "chequeo" borró el grant recién aplicado a Catalog. Lo detecté al re-verificar, lo restauré de inmediato, y confirmé con una pasada final (usando siempre el payload completo, nunca vacío) que los 6 streams tienen exactamente 1 share activo cada uno (Everyone: Viewer). Ningún otro stream se vio afectado por este error, solo Catalog, y quedó restaurado.
