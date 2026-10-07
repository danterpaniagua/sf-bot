## Resumen

Desde el 2026-09-25, la cola SQS `PRD_BranchMessages.fifo` —por la cual `platforms-service` recibe las confirmaciones de estado enviadas por SmartCloud (aceptado, listo, despachado, entregado, rechazado) para reenviarlas a la sucursal vía `news`— mostró picos recurrentes de `ApproximateAgeOfOldestMessage` a lo largo de todo el fin de semana (25 al 28/09), con mensajes esperando en cola hasta varias horas antes de ser procesados. Un aumento reactivo de CPU aplicado el 25/09 no eliminó el problema: los picos continuaron con severidad igual o mayor durante todo el fin de semana. El 28/09 se aplicó una nueva revisión que reduce la memoria por debajo de la configuración previa a la incidencia. La causa raíz de fondo aún no está confirmada.

## Tabla resumen

| Campo | Valor |
|---|---|
| Ticket Jira | [GITIN-2110](https://smartit-ar.atlassian.net/browse/GITIN-2110) |
| ID alerta | N/A — reportado internamente, sin alerta automática asociada |
| Sistema | `platforms-service` (SmartPedidos) — cola SQS `PRD_BranchMessages.fifo` |
| Severidad | Medio-Alto |
| Detectado | 2026-09-25 |
| Resuelto | No resuelto — investigación en curso, ver "Acciones propuestas" |
| Responsable | Equipo SRE SmartPedidos |

## Causa raíz

**No confirmada.** Se descartó la hipótesis de capacidad de CPU como causa principal: la revisión `:267` duplicó el CPU asignado a `platforms-service` (512→1024) el 25/09, pero los picos de edad de cola persistieron durante todo el fin de semana con magnitud igual o mayor (peor pico del fin de semana: 374s, domingo 21:05 ART, con CPU en apenas 49% de uso — muy lejos de saturación incluso con el CPU original). No se encontró ningún error de aplicación en Graylog durante las ventanas de incidente verificadas, confirmado mediante un chequeo de sanidad que descarta que se trate de una búsqueda fallida. El código de `platforms-service` (`pollFromQueue`/`handleMessageBatch`, rama `develop`) no registra ningún log en el camino exitoso —ni tamaño de cola, ni duración de procesamiento— lo que impide diagnosticar el mecanismo exacto solo con logs. La hipótesis principal, no confirmada, es que una llamada HTTP saliente hacia la plataforma de delivery (PedidosYa/Rappi/etc.) dentro de las estrategias de "listo"/"despachado"/"entregado" queda colgada sin timeout configurado, bloqueando el consumidor sin elevar el uso de CPU — patrón de falla ya documentado para este mismo sistema (ver Hallazgo H6). El volumen de mensajes en esta cola subió 26-40% de forma sostenida desde el fin de semana del 18/09 (Hallazgo H8), coincidiendo con el período en que empezaron a reportarse las demoras — pero el detalle por hora muestra que el pico más severo (domingo 21:05) no coincidió con un momento de tráfico inusualmente alto, ni contra el mismo horario de la semana anterior ni contra el propio pico diario (14:00-16:00 ART). El volumen más alto puede ser un factor de fondo, pero no explica por sí solo el momento puntual en que ocurre cada pico.

## Hallazgos

| # | Hallazgo | Riesgo |
|---|---|---|
| H1 | `PRD_BranchMessages.fifo` mostró picos recurrentes de `ApproximateAgeOfOldestMessage` durante todo el fin de semana del 26 al 28/09: viernes 23:45 (320s), sábado 14:40 (304s), sábado 18:40 (303s), sábado 21:40 (296s, CPU máximo del fin de semana: 60.3%), domingo 21:05 (374s, el pico más alto de toda la investigación). | Alto |
| H2 | La revisión `:267` (CPU 512→1024, aplicada el 25/09 como mitigación reactiva) no correlaciona con una mejora: el pico más severo del fin de semana ocurrió después del despliegue, con CPU muy por debajo de saturación. Esto debilita la hipótesis de capacidad de CPU como causa. | Alto |
| H3 | No se encontró ningún log de error de aplicación (`sqs_consumer`, `batch_processing`) en Graylog durante las ventanas de incidente verificadas (25/09). Confirmado mediante chequeo de sanidad con un término de alto volumen (29.318 resultados en la misma ventana) — el resultado en cero es real, no una falla de búsqueda. | Medio |
| H4 | El código de `platforms-service` (`api/src/platforms/provider/aws.js`, rama `develop`) no registra ningún evento a nivel INFO/PERF en el camino exitoso del consumidor SQS. La profundidad real de la cola (`sizeMessageSQS`), calculada en cada batch, nunca se registra en los logs — solo se usa internamente para decidir el auto-escalado de consumidores. Esto explica directamente H3 y es una brecha de observabilidad real, no solo un hallazgo circunstancial. | Alto |
| H5 | El pico del domingo 21:05 ART se trazó hasta un evento concreto: 843 documentos `news` de 405 sucursales distintas actualizados en la ventana 21:02–21:14 ART, de los cuales 292 (35%) se procesaron en una ráfaga de 11 segundos (21:06:23–21:06:34 ART) — un patrón de acumulación y liberación en lote, no una demora pareja. El 94% de la ráfaga corresponde a confirmaciones de entrega (`deliv_ord`). | Alto |
| H6 | El detalle de transiciones (`traces[]`) de una muestra de 15 órdenes de la ráfaga muestra que las etapas tempranas (nueva→recibida→vista→confirmada) son consistentemente rápidas, mientras que la demora se concentra siempre en las etapas finales (confirmada→lista, lista→despachada, despachada→entregada) — con brechas individuales de hasta 3.5 horas entre transiciones. Este patrón coincide con el mecanismo de falla ya documentado en la skill `ops-aws` (F-006): una dependencia externa sin timeout configurado puede bloquear el proceso sin elevar el uso de CPU. | Alto |
| H7 | `platform-service-production-task` tuvo tres revisiones en esta ventana: `:266` (512 CPU/2048 MB, base previa) → `:267` (1024/2048, mitigación reactiva, 25/09) → `:268` (512/1024, 28/09, actualmente activa). `:268` no es una simple reversión de `:267`: la memoria queda por debajo de la base de 2048 MB vigente desde el ajuste del 2026-08-05. El motivo de esta reducción de memoria no fue confirmado con el equipo. | Medio |
| H8 | El volumen de mensajes recibidos en `PRD_BranchMessages.fifo` (`NumberOfMessagesReceived`, últimos 30 días) muestra un salto real y sostenido: los fines de semana del 18/09 (814.228) y 25/09 (823.794) están 26-40% por encima de los tres fines de semana anteriores (573.443–655.409), coincidiendo con el período en que empezaron a reportarse las demoras (GITIN-2068/GITIN-2084, 17-19/09) — coincidencia temporal, no confirmada como causal. Sin embargo, el detalle por hora **debilita** la hipótesis de volumen como causa directa del pico del domingo 21:05: esa hora tuvo un volumen prácticamente idéntico al mismo horario del domingo anterior (24.349 vs. 24.077 mensajes) y muy por debajo del pico real del propio día (14:00-16:00 ART, 37.000-44.000 mensajes) — el peor evento de este ticket no coincidió con el momento de mayor tráfico, ni del día ni de la semana. | Medio |
| H9 | Costo incremental de la mitigación reactiva `:267` (CPU 512→1024, todo el fin de semana, 58.75h): estimado entre **USD 4 y 12**, según el método de cálculo. Tres métodos independientes, sin convergencia exacta: (a) tarifa Fargate por task-hora × conteo de tasks documentado (`desiredCount: 10`) → USD 11.89; (b) delta de costo real diario en Cost Explorer → implica ~5.4 tasks reales → USD 5.95; (c) delta de costo real horario en Cost Explorer (el más granular disponible, `HOURLY` es el límite de AWS Cost Explorer) → implica ~3.7 tasks reales → USD 4.43. La brecha entre métodos se debe a ruido real en el costo horario de referencia (varía ±35% hora a hora incluso antes de la mitigación) y a que el costo de Cost Explorer no está aislado por servicio (incluye `concentrador-service`, sin cambios, más cualquier otro gasto bajo la categoría "Amazon Elastic Container Service"). Monto no crítico en términos absolutos, pero el rango no se pudo cerrar sin Cost Allocation Tags a nivel de servicio ECS. | Bajo |

## Recursos afectados

| Componente | Impacto |
|---|---|
| `platforms-service` | Consumidor de `PRD_BranchMessages.fifo` (`pollFromQueue`/`setNews`) — origen del retraso en el procesamiento de confirmaciones de estado |
| Cola SQS `PRD_BranchMessages.fifo` | Acumulación intermitente de mensajes sin consumir, hasta varias horas de antigüedad en los casos más severos |
| Colección `news` (MongoDB) | Actualizaciones de estado (`updatedAt`) retrasadas y luego liberadas en lote; hasta 405 sucursales distintas afectadas en un solo evento (domingo 21:05 ART) |
| `platform-service-production-task` (ECS) | Tres cambios de configuración de capacidad en la ventana investigada (`:266`→`:267`→`:268`), ninguno con causa raíz confirmada como justificación |

## Comandos ejecutados

Todos los comandos y scripts usados en esta investigación están documentados en `scripts.sh`, dentro de esta misma carpeta de evento. Resultados reales de cada uno persistidos en `data/`.

| # | Comando / Script | Propósito |
|---|---|---|
| C1 | CloudWatch `ApproximateAgeOfOldestMessage`, 6h | Chequeo inicial de la cola `PRD_BranchMessages.fifo` |
| C2 | CloudWatch `ApproximateAgeOfOldestMessage`, fin de semana completo | Confirmar recurrencia de los picos durante toda la ventana de `:267` |
| C3 | CloudWatch `CPUUtilization`, `platform-service-production-service`, fin de semana | Cruzar picos de cola contra uso real de CPU |
| C4 | `describe-task-definition` `:266`/`:267` | Confirmar qué cambió `:267` (CPU/memoria/imagen/env) |
| C5 | `describe-services` (post-`:267`) | Confirmar rollout completo de `:267` |
| C6 | `describe-task-definition` `:268` | Confirmar qué cambia `:268` respecto a `:266`/`:267` |
| C7 | `describe-services` (post-`:268`) | Confirmar estado de rollout de `:268` |
| C8 | Graylog, términos `sqs_consumer`/`batch_processing`, ambas ventanas de incidente (25/09) | Buscar errores de aplicación durante los incidentes |
| C9 | Graylog, chequeo de sanidad (`platforms-service`) | Confirmar que la búsqueda realmente alcanza la ventana/índice (descarta falso negativo) |
| C10 | `mongo_news_volume_weekend.js` | Volumen de `news` por hora, fin de semana completo |
| C11 | `mongo_trace_sunday_2105.js` | Documentos `news` actualizados justo en/después del pico del domingo 21:05 ART |
| C12 | `mongo_traces_sunday_burst.js` | Detalle de `traces[]` completo para 15 órdenes de la ráfaga |
| C13 | Lookup `db.newsTypes` | Mapeo `typeId` → código/nombre de transición |
| C14 | Deploy `:267` | Mitigación reactiva de CPU |
| C15 | Deploy `:268` | Nueva revisión, aún sin motivo confirmado |
| C16 | CloudWatch `NumberOfMessagesReceived`, 30 días | Comparar volumen de este fin de semana contra fines de semana previos |
| C17 | `describe-services`, historial de eventos | Confirmar conteo real de tasks corriendo durante la ventana de `:267` (visibilidad limitada a las últimas 100 eventos de la API) |
| C18 | Cost Explorer `get-cost-and-usage`, granularidad diaria | Costo real ECS por día, línea base pre-mitigación vs. días con `:267` activo |
| C19 | Cost Explorer `get-cost-and-usage`, granularidad horaria | Costo real ECS por hora, mismo cálculo con mayor resolución (límite de granularidad de Cost Explorer) |

## Acciones propuestas

1. (Dev) Revisar `ReadyStrategy`, `DispatchStrategy` y `DeliveryStrategy` (`api/src/platforms/management/strategies/orderStrategy/`) para confirmar si realizan llamadas HTTP salientes hacia la plataforma de delivery (PedidosYa/Rappi/etc.) sin timeout configurado — hipótesis principal de causa raíz (H6), aún no verificada en código.
2. (Dev) Agregar logging a nivel INFO/PERF en `pollFromQueue`/`handleMessageBatch` (`api/src/platforms/provider/aws.js`) — como mínimo, tamaño de cola (`sizeMessageSQS`) y duración de procesamiento por batch — para permitir diagnóstico directo desde Graylog en el próximo evento (H4).
3. (SRE) Confirmar con el equipo el motivo de la reducción de memoria en `:268` (1024 MB, por debajo de la base de 2048 MB vigente desde 2026-08-05) y si fue una decisión deliberada o un ajuste no relacionado con este incidente (H7).
4. (SRE) Una vez agregado el logging de H4/acción 2, monitorear la próxima recurrencia del patrón de ráfaga (H5) para confirmar o descartar la hipótesis de H6 con evidencia directa de logs, en lugar de reconstrucción vía CloudWatch + MongoDB.
5. (SRE) Evaluar si este mecanismo de cola explica también el error `CRS: 409` reportado en GITIN-2109 (franquicia 5470, PedidosYa) — la ráfaga trazada en H5/H6 incluye tanto confirmaciones de entrega como de "listo", pero no se confirmó una correlación directa orden-a-orden entre ambos tickets.
