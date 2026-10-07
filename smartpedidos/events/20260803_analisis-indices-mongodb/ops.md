# 20260803_analisis-indices-mongodb

**Tags:** SmartPedidos, MongoDB

## Resumen

Relevamiento de inventario de índices y uso real en el cluster MongoDB Atlas `PedidosSmartfran` (base `smartfran`, `us-east-1`), como seguimiento a los hallazgos secundarios de `20260803_mongodb-downsize-m20` (GITIN-1741) sobre sobre-indexación en `branches` y `logerrors`. Con `$indexStats` denegado a nivel de cuenta, se usó Atlas Performance Advisor como fuente de datos de uso real. Se confirmó una regresión real (`logerrors.createdAt_1`, eliminado sin verificar dependencia de query) y se descartó parcialmente la hipótesis original: `branches` no está sobre-indexado, le faltan índices para patrones de consulta nuevos. **Este ticket no llegó a cerrarse de forma independiente** — quedó pausado a la espera de que el downsize a M20 se estabilizara, y fue retomado formalmente como [GITIN-2006](https://smartit-ar.atlassian.net/browse/GITIN-2006) el 2026-09-08, donde se cerró con datos y hallazgos actualizados (ver ese ticket para el resultado final).

## Tabla resumen

| Campo | Valor |
|---|---|
| Ticket Jira | [GITIN-1744](https://smartit-ar.atlassian.net/browse/GITIN-1744) |
| Sistema | MongoDB Atlas — cluster `PedidosSmartfran`, base `smartfran`, `us-east-1` |
| Alcance | Revisión de índices cluster-wide (34 colecciones) |
| Detectado | 2026-08-03, seguimiento de `20260803_mongodb-downsize-m20` ([GITIN-1741](https://smartit-ar.atlassian.net/browse/GITIN-1741)) |
| Resuelto | **No, de forma independiente.** Pausado el 2026-08-04 a la espera de ~1-2 semanas de estabilización post-downsize a M20. Retomado formalmente como [GITIN-2006](https://smartit-ar.atlassian.net/browse/GITIN-2006) el 2026-09-08, donde sí se cerró — ver ese ticket para el resultado final, no repetido acá. |
| Responsable | SRE |

## Causa raíz

`20260803_mongodb-downsize-m20` (GITIN-1741) había flagueado, como hallazgo secundario, que `branches` (~10x ratio índices/datos) y `logerrors` (~6.2x, antes de que sus índices secundarios se eliminaran mid-sesión en esa misma ticket) mostraban una relación índices/datos desproporcionada — sin confirmar con datos reales de uso (`$indexStats`) cuáles de esos índices eran realmente necesarios. Este ticket es ese seguimiento, ampliado a todo el cluster en vez de limitarse a esas dos colecciones.

## Hallazgos

| # | Hallazgo | Riesgo |
|---|---|---|
| H1 | `$indexStats` denegado a nivel de cuenta completo, en las 34 colecciones sin excepción — no es una restricción por colección. Inventario de tamaño (`.stats()`) sigue disponible; Atlas Performance Advisor (paneles Unused/Suggested Indexes) se usó como fuente alternativa de datos de uso real. | Bajo (mitigado) |
| H2 | 16 índices sin uso confirmado (ventana de 7 días) en 5 colecciones, ~145.2 MB total — pero las hipótesis de redundancia basadas solo en tamaño/forma acertaron solo parcialmente: varios índices que parecían redundantes por prefijo compartido resultaron estar en uso activo, y otros no flagueados por forma resultaron sin uso (`ordertimes.branch_1`, el mayor individual, 46.1 MB). No accionado — pendiente de reconfirmar contra datos post-M20. | Bajo (informativo, no accionado) |
| H3 | `logerrors.createdAt_1` — uno de los 4 índices secundarios eliminados mid-sesión en `GITIN-1741` sin verificar dependencia de query antes del drop — confirmado como regresión real: una consulta que dependía de ese índice ahora hace collection scan completo (352.943 documentos escaneados, ~13 segundos promedio de ejecución). Baja frecuencia (~1 vez/día) pero regresión genuina, no hipotética. | Medio |
| H4 | `branches` reencuadrado: cero índices flagueados como sin uso, incluyendo los dos compuestos grandes que motivaron el "10x" en `GITIN-1741` — Atlas confirma que están en uso activo. El problema real es cobertura faltante para patrones de consulta agregados después de crear esos índices (`alreadyClosedPediGrido`, compuestos liderados por `address.country`), con near-full-scans. | Bajo/Medio (informativo, reencuadra el hallazgo original) |
| H5 | Discrepancia de tamaño sin resolver en `ordertimes.branch_1`: 46.1 MB (Atlas Advisor) vs. 8.01 MB (`.stats()`/`indexSizes`) — ~5.7x de diferencia, posible base de medición distinta (agregado de réplica vs. nodo único). No usar ninguna de las dos cifras hasta reconciliar. | Bajo (sin resolver al momento de la pausa) |
| H6 | Salto de ~25x en la frecuencia de la sugerencia `branches.alreadyClosedPediGrido_1_lastGetNews_1` entre el pull M30 (0.21/hr) y el pull M20 a 1 día del downsize (5.25/hr) — sin explicar: podría ser cambio real de tráfico bajo M20, o diferencia en la ventana de tiempo filtrada entre ambos pulls. No usar la cifra de impacto de Atlas (103.7 MB/ejecución) como validada hasta reconciliar. | Bajo (sin resolver al momento de la pausa) |
| H7 | `logerrors` perdió aproximadamente la mitad de sus documentos (352.943 → 178.486) el mismo día, entre la sesión de `GITIN-1741` y esta — no investigado, tangencial al alcance de este ticket de auditoría de índices. | Bajo (no investigado, fuera de alcance) |

## Recursos afectados

| Componente | Impacto |
|---|---|
| Concentrador | Gestiona `branches` (CRUD de sucursales) — colección con hallazgos de cobertura faltante (H4) |
| Platforms | Escribe flags de cierre por plataforma y métricas de tiempos de pedido — colecciones `branches`/`ordertimes`/`orders`/`news` bajo análisis |

## Comandos ejecutados

| # | Comando / Script | Propósito |
|---|---|---|
| — | Inventario cluster-wide (`.stats()` + `$indexStats` con fallback a solo-tamaño ante denegación) — ver "Data-gathering query" en `investigation.md` | Confirmar tamaño de índices en las 34 colecciones e identificar el alcance real de la denegación de `$indexStats` (H1) |
| — | Atlas Performance Advisor — panel "Unused Indexes" (pull M30, 2026-08-03) | Relevar los 16 índices sin uso confirmado (H2) |
| — | Atlas Performance Advisor — panel "Suggested Indexes" (pull M30, 2026-08-03) | Relevar 5 sugerencias, incluyendo la que confirma la regresión de `logerrors.createdAt_1` (H3) |
| — | Atlas Performance Advisor — panel "Suggested Indexes" (re-pull M20, 2026-08-04, confirmado por el usuario como reflejando ya el tier M20) | Diff contra el pull M30 — 8 sugerencias vs. 5, detecta el salto de frecuencia en `branches` (H6) |

Detalle completo, incluyendo la query de inventario cluster-wide, en `20260803_analisis-indices-mongodb_investigation.md`.

## Acciones propuestas

**Estado al momento de la pausa (2026-08-04) — no reflejan el resultado final, ver GITIN-2006:**

1. **(SRE, pendiente al pausar)** Reponer `logerrors.createdAt_1` — regresión confirmada (H3), recomendado independientemente del resultado del downsize. No accionado en este ticket; requiere confirmación del usuario antes de ejecutar el write sobre el cluster de producción.
2. **(SRE, pendiente al pausar)** Re-relevar Atlas Performance Advisor tras 1-2 semanas de estabilización en M20 antes de dar por definitiva la lista de 16 índices sin uso o las 5 sugerencias del pull M30.
3. **(SRE, pendiente al pausar)** Resolver la discrepancia de tamaño de `ordertimes.branch_1` (H5) antes de finalizar cualquier lista de baja de índices.
4. **(SRE, pendiente al pausar)** Confirmar si la ventana de "sin uso" de 7 días de Atlas se reinicia con el patrón de reinicio periódico de nodo ya observado en `GITIN-1741`, antes de tratar la lista de 16 índices como definitiva.
5. **(SRE, pendiente al pausar)** Reconciliar el salto de ~25x en frecuencia de `branches.alreadyClosedPediGrido_1_lastGetNews_1` (H6) antes de citar la cifra de impacto de Atlas como validada.

**Seguimiento real:** todos los puntos anteriores fueron retomados y resueltos (o superados por datos más recientes) en [GITIN-2006](https://smartit-ar.atlassian.net/browse/GITIN-2006) — no duplicar trabajo, consultar ese ticket antes de accionar cualquiera de estos ítems.

## Hallazgos secundarios

- Este ticket quedó pausado sin cerrarse — la continuación formal bajo `GITIN-2006` invalidó parte de lo relevado acá (la lista de 16 índices sin uso ya no se sostiene contra datos frescos de Atlas; el punto de reponer `logerrors.createdAt_1` quedó sin efecto porque esa colección terminó en cero documentos tras la migración de logging a Graylog). Este `ops.md` documenta el estado y los hallazgos de este ticket en su momento, no el resultado final — ese vive en `smartpedidos/events/20260908_gitin2006-mongo-index-review/ops.md`.
