# Onboarding completo de PROD a Graylog — GITIN-1834

**Tags:** `SmartCloud`, `Graylog`, `Terraform`, `Azure`, `PROD`

## Resumen

6 de los 8 App Services de PROD (Pos, Platform, Person, Admin, Catalog y Orders) no estaban integrados al pipeline de ingesta de logs a Graylog — Orders no tenía ningún Diagnostic Setting configurado — dejando a esas apps sin visibilidad centralizada de logs para diagnóstico en producción. Se completó el onboarding de las 6 apps siguiendo el mismo patrón ya usado para Sales y Business (Diagnostic Settings → Event Hub compartido → Logstash → Graylog). El apply de Terraform provocó una regresión que sobrescribió el Diagnostic Setting de Log Analytics preexistente en 4 de las 6 apps (Pos, Platform, Admin, Catalog); la regresión fue identificada y corregida el mismo día, con verificación independiente posterior. Se crearon además 6 streams dedicados en Graylog para las 6 apps, verificados contra tráfico real antes de activar el enrutamiento exclusivo. Quedan puntos de verificación adicional abiertos (ver Acciones propuestas) antes del cierre definitivo del ticket.

## Tabla resumen

| Campo | Valor |
|---|---|
| Ticket Jira | GITIN-1834 |
| ID alerta | N/A — tarea planificada, no alerta |
| Sistema | SmartFran Cloud — pipeline de logs a Graylog (Diagnostic Settings, Event Hub, Terraform en repo `cloud-graylog`) |
| Severidad | Media (regresión temporal del destino Log Analytics en 4 apps productivas, corregida el mismo día) |
| Detectado | 2026-08-12 |
| Resuelto | Parcial — onboarding y regresión resueltos; puntos de verificación adicional pendientes (ver Acciones propuestas) |
| Responsable | SRE |

## Causa raíz

Los Diagnostic Settings de Azure son un PUT de reemplazo total indexado por el campo `name`, no aditivo. El Terraform nuevo reutilizó la misma convención de nombre (`SmartFran.Cloud.PRO.{App}_DiagnosticSettings`) que ya usaban los Diagnostic Settings preexistentes de Log Analytics (creados fuera de Terraform) en Pos, Platform, Admin y Catalog, por lo que el apply los reemplazó por un objeto que solo apuntaba al Event Hub, perdiendo el destino de Log Analytics. Person sobrevivió únicamente porque su `name` original tenía un espacio inicial, generando un string técnicamente distinto que evitó la colisión.

## Hallazgos

| # | Hallazgo | Riesgo |
|---|---|---|
| H1 | El apply de Terraform sobrescribió el Diagnostic Setting de Log Analytics preexistente en Pos, Platform, Admin y Catalog, dejando activo solo el destino Event Hub. | Alto |
| H2 | La referencia de `workspaceId` en el setting sobreviviente de Person apuntaba a una subscripción inexistente (`d6ab1add...`), no validada por Azure hasta el momento de escritura del recurso. | Medio |
| H3 | El volumen de Graylog a nivel flota subió de ~15k a ~200k mensajes tras el onboarding; el 86,7% del total corresponde a Catalog, con una relación `AppServiceConsoleLogs`:`AppServiceHTTPLogs` de 160:1 — indica verbosidad de logging de consola desacoplada del tráfico HTTP real, no un problema del pipeline de ingesta. | Medio |
| H4 | El mensaje real de Orders capturado muestra `event_original` con ~19 registros apilados en vez de uno solo, contradiciendo el fix documentado en CG-005; el tamaño resultante (22.910 bytes) quedó bajo el límite de Lucene (32.766 bytes) en este caso puntual, pero un batch mayor en una app de mayor volumen (ej. Catalog) podría reproducir el modo de fallo original de Business. | Medio |
| H5 | El endpoint `/api/system/indexer/failures` devolvió únicamente entradas históricas del 31/07 en ambas consultas realizadas, confirmando que no refleja el estado en tiempo real — no permite confirmar ni descartar fallos de indexación actuales en Catalog u otras apps. | Bajo |
| H6 | Durante la verificación de permisos, un POST con body vacío al endpoint de sharing de entidades reemplazó momentáneamente los grants ya aplicados al stream de Catalog; fue detectado y corregido en el momento, sin impacto en los otros 5 streams. | Bajo |

## Recursos afectados

| Recurso | Detalle |
|---|---|
| App Services PROD | `SmartFran-Cloud-{Pos,Platform,Person,Admin,Catalog,Orders}-PRO` (RG `SmartFran.Cloud.PRO`, subscription `SmartIT Cloud` `85c76dea-3304-4310-8656-bf21b28e4f4b`) |
| Event Hub | `smartfran-graylog-evhns-pro` (namespace compartido) |
| Log Analytics Workspace | `SmartFranCloudPro` (customerId `76536d4a-5616-44ae-bee4-0aa6963b5d28`) |
| Graylog | Instancia dedicada SmartCloud (`sfcloud-monitoreo.smartfran.com/graylog`) — 6 Index Sets y 6 Streams nuevos (`SFC-{App}-prod` / `PROD-{App}-AppServicePlan`) |
| Terraform | `cloud-graylog/terraform/app_services.tf`, `main.tf` (repo separado, no forma parte de este monorepo) |

## Comandos ejecutados

| # | Comando/Script | Propósito |
|---|---|---|
| C1 | `scripts.sh` — plan Terraform (6 recursos) | Validar el alta de los 6 Diagnostic Settings antes de aplicar |
| C2 | `scripts.sh` — ⚠️ apply Terraform inicial | Crear los 6 Diagnostic Settings nuevos apuntando al Event Hub |
| C3-C4 | `scripts.sh` — métricas `IncomingMessages`/`ThrottledRequests` | Descartar throttling de capacidad como causa de una ventana de métrica en 0.0 |
| C5 | `scripts.sh` — `diagnostic-settings list` por app | Confirmar la pérdida del destino Log Analytics en 4 apps |
| C6-C7 | `scripts.sh` — verificación de subscripción/workspace | Identificar el `workspaceId` real tras una referencia inválida en el objeto sobreviviente de Person |
| C8 | `scripts.sh` — ⚠️ re-apply Terraform (4 recursos) | Restaurar Log Analytics + Event Hub en Pos/Platform/Admin/Catalog |
| C9 | `scripts.sh` — `diagnostic-settings list` post-fix | Verificar de forma independiente ambos destinos activos |
| C10-C11 | `scripts.sh` — Views Search API (conteo por app y por categoría) | Confirmar entrega real de datos y aislar el origen del pico de volumen (Catalog) |
| C12 | `scripts.sh` — `/system/indexer/failures` | Buscar fallos de indexación recientes (resultado inconcluso) |
| S1 | `create_streams.sh` — ⚠️ creación de 6 Index Sets + Streams + reglas | Crear el pipeline de streams dedicados por app en Graylog PROD |

## Acciones propuestas

1. Confirmar que los Diagnostic Settings de Sales y Business no están expuestos al mismo riesgo de colisión de `name` identificado en H1 — verificar a nivel JSON que son objetos genuinamente distintos, no otro near-miss sin detectar.
2. Confirmar el estado de integración VNet para las 6 apps nuevas (`az webapp vnet-integration list` por app) — solo Business está confirmada como integrada a VNet hasta el momento.
3. Verificar a nivel de VM (SSH, fuera del alcance de la API pública de Graylog) si existen fallos de indexación activos por `event_original`/`max_bytes_length_exceeded` en índices `catalog__*` u otras apps de alto volumen, dado que H5 dejó esto sin resolver de forma concluyente.
4. Re-verificar si la métrica `IncomingMessages` del Event Hub realmente quedó en 0.0 durante la ventana observada tras el primer apply, o si se trató de un retraso de reporte de Azure Monitor con backfill posterior.
5. Actualizar `cloud-graylog/CLAUDE.md` (tabla de onboarding por app en "App Services — Production" y sección "Log Analytics Workspace & Diagnostic Settings") para reflejar las 8 apps ya onboardeadas.
6. Coordinar con el equipo dueño de Catalog una revisión del nivel de logging de consola en producción (H3) — fuera del alcance de este ticket, pero actualmente es la mayor fuente de volumen de ingesta de la flota.
7. Confirmar y, de corresponder, commitear el estado pendiente en el repo `cloud-graylog` (incluye el Terraform de este ticket) — el repo tiene estado no confirmado preexistente, no originado por este ticket.

## Hallazgos secundarios

Al verificar las reglas reales de `PROD-Sales-AppServicePlan` y `PROD-Business-AppServicePlan` se confirmó que ambos ya usan el patrón seguro de match exacto (campo `name`, sin `contains`/regex, sin invertir), que se tomó como base para las 6 reglas nuevas de este ticket. Una nota de investigación previa vinculaba este patrón a un ticket `CG-006`/`operations/events/20260703_index-separation`, pero esa carpeta no existe en el repositorio — la referencia no pudo verificarse y se retira de este ticket. El patrón en sí sigue confirmado de forma independiente, contra la configuración real vía API.
