# Eventos — 20260908_gitin2013-query-insights-slow-queries

## 2026-09-08 12:30 — Apertura de investigación

He abierto la investigación para GITIN-2013 (parent GITIN-1857) sobre las consultas lentas reportadas por Atlas Query Insights en `PedidosSmartfran`. He intentado verificar el estado de profiling y operaciones en curso vía mongosh (`data/slow-queries-20260908.txt`) — las tres verificaciones (`getProfilingStatus()`, `system.profile`, `currentOp()`) devolvieron `Unauthorized`, consistente con las restricciones de cuenta ya conocidas desde GITIN-2006. He confirmado que Atlas Query Insights (UI) es la única fuente viable para este ticket.

## 2026-09-08 12:45 — Primeros hallazgos: conteo sin filtro sobre `news`

He recibido y registrado tres entradas de Query Insights sobre `smartfran.news`, todas con el mismo pipeline (`{$match:{}}, {$group:{_id:1,n:{$sum:1}}}`), equivalente a un `countDocuments()` sin filtro. He identificado un candidato de código real en `concentradorService/api/src/controllers/news.js:193-195`, un helper de paginación que puede degenerar a filtro vacío. He confirmado que no es un problema de indexación — un `$match` vacío obliga a recorrer toda la colección sin importar qué índice exista.

## 2026-09-08 13:00 — Hallazgo sobre `branches`: `$lookup` mal ordenado

He registrado una entrada de Query Insights sobre `smartfran.branches` con una advertencia directa de Atlas ("$lookup usage detected"). He identificado que el filtro real de búsqueda se aplica en un segundo `$match`, después de dos `$lookup`, haciendo que ambos joins corran sobre miles de documentos innecesarios.

## 2026-09-08 13:15 — Panel "Top namespace operations" y descubrimiento del trigger `clearCollection`

He registrado el panel de operaciones por namespace (`data/query-insights-top-namespaces-20260908.txt`), que mostró escrituras lentas en `orders` (promedio 8,88 s) y `ordertimes` (promedio 5,73 s). Una cuarta entrada de `news` (11,01 s, 432.123 documentos examinados) mostró un conteo muy por encima de las otras — contradiciendo el crecimiento sostenido que había asumido antes. Una quinta entrada, con `appName: app-services|triggers_stitchapp-ydkmc`, resolvió esa discrepancia: un trigger de Atlas App Services, no documentado antes en este repositorio, elimina periódicamente documentos viejos de `news`. He confirmado, vía la lista de Triggers, que se llama `clearCollection`, corre diariamente a las 13:08 UTC, y coincide exactamente con el horario observado.

## 2026-09-08 13:30 — Código fuente del trigger y explicación de las escrituras lentas

He recibido el código fuente completo de `clearCollection` (`data/clearCollection-trigger-source-20260908.txt`). He confirmado que ejecuta 7 `deleteMany()` secuenciales sin batching sobre `orders`, `news`, `ordersFaileds`, `logerrors`, `openclosedlogs`, `rejectpeyas` y `ordertimes`. Esto explica directamente las escrituras lentas del panel de namespaces — no son atribuibles a los índices agregados en GITIN-2006. También he detectado que `ordertimes` reutiliza la variable de fecha declarada para `openclosedlogs` en vez de tener la propia — mismo valor funcional, problema de mantenibilidad menor.

## 2026-09-08 13:40 — Cambio de horario del trigger

He registrado que el horario de `clearCollection` cambió de `08 13 * * *` a `08 10 * * *` (13:08 UTC → 10:08 UTC). He dejado esta acción registrada como hecho confirmado, sin asumir la motivación exacta hasta confirmarla.

## 2026-09-08 13:45 — Redacción del ticket

He redactado `ops.md` con el estado consolidado: tres hallazgos principales (conteo sin filtro en `news`, `$lookup` mal ordenado en `branches`, trigger `clearCollection` sin batching), un ajuste ya aplicado (horario del trigger), y las acciones propuestas para Desarrollo y SRE.
