**Resumen**

El servicio TaskOperatorService (`SFCG-TO-01`) estuvo inactivo durante aproximadamente 15h19m (2026-08-11 20:06 GMT a 2026-08-12 11:25 GMT), generando la alerta de tarea sin ejecutar de este ticket. La caída no fue detectada por el health-check automático (`Check_list_SF`) debido a que el script hacía referencia a un nombre de servicio incorrecto. Se corrigió el script en el servidor y se verificó que el servicio está operativo. En paralelo, se investigaron 27 tareas cuyo último evento registrado era `Rerun`, inicialmente interpretadas como bloqueadas; se confirmó que todas habían finalizado correctamente y ya contaban con su próxima ejecución correctamente programada — no requirieron ninguna acción.

**Tabla resumen**

| Campo | Valor |
|---|---|
| Ticket Jira | [GITIN-1828](https://smartit-ar.atlassian.net/browse/GITIN-1828) |
| Caso | TaskOperatorService inactivo ~15h, alerta de tarea sin ejecutar |
| Base de datos / Host | `SmartFran.Solution.SmartLoyalty` (`Sch.Task`/`Sch.TaskEvent`/`Sch.Job`) / `SFCG-TO-01` |
| Severidad | Alta (caída no detectada durante ~15h) |
| Detectado | 2026-08-12 |
| Resuelto | 2026-08-12 |
| Responsable | Dante Paniagua, SRE |

**Causa raíz**

El servicio Windows `SmartLoyalty.TaskOperator.Service` en `SFCG-TO-01` dejó de responder el 2026-08-11 20:06 GMT. Un intento de reinicio automático falló por timeout (30000 ms, Eventos 7009/7000 del Service Control Manager) y el servicio permaneció caído hasta el reinicio manual del 2026-08-12 11:25 GMT. La tarea programada `Check_list_SF`, responsable de detectar el servicio caído y reiniciarlo cada 5 minutos, hacía referencia al nombre de servicio `Solution.SmartLoyalty.TaskOperatorService`, que no corresponde al nombre real (`SmartLoyalty.TaskOperator.Service`), por lo que nunca detectó ni corrigió la caída durante todo el período.

**Hallazgos**

| # | Hallazgo | Riesgo |
|---|---|---|
| H1 | Caída no detectada de TaskOperatorService (~15h19m) por nombre de servicio incorrecto en el script de health-check automático | Alto |
| H2 | El arranque del servicio (`OnStart`) ejecuta la recuperación de tareas pendientes de forma síncrona y secuencial; tras una caída prolongada esto contribuye a un arranque manual lento | Medio |
| H3 | 27 tareas con evento `Rerun` como último estado fueron identificadas inicialmente como bloqueadas por una consulta diagnóstica; se confirmó que todas habían finalizado correctamente (`Done` no nulo) y ya tenían su próxima ejecución programada — no había ningún bloqueo real | Bajo |
| H4 | Secuencia de detención/deshabilitación/reinicio manual del servicio detectada el 2026-08-11 entre las 12:20 y 12:31 GMT, de causa aún no confirmada — posible intento previo de remediación no documentado | Bajo |

**Recursos afectados**

| Job | Instancias evaluadas | Estado final |
|---|---|---|
| `PromotionFilterProcessor` | 2 | Completadas; próxima ejecución programada 2026-08-13 |
| `ExchangeOptionFilterProcessor` | 2 | Completadas; próxima ejecución programada 2026-08-13 |
| `AutoAcceptAccountRecovery` | 7 | Completadas; próxima ejecución programada 2026-08-12 15:00 GMT (job horario) |
| `CancelOldOrderJob` | 2 | Completadas; próxima ejecución programada 2026-08-13 |
| `FixMissingArticleIdSaleDetailProcessor` | 2 | Completadas; próxima ejecución programada 2026-08-13 |
| `EtlDwGridoSurveyProcessor` | 2 | Completadas; próxima ejecución programada 2026-08-13 |
| `EtlDwGridoLocationProcessor` | 2 | Completadas; próxima ejecución programada 2026-08-13 |
| `EtlDwGridoCustomerProcessor` | 1 | Completada; próxima ejecución programada 2026-08-13 |
| `EtlDwGridoSaleProcessor` | 1 | Completada; próxima ejecución programada 2026-08-13 |
| `EtlDwGridoCustomerSaleProcessor` | 2 | Completadas; próxima ejecución programada 2026-08-13 |
| `EtlDwGridoBranchOfficeProcessor` | 2 | Completadas; próxima ejecución programada 2026-08-13 |
| `EtlSmlTarget` | 2 | Completadas; próxima ejecución programada 2026-08-13 |

**Métricas del evento**

| Métrica | Valor |
|---|---|
| Duración de la caída de TaskOperatorService | ~15h19m (2026-08-11 20:06 – 2026-08-12 11:25 GMT) |
| Tareas evaluadas como potencialmente bloqueadas | 27 |
| Duplicados históricos cancelados (limpieza, sin impacto operativo) | 15 |
| Tareas que efectivamente requerían acción | 0 |

**Consultas ejecutadas**

| # | Query | Propósito |
|---|---|---|
| Q1 | Tareas nunca iniciadas | Buscó tareas con evento `Created` sin evento posterior — 0 resultados |
| Q2 | Tareas vencidas contra `Sch.Task` | Identificó las 27 tareas con último evento distinto de `Ended`/`Canceled`/`Disabled` |
| Q3 | Duración histórica por job | Determinó el orden de prioridad para el reintento (mayor duración primero) |
| Q4 | Cancelación de duplicados | `UPDATE` — canceló los 15 duplicados históricos más antiguos |
| Q5 | Reprogramación directa (`UPDATE ExecuteOn`) | Intento inicial de reprogramación; confirmado ineficaz — no genera el evento `Created` que requiere el scheduler |
| Q6 | Verificación de estado post-reprogramación | Confirmó (3 verificaciones, ~18 min) que Q5 no produjo ejecución real |
| Q7 | Estado real de `Sch.Task` (no `TaskEvent`) | Confirmó `Done` no nulo en las 12 tareas — ya habían finalizado correctamente |
| Q8 | `EXEC [dbo].[ReRunTask]` | Intento de reprogramación vía procedimiento oficial — las 12 llamadas fueron rechazadas por control de duplicados del propio procedimiento |
| Q9 | Búsqueda de tarea bloqueante por job | Confirmó que cada job ya tenía su próxima ejecución correctamente programada — resolvió el caso |

**Acciones propuestas**

1. Corregido el nombre de servicio en `ServicesAndTaskStatus.ps1` (copia desplegada en `SFCG-TO-01`, backup guardado como `ServicesAndTaskStatus.ps1.bak_20260812`). Pendiente aplicar el mismo cambio en el control de versiones que administra este script, para que no se pierda en el próximo despliegue. (SRE)
2. Confirmar con el equipo de desarrollo la causa de la caída real del servicio del 2026-08-11 20:06 GMT (revisar log de aplicación / buzón de alertas IT). (SRE)
3. Confirmar el origen de la secuencia de detención/reinicio manual del 2026-08-11 entre las 12:20 y 12:31 GMT. (SRE)
4. Sin acciones pendientes sobre las 27 tareas evaluadas — todas completaron correctamente y ya tienen su próxima ejecución programada.
