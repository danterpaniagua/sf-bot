# 20260908_gitin2006-mongo-index-review

**Tags:** SmartPedidos, MongoDB

## Resumen

Se retomó la revisión de índices del cluster MongoDB Atlas `PedidosSmartfran` (base `smartfran`, `us-east-1`), pausada en agosto bajo GITIN-1744 a la espera de que el downsize a M20 (GITIN-1741) se estabilizara. Con más de cinco semanas de datos limpios de Atlas Performance Advisor cruzados contra tres relevamientos sucesivos (M30, M20 recién bajado, y el actual), se confirmaron patrones de consulta con volumen de escaneo alto y creciente en `branches` y `ordertimes`, no atribuibles a ruido de muestreo. Se aplicaron y verificaron los tres índices de mayor impacto; quedan dos adicionales de menor impacto pendientes y una consulta bajo revisión con Desarrollo por posible obsolescencia. La lista previa de 16 índices sin uso (~145 MB) de GITIN-1744 ya no se sostiene contra los datos actuales de Atlas.

## Tabla resumen

| Campo | Valor |
|---|---|
| Ticket Jira | [GITIN-2006](https://smartit-ar.atlassian.net/browse/GITIN-2006) (parent [GITIN-1857](https://smartit-ar.atlassian.net/browse/GITIN-1857)), continuación de [GITIN-1744](https://smartit-ar.atlassian.net/browse/GITIN-1744) |
| Sistema | MongoDB Atlas — cluster `PedidosSmartfran`, base `smartfran`, `us-east-1` |
| Alcance | Revisión de índices cluster-wide (33-34 colecciones) |
| Detectado | 2026-08-03 (GITIN-1744), retomado 2026-09-08 |
| Resuelto | Sí, 2026-09-08 — alcance cumplido (3 índices de mayor impacto aplicados y verificados); 2 índices de menor impacto, la consulta bajo revisión con Desarrollo, y el monitoreo de recursos bajo M20 quedan como seguimiento, no bloquean el cierre |
| Responsable | SRE |

## Causa raíz

No es un incidente puntual sino un hallazgo de optimización: los índices originales de `branches` y `ordertimes` no cubren patrones de consulta que crecieron en volumen y frecuencia desde que esos índices se crearon (nuevos flags de plataforma, métricas de latencia). Confirmado con datos reales de uso (Atlas Performance Advisor), no solo por tamaño/forma de índice.

## Hallazgos

| # | Hallazgo | Riesgo |
|---|---|---|
| H1 | `branches`: patrón de consulta por flag de plataforma (PediGrido + lastGetNews) creció ~90x en frecuencia en 5 semanas (0.21 → 5.25 → 19.04/hr), sin índice de cobertura hasta esta sesión | Medio |
| H2 | `branches`: segundo patrón por país + flag de plataforma (Peya) con crecimiento sostenido de frecuencia (~3x en 5 semanas) | Bajo/Medio |
| H3 | `ordertimes`: consulta de métricas de latencia con tiempo de ejecución empeorando (393 ms → 2778 ms), escaneando ~380K de ~372K documentos por ejecución | Medio |
| H4 | `ordertimesavgcrons`: consulta que escanea la colección completa en cada ejecución y nunca devuelve resultados, estable en los tres relevamientos — posible consulta obsoleta | Bajo — a confirmar con Desarrollo |
| H5 | La lista de 16 índices sin uso (~145 MB) de GITIN-1744 ya no se sostiene: Atlas reporta 0 recomendaciones de baja actualmente. No se distingue si es uso real recuperado o reinicio de la ventana de medición | Bajo — no accionable sin reconfirmar |
| H6 | `logerrors` quedó en cero documentos, consistente con la migración de logging a Graylog ya conocida — resuelve el pendiente de reponer `createdAt_1` en esa colección (ya no aplica, sin tráfico de consultas real) | Resuelto |
| H7 | No se relevó el impacto en uso de recursos del clúster (CPU, caché, lecturas a disco) durante la creación de los 3 índices aplicados, sobre `branches` y `ordertimes` (>370K documentos cada una), corriendo ya en el tier M20 del downsize de GITIN-1741 | Medio — pendiente de monitoreo |

## Recursos afectados

| Componente | Impacto |
|---|---|
| Concentrador | Gestiona `branches` (CRUD de sucursales) — nuevos índices aplicados en esa colección |
| Platform | Escribe los flags de cierre por plataforma y las métricas de tiempos de pedido — colecciones `branches`/`ordertimes` con cambios de índice |

## Comandos ejecutados

| # | Comando / Script | Propósito |
|---|---|---|
| C1 | `scripts.js` → `data/index-inventory-20260908.txt` | Inventario cluster-wide de tamaño de índices (`.stats()`, con fallback ante `$indexStats` denegado a nivel de cuenta) |
| C2 | Atlas Performance Advisor — panel "Drop Indexes" | Confirmar candidatos a eliminación de índices (resultado: 0 recomendaciones) |
| C3 | Atlas Performance Advisor — panel "Create Indexes" → `data/create-indexes-20260908.txt` | Relevar las 6 sugerencias de índices faltantes con métricas de uso real |
| C4 | `scripts.js` → `data/verify-new-indexes-20260908.txt` | Verificar vía `getIndexes()` que los 3 índices aplicados quedaron creados |

## Acciones propuestas

Ticket cerrado — el alcance principal (índices de mayor impacto identificados y aplicados) ya se cumplió. Los siguientes puntos quedan como seguimiento, no bloquean el cierre:

1. (SRE) Aplicar los 2 índices restantes de menor impacto sobre `branches` (`alreadyClosedRappi_1_lastGetNews_1`, `address.country_1_alreadyClosedUber_1`) como parte del mantenimiento en curso.
2. (Dev) Confirmar si la consulta detrás de `ordertimesavgcrons.avg_calculatedAt` es obsoleta antes de decidir entre indexarla o retirarla.
3. (SRE) Monitorear uso de recursos del clúster (CPU, caché, lecturas a disco) en las próximas semanas bajo M20 — mismas señales que GITIN-1741 — dado el cambio de estructura reciente y el crecimiento general del volumen de índices en `ordertimes`.
4. (SRE) No accionar la lista de 16 índices sin uso de GITIN-1744 sin volver a confirmarla contra datos actuales de Atlas.

## Hallazgos secundarios

- `ubercheckorders.token_1` — 8.47 MB, ~42% del tamaño de esa colección; no relevado en el alcance original de GITIN-1744, queda como candidato para una futura pasada, sin prioridad definida.
- El conteo total de colecciones bajó de 34 (agosto) a 33 (esta sesión) — no investigado, tangencial al alcance de índices.
