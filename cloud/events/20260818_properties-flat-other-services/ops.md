# Unificar TraceKey / AppLevel / TenantId / Service / Environment en Graylog — GITIN-1883

**Tags:** `SmartCloud`, `Graylog`, `Azure`, `PROD`

## Resumen

Los mensajes `AppServiceConsoleLogs` de Business, Admin, Platform, Person, Catalog y Orders (App Services PROD/DEV, ingesta vía Event Hub) llevan un payload CLEF de Serilog completo dentro de `resultDescription` (string JSON), y dentro de ese payload, dentro de su propio objeto `Properties`, viajan `TraceKey`, `TenantId`, `Service` y `Environment` — ninguno promovido a campo de nivel superior, por lo que no eran buscables/filtrables en Graylog salvo abriendo el JSON crudo manualmente. Por separado, Sales (sink GELF directo, GITIN-1811/1835) sí tenía estos mismos campos accesibles, pero con nombre distinto (`Properties_TraceKey`, `Properties_Service`, etc., vía auto-flatten de GELF), generando una inconsistencia de naming entre servicios. El alcance final de este ticket cubre ambos problemas: promover los 4 campos para los 6 servicios vía Event Hub, y unificar el nombre (sin prefijo `Properties_`) también para Sales. `AppLevel` ya estaba resuelto de forma universal desde GITIN-1835 — incluido en el alcance solo como referencia/verificación, no requirió cambios. Ticket relacionado: GITIN-1811 (cerrado, causa raíz original del payload CLEF anidado) y GITIN-1835 (cerrado, formateo de mensajes CLEF directos de Sales — 2 de sus reglas de Graylog Pipeline Rules requirieron actualización como parte de este ticket, ver Causa raíz).

## Tabla resumen

| Campo | Valor |
|---|---|
| Ticket Jira | GITIN-1883 |
| ID alerta | N/A — pedido directo, no alerta |
| Sistema | Graylog SmartCloud (`sfcloud-monitoreo.smartfran.com`) — pipeline Logstash `azure-eventhub-to-graylog.conf` |
| Severidad | Baja — no hay pérdida de datos, campos ya existen dentro de `resultDescription`, solo no son planos/buscables |
| Detectado | 2026-08-18 |
| Resuelto | Sí — 2026-08-18. Desplegado y confirmado contra tráfico real: los 5 campos (`TraceKey`/`AppLevel`/`TenantId`/`Service`/`Environment`) planos y con nombre unificado en Business, Platform, Person y Sales; Admin/Catalog/Orders no verificados individualmente para `Service`/`Environment` (mismo código, no bloquea cierre) |
| Responsable | SRE |

## Causa raíz

El bloque Ruby de `azure-eventhub-to-graylog.conf` que parsea `resultDescription` (agregado en GITIN-1835 para extraer `AppLevel`) solo leía el campo `Level` del payload CLEF parseado — nunca leyó el resto de `Properties`. `TraceKey`, `TenantId`, `Service` y `Environment` quedaban por lo tanto atrapados dentro del string `resultDescription`, un nivel más de anidamiento que en Sales.

En Sales el mismo `Properties` vive en el nivel superior del propio mensaje GELF (sink directo de Serilog, GITIN-1811/1835), y Graylog lo aplana automáticamente a `Properties_TraceKey`/`Properties_Service`/etc. sin necesidad de ninguna regla — pero con un nombre distinto al de los otros 6 servicios, generando la inconsistencia de naming que este ticket también resuelve. La corrección: el mismo bloque Ruby ahora también lee ese `Properties` de nivel superior cuando existe (rama Sales) y, para evitar que Graylog siga generando los duplicados `Properties_*`, stringifica ese campo después de extraer lo necesario. Esto rompía 2 reglas de Graylog Pipeline Rules de GITIN-1835 que dependían literalmente de `Properties_Service`/`Properties_Environment` (la regla de `source` y la regla Stage 1 de ruteo a `PROD-Sales-AppServicePlan`) — actualizadas en el mismo cambio para leer los nuevos campos planos.

## Hallazgos

| # | Hallazgo | Riesgo |
|---|---|---|
| H1 | `TraceKey`, `TenantId`, `Service` y `Environment` confirmados presentes dentro de `resultDescription.Properties` en 6/6 apps muestreadas (Business, Admin, Platform, Person, Catalog, Orders) — ninguno promovido a campo de nivel superior. Causa raíz | Medio |
| H2 | Sales y Pos devuelven 0 mensajes `AppServiceConsoleLogs` en la ventana muestreada (7 días) — consistente con GITIN-1811 (categoría no soportada por Azure para apps .NET en Windows). Pos queda fuera de alcance de este ticket (aparentemente no emite esta categoría en absoluto); Sales sí está en alcance vía su path directo (ver H5) | Bajo |
| H3 | `TenantId` viene vacío (string vacío) en mensajes de sistema/background sin contexto de tenant activo (confirmado en Admin, Platform, Person) — variabilidad real de la aplicación, no un bug del pipeline. El fix deja el campo sin setear en ese caso en vez de promover un string vacío | Bajo |
| H4 | `AppLevel` ya está correctamente aplanado y coincide con el `Level` real del CLEF en los 6 mensajes muestreados — no requiere cambios, se incluye en la tabla de verificación solo como confirmación de que el mecanismo ya funciona correctamente | Bajo |
| H5 | Sales ya tenía `TraceKey`/`TenantId`/`Service`/`Environment` accesibles vía el auto-flatten de GELF, pero bajo el prefijo `Properties_` — inconsistencia de naming resuelta como parte de este ticket (a pedido explícito), no un hallazgo nuevo de causa raíz sino una decisión de alcance ampliado | Bajo |
| H6 | Actualizar los campos de Sales (quitar el prefijo `Properties_`) rompía 2 reglas de Graylog Pipeline Rules de GITIN-1835 que dependían literalmente de `Properties_Service`/`Properties_Environment` — identificado antes de desplegar, actualizado en el mismo cambio (ver Causa raíz) | Medio |

## Recursos afectados

| Recurso | Detalle |
|---|---|
| App Services PROD/DEV | `SmartFran-Cloud-{Business,Admin,Platform,Person,Catalog,Orders,Sales}-PRO` y equivalentes DEV — origen de los mensajes con los campos a aplanar/unificar |
| Logstash | VM `sfcloud-monitoreo`, `/etc/logstash/conf.d/azure-eventhub-to-graylog.conf` — pipeline modificado (3 despliegues incrementales: TraceKey/TenantId, luego Service+Environment, luego unificación de Sales) |
| Repo `cloud-graylog` | `docs/azure-eventhub-to-graylog.conf` — copia versionada, editada en esta sesión; diff contra la VM confirmado limpio salvo credenciales y redacción de comentarios (esperado) |
| Graylog Pipeline Rules | 3 reglas de GITIN-1835 actualizadas: `GITIN-1835: CLEF source from Properties.Service` (`6a7f29664814bcaed30c7de7`), `GITIN-1835: CLEF source fallback` (`6a7f24784814bcaed30c6d52`), `GITIN-1835: CLEF Azure resource fields for Sales PRO` (`6a7f2cb84814bcaed30c8de3`) |
| Graylog Streams | `PROD-{Business,Admin,Platform,Person,Catalog,Orders,Sales}-AppServicePlan` — destino de verificación post-deploy |

## Comandos ejecutados

| # | Comando/Script | Propósito |
|---|---|---|
| C1 | `scripts.sh` — 1 mensaje `AppServiceConsoleLogs` por app vía Views Search API, guardado en `console-logs-samples/` | Confirmar el path real de `TraceKey`/`AppLevel`/`TenantId`/`Service`/`Environment` antes de tocar el pipeline |
| — | Edición directa de `cloud-graylog/docs/azure-eventhub-to-graylog.conf` (3 rondas, sin script) | Agregar y extender el bloque Ruby GITIN-1883: `TraceKey`/`TenantId` → `+Service` → `+Environment` → unificación de Sales (rama `Properties` de nivel superior + stringificación) |
| — | `ruby -c` sobre el bloque extraído en cada ronda | Validar sintaxis Ruby aislada — sin `logstash` instalado localmente para validar el `.conf` completo |
| C2 ⚠️ | `scripts.sh` — `patch --dry-run` + `patch` en la VM (3 patches: `gitin-1883.patch`, `gitin-1883-service.patch`, `gitin-1883-environment.patch`, `gitin-1883-sales-unify.patch`), `logstash -t` en cada uno | Aplicar los cambios incrementalmente sin tocar las líneas de credenciales — resultado: `Configuration OK` en los 4 |
| C3 ⚠️ | `scripts.sh` — `sudo systemctl restart logstash` (4 reinicios, uno por despliegue) | Recargar el pipeline — resultado: `active (running)` en los 4 |
| C4 ⚠️ | 3× `curl -X PUT /api/system/pipelines/rule/{id}` — actualización de las reglas de Graylog Pipeline Rules de GITIN-1835 (`Properties_Service`→`Service`, `Properties_Environment`→`Environment`) | Evitar que el fix de unificación de Sales rompiera su formateo de `source`/ruteo a stream — resultado: `"errors": null` en las 3 |
| C5 | `scripts.sh` — `_exists_:TraceKey`/`_exists_:TenantId`/`_exists_:Service`/`_exists_:Environment` vía Views Search API, más lecturas puntuales de mensajes reales por app | Confirmar contra tráfico real — resultado: los 5 campos planos y unificados en Business, Platform, Person y Sales; sin regresión en `source`/`name`/ruteo de Sales |

## Acciones propuestas

1. ~~Confirmar que `cloud-graylog/docs/azure-eventhub-to-graylog.conf` coincide con el archivo real en la VM antes de tocarlo~~ — **HECHO 2026-08-18.** Diff contra la VM sin drift inesperado: solo difieren las líneas de credenciales (SAS de Event Hub / storage key, reales en la VM, correctamente reemplazadas por placeholders en el repo — por diseño) y la redacción de comentarios (solo se parchearon líneas de código funcional en la VM, nunca comentarios — esperado). Verificado dos veces, incluida una verificación final tras el tercer despliegue.
2. ~~Desplegar `TraceKey`/`TenantId` para los 6 servicios vía Event Hub~~ — **HECHO 2026-08-18.**
3. ~~Extender a `Service` y `Environment`~~ — **HECHO 2026-08-18**, a pedido explícito, mismo patrón guardado contra valores vacíos.
4. ~~Unificar el naming de Sales (quitar prefijo `Properties_`)~~ — **HECHO 2026-08-18**, a pedido explícito. Incluyó actualizar 3 reglas de Graylog Pipeline Rules de GITIN-1835 para evitar romper el formateo/ruteo de Sales — confirmado sin regresión contra tráfico real posterior al despliegue completo.
5. ~~Confirmar contra tráfico real~~ — **HECHO 2026-08-18.** Confirmado en Business, Platform, Person (Event Hub) y Sales (direct-GELF): los 5 campos (`TraceKey`/`AppLevel`/`TenantId`/`Service`/`Environment`) planos, sin prefijo, mismo nombre en todos. `source`/`name`/`streams` de Sales confirmados sin regresión tras la actualización de reglas.
6. **(SRE, seguimiento opcional)** Confirmar en una ventana más amplia que Admin/Catalog/Orders también generan `Service`/`Environment` de forma individual (ya confirmado para `TraceKey`/`TenantId` en el primer despliegue) — no bloquea el cierre, mismo bloque de código aplicándose a las 6 apps por igual.
7. **(Dev, opcional/fuera de alcance)** Si Pos también necesita `AppServiceConsoleLogs` operativo, evaluar el mismo workaround de sink GELF directo que se implementó para Sales en GITIN-1811/1835 — no confirmado como necesario, solo un paralelismo notado en H2.
8. **(SRE, fuera de alcance de este ticket)** GITIN-1835 (ítem abierto #3) sigue pendiente: la regla Stage 1 solo cubre `Service: "Sales"` + `Environment: "Production"` (antes `Properties_Service`/`Properties_Environment`, ya migrado en este ticket). Confirmado en vivo (30 min, muestra previa al deploy de unificación): 150 mensajes `Sales`/`Development` y 2 `SmartFran.Cloud.Sales.API`/vacío quedan sin `name` asignado. Todo Sales, nada de las 6 apps de este ticket — no se reabre GITIN-1835, solo se deja registrada la cuantificación real para cuando se retome ese ítem.
9. **(SRE)** Actualizar `cloud/docs/graylog-log-fields.md` para reflejar el estado final (naming unificado, ya no hay inconsistencia `Properties_` vs. plano) — la sección "Known naming inconsistency" de ese doc quedó desactualizada por este ticket.
