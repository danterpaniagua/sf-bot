# Eventos — 20260908_gitin2006-mongo-index-review

## 2026-09-08 09:00 — Apertura de investigación, confirmación de continuidad con GITIN-1744

He abierto la investigación para GITIN-2006, retomando el análisis de índices del cluster `PedidosSmartfran` que había quedado pausado en GITIN-1744 a la espera de que el downsize a M20 (GITIN-1741) se estabilizara. Se confirmó la vinculación entre ambos tickets: no son trabajos separados.

## 2026-09-08 09:30 — Inventario cluster-wide de tamaño de índices

He corrido el script de inventario contra las 33 colecciones del cluster (`data/index-inventory-20260908.txt`). He confirmado que `$indexStats` sigue denegado a nivel de cuenta, sin cambios desde agosto. He detectado que `logerrors` quedó en cero documentos, consistente con la migración de logging a Graylog ya conocida — esto resuelve el pendiente de reponer el índice `createdAt_1` en esa colección, porque ya no queda tráfico de consultas real que proteger. También he resuelto la discrepancia de tamaño pendiente sobre `ordertimes.branch_1`: el valor fresco de `.stats()` (46.10 MB) coincide con el de Atlas Advisor de agosto, confirmando que la lectura anterior de 8.01 MB era la incorrecta.

## 2026-09-08 10:00 — Relevamiento de Atlas Performance Advisor (Drop + Create Indexes)

He relevado los dos paneles de Atlas Performance Advisor. El panel de eliminación de índices no arrojó ninguna recomendación, lo cual contradice la lista de 16 índices sin uso armada en GITIN-1744 hace más de un mes — no he accionado esa lista sin volver a confirmarla. El panel de creación de índices arrojó 6 sugerencias; he cruzado las tres capturas sucesivas (M30, M20 recién bajado, y esta) y he confirmado que tres de los seis patrones muestran crecimiento sostenido y real a lo largo de cinco semanas, no ruido de muestreo puntual.

## 2026-09-08 10:30 — Aplicación y verificación de los tres índices de mayor impacto

Se aplicaron los tres índices de mayor impacto identificados: dos sobre `branches` y uno sobre `ordertimes`. He verificado su creación vía `getIndexes()` (`data/verify-new-indexes-20260908.txt`) y he confirmado que los tres quedaron creados correctamente.

## 2026-09-08 11:00 — Corrección: afirmación de "sin impacto" no verificada

La afirmación "sin impacto sobre el flujo de pedidos" no estaba respaldada por datos reales: solo se había confirmado que los índices quedaron creados, no que el build no generó presión adicional sobre un clúster corriendo ya en el tier M20 reducido. He corregido los emails a PM y a Operaciones para reemplazar esa afirmación por una recomendación de monitoreo, y he dejado la corrección registrada en la investigación.

## 2026-09-08 11:15 — Redacción de comunicaciones y ticket

He redactado el email de estado a Operaciones (`email_ops.md`) y el reporte corto a PM (`email_pm_status.md`, vía `/status-report`), ambos referenciando GITIN-1744 y GITIN-2006 como tickets vinculados. He redactado el ticket principal (`ops.md`) con el estado consolidado: 3 índices aplicados, 2 pendientes, 1 consulta en revisión con Desarrollo, y la lista de índices sin uso de GITIN-1744 marcada como no accionable sin reconfirmar.

## 2026-09-08 12:05 — Cierre del ticket

He cerrado el ticket: el alcance principal (identificar y aplicar los índices de mayor impacto) ya está cumplido. He dejado los 2 índices restantes de menor impacto, la consulta de `ordertimesavgcrons` en revisión con Desarrollo, y el monitoreo de recursos del clúster bajo M20 como seguimiento, sin que bloqueen este cierre.
