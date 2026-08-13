# Eventos — 20260803_mongodb-downsize-m20

## 2026-08-03 09:30 — Apertura de investigación

He abierto la investigación para evaluar la factibilidad de bajar el tier del cluster `PedidosSmartfran` (MongoDB Atlas, `us-east-1`) de M30 a M20. Confirmé la identidad del cluster y las colecciones principales a partir de `smartpedidos/docs/infrastructure.md`; el tier actual no estaba documentado ahí, así que lo tomé como primer bloqueante a resolver.

## 2026-08-03 09:45 — Relevamiento inicial y limitación de credenciales

Relevé estadísticas de las colecciones principales (`logerrors`, `branches`, `orders`, `ordertimes`, `openclosedlogs`, entre otras) vía `mongosh`. Confirmé que las credenciales en uso no tienen permisos de admin — `db.serverStatus()` y `rs.status()` devolvieron `Unauthorized on admin` — por lo que las métricas de conexiones y replicación debieron obtenerse desde la UI de Atlas en lugar de mongosh.

Detecté sobre-indexación en dos colecciones: `logerrors` (índices ~6.2x el tamaño de los datos) y `branches` (~10x, con dos índices multikey compuestos sobre el array `platforms` concentrando casi todo el peso). `branches` además mostró un patrón de escritura muy intenso para su tamaño (~47.5M `modify calls` acumulados sobre solo 2.346 documentos).

## 2026-08-03 10:00 — Confirmación de tier y hallazgo del precedente de enero

Confirmé en la UI de Atlas que el tier actual es **M30** (2 vCPU / 8 GB RAM), replica set de 3 nodos, no shardeado — con lo cual el downsize a M20 es una reducción real de RAM, no un cambio de topología.

El usuario aportó un email interno enviado en enero de 2026: **el 19/1 se bajó de M30 a M20 en producción y se revirtió el 21/1**, tras observar CPU picos de hasta 35% (vs. 15-25% normal en M30) y RAM limitada a ~1.300-1.500 MB en M20 (vs. 2.000-3.500 MB en M30). La recomendación formal de ese momento fue mantener M30, citando además el crecimiento proyectado de `ordertimes` (27.6% del total de índices en ese momento) como riesgo adicional.

Métricas de RAM de las últimas 4 semanas (Atlas UI, hasta 2026-08-03) mostraron picos de 3.776-3.830 MB en 2 de 3 réplicas — muy cerca del techo total de M20 (4.096 MB) — y consistentes con el rango observado en M30 tras la reversión de enero.

## 2026-08-03 10:20 — Eliminación de índices de `logerrors` y verificación del timeline

El usuario eliminó los índices secundarios de `logerrors` en vivo durante la sesión (quedó solo `_id_`), liberando ~906 MB de tamaño de índice en disco. Inicialmente se atribuyó el cese de escritura a `logerrors` a enero de 2026, pero verificando el historial de git de los clones locales (`concentrador-service`, `platforms-service`) confirmé que el mecanismo que permite deshabilitar la escritura a Mongo (`mongoLogEnabled`) se desplegó recién el **2026-07-20**, hace dos semanas — no en enero. Antes de ese commit, `Log.save()` escribía a `logerrors` sin condición.

Esto es relevante: el ciclo más reciente del gráfico de RAM (íntegramente posterior al 07/20) volvió a subir a 3.473 MB en la Réplica 2, cerca del pico histórico — evidencia de que `logerrors` no era el principal responsable de la presión de memoria.

## 2026-08-03 10:35 — Corrección de enfoque: RAM vs. presión de caché real

El usuario señaló correctamente que el uso de RAM de WiredTiger tiende naturalmente a ocupar toda la caché disponible — eso no es en sí mismo señal de problema. Corregí el análisis: la señal real de estrés no es el % de RAM usada sino la presión de eviction (lecturas a disco, CPU elevado). Releyendo la evidencia de enero bajo este criterio, el hallazgo relevante pasa a ser el aumento de CPU (15-25% → 35%), no el techo de RAM per se.

## 2026-08-03 10:46 — Métricas de Cache Usage y Disk IOPS: la evidencia actual no reproduce el problema de enero

Con las métricas correctas (paneles "Cache Usage" y "Disk IOPS" de Atlas), encontré que el uso real de caché WiredTiger topea en ~1.2-1.5 GB por réplica (`DIRTY` insignificante, 19-24 MB) y que los Read IOPS son casi nulos (~0.3-0.42/s) — es decir, casi no hay lecturas a disco, señal de que la caché actual alcanza cómodamente para el working set activo. Esto contrasta con el techo real observado en M20 durante la prueba de enero (~1.300-1.500 MB antes de saturar).

Sumado a que las condiciones cambiaron desde enero (índices de `ordertimes` reducidos ~76%, escritura a `logerrors` detenida hace 2 semanas), la recomendación pasó de "no-go" a favorable para reintentar M20, condicionado a monitoreo activo dado que ya hubo una reversión real en el pasado.

## 2026-08-03 10:50 — Decisión: proceder con downsize a M20 con monitoreo

Definimos avanzar con el downsize a M20, con monitoreo activo de CPU, Cache Usage/eviction y Disk Read IOPS, y criterios de rollback explícitos basados en los mismos síntomas que motivaron la reversión de enero (CPU sostenido >30-35%, aparición de Read IOPS sostenidos por encima del baseline actual, o degradación de latencia percibida en `platforms-service`/`concentrador-service`). Investigación marcada como converged. Email a Operaciones redactado en paralelo (`20260803_mongodb-downsize-m20_email-ops.md`).
