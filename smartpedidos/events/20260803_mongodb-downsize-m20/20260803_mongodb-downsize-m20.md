# 20260803_mongodb-downsize-m20

**Tags:** SmartPedidos, MongoDB

## Resumen

Se evaluó la factibilidad de bajar el tier del cluster MongoDB Atlas `PedidosSmartfran` (base `smartfran`, `us-east-1`) de **M30 a M20**. En enero de 2026 ya se había intentado este downsize (19/1 → reversión el 21/1) por degradación observada: CPU picos de 35% y RAM limitada muy por debajo del techo de M20, con recomendación formal de mantener M30. Tras relevar métricas actuales de caché real (WiredTiger) y Disk IOPS — no solo memoria del sistema operativo — y confirmar cambios de condición desde enero (limpieza de índices de `ordertimes`, cese de escritura a `logerrors` desde el 20/7), la evidencia actual no reproduce el cuadro que motivó la reversión de enero. Se decide reintentar el downsize a M20, con monitoreo activo y criterios de rollback explícitos.

## Tabla resumen

| Campo | Valor |
|---|---|
| Ticket Jira | [GITIN-1741](https://smartit-ar.atlassian.net/browse/GITIN-1741) |
| Sistema | MongoDB Atlas — cluster `PedidosSmartfran`, base `smartfran`, `us-east-1` |
| Tier actual | M30 (2 vCPU / 8 GB RAM) |
| Tier propuesto | M20 (2 vCPU / 4 GB RAM) |
| Topología | Replica set 3 nodos, no shardeado (confirmado — M20 no soporta sharding, no aplica como bloqueante) |
| Intento previo | 19/1/2026 → revertido 21/1/2026 |
| Fecha de esta decisión | 03/08/2026 |
| Responsable | SRE |

## Justificación (evidencia relevada)

**Precedente de enero (real, no descartado):** durante la prueba M20 del 19-21/1, CPU subió a picos de 35% (vs. 15-25% normal en M30) y la RAM quedó limitada a ~1.300-1.500 MB — señal de presión de eviction sobre una caché insuficiente para el working set de ese momento. Se revirtió a M30 y se recomendó mantenerlo.

**Condiciones cambiaron desde enero:**
- Índices de `ordertimes` reducidos ~76% (220 MB → 52,58 MB de índice total).
- Escritura a `logerrors` deshabilitada desde el 20/7/2026 (confirmado vía historial de git de `concentrador-service`/`platforms-service`, no en enero como se creía inicialmente).
- Durante esta sesión se eliminaron además los índices secundarios de `logerrors` (~906 MB liberados en disco), quedando solo el índice `_id_`.

**Métricas actuales (Atlas UI, 03/08/2026) muestran la caché real sin presión:**
- Cache Usage (WiredTiger real, no memoria de sistema operativo): pico ~1.2-1.5 GB por réplica, `DIRTY` insignificante (19-24 MB).
- Disk Read IOPS: ~0.3-0.42/s — prácticamente nulo, la caché actual cubre casi la totalidad de las lecturas.
- Estos valores están dentro del rango que M20 puede ofrecer (~1-1.5 GB de caché WiredTiger según fórmula usada), a diferencia del cuadro observado en la prueba de enero.

**Nota metodológica:** la comparación inicial se apoyó en % de RAM de sistema operativo ocupada, lo cual sobreestima el riesgo — WiredTiger tiende a ocupar toda la caché disponible por diseño, eso no es en sí mismo señal de estrés. La señal real es presión de eviction (Read IOPS, CPU), que es la que se usó para la decisión final.

## Hallazgos

| # | Hallazgo | Riesgo |
|---|---|---|
| H1 | Prueba real de enero (M20, 19-21/1) mostró degradación (CPU 35%, RAM limitada) y fue revertida | Medio — antecedente real, no descartado, mitigado con monitoreo |
| H2 | Cache Usage y Disk Read IOPS actuales no muestran presión de eviction | Bajo — evidencia favorable, pero medida solo en M30, no en M20 |
| H3 | `branches` muestra fuerte sobre-indexación (~10x tamaño de datos) e intensa escritura (~47,5M modify calls acumulados sobre 2.346 documentos) | Medio — no es bloqueante de este ticket, pero es presión de caché adicional no resuelta, ver Hallazgos secundarios |
| H4 | Tamaño de disco provisionado (~10 GB) es menor al default de M30 — deberá confirmarse el tamaño de disco al reconfigurar a M20 | Bajo — verificación operativa simple |

## Recursos afectados

| Componente | Impacto |
|---|---|
| MongoDB Atlas `PedidosSmartfran` | Cambio de tier M30 → M20, reversible |
| platforms-service | Consumidor de la base; sensible a latencia si la caché de M20 resulta insuficiente |
| concentrador-service | Ídem — además dependiente del cluster para `deadLetterSave()` y estado de `news` |

## Acciones propuestas

1. (SRE) Ejecutar el downsize de tier M30 → M20 en Atlas, confirmando previamente el tamaño de disco provisionado (ver H4).
2. (SRE) Monitorear activamente durante y después del cambio: CPU (umbral ~30-35% sostenido), Disk Read IOPS (cualquier suba sostenida desde el baseline actual ~0.3-0.42/s), y Cache Usage/eviction.
3. (SRE) Definir rollback inmediato a M30 si se repiten los síntomas de enero (CPU sostenido >30-35%, Read IOPS en alza, o degradación de latencia perceptible en platforms-service/concentrador-service).
4. (Dev) Confirmar que ninguna consulta dependía de los índices eliminados de `logerrors` (`createdAt_1`, `updatedAt_-1`, `message_1_updatedAt_-1`, `message_1_createdAt_-1`) — no verificado contra patrones de query reales antes del drop.
5. (Dev/SRE) Re-analizar queries e índices de las colecciones principales (`orders`, `branches`, `ordertimes`, `news`) antes de temporada de pico, como preparación independiente del resultado del downsize — ver Hallazgos secundarios.

## Hallazgos secundarios

- Sobre-indexación en `branches` (H3) y el patrón de escritura intensa sobre esa colección quedan fuera de alcance de este ticket — no bloquean el downsize pero representan presión de caché evitable a mediano plazo.
- **Propuesta de preparación para temporada de pico:** dado lo relevado en esta investigación (`branches` con índices ~10x el tamaño de los datos, dominados por índices multikey compuestos sobre el array `platforms`; `logerrors` tenía el mismo patrón antes del drop de índices de hoy), se propone un análisis de queries e índices más amplio antes de la próxima temporada de pico — no limitado a las colecciones ya relevadas acá. Objetivo: confirmar con planes de ejecución reales (`explain()`) qué índices están efectivamente en uso, detectar índices redundantes o faltantes en las colecciones de mayor volumen (`orders`, `ordertimes`), y asegurar que la capacidad de caché elegida (M20 o M30, según el resultado del monitoreo de este ticket) tenga margen ante el pico de tráfico, no solo ante el tráfico actual. No iniciado — queda como propuesta de seguimiento, alcance y ticket a definir.
