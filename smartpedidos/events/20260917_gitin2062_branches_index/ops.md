# GITIN-2062 — Índice en smartfran.branches

## Resumen

Un relevamiento de Atlas Performance Advisor sobre el cluster `PedidosSmartfran` (2026-09-16, continuación de [GITIN-2013](https://smartit-ar.atlassian.net/browse/GITIN-2013)) detectó dos índices faltantes en `smartfran.branches`, correspondientes a las plataformas Rappi y Uber — mismo patrón ya conocido desde [GITIN-1744](https://smartit-ar.atlassian.net/browse/GITIN-1744)/[GITIN-2006](https://smartit-ar.atlassian.net/browse/GITIN-2006): `branches` no está sobre-indexada, le falta cobertura para los flags de plataforma que se van agregando con cada nueva integración. Ambas sugerencias se verificaron con `explain()` contra la consulta real (no solo la forma simplificada que reporta Atlas) antes de decidir: el índice de Rappi se creó pero se confirmó que el planner no lo usa; el de Uber se confirmó que sí sería usado, pero su impacto agregado (<1 segundo/día) no justifica el costo en un cluster M20. **Conclusión: no se necesita ningún índice nuevo en `branches` por ahora.**

## Tabla resumen

| Campo | Valor |
|---|---|
| Ticket Jira | [GITIN-2062](https://smartit-ar.atlassian.net/browse/GITIN-2062) |
| Sistema | MongoDB Atlas — cluster `PedidosSmartfran`, colección `branches` |
| Detectado | 2026-09-16, vía Atlas Performance Advisor (continuación de GITIN-2013) |
| Resuelto | Sí (2026-09-17) — ambas sugerencias investigadas y verificadas con `explain()`; ningún índice nuevo se considera necesario por ahora (Rappi: verificado sin uso; Uber: verificado útil pero impacto insuficiente para el costo en M20). Índice de Rappi queda creado mientras se decide si eliminarlo |
| Responsable | Dante Paniagua (SRE) |

## Causa raíz

`checkOfflinePOSrappi()` (`concentradorService/api/src/controllers/branch.js:448`), un monitor de heartbeat de POS que corre cada minuto vía `node-cron` interno, consulta `branches` filtrando por `alreadyClosedRappi` y `lastGetNews` sin tener un índice que soporte esa combinación — cada ejecución que detecta sucursales con heartbeat vencido hace un scan parcial de la colección. El mismo patrón (consulta sin índice de soporte para un flag de plataforma) es estructural: ya se dio con PediGrido/Peya (resuelto en GITIN-2006) y ahora con Rappi/Uber.

## Hallazgos

| # | Hallazgo | Riesgo |
|---|---|---|
| H1 | Índice faltante `{alreadyClosedRappi: 1, lastGetNews: 1}` — usado por `checkOfflinePOSrappi()`, un mecanismo real de cierre automático de sucursales con POS caído, no un caso de borde. Frecuencia observada subió de 4.5/hr a 15.08/hr en un día. **Corrección (2026-09-17): el índice fue creado pero `explain()` confirma que el planner NO lo usa** — la consulta real de 3 condiciones sigue usando el índice preexistente `platforms.platform_1_platforms.branchReference_1` (más selectivo), y ya es rápida (7ms) sin el índice nuevo. La sugerencia de Atlas se basó en una forma de consulta más simple (2 campos, sin filtro de plataforma) que no coincide con el uso real | Alto — **índice creado, pero sin beneficio confirmado; pendiente decidir si se elimina** |
| H2 | Índice faltante `{"address.country": 1, alreadyClosedUber: 1}` — origen confirmado: `sendStatusUberEats()` (cron por país/horario configurado, no el heartbeat continuo). `explain()` confirma que ningún índice existente lo sirve bien (187ms, 1.047 examinados → 66 devueltos) y que el índice propuesto sí sería usado. **Impacto agregado cuantificado: <1 segundo/día** (frecuencia real 0.17/hr). **Decisión (2026-09-17): no aplicar** — beneficio insuficiente para justificar el costo de almacenamiento/escritura en un cluster M20 | Bajo — **descartado por costo/beneficio, no por falta de utilidad** |
| H3 | Patrón estructural confirmado: cada integración de plataforma nueva agrega su propio monitor de heartbeat con el mismo tipo de consulta, y ninguna llega con índice de soporte desde el inicio — Atlas recién lo detecta semanas después, con tráfico real acumulado | Informativo — riesgo de que se repita con la próxima plataforma |

## Recursos afectados

| Componente | Impacto |
|---|---|
| Concentrador (`checkOfflinePOSrappi`) | Monitor de heartbeat de POS para Rappi, corre cada minuto — beneficiado directamente por H1 |
| `smartfran.branches` | Colección con los dos índices en cuestión |

## Comandos ejecutados

| # | Comando | Propósito |
|---|---|---|
| C1 | `db.branches.createIndex({alreadyClosedRappi: 1, lastGetNews: 1})` (aplicado vía Atlas UI, no mongosh) | Resolver H1 |
| C2 | `db.branches.getIndexes().length` | Confirmar aplicación (9 → 10) |

## Acciones propuestas

1. **(SRE)** — Índice de Rappi creado y confirmado en el listado de índices (2026-09-17). **Verificado vía `explain()` que el planner no lo usa para la consulta real** — evaluar si corresponde eliminarlo (sin beneficio, costo de escritura) o si existe otra consulta real (no encontrada todavía) que sí se beneficie de él antes de eliminarlo.
2. **(SRE)** — Trazado el origen real del patrón de Uber (`sendStatusUberEats()`, no `checkOfflinePOSuber()`) y verificado con `explain()` que el índice propuesto sí sería usado. Hecho.
3. **(SRE)** — **No aplicar el índice de Uber por ahora.** Aunque verificado como técnicamente útil, el impacto agregado es menor a 1 segundo/día (frecuencia real 0.17/hr) — no justifica el costo de almacenamiento/escritura en un cluster M20. Revisar si la frecuencia o el costo por ejecución cambian materialmente (más países/horarios configurados, o upgrade de tier).
4. **(Dev/SRE)** — Evaluar si conviene agregar una verificación de índices como parte del checklist de integración de una nueva plataforma, dado que este patrón ya se repitió con PediGrido, Peya, Rappi y Uber — no es un hallazgo aislado.

## Archivos de evidencia

Ver `smartpedidos/events/20260908_gitin2013-query-insights-slow-queries/` para el detalle completo del relevamiento de Atlas que originó este ticket — no duplicado acá.
