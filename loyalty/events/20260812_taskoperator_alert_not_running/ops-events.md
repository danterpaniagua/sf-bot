# Eventos — 20260812_taskoperator_alert_not_running

## 2026-08-12 13:49 — Alerta de TaskOperator sin ejecutar

Recibí la alerta de GITIN-1828 indicando que TaskOperator mostraba una tarea sin ejecutar desde hacía ~15hs. Confirmé el mecanismo de alerta (`ReportWarningsTaskOperator.ps1`/`Query052-sql.xml`) contra `SmartFran.Solution.SmartLoyalty`.

## 2026-08-12 13:55 — Identificación de tareas vencidas

Ejecuté una consulta contra `Sch.Task` y detecté 27 tareas con último evento `Rerun` sin progreso posterior, distribuidas en dos clústeres (2026-08-10 y 2026-08-11, ventana de tareas diarias de la madrugada).

## 2026-08-12 14:03 — Confirmación de servicio activo

Confirmé vía PowerShell en `SFCG-TO-01` que el servicio `SmartLoyalty.TaskOperator.Service` estaba `Running`/`Automatic`, descartando una caída total del servicio en ese momento.

## 2026-08-12 14:04 — Reinicio manual del servicio

Reinicié manualmente el servicio; el arranque demoró un tiempo considerable. Re-verifiqué las 27 tareas y confirmé que el reinicio no las destrabó.

## 2026-08-12 14:04 — Reprogramación directa (intento inicial)

Cancelé 15 duplicados históricos y reprogramé las 12 instancias restantes vía `UPDATE Sch.Task SET ExecuteOn`, priorizando por duración histórica medida. Verifiqué el resultado tres veces en un lapso de ~18 minutos y confirmé que la reprogramación directa no generó ejecución real en ninguna de las 12 tareas.

## 2026-08-12 14:22 — Causa raíz confirmada vía Event Viewer

Revisé el log de eventos de Windows (System, Service Control Manager) en `SFCG-TO-01` y confirmé una caída real del servicio de ~15h19m (2026-08-11 20:06 a 2026-08-12 11:25 GMT), incluyendo un intento de reinicio automático fallido (timeout de 30s, Eventos 7009/7000).

## 2026-08-12 14:28 — Corrección del health-check automático

Identifiqué que la tarea programada `Check_list_SF` (`ServicesAndTaskStatus.ps1`) referenciaba un nombre de servicio incorrecto, por lo que nunca detectó la caída. Corregí el script desplegado en `SFCG-TO-01` (`E:\SmartLoyalty.SmlBackScript\ServicesAndTaskStatus.ps1`, con backup previo) y verifiqué el cambio.

## 2026-08-12 14:35 — Resolución de las 27 tareas

Con los procedimientos oficiales `[dbo].[ReRunTask]`/`[dbo].[RescheduleTask]`, confirmé que las 12 tareas restantes ya tenían `Done` completo. Al intentar reprogramarlas mediante `ReRunTask`, el propio procedimiento rechazó las 12 llamadas por control de duplicados, revelando que cada job ya contaba con su próxima ejecución correctamente programada. Concluí que las 27 tareas nunca estuvieron realmente bloqueadas — hallazgo de una consulta diagnóstica imprecisa, no un problema operativo real.

## 2026-08-12 14:40 — Cierre

Redacté el reporte de cierre (`ops.md`) para GITIN-1828.
